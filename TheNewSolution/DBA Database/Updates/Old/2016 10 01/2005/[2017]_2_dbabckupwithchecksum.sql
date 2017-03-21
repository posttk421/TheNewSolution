USE DBA

DELETE FROM [Option]
WHERE OptionLevel = 'Server' 
	AND OptionName = 'BackupCheckSUM';

INSERT INTO [Option]
(OptionLevel, OptionName, OptionValue, OptionDescription)
VALUES
('Server', 'BackupCheckSUM', 1, 'Will require backups to use the CheckSUM parameter');

GO

/****** Object:  UserDefinedFunction [dbo].[fn_CreateBckupStatemnt]    Script Date: 02/08/2017 7:51:39 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[fnCreateBackupStatement]
	(
	@DbName VARCHAR(200)
	, @BackupType CHAR(1)
	, @DestinationPath VARCHAR(1000)
	, @FileCount INT = NULL
	)
RETURNS NVARCHAR(4000)
AS
BEGIN

/*****************
Name: fnCreateBackupStatement
Author: Dustin Marzolf
Created: 2/26/2016

Purpose: To programmatically generate the backup statements.

Update: 5/8/2016 - Dustin Marzolf
	Corrected logic that let the setting in DBA.dbo.Option truly control whether compression
	is enabled or not.  Logic is:
		* If the option in DBA.dbo.Option allows it AND the server edition allows it then enable compression.
		* If either DBA.dbo.Option or the server edition do not allow compression, then do not use compression.

Inputs:
	@DbName VARCHAR(200) - The name of the database to be backed up.
	@BackupType CHAR(1) - The type of the backup.
	@DestinationPath VARCHAR(1000) - The destination path
	@FileCount INT (NULL) - The number of files to put the backup in.  
		If NULL is specified then the system will attempt to determine it based
		on the size of the last backup.
		@FileCount will always be 1 if doing a LOG backup.
	
Outputs:
	NVARCHAR(4000) - The statement to generate that creates the backups.
	
NOTES:
* Database name must exist or this will exit.
* BackupTypes must be supported (D - FULL, L - LOG)
* Uses compression if it's supported.

********************/

--Return Value.
DECLARE @RetVal NVARCHAR(4000)

-- Validation
IF NOT(@DbName IN (SELECT name FROM sys.databases))
BEGIN
	RETURN N'-- Specified database does not exist.'
END

SET @BackupType = UPPER(@BackupType)
IF NOT(@BackupType IN ('D', 'L'))
BEGIN
	RETURN N'-- Specified backup type not supported.'
END

/** Additional declarations needed for work. **/
DECLARE @IsCompression BIT
DECLARE @IsServerCompression BIT
DECLARE @TimeStamp VARCHAR(200) 
SET @TimeStamp = CAST(REPLACE(REPLACE(CONVERT(VARCHAR(20), GETDATE(), 120), ':', '_'), '-', '_') AS NVARCHAR(100))
DECLARE @BackupFileName VARCHAR(200)
DECLARE @BackupSetName VARCHAR(200)
DECLARE @Options NVARCHAR(4000)
DECLARE @BckupSizeGB DECIMAL(10,2)
DECLARE @CurrentFileCount INT
DECLARE @BackupFileList VARCHAR(MAX)
DECLARE @BackupCheckSUM BIT

--Compression Enabled if Enterprise 2008 or Standard 2008 R2 or later.
IF (SERVERPROPERTY('EngineEdition') = 3
	AND LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) >= '10'
	)
	OR (SERVERPROPERTY('EngineEdition') = 2
		AND LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) >= '10'
		AND RIGHT(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 5), 2) >= '50'
		)
BEGIN
	SET @IsCompression = 1
END

--But compression should only be done if the flag is enabled in DBA.dbo.Option.
SET @IsServerCompression = CASE WHEN ISNULL((SELECT DBA.dbo.fn_GetOptVal('Server', 'BackupCompression')), 0) = 1 THEN 1 ELSE 0 END

