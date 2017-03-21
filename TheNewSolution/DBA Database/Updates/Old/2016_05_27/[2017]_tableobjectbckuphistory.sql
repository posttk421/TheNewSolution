USE DBA
GO

IF OBJECT_ID('DBA.dbo.Data_ObjectBackupHistory') IS NOT NULL
BEGIN
	DROP TABLE Data_ObjectBackupHistory
END
GO

CREATE TABLE Data_ObjectBackupHistory
	(
	ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, DateAdded DATETIME NOT NULL
	, ObjectType VARCHAR(100) NOT NULL
	, ObjectName VARCHAR(200) NULL
	, FilePath VARCHAR(2000) NOT NULL
	, DateRemoved DATETIME NULL
	)