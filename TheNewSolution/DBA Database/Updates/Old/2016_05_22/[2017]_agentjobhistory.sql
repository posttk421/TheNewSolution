USE DBA

IF OBJECT_ID('DBA.dbo.Data_AgentJobHistory') IS NOT NULL
BEGIN
	DROP TABLE DBA.dbo.Data_AgentJobHistory
END

IF OBJECT_ID('DBA.dbo.sp_agntJobHist') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_agntJobHist
END 

GO

CREATE TABLE Data_AgentJobHistory
	(
	ServerName SYSNAME NOT NULL
	, Job_ID UNIQUEIDENTIFIER NOT NULL
	, DateGathered DATETIME
	, StepID INT NOT NULL
	, StepName VARCHAR(500) NULL
	, StepMessage VARCHAR(MAX) NULL
	, RunStatus INT NULL
	, DateStarted DATETIME NULL
	, RunDuration_Second BIGINT NULL
	)
	
GO

CREATE PROCEDURE sp_agntJobHist
AS

DECLARE @LastGathered DATETIME 
DECLARE @RightNow DATETIME

SET @LastGathered = ISNULL((SELECT MAX(DateStarted) FROM Data_AgentJobHistory), DATEADD(week, -6, GETDATE()))
SET @RightNow = GETDATE()

INSERT INTO Data_AgentJobHistory
(ServerName, Job_ID, DateGathered, StepID, StepName, StepMessage, RunStatus, DateStarted, RunDuration_Second)
SELECT @@SERVERNAME
	, H.job_id
	, @RightNow
	, H.step_id
	, H.step_name
	, H.[message]
	, H.run_status
	, DBA.dbo.fn_JOBrunToDT(H.run_date, H.run_time)
	, DBA.dbo.fn_JOBDurToSec(H.run_duration)
FROM msdb.dbo.sysjobhistory H
WHERE DBA.dbo.fn_JOBrunToDT(H.run_date, H.run_time) >= @LastGathered

--Find failed jobs.
DECLARE @JobID VARCHAR(200)
DECLARE @StepID VARCHAR(10)
DECLARE @JobName VARCHAR(200)
DECLARE @StepMessage VARCHAR(MAX)
DECLARE @LogMessage VARCHAR(MAX)

DECLARE curFailed CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT CAST(H.Job_ID AS VARCHAR(200))
		, CAST(H.StepID AS VARCHAR(10))
		, L.JobName
		, H.StepMessage
	FROM Data_AgentJobHistory H
		INNER JOIN Data_AgentJobList L ON L.Job_ID = H.Job_ID
	WHERE DateGathered >= @RightNow
		AND H.RunStatus <> 1
		AND H.StepID <> 0
	ORDER BY H.Job_ID
		, H.StepID
		
OPEN curFailed
		
FETCH NEXT FROM curFailed
INTO @JobID, @StepID, @JobName, @StepMessage

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @LogMessage = 'JobName: ' + @JobName + ' StepID: ' + @StepID + ' JobID: ' + @JobID + ' Error Message ' + @StepMessage
	
	EXEC DBA.dbo.sp_logMsg 4, 'Agent Job', 'Step Failed', @LogMessage, NULL

	--Get the next failed step.
	FETCH NEXT FROM curFailed
	INTO @JobID, @StepID, @JobName, @StepMessage

END --End WHILE @@FETCH_STATUS = 0 (Looping through failed steps)

--Cleanup
CLOSE curFailed
DEALLOCATE curFailed