IF @IsCompression = 1 AND @IsServerCompression = 0
BEGIN
	SET @IsCompression = 0
END

--Determine if checksum should be used.
SET @BackupCheckSUM = CASE WHEN ISNULL((SELECT DBA.dbo.fn_GetOptVal('Server', 'BackupCheckSUM')), 0) = 1 THEN 1 ELSE 0 END

/** How many backup files to use **/

--If log then always use 1 backup file, regardless of what is input.
IF @BackupType = 'L' AND ISNULL(@FileCount, 0) <> 1
BEGIN
	SET @FileCount = 1
END

--If full backup and NULL (Auto) specified, then determine the count.
IF @BackupType = 'D' AND @FileCount IS NULL
BEGIN
	SET @BckupSizeGB = (	SELECT TOP 1 ISNULL(CompressedSizeGB, BckupSizeGB) 
							FROM DBA.dbo.Data_BackupHistory 
							WHERE DatabaseName = @DbName 
								AND BackupType = 'D'
							ORDER BY DateGathered DESC
							)
	
	SET @FileCount = CASE	WHEN @BckupSizeGB IS NULL THEN 1
							WHEN @BckupSizeGB BETWEEN 0.0 AND 2500 THEN 1
							WHEN @BckupSizeGB BETWEEN 2500 AND 5000 THEN 5
							WHEN @BckupSizeGB BETWEEN 5000 AND 10000 THEN 10
							WHEN @BckupSizeGB BETWEEN 10000 AND 50000 THEN 20
							WHEN @BckupSizeGB BETWEEN 50000 AND 100000 THEN 30
							WHEN @BckupSizeGB >= 100000 THEN 30
							ELSE 1
							END
END

/** Assemble Backup Command **/
--What are we doing?
IF @BackupType = 'D'
BEGIN
	SET @RetVal = 'BACKUP DATABASE ' + QUOTENAME(@DbName)
	SET @BackupFileName = @DbName + ' FULL BACKUP ' + @TimeStamp + '.BAK'
	SET @BackupSetName = @DbName + ' FULL BACKUP'
END

IF @BackupType = 'L'
BEGIN
	SET @RetVal = 'BACKUP LOG ' + QUOTENAME(@DbName)
	SET @BackupFileName = @DbName + ' LOG BACKUP ' + @TimeStamp + '.TRN'
	SET @BackupSetName = @DbName + ' LOG BACKUP'
END

--Where are we putting it?
IF RIGHT(@DestinationPath, 1) <> '\'
BEGIN
	SET @DestinationPath = @DestinationPath + '\'
END

--Assemble the backup path.
SET @CurrentFileCount = 1
SET @BackupFileList = ''
WHILE @CurrentFileCount <= @FileCount AND LEN(@BackupFileList) <= 3000
BEGIN
	IF @CurrentFileCount >= 2
	BEGIN
		SET @BackupFileList = @BackupFileList + ', '
	END
	
	SET @BackupFileList = @BackupFileList + 'DISK = N' + '''' + @DestinationPath + REPLACE(@BackupFileName, '.BAK', '_' + RIGHT('000' + CAST(@CurrentFileCount AS VARCHAR(3)), 3) + '.BAK') + ''''
	
	SET @CurrentFileCount = @CurrentFileCount + 1
	
END


SET @DestinationPath = @DestinationPath + @BackupFileName

--What options?
SET @Options = 'RETAINDAYS = 14, NOFORMAT, NOINIT, SKIP, NOREWIND, NOUNLOAD, STATS = 10'

IF @IsCompression = 1
BEGIN
	SET @Options = @Options + ', COMPRESSION'
END

IF @BackupCheckSUM = 1
BEGIN
	SET @Options = @Options + ', CHECKSUM'
END

--Put it all together.
SET @RetVal = @RetVal + ' TO ' + @BackupFileList
					+ ' WITH ' + @Options 
					+ ', NAME = N' + '''' + @BackupSetName + ''''
					
RETURN @RetVal

END




GO



