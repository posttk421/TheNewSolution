USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_GetAgtJoblist]    Script Date: 02/08/2017 09:46:43 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_GetAgtJoblist]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[sp_GetAgtJoblist]
GO

USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_GetAgtJoblist]    Script Date: 02/08/2017 09:46:43 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[sp_GetAgtJoblist]
AS

/**********************************
Name: sp_GetAgtJoblist

Author: Dustin Marzolf
Created: 3/22/2016

Purpose: To Gather a list of the agent jobs and some
	statistical information about them.
	
The objective of this procedure is to populate the table Data_AgentJobList with
a list of all agent jobs.  New jobs, deleted jobs and changed jobs (for various types
of "change") will be logged with a severity of 1.

While this process will inform of a jobs most recent status, that's not it's intent.
For detailed job performance information, see the other Agent Job Tables.

*************************************/

--Needed variables.
DECLARE @LastGathered DATETIME
DECLARE @RightNow DATETIME

--Last date last run or 6 weeks ago.
SET @LastGathered = ISNULL((SELECT MAX(DateLastRun) FROM Data_AgentJobList), DATEADD(wk, -6, GETDATE()))
SET @RightNow = GETDATE()

DECLARE @AgentJobList TABLE
	(
	ServerName SYSNAME NOT NULL
	, ListedInServer BIT NULL
	, JobName SYSNAME NOT NULL
	, Job_ID UNIQUEIDENTIFIER NOT NULL
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
	
DECLARE @Exceptions TABLE
	(
	JobName SYSNAME NOT NULL
	, JobID UNIQUEIDENTIFIER NOT NULL
	, IssueDescription VARCHAR(MAX) NULL
	)

--Get initial bit of data.
INSERT INTO @AgentJobList
(ServerName, ListedInServer, JobName, Job_ID, JobDescription, JobIsEnabled, OwnerName
	, DateCreated, DateModified, VersionNumber)
SELECT @@SERVERNAME
	, 1
	, JOB.name
	, JOB.job_id
	, JOB.[description]
	, JOB.[enabled]
	, P.name AS OwnerName
	, JOB.date_created
	, JOB.date_modified
	, JOB.version_number
FROM msdb.dbo.sysjobs JOB
	LEFT OUTER JOIN sys.server_principals P ON P.[sid] = JOB.owner_sid
	
--Correct Description
UPDATE @AgentJobList
SET JobDescription = NULL
WHERE JobDescription = ''
	OR JobDescription = 'No description available.'
	
--Get various further complicated pieces of information.
UPDATE @AgentJobList
SET StepCount_All = B.StepCount
	, StepCount_TSQL = C.StepCount
	, StepCount_PShell = D.StepCount
	, StepCount_CMDExec = E.StepCount
	, StepCount_SSIS = F.StepCount
	, StepCount_Others = G.StepCount
	, DateLastRun = History.DateLastRun 
	, LastRunOutcome = History.run_status 
	, LastRunDuration_Second = DBA.dbo.fn_JOBDurToSec(History.run_duration)
	, NextRunTime = DBA.dbo.fn_JOBrunToDT(Sched.next_run_date, Sched.next_run_time)
FROM @AgentJobList A
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S GROUP BY S.job_id) B ON B.job_id = A.Job_ID
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S WHERE S.subsystem = 'TSQL' GROUP BY S.job_id) C ON C.job_id = A.Job_ID
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S WHERE S.subsystem = 'PowerShell' GROUP BY S.job_id) D ON D.job_id = A.Job_ID
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S WHERE S.subsystem = 'CmdExec' GROUP BY S.job_id) E ON E.job_id = A.Job_ID
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S WHERE S.subsystem = 'SSIS' GROUP BY S.job_id) F ON F.job_id = A.Job_ID
	LEFT OUTER JOIN (SELECT S.job_id, COUNT(S.step_id) AS StepCount FROM msdb.dbo.sysjobsteps S WHERE NOT(S.subsystem IN ('SSIS', 'CmdExec', 'PowerShell', 'TSQL'))  GROUP BY S.job_id) G ON G.job_id = A.Job_ID
	OUTER APPLY (SELECT TOP 1 H.run_status, DBA.dbo.fn_JOBrunToDT(H.run_date, H.run_time) AS DateLastRun, H.run_duration FROM msdb.dbo.sysjobhistory H WHERE H.job_id = A.Job_ID AND DBA.dbo.fn_JOBrunToDT(H.run_date, H.run_time) > @LastGathered ORDER BY DBA.dbo.fn_JOBrunToDT(H.run_date, H.run_time) DESC) History
	LEFT OUTER JOIN msdb.dbo.sysjobschedules Sched ON Sched.job_id = A.Job_ID

