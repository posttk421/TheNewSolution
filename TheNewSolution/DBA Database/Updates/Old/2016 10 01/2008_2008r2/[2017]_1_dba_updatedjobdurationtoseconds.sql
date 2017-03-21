USE [DBA]
GO

/****** Object:  UserDefinedFunction [dbo].[fn_JOBDurToSec]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[fn_JOBDurToSec]
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

Update: 11/7/2016 - Dustin
	Updated logic so that it would return NULL for all values over 90,000 would return NULL.  
	This value is 9 hours.  Values over this would cause the function to blow up.  

**********************/

--Needed variables.
DECLARE @RetVal BIGINT
DECLARE @Time TIME 

IF ISNULL(@run_duration, 0) = 0
BEGIN
	RETURN 0
END

IF ABS(@run_duration) > 90000
BEGIN
	RETURN NULL
END

--Get the value as a time variable.
SET @Time = CAST(STUFF(STUFF(REPLACE(STR(@run_duration, 6), ' ', '0'), 3, 0, ':'), 6, 0, ':') AS time(0))

--Convert to seconds (hours, minutes, etc.)
SET @RetVal = (DATEPART(HOUR, @Time) * 60 * 60) + (DATEPART(MINUTE, @Time) * 60) + (DATEPART(SECOND, @Time))

RETURN @RetVal

END

GO

