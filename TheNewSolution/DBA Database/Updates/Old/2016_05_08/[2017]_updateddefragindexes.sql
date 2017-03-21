USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[spDefragmentIndexes]    Script Date: 02/08/2017 08:58:16 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[spDefragmentIndexes]
	(
	@DefragmentThreshold FLOAT = 5.0
	, @RebuildThreshold FLOAT = 30.0
	, @IsExecuteSQL BIT = 1
	, @DbName VARCHAR(250) = NULL
	, @DefragDelayText VARCHAR(20) = '00:00:05'
	, @Script VARCHAR(MAX) OUTPUT
	)
AS

/**
--For Testing...
DECLARE	@DefragmentThreshold FLOAT = 5.0
DECLARE	@RebuildThreshold FLOAT = 30.0
DECLARE	@IsExecuteSQL BIT = 0
DECLARE	@DbName VARCHAR(250) = NULL
DECLARE	@DefragDelayText VARCHAR(20) = '00:00:05'
DECLARE	@Script VARCHAR(MAX) 
**/

--Settings.
SET NOCOUNT ON
SET XACT_Abort ON
SET Quoted_Identifier ON

/******************************
Name: spDefragmentIndexes

Author: Dustin Marzolf, based on scripts by Michelle Ufford, http://sqlfool.com

Created: 2/11/2016

Purpose: To degragment the indexes in the specified database or server.

Inputs:
	@DefragmentThreshold FLOAT = 5.0 - If the fragmentation is less than this, will leave alone.
	@RebuildThreshold FLOAT = 30.0 - If the fragmentation exceeds this, then it will rebuild instead of reorganizing.
	@IsExecuteSQL BIT = 1 - If true, then will actually execute the SQL statements, otherwise will not.
	@DbName VARCHAR(250) = NULL - The name of the database to defragment, if NULL then will process through all.
	@DefragDelayText VARCHAR(20) = '00:00:05' - The time to wait between defragment commands.  Must be in HH:mm:ss format.

Outputs:
	@Script VARCHAR(MAX) - contains the SQL commands.  If you set IsExecuteSQL to 0, then you need
		to use this to either display or execute the commands.
		
**********************************/

--Input Validations...
IF NOT(@DefragmentThreshold BETWEEN 0.00 AND 100.00)
BEGIN
	SET @DefragmentThreshold = 5.0
END

IF NOT(@RebuildThreshold BETWEEN 0.00 AND 100.00)
BEGIN
	SET @RebuildThreshold = 30.0
END

IF NOT(@DefragDelayText LIKE '00:[0-5][0-9]:[0-5][0-9]')
BEGIN
	SET @DefragDelayText = '00:00:05'
END

IF @IsExecuteSQL IS NULL
BEGIN
	SET @IsExecuteSQL = 1
END

SET @Script = ''

/** Variable Declaration and initial population Begins **/

DECLARE @LogMessage VARCHAR(MAX)
DECLARE @DBName VARCHAR(250)
DECLARE @DBID INT
DECLARE @OnlineRebuild BIT = 0
DECLARE @Query NVARCHAR(4000)
DECLARE @CRCL CHAR(2) = CHAR(13) + CHAR(10)

--Only Enterprise and DataCenter editions support Online Rebuilds.
IF UPPER(CAST(SERVERPROPERTY('Edition') AS VARCHAR(100))) LIKE UPPER('%Enterprise%')
	OR UPPER(CAST(SERVERPROPERTY('Edition') AS VARCHAR(100))) LIKE UPPER('%Data%Center%')
BEGIN
	SET @OnlineRebuild = 1
END

--Holds the database name(s) to process.
DECLARE @Database TABLE
	(
	DatabaseID INT NOT NULL
	, DatabaseName VARCHAR(250) NOT NULL
	)
	
INSERT INTO @Database 
(DatabaseID, DatabaseName)
SELECT DB.database_id 
	, DB.name
FROM sys.databases DB
WHERE NOT(DB.name IN ('master', 'msdb', 'tempdb', 'model'))
	AND (	DB.name = @DbName
			OR @DbName IS NULL
			)
	AND DB.[state] = 0
	
