INSERT INTO DBA.dbo.[Option]
(OptionLevel, OptionName, OptionValue, OptionDescription)
VALUES
('Server', 'AgentJobError_ONLY_DBA', 1, 'Setting this to 1 will cause the Agent History to only treat _DBA_* job failures as severity 4.  Other job failures will be severity 1.  Setting this to 0 will cause all job failures to be severity 4.')

USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_agntJobHist]    Script Date: 02/08/2017 1:10:43 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




ALTER PROCEDURE [dbo].[sp_agntJobHist]
AS

/******************************************

Update 11/8/2016 - Dustin Marzolf.
	Added logic to handle edge cases better without erroring out.
	Added logic to handle new option to only report severity 4 errors for _DBA_* Jobs
		instead of for all jobs.

*******************************************/

DECLARE @LastGathered DATETIME 
DECLARE @RightNow DATETIME

SET @LastGathered = ISNULL((SELECT MAX(DateStarted) FROM Data_AgentJobHistory WHERE DateStarted IS NOT NULL), DATEADD(week, -6, GETDATE()))
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
	AND H.run_status <> 4

--Find failed jobs.
DECLARE @JobID VARCHAR(200)
DECLARE @StepID VARCHAR(10)
DECLARE @JobName VARCHAR(200)
DECLARE @StepMessage VARCHAR(MAX)
DECLARE @LogMessage VARCHAR(MAX)
DECLARE @DateStarted DATETIME
DECLARE @DBAOnlySeverity4 BIT

SET @DBAOnlySeverity4 = CAST((SELECT ISNULL(DBA.dbo.fn_GetOptVal('Server', 'AgentJobError_ONLY_DBA'), '0')) AS BIT)

DECLARE curFailed CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT CAST(H.Job_ID AS VARCHAR(200))
		, CAST(H.StepID AS VARCHAR(10))
		, L.JobName
		, H.StepMessage
		, H.DateStarted 
	FROM Data_AgentJobHistory H
		INNER JOIN Data_AgentJobList L ON L.Job_ID = H.Job_ID
	WHERE DateGathered >= @RightNow
		AND H.RunStatus <> 1
		AND H.StepID <> 0
		AND (
			@DBAOnlySeverity4 = 0
			OR (@DBAOnlySeverity4 = 1
				AND L.JobName LIKE '_DBA_%')
			)
	ORDER BY H.Job_ID
		, H.StepID
		
OPEN curFailed
		
FETCH NEXT FROM curFailed
INTO @JobID, @StepID, @JobName, @StepMessage, @DateStarted

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @LogMessage = 'JobName: ' + @JobName + ' StepID: ' + @StepID + ' JobID: ' + @JobID + ' Error Message ' + @StepMessage
	
	EXEC DBA.dbo.sp_logMsg 4, 'Agent Job', 'Step Failed', @LogMessage, NULL, @DateStarted

	--Get the next failed step.
	FETCH NEXT FROM curFailed
	INTO @JobID, @StepID, @JobName, @StepMessage, @DateStarted

END --End WHILE @@FETCH_STATUS = 0 (Looping through failed steps)

--Cleanup
CLOSE curFailed
DEALLOCATE curFailed


GO


