
USE DBA;

UPDATE [Option]
SET OptionValue = '\\DMDBAPRDbak02\D$\SQLBCKUPS'
WHERE OptionValue LIKE '\\10.10.10%'
	AND OptionName = 'BackupFolderRoot'
	AND OptionLevel = 'Server'

UPDATE [Option]
SET OptionValue = '0'
WHERE OptionName IN ('BackupRetention_WeeklyCount', 'BackupRetention_MonthlyCount')
	AND OptionLevel = 'Server'

UPDATE [Option]
SET OptionValue = '1'
WHERE OptionName IN ('BackupRetentionFull_Days', 'BackupRetentionTran_Days')
	AND OptionLevel = 'Server' 

UPDATE [Option]
SET OptionValue = '1'
WHERE OptionName = 'BackupCompression'
	AND OptionLevel = 'Server'