USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[spBackupDatabase]    Script Date: 02/08/2017 1:46:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[spBackupDatabase]
	(
	@DbName VARCHAR(200) = NULL
	, @BackupType CHAR(1) = NULL
	, @IsDebug BIT = 0
	)
AS

/**********
Name: spBackupDatabase
Author: Dustin Marzolf
Created: 2/26/2016
 Output:
	None - If @IsDebug = 1 then will print the statements.
	
NOTES:
* If preferred type of backup cannot be determined (from Option_Database) then will default to Full backup
* If database is in FULL Recovery Model and indicated backup type is full, will take a log first (inserting the proper command)
* If database is in FULL recovery model and indicated backup is log, will only do this if it's not the first
	backup in the chain (first backup must be a FULL).  
	
Example 1)
* Database has no entry in Option_Database, Defaults to FULL backup.
* No prior backup, takes just the FULL.

Example 2) 
* Database is supposed to take a LOG backup according to Option_Database.
* Database has NO prior FULL backup.  System takes FULL backup instead.

Example 3)
* Database is supposed to take a full backup according to Option_Database.
* Database is in FULL recovery mode.
* System takes LOG, then FULL
	
********************/

SET NOCOUNT ON

DECLARE @DBName VARCHAR(200)
DECLARE @BackupFolder VARCHAR(1000)
DECLARE @BUType CHAR(1)
DECLARE @BackupCommand NVARCHAR(4000)
DECLARE @RecoveryModel VARCHAR(100)
DECLARE @IsFirstBackup BIT 
SET @IsFirstBackup = 0

DECLARE @Holder TABLE
	(
	IndexID INT PRIMARY KEY IDENTITY(1,1) NOT NULL
	, DatabaseName VARCHAR(200) NULL
	, BackupFolder VARCHAR(1000) NULL
	, BackupType CHAR(1) NULL
	, BackupCommand NVARCHAR(4000) NULL
	, RecoveryModel VARCHAR(50) NULL
	, FirstBackup BIT NULL
	)

DECLARE @Databases TABLE
	(
	name SYSNAME NULL
	, recovery_model_desc NVARCHAR(50) NULL
	, IsFirstBackup BIT NULL DEFAULT 0 
	)

/** Populate the @Databases Table **/
INSERT INTO @Databases (name, recovery_model_desc, IsFirstBackup)
SELECT D.name
	, D.recovery_model_desc
	, CASE WHEN R.last_log_backup_lsn IS NULL THEN 1 ELSE 0 END
FROM sys.databases D
	LEFT OUTER JOIN sys.database_recovery_status R ON R.database_id = D.database_id 
WHERE D.name <> 'tempdb'
	AND (D.name = @DbName
		OR @DbName IS NULL
		)

--If no database is specified and backuptype is L, then only backup databases that
--are FULL or BULK_LOGGED
IF @BackupType = 'L' AND @DbName IS NULL
BEGIN

	DELETE FROM @Databases
	WHERE recovery_model_desc = 'SIMPLE'

END

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT name
		, recovery_model_desc
		, IsFirstBackup
	FROM @Databases
	
OPEN curDB

FETCH NEXT FROM curDB 
INTO @DBName, @RecoveryModel, @IsFirstBackup

WHILE @@FETCH_STATUS = 0
BEGIN

	/** Set the Backup Folder **/
	SET @BackupFolder = (SELECT DBA.dbo.fn_GetBckupFolder(@DBName))

	/** Set the Backup Type **/
	SET @BUType = ISNULL(@BackupType, (SELECT DBA.dbo.fn_GetDbbckuptype(@DBName, DATEPART(dw, GETDATE()))))	
	
	--If recovery is simple then you have to take a FULL backup.  
	IF @RecoveryModel = 'SIMPLE'
	BEGIN
		SET @BUType = 'D'
	END
	
	--If Backup Type is LOG and this is the first backup, then it MUST be a full.
	IF @BUType = 'L' AND @IsFirstBackup = 1
	BEGIN
		SET @BUType = 'D'
	END
		
	--If the recovery model is FULL or Bulk Logged and we are taking a FULL backup, then take a LOG first (unless it's the first backup).
	IF @BUType = 'D' AND @IsFirstBackup = 0 AND NOT(@RecoveryModel = 'SIMPLE')
	BEGIN
	
		SET @BackupCommand = (SELECT DBA.dbo.fnCreateBackupStatement(@DBName, 'L', @BackupFolder, 1))
		
		INSERT INTO @Holder
		(DatabaseName, BackupFolder, BackupType, BackupCommand, RecoveryModel, FirstBackup)
		VALUES
		(@DBName, @BackupFolder, 'L', @BackupCommand, @RecoveryModel, @IsFirstBackup)
		
	END
	
	/** Set the Backup Command for the backup **/	
	SET @BackupCommand = (SELECT DBA.dbo.fnCreateBackupStatement(@DBName, @BUType, @BackupFolder, NULL))

	INSERT INTO @Holder
	(DatabaseName, BackupFolder, BackupType, BackupCommand, RecoveryModel, FirstBackup)
	VALUES
	(@DBName, @BackupFolder, @BUType, @BackupCommand, @RecoveryModel, @IsFirstBackup)
	
	--Get next Database Name.
	FETCH NEXT FROM curDB 
	INTO @DBName, @RecoveryModel, @IsFirstBackup

END --End WHILE @@FETCH_STATUS = 0 (Looping through curDB)

--Cleanup CurDB
CLOSE curDB
DEALLOCATE curDB

/** Remove Skip Commands **/
DELETE FROM @Holder
WHERE BackupType = 'X'

/** Begin Executing Commands**/

DECLARE curBackup CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT DatabaseName
		, BackupCommand
		, BackupType
	FROM @Holder
	ORDER BY IndexID
	
OPEN curBackup

FETCH NEXT FROM curBackup
INTO @DBName, @BackupCommand, @BUType

WHILE @@FETCH_STATUS = 0
BEGIN

	IF @IsDebug = 1
	BEGIN
		PRINT '/** ' + @DBName + ' **/'
		PRINT @BackupCommand
	END
	
	IF @IsDebug = 0
	BEGIN
		SET @DBName = 'Backing Up ' + @DBName
		EXEC DBA.dbo.sp_logMsg 0, 'Backup', @DBName, @BackupCommand, NULL
		EXEC sp_executesql @BackupCommand	
	END

	--Get the next entry.
	FETCH NEXT FROM curBackup
	INTO @DBName, @BackupCommand, @BUType

END --End WHILE @@FETCH_STATUS = 0 (Looping through list of commands)

CLOSE curBackup
DEALLOCATE curBackup

--Populate the backup history table.
IF @IsDebug = 0
BEGIN
	EXEC DBA.dbo.spGetBackupHistory 
END


GO


