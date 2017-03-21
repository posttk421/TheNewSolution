USE [DBA]
GO

/****** Object:  UserDefinedFunction [dbo].[fn_JOBrunToDT]    Script Date: 02/08/2017 12:00:00 AM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[fn_JOBrunToDT]') AND type in (N'FN', N'IF', N'TF', N'FS', N'FT'))
DROP FUNCTION [dbo].[fn_JOBrunToDT]
GO

USE [DBA]
GO

/****** Object:  UserDefinedFunction [dbo].[fn_JOBrunToDT]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fn_JOBrunToDT]
	(
	@run_date INT
	, @run_time INT
	)
RETURNS DATETIME
BEGIN

/****************
Name: fn_JOBrunToDT

Author: Dustin Marzolf
Created: 3/20/2016

Purpose: converts msdb.dbo.sysjob tables run_date and run_time into a Date/Time

Inputs:

	@run_date INT - An integer representation of the Year, Month, Date in YYYMMDD format.
	@run_time INT - An integr representing the time

Outputs:

	A datetime value representing the run_date and run_time.
	
NOTES:

	Based on scripts by James Serra, http://www.jamesserra.com/archive/2011/06/easier-way-to-view-sql-server-job-history/

*****************/

--Necessary Variables.
DECLARE @RetVal DATETIME
DECLARE @RunDate DATE
DECLARE @RunTime VARCHAR(20)

--Exit Conditions.
IF ISNULL(@run_date, 0) = 0 OR ISNULL(@run_time, 0) = 0
BEGIN
	RETURN NULL
END

--Date Portion
SET @RunDate = CAST(CAST(@run_date AS VARCHAR(10)) AS DATE)

--Time Portion
SET @RunTime = CAST((@run_time + 1000000) AS VARCHAR(20))

SET @RunTime = SUBSTRING(@RunTime, 2, 2)
				+ ':' + SUBSTRING(@RunTime, 4, 2)
				+ ':' + SUBSTRING(@RunTime, 6, 2)
				
--Put it together.
SET @RetVal = CAST(DBA.dbo.fn_FrmtDate(@RunDate, 0) + ' ' + @RunTime AS DATETIME)

RETURN @RetVal

END
GO