--To hold the list of indexes.
DECLARE @IndexList TABLE
	(
	GlobalIndexID INT NOT NULL PRIMARY KEY IDENTITY(1,1)
	, DatabaseID INT NULL
	, DatabaseName VARCHAR(250) NULL
	, ObjectID INT NULL
	, IndexID INT NULL
	, PartitionNumber SMALLINT NULL
	, Fragmentation FLOAT NULL
	, [PageCount] INT NULL
	, DefragStatus BIT NULL
	, SchemaName VARCHAR(250) NULL
	, ObjectName VARCHAR(250) NULL
	, IndexName VARCHAR(250) NULL
	, IsAllowRowLocks BIT NULL
	, IsAllowPageLocks BIT NULL
	, IsContainsLOB BIT NULL
	, IsIndexPartitioned BIT NULL
	, SQLStatement NVARCHAR(4000) NULL
	)
	
DECLARE @GlobalIndexID INT
DECLARE @IndexName VARCHAR(250)
DECLARE @SchemaName VARCHAR(250)
DECLARE @ObjectName VARCHAR(250)
DECLARE @IsAllowRowLocks BIT
DECLARE @IsAllowPageLocks BIT
DECLARE @IsContainsLOB BIT
DECLARE @IsIndexPartitioned BIT
DECLARE @PartitionNumber SMALLINT
DECLARE @Fragmentation FLOAT
DECLARE @IsShouldReorganize BIT
DECLARE @MntIndexID INT
DECLARE @MaxIndexesToRebuild INT

/** Possible Exit Conditions **/
IF ISNULL((SELECT COUNT(DatabaseID) FROM @Database), 0) = 0
BEGIN
	SET @Script = 'No databases found that meet eligible criteria (not system database, online) and matching the name indicated.  Check your inputs.'
	--RETURN @Script
END
	
/***********************************************
Begin working on the data...
************************************************/

--Loop through the databases and get the list of indexes and their fragmentation level.
DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT DatabaseID
		, DatabaseName
	FROM @Database 

OPEN curDB

FETCH NEXT FROM curDB
INTO @DBID, @DBName

WHILE @@FETCH_STATUS = 0
BEGIN

	--Get the list of indexes.
	INSERT INTO @IndexList 
	(DatabaseID, DatabaseName, ObjectID, IndexID, PartitionNumber, Fragmentation, [PageCount], DefragStatus)
	SELECT @DBID
		, @DBName
		, S.[object_id] 
		, S.index_id 
		, S.partition_number 
		, S.avg_fragmentation_in_percent 
		, S.page_count 
		, 0
	FROM sys.dm_db_index_physical_stats (@DBID, OBJECT_ID(NULL), NULL , NULL, 'LIMITED') S
	WHERE S.avg_fragmentation_in_percent >= @DefragmentThreshold 
		AND S.index_id > 0
		AND S.page_count > 8
	OPTION (MAXDOP 1)
	
	IF @DBID IN (SELECT DatabaseID FROM @IndexList)
	BEGIN
	
		--The database had indexes that needed defragmenting, get the additional data...	
		--There is quite a bit of information to get...
		IF OBJECT_ID('tempdb..#TempObjects') IS NOT NULL
		BEGIN
			DROP TABLE #TempObjects
		END
		
		CREATE TABLE #TempObjects
			(
			ObjectID INT NULL
			, ObjectName VARCHAR(250) NULL
			, SchemaName VARCHAR(250) NULL
			, IndexID INT NULL
			, IndexName VARCHAR(250) NULL
			, IsAllowRowLocks BIT NULL
			, IsAllowPageLocks BIT NULL
			, IsContainsLOB BIT NULL
			, IsIndexPartitioned BIT NULL
			)
			
		SET @Query = 'USE ' + QUOTENAME(@DBName)
						+ ' INSERT INTO #TempObjects (ObjectID, ObjectName, SchemaName, IndexID, IndexName, IsAllowRowLocks, IsAllowPageLocks, IsContainsLOB, IsIndexPartitioned)'
						+ ' SELECT o.[object_id], o.name, s.name, i.index_id, i.name, i.allow_row_locks, i.allow_page_locks'
						+ ' , IsContainsLOB = CASE WHEN LOB.ColumnCount IS NOT NULL THEN 1 ELSE 0 END'
						+ ' , IsIndexPartitioned = CASE WHEN PART.PartitionCount > 1 THEN 1 ELSE 0 END'
						+ ' FROM ' + QUOTENAME(@DBName) + '.sys.objects o'
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.indexes i ON o.[object_id] = i.[object_id]'
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.schemas s ON s.[schema_id] = o.[schema_id]'
						+ ' LEFT OUTER JOIN ' + QUOTENAME(@DBName) + '.sys.partitions p ON p.[object_id] = o.[object_id] AND p.index_id = i.index_id'
						+ ' LEFT OUTER JOIN (	SELECT c.[object_id], COUNT(c.column_id) AS ColumnCount'
						+ '						FROM ' + QUOTENAME(@DBName) + '.sys.columns c'
						+ '						WHERE (c.system_type_id IN (34, 35, 99) OR c.max_length = -1)'
						+ '						GROUP BY c.[object_id]'
						+ '						) LOB ON LOB.[object_id] = o.[object_id]'
						+ ' LEFT OUTER JOIN (	SELECT p.[object_id], p.index_id, COUNT(p.partition_number) AS PartitionCount'
						+ '						FROM ' + QUOTENAME(@DBName) + '.sys.partitions p'
						+ '						GROUP BY p.[object_id], p.index_id'
						+ '						) PART ON PART.[object_id] = o.[object_id] AND PART.index_id = i.index_id'
						+ ' WHERE i.[type] > 0'
						
		EXEC sp_executesql @Query
						
		UPDATE @IndexList 
		SET ObjectName = O.ObjectName
			, SchemaName = O.SchemaName
			, IndexName = O.IndexName
			, IsAllowRowLocks = ISNULL(O.IsAllowRowLocks, 0)
			, IsAllowPageLocks = ISNULL(O.IsAllowPageLocks, 0)
			, IsContainsLOB = ISNULL(O.IsContainsLOB, 0)
			, IsIndexPartitioned = ISNULL(O.IsIndexPartitioned, 0)
		FROM @IndexList I
			INNER JOIN #TempObjects O ON O.ObjectID = I.ObjectID AND I.IndexID = O.IndexID
		
		--Cleanup...	
		IF OBJECT_ID('tempdb..#TempObjects') IS NOT NULL
		BEGIN
			DROP TABLE #TempObjects
		END	
									
	END	--IF @DBID IN (SELECT DatabaseID FROM @IndexList)		

	--Get next database name from curDB
	FETCH NEXT FROM curDB
	INTO @DBID, @DBName