--First, insert new jobs.	
INSERT INTO Data_AgentJobList
(ServerName, DateAdded, ListedInServer, JobName, Job_ID, JobDescription, JobIsEnabled
	, OwnerName, DateCreated, DateModified, VersionNumber, StepCount_All, StepCount_SSIS
	, StepCount_CMDExec, StepCount_PShell, StepCount_TSQL, StepCount_Others, DateLastRun
	, LastRunOutcome, LastRunDuration_Second, NextRunTime)
OUTPUT Inserted.JobName, Inserted.Job_ID, 'New Job Entered' INTO @Exceptions (JobName, JobID, IssueDescription)
SELECT @@SERVERNAME
	, @RightNow
	, 1
	, A.JobName
	, A.Job_ID
	, A.JobDescription
	, A.JobIsEnabled
	, A.OwnerName
	, A.DateCreated
	, A.DateModified
	, A.VersionNumber
	, A.StepCount_All
	, A.StepCount_SSIS
	, A.StepCount_CMDExec
	, A.StepCount_PShell
	, A.StepCount_TSQL
	, A.StepCount_Others
	, A.DateLastRun
	, A.LastRunOutcome
	, A.LastRunDuration_Second
	, A.NextRunTime
FROM @AgentJobList A
WHERE NOT(A.Job_ID IN (SELECT Job_ID FROM Data_AgentJobList))

--Find any deleted jobs.
UPDATE Data_AgentJobList
SET ListedInServer = 0
OUTPUT Inserted.JobName, Inserted.Job_ID, 'Job No Longer Listed' INTO @Exceptions (JobName, JobID, IssueDescription)
WHERE NOT(Job_ID IN (SELECT Job_ID FROM @AgentJobList))

--Look for changes.
UPDATE Data_AgentJobList
SET JobIsEnabled = A.JobIsEnabled
	, OwnerName = A.OwnerName
	, DateModified = A.DateModified
	, VersionNumber = A.VersionNumber
	, StepCount_All = A.StepCount_All
OUTPUT Inserted.JobName, Inserted.Job_ID, 'Enabled, Owner, Date Modified, Version Number or Step Count changed.' INTO @Exceptions (JobName, JobID, IssueDescription)
FROM Data_AgentJobList D
	INNER JOIN @AgentJobList A ON A.Job_ID = D.Job_ID
WHERE ISNULL(D.JobIsEnabled, 0) <> ISNULL(A.JobIsEnabled, 0)
	OR ISNULL(D.OwnerName, '') <> ISNULL(A.OwnerName, '')
	OR ISNULL(D.DateModified, '1/1/1950') <> ISNULL(A.DateModified, '1/1/1950')
	OR ISNULL(D.VersionNumber, 0) <> ISNULL(A.VersionNumber, 0)
	OR ISNULL(D.StepCount_All, 0) <> ISNULL(A.StepCount_All, 0)
	
--Update All remaining stat information.
UPDATE Data_AgentJobList
SET StepCount_All = A.StepCount_All
	, StepCount_SSIS = A.StepCount_SSIS
	, StepCount_CMDExec = A.StepCount_CMDExec
	, StepCount_PShell = A.StepCount_PShell
	, StepCount_TSQL = A.StepCount_TSQL
	, StepCount_Others = A.StepCount_Others
	, DateLastRun = A.DateLastRun
	, LastRunOutcome = A.LastRunOutcome
	, LastRunDuration_Second = A.LastRunDuration_Second
	, NextRunTime = A.NextRunTime
FROM Data_AgentJobList D
	INNER JOIN @AgentJobList A ON A.Job_ID = D.Job_ID
	
/** Exception Processing **/
DECLARE @JobName VARCHAR(200)
DECLARE @JobID VARCHAR(200)
DECLARE @IssueDescription VARCHAR(MAX)

DECLARE curExceptions CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT CAST(JobName AS VARCHAR(200))
		, CAST(JobID AS VARCHAR(200))
		, IssueDescription
	FROM @Exceptions
	
OPEN curExceptions

FETCH NEXT FROM curExceptions
INTO @JobName, @JobID, @IssueDescription

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @IssueDescription = 'Job Name: ' + @JobName + ' Job ID: ' + @JobID + ' ' + @IssueDescription
	
	EXEC DBA.dbo.sp_logMsg 1, 'Agent Job Config', 'Configuration Changes', @IssueDescription, NULL 
	
	--Get next exception.
	FETCH NEXT FROM curExceptions
	INTO @JobName, @JobID, @IssueDescription

END --End WHILE @@FETCH_STATUS = 0 (Looping through exceptions)

--Cleanup exceptions.
CLOSE curExceptions
DEALLOCATE curExceptions


GO


