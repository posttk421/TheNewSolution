USE [DBA]
GO

IF OBJECT_ID('sp_Getbckfilestodel') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_Getbckfilestodel
END

GO

/****** Object:  StoredProcedure [dbo].[sp_Getbckfilestodel]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[sp_Getbckfilestodel]
	(
	@DbName VARCHAR(200)
	)
AS

/***************
Name: sp_Getbckfilestodel
Author: Dustin Marzolf
Created: 2/26/2016

Update 5/13/2016 - Dustin Marzolf
	Updated due to new field names in related tables.
	Updated to not return backups that have already been deleted.
 Output:
	a Table with two columns, a list of files (path and names) and a database.
	
Notes:

The Rules are as follows.

It is expected that we need to delete the prior full backup if we are taking a full backup as
there won't be enough space on the disk.  As such, the logic depends on what is about to be done.

If the expected backup type is a FULL backup then it is safe to delete all prior files (FULL and LOG)

If the expected backup type is a LOG backup then we need to keep the immediately prior FULL and the subsequent LOGS on hand.

****************/

--For good measure, update the tables used for decision making.
EXEC sp_BackupUpdateMediaInfo

/** Identify Files To Be Deleted **/

--Hold the Results.
DECLARE @OkToDelete TABLE
	(
	DatabaseName VARCHAR(200) NULL
	, BackupFile VARCHAR(1000) NULL
	)
	
-- Expecting to do a full
INSERT INTO @OkToDelete
(DatabaseName, BackupFile)
SELECT B.DatabaseName
	, F.FilePathName
FROM Data_BackupSet B
	LEFT OUTER JOIN Data_BackupMediaFiles F ON F.DatabaseName = B.DatabaseName AND F.MediaSetID = B.MediaSetID
	CROSS APPLY (SELECT DBA.dbo.fn_GetDbbckuptype(B.DatabaseName, DATEPART(dw, GETDATE())) AS ExpectedType) T
WHERE T.ExpectedType = 'D'
	AND CAST(B.DateBackupSetExpires AS DATE) <= CAST(GETDATE() AS DATE)
	AND (B.DatabaseName = @DbName OR @DbName IS NULL)
	AND F.DateFileDeleted IS NULL

--Expecting to do a Log.
--The Last FULL and it's children Logs are ok to keep.
INSERT INTO @OkToDelete
(DatabaseName, BackupFile)
SELECT B.DatabaseName
	, F.FilePathName
FROM Data_BackupSet B
	LEFT OUTER JOIN Data_BackupMediaFiles F ON F.DatabaseName = B.DatabaseName AND F.MediaSetID = B.MediaSetID
	CROSS APPLY (SELECT DBA.dbo.fn_GetDbbckuptype(B.DatabaseName, DATEPART(dw, GETDATE())) AS ExpectedType) T
	CROSS APPLY (	SELECT TOP 1 Back.*
					FROM Data_BackupSet Back
					WHERE Back.DatabaseName = B.DatabaseName
						AND Back.BackupType = 'D'
					ORDER BY Back.DateBackupEnd DESC
					) AS LastFull
WHERE B.DateBackupEnd < LastFull.DateBackupEnd
	AND T.ExpectedType = 'L'
	AND CAST(B.DateBackupSetExpires AS DATE) < CAST(GETDATE() AS DATE)
	AND (B.DatabaseName = @DbName OR @DbName IS NULL)
	AND F.DateFileDeleted IS NULL
	
SELECT DatabaseName, BackupFile FROM @OkToDelete
	


GO