END --WHILE @@FETCH_STATUS = 0 (Looping through curDB)

--Cleanup curDB
CLOSE curDB
DEALLOCATE curDB

/******
Remove Indexes from @IndexList where the following hold true.
- The fragmentation level is within 5% of the last time that index was defragmented.

The objective is to not continuously defragment indexes when that is their normal level of 
fragmentation.  Or where the fragmentation level is normal.
*******/

DELETE FROM @IndexList
WHERE GlobalIndexID IN (SELECT I.GlobalIndexID
						FROM @IndexList I
							CROSS APPLY (	SELECT TOP 1 O.* 
											FROM DBA.dbo.Mnt_Index O 
											WHERE O.DatabaseName = I.DatabaseName 
														AND O.SchemaName = I.SchemaName 
														AND O.ObjectName = I.ObjectName 
														AND O.IndexName = I.IndexName
											ORDER BY O.DateEnd DESC
											) M
						WHERE ABS((100 - M.FragmentationLevel) / (100 - I.Fragmentation)) > .90
						)
						
--Remove indexes that never finished rebuilding...
DELETE FROM @IndexList
WHERE GlobalIndexID IN (SELECT I.GlobalIndexID
						FROM @IndexList I
							INNER JOIN DBA.dbo.Mnt_Index O ON O.DatabaseName = I.DatabaseName
																AND O.SchemaName = I.SchemaName
																AND O.IndexName = I.IndexName
						WHERE O.DateEnd IS NULL
						)

--Limit the number of indexes to 250 per database OR 1000 (whichever is higher)						
SET @MaxIndexesToRebuild = (SELECT COUNT(DISTINCT I.DatabaseName) FROM @IndexList I) * 250

IF @MaxIndexesToRebuild < 1000
BEGIN
	SET @MaxIndexesToRebuild = 1000
END
--Remove the ones that we won't be running tonight.
DELETE FROM @IndexList
WHERE NOT(GlobalIndexID IN (SELECT TOP (@MaxIndexesToRebuild) GlobalIndexID
						FROM @IndexList
						ORDER BY Fragmentation DESC
						))
											
