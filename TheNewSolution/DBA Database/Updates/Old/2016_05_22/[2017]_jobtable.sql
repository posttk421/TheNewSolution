IF OBJECT_ID('DBA.dbo.Data_AgentJobList') IS NOT NULL
BEGIN
	DROP TABLE Data_AgentJobList
END

CREATE TABLE Data_AgentJobList
	(
	ServerName SYSNAME NOT NULL
	, DateAdded DATETIME NOT NULL
	, ListedInServer BIT NULL
	, JobName SYSNAME NOT NULL
	, Job_ID UNIQUEIDENTIFIER NOT NULL UNIQUE
	, JobDescription VARCHAR(1000) NULL
	, JobIsEnabled BIT NULL
	, OwnerName SYSNAME NULL
	, DateCreated DATETIME NULL
	, DateModified DATETIME NULL
	, VersionNumber INT NULL
	, StepCount_All INT NULL
	, StepCount_SSIS INT NULL
	, StepCount_CMDExec INT NULL
	, StepCount_PShell INT NULL
	, StepCount_TSQL INT NULL
	, StepCount_Others INT NULL
	, DateLastRun DATETIME
	, LastRunOutcome INT NULL
	, LastRunDuration_Second BIGINT NULL
	, NextRunTime DATETIME NULL
	)