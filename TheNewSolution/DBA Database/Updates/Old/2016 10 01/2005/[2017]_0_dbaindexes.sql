USE DBA
GO

IF OBJECT_ID('DBA.dbo.Audit_LoginDatabase') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Audit_LoginDatabase_DateGathered_LoginName ON Audit_LoginDatabase (DateGathered, LoginName);
END

GO

IF OBJECT_ID('DBA.dbo.Audit_LoginServer') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Audit_LoginServer_DateGathered_LoginName ON Audit_LoginServer (DateGathered, LoginName);
END

GO

IF OBJECT_ID('DBA.dbo.Data_AgentJobHistory') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_AgentJobHistory_DateGathered_Job_ID ON Data_AgentJobHistory (DateGathered, Job_ID);
END

GO

IF OBJECT_ID('DBA.dbo.Data_AgentJobList') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_AgentJobList_DateAdded_Job_ID ON Data_AgentJobList (DateAdded, Job_ID);
END

GO

IF OBJECT_ID('DBA.dbo.Data_BackupHistory') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_BacakupHistory_DateGathered_DatabaseName ON Data_BackupHistory (DateGathered, DatabaseName);
END

GO

IF OBJECT_ID('DBA.dbo.Data_BackupMediaFiles') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_BackupMediaFiles_DatabaseName_MediaSetID_FamilySeqNumber ON Data_BackupMediaFiles (DatabaseName, MediaSetID, FamilySeqNumber);
END

GO

IF OBJECT_ID('DBA.dbo.Data_BackupSet') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_BackupSet_DateGathered_BackupSetUUID_MediaSetID ON Data_BackupSet (DateGathered, BackupSetUUID, MediaSetID);
END

GO

IF OBJECT_ID('DBA.dbo.Data_Database') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_Database_DateGathered_DatabaseName ON Data_Database (DateGathered, DatabaseName);
END

GO

IF OBJECT_ID('DBA.dbo.Data_DatabaseFiles') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_DatabaseFiles_DateGathered_DatabaseName_FileGUID ON Data_DatabaseFiles (DateGathered, DatabaseName, FileGUID);
END

GO

IF OBJECT_ID('DBA.dbo.Data_ObjectBackupHistory') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_ObjectBackupHistory_DateAdded_ObjectName ON Data_ObjectBackupHistory (DateAdded, ObjectName);
END

GO

IF OBJECT_ID('DBA.dbo.Data_SQLConfigChanges') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_SQLConfigChanges_DateStart_ApplicationName ON Data_SQLConfigChanges (DateStart, ApplicationName);
END

GO

IF OBJECT_ID('DBA.dbo.Data_SystemDisk') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Data_SystemDisk_DateGathered_DriveLetter ON Data_SystemDisk (DateGathered, DriveLetter);
END

GO

IF OBJECT_ID('DBA.dbo.Info_LoginDatabase') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Info_LoginDatabase_LoginName ON Info_LoginDatabase (LoginName);
END

GO

IF OBJECT_ID('DBA.dbo.Info_LoginDatabaseObject') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Info_LoginDatabaseObject_LoginName ON Info_LoginDatabaseObject (LoginName);
END

GO

IF OBJECT_ID('DBA.dbo.Info_Message') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Info_Message_DateMessage ON Info_Message (DateMessage);
END

GO

IF OBJECT_ID('DBA.dbo.Mnt_CheckDB') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Mnt_CheckDB_DateGathered_DatabaseName_RowID ON Mnt_CheckDB (DateGathered, DatabaseName, RowID);
END

GO

IF OBJECT_ID('DBA.dbo.[Option]') IS NOT NULL
BEGIN
CREATE CLUSTERED INDEX IX_Option_OptionLevel_OptionName ON [Option] (OptionLevel, OptionName);
END

GO
