USE DBA
GO

IF OBJECT_ID('DBA.dbo.sp_GetMntDBFile') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetMntDBFile
END

IF OBJECT_ID('DBA.dbo.Mnt_DatabaseFile') IS NOT NULL
BEGIN
	DROP TABLE Mnt_DatabaseFile
END

GO

CREATE TABLE Mnt_DatabaseFile
	(
	DatabaseFileID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY 
	, ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, DatabaseName SYSNAME NOT NULL
	, DateGathered DATETIME NOT NULL DEFAULT GETDATE()
	, FileGUID UNIQUEIDENTIFIER NULL
	, FileType CHAR(4) NULL
	, NameOfFile SYSNAME NULL
	, SpaceUsedOnDisk_MB DECIMAL(10,2) NULL
	, SpaceUsedInFile_MB DECIMAL(10,2) NULL
	, SpaceFreeInFile_MB DECIMAL(10,2) NULL
	)

CREATE NONCLUSTERED INDEX NIX_Mnt_DatabaseFile_DatabaseName_DateGathered_FileType_DatabaseFileID ON Mnt_DatabaseFile (DatabaseName, DateGathered, FileType, DatabaseFileID)

GO

USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[spGetDatabaseFiles]    Script Date: 02/08/2017 9:29:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[sp_GetMntDBFile]
	(
	@DbName SYSNAME
	)
AS

/***********************
Name: sp_GetMntDBFile

Author: Dustin Marzolf

Created: 11/4/2016

Purpose: Gets data about the configuration of the database files for analysis.

Inputs: @DbName - The name of the database to get the data for.  NULL will get all databases.

************************/

SET NOCOUNT ON

--Needed Variables.
DECLARE @Query NVARCHAR(4000)
DECLARE @RightNow DATETIME 
SET @RightNow = GETDATE()
DECLARE @curDBName SYSNAME

IF OBJECT_ID('tempdb..#DBFiles') IS NOT NULL
BEGIN
	DROP TABLE #DBFiles
END

CREATE TABLE #DBFiles
	(
	DatabaseName SYSNAME NULL
	, FileGUID UNIQUEIDENTIFIER NULL
	, FileType CHAR(4) NULL
	, NameOfFile SYSNAME NULL
	, SpaceUsedOnDisk_MB DECIMAL(10,2)
	, SpaceUsedInFile_MB DECIMAL(10,2)
	)
	
DECLARE curDatabase CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT name
	FROM sys.databases
	WHERE name = @DbName
		OR @DbName IS NULL
	ORDER BY name
	
OPEN curDatabase

FETCH NEXT FROM curDatabase
INTO @curDBName

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @Query = 'USE ' + QUOTENAME(@curDBName)
				+ ' INSERT INTO #DBFiles'
				+ ' (DatabaseName, FileGUID, FileType, NameOfFile, SpaceUsedOnDisk_MB, SpaceUsedInFile_MB)'
				+ ' SELECT DB_NAME()'
				+ '	, D.file_guid'
				+ '	, D.type_desc' 
				+ '	, D.name' 
				+ '	, (D.size * 8.00 / 1024.00)'
				+ '	, CAST(FILEPROPERTY(D.name, ' + QUOTENAME('SpaceUsed', '''') + ') AS INT)/128.00'
				+ ' FROM sys.database_files D'
				+ ' LEFT OUTER JOIN sys.filegroups F ON F.data_space_id = D.data_space_id'
				+ ' INNER JOIN sys.sysfiles S ON S.fileid = D.[file_id]'
				
	EXEC sp_executesql @Query

	--Get the next database.
	FETCH NEXT FROM curDatabase
	INTO @curDBName

END --WHILE @@FETCH_STATUS = 0 (Looping through curDatabase)

--Cleanup curDatabase
CLOSE curDatabase
DEALLOCATE curDatabase

/** Insert into the permanent table, and do some calculations **/
INSERT INTO Data_DatabaseFiles
(DatabaseName, DateGathered, FileGUID, FileType, NameOfFile, SpaceUsedOnDisk_MB, SpaceUsedInFile_MB, SpaceFreeInFile_MB)
SELECT T.DatabaseName
	, @RightNow
	, T.FileGUID 
	, T.FileType 
	, T.NameOfFile 
	, T.SpaceUsedOnDisk_MB 
	, T.SpaceUsedInFile_MB 
	, SpaceFreeInFile_MB = ISNULL(T.SpaceUsedOnDisk_MB, 0.00) - ISNULL(T.SpaceUsedInFile_MB, 0.00)
FROM #DBFiles T


IF @DbName IS NOT NULL
BEGIN

	/** Check for recent large growth on disk **/
	ALTER TABLE #DBFiles
	ADD SizeOnDisk_Last DECIMAL(10,2) NULL
		, DateLastSizeOnDisk DATETIME NULL
		, SizeOnDisk_Average DECIMAL(10,2) NULL

	UPDATE #DBFiles
	SET SizeOnDisk_Last = F.SpaceUsedOnDisk_MB
		, DateLastSizeOnDisk = F.DateGathered
		, SizeOnDisk_Average = G.SizeOnDisk_Average
	FROM #DBFiles D
		OUTER APPLY (SELECT TOP 1 E.SpaceUsedOnDisk_MB
								, E.DateGathered
					FROM Data_DatabaseFiles E
					WHERE E.DatabaseName = D.DatabaseName
						AND E.NameOfFile = D.NameOfFile
						AND E.DateGathered < @RightNow
					ORDER BY E.DateGathered DESC
					) F
		OUTER APPLY (SELECT AVG(E.SpaceUsedOnDisk_MB) AS SizeOnDisk_Average
					FROM Data_DatabaseFiles E
					WHERE E.DatabaseName = D.DatabaseName
						AND E.NameOfFile = D.NameOfFile
						AND E.DateGathered > DATEADD(DAY, -30, @RightNow)
					GROUP BY E.DatabaseName, E.NameOfFile
					) G

	DELETE FROM #DBFiles
	WHERE ABS(SpaceUsedOnDisk_MB / ISNULL(SizeOnDisk_Last, SpaceUsedOnDisk_MB)) >= .05
		OR ABS(SpaceUsedOnDisk_MB / ISNULL(SizeOnDisk_Average, SpaceUsedOnDisk_MB)) >= .10

	IF ISNULL((SELECT COUNT(*) FROM #DBFiles), 0) >= 1
	BEGIN
	
		DECLARE @LogMessage VARCHAR(200)
		SET @LogMessage = 'Investigate database growth for ' + ISNULL(CAST(@DbName AS VARCHAR(100)), '')
		
		EXEC sp_logMsg 4, 'Growth', 'Database Growth is too rapid', @LogMessage, NULL
	
	END

END
	
--Cleanup.
IF OBJECT_ID('tempdb..#DBFiles') IS NOT NULL
BEGIN
	DROP TABLE #DBFiles
END

GO




