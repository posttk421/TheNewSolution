IF OBJECT_ID('DBA.dbo.fn_JOBDurToSec') IS NOT NULL
BEGIN
	DROP FUNCTION fn_JOBDurToSec
END
GO

CREATE FUNCTION fn_JOBDurToSec
	(
	@run_duration INT
	)
RETURNS BIGINT
BEGIN

/********************
Name: fn_JOBDurToSec

Author: Dustin Marzolf
Created: 3/22/2016

Purpose: To convert the duration value from the msdb.dbo.sysjobhistory into seconds

**********************/

--Needed variables.
DECLARE @RetVal BIGINT
DECLARE @Time TIME 

IF ISNULL(@run_duration, 0) = 0
BEGIN
	RETURN 0
END

--Get the value as a time variable.
SET @Time = CAST(STUFF(STUFF(REPLACE(STR(@run_duration, 6), ' ', '0'), 3, 0, ':'), 6, 0, ':') AS time(0))

--Convert to seconds (hours, minutes, etc.)
SET @RetVal = (DATEPART(HOUR, @Time) * 60 * 60) + (DATEPART(MINUTE, @Time) * 60) + (DATEPART(SECOND, @Time))

RETURN @RetVal

END