/******************************************

Now we have all the data we need to form the SQL Statements.

Loop through, Create the SQL Statement for each, Update the Script Output, etc.

********************************************/

DECLARE curIndexes CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT GlobalIndexID
		, DatabaseName
		, IndexName
		, SchemaName
		, ObjectName
		, IsAllowRowLocks
		, IsAllowPageLocks
		, IsContainsLOB 
		, IsIndexPartitioned
		, PartitionNumber
		, Fragmentation
	FROM @IndexList I
	ORDER BY DatabaseID

OPEN curIndexes

FETCH NEXT FROM curIndexes INTO
@GlobalIndexID, @DBName, @IndexName, @SchemaName, @ObjectName, @IsAllowRowLocks
	, @IsAllowPageLocks, @IsContainsLOB, @IsIndexPartitioned, @PartitionNumber
	, @Fragmentation
	
WHILE @@FETCH_STATUS = 0
BEGIN

	--Reorganize or Rebuild?
	--If the fragmentation is below the rebuild threshold
	-- or there is an LOB 
	-- or the index is partitioned
	-- then we should rebuild.
	IF @Fragmentation < @RebuildThreshold 
		OR @IsContainsLOB = 1
		OR @IsIndexPartitioned = 1
	BEGIN
		SET @IsShouldReorganize = 1
	END
	
	--If page locks are not allowed then we cannot reorganize.
	IF @IsAllowPageLocks = 0
		OR (@Fragmentation >= @RebuildThreshold 
			AND @IsContainsLOB = 0
			AND @IsIndexPartitioned = 0
			)
	BEGIN
		SET @IsShouldReorganize = 0
	END
	
	/** Construct Statement **/
	SET @Query = 'ALTER INDEX ' + QUOTENAME(@IndexName) + ' ON ' + QUOTENAME(@DBName) + '.' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName)
	
	IF @IsShouldReorganize = 1
	BEGIN
		--We are recorganizing.
		SET @Query = @Query + ' REORGANIZE'
	END
	ELSE
	BEGIN
		--We are rebuilding.
		SET @Query = @Query + ' REBUILD WITH (ONLINE = ' + CASE WHEN @OnlineRebuild = 1 THEN 'ON' ELSE 'OFF' END + ')'
	END
	
	--Store the SQL Statement...
	UPDATE @IndexList
	SET SQLStatement = @Query
	WHERE GlobalIndexID = @GlobalIndexID 

	--Append the output.
	SET @Script = @Script + @CRCL + @Query
	
	BEGIN TRY
	
		--Determine if we should execute the query.
		--If so, we are also going to log our actions...
		IF @IsExecuteSQL = 1
		BEGIN
		
			INSERT INTO DBA.dbo.Mnt_Index 
			(ServerName, DatabaseName, SchemaName, ObjectName, IndexName, FragmentationLevel, DateStart, SQLStatement)
			VALUES
			(@@SERVERNAME, @DBName, @SchemaName, @ObjectName, @IndexName, @Fragmentation, GETDATE(), @Query)
		
			SET @MntIndexID = SCOPE_IDENTITY()
		
			--Execute the query...
			EXEC sp_executesql @Query
			
			UPDATE DBA.dbo.Mnt_Index
			SET DateEnd = GETDATE()
			WHERE Mnt_IndexID = @MntIndexID
			
			SET @MntIndexID = NULL
			
			--Delay...
			WAITFOR DELAY @DefragDelayText
			
		END
		
	END TRY
	BEGIN CATCH
	
		INSERT INTO DBA.dbo.Mnt_Index 
		(ServerName, DatabaseName, SchemaName, ObjectName, IndexName, FragmentationLevel, DateStart, SQLStatement)
		VALUES
		(@@SERVERNAME, @DBName, @SchemaName, @ObjectName, @IndexName, @Fragmentation, GETDATE(), @Query)
		
	END CATCH						

	--Get the next Index to defragment.
	FETCH NEXT FROM curIndexes INTO
	@GlobalIndexID, @DBName, @IndexName, @SchemaName, @ObjectName, @IsAllowRowLocks
		, @IsAllowPageLocks, @IsContainsLOB, @IsIndexPartitioned, @PartitionNumber
		, @Fragmentation

END --WHILE @@FETCH_STATUS = 0 (Looping through all Indexes)

--Cleanup curIndexes.
CLOSE curIndexes
DEALLOCATE curIndexes

GO


