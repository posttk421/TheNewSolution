
--Stop backup compression.
 UPDATE DBA.dbo.[Option]
 SET OptionValue = 0
 WHERE OptionLevel = 'Server'
	AND OptionName = 'BackupCompression'

--Change Backup Path.
UPDATE DBA.dbo.[Option]
SET OptionValue = '\\10.10.10.117\sql2'
WHERE OptionLevel = 'Server'
	AND OptionName = 'BackupFolderRoot'

--Get new Login Data
EXEC DBA.dbo.spGetLoginData 1
