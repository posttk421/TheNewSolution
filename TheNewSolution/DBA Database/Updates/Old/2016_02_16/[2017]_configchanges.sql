USE [DBA]

IF OBJECT_ID('DBA.dbo.Data_SQLConfigChanges') IS NOT NULL
BEGIN

	IF OBJECT_ID('tempdb..#TempData_SQLConfigChanges') IS NOT NULL
	BEGIN
		DROP TABLE #TempData_SQLConfigChanges
	END

	SELECT * INTO #TempData_SQLConfigChanges FROM Data_SQLConfigChanges 

	DROP TABLE Data_SQLConfigChanges
	
END

CREATE TABLE Data_SQLConfigChanges
	(
	ServerName SYSNAME DEFAULT @@SERVERNAME
	, TextData VARCHAR(500) NULL
	, HostName VARCHAR(155) NULL
	, ApplicationName VARCHAR(255) NULL
	, DatabaseName VARCHAR(155) NULL
	, LoginName VARCHAR(155) NULL
	, SPID INT NULL
	, DateStart DATETIME NULL
	, EventSequence INT NULL
	, FilePath VARCHAR(500) NULL
	)
	
IF OBJECT_ID('tempdb..#TempData_SQLConfigChanges') IS NOT NULL
BEGIN

	INSERT INTO Data_SQLConfigChanges
	SELECT * FROM #TempData_SQLConfigChanges

	DROP TABLE #TempData_SQLConfigChanges
	
END

	
GO

IF OBJECT_ID('DBA.dbo.sp_GetSQLConfigChanges') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetSQLConfigChanges
END

GO

CREATE PROCEDURE sp_GetSQLConfigChanges 
	(
	@SpecifiedFilePath VARCHAR(500) = NULL
	)
AS

/*******************
Name: sp_GetSQLConfigChanges

Author: Dustin Marzolf - based on scripts by Robert Pearl http://www.mssqltips.com/sqlservertip/2364/capturing-and-alerting-on-sql-server-configuration-changes/
Created: 4/15/2016

Purpose: To track changes in SQL Configuration.

Inputs:

	@SpecifiedFilePath VARCHAR(500) = NULL - A trace file to read.  If NULL then uses current trace file.  
		Otherwise will use what is loaded in.

********************/

SET NOCOUNT ON

--First, create table to hold new data.
IF OBJECT_ID('tempdb..#configchange') IS NOT NULL
BEGIN
	DROP TABLE #configchange
END

CREATE TABLE #configchange
	(
	TextData VARCHAR(500) NULL
	, HostName VARCHAR(155) NULL
	, ApplicationName VARCHAR(255) NULL
	, DatabaseName VARCHAR(155) NULL
	, LoginName VARCHAR(155) NULL
	, SPID INT NULL
	, DateStart DATETIME NULL
	, EventSequence INT NULL
	, FilePath VARCHAR(500) NULL
	)
	
--Other required variables.
DECLARE @LatestTraceFile VARCHAR(500)
DECLARE @LatestEntryDate DATETIME
DECLARE @CurrentTraceFile VARCHAR(500)

SELECT TOP 1 @LatestTraceFile = D.FilePath
			, @LatestEntryDate = D.DateStart
FROM DBA.dbo.Data_SQLConfigChanges D
ORDER BY D.DateStart DESC

SET @CurrentTraceFile = (	SELECT TOP 1 CAST(value AS VARCHAR(500)) 
							FROM fn_trace_getinfo(DEFAULT) 
							WHERE property=2
							ORDER BY traceid
							)
							
/** What are we doing?

	- If a specific trace file was indicated, then read that file.
	- If no specific trace file was read in, then see if there was a roll-over
		in the latest trace file, read that in.
	- Read the current trace file.
	
	**/
	
--We were told to import a very specific trace file.  
IF @SpecifiedFilePath IS NOT NULL
BEGIN

	--Get the Data.
	INSERT INTO #configchange
	(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence, FilePath)
	SELECT SUBSTRING(ISNULL(TextData, ' '), 1, 500)
		, HostName
		, ApplicationName
		, DatabaseName
		, LoginName
		, SPID
		, StartTime
		, EventSequence
		, @SpecifiedFilePath AS FilePath
	FROM fn_trace_gettable(@SpecifiedFilePath, 1) fn
	WHERE (	LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configure%'
			OR LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configuration%'
			)	
		AND NOT(LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%insert into%#configchange%')
		AND NOT(EventSequence IN (SELECT EventSequence FROM DBA.dbo.Data_SQLConfigChanges WHERE FilePath = @SpecifiedFilePath))
	ORDER BY StartTime DESC

END

--Specified File Path is blank and we have changed trace files since last run.
--Try to read the most recent (but not current) trace file.
IF @SpecifiedFilePath IS NULL AND @LatestTraceFile <> @CurrentTraceFile 
BEGIN

	BEGIN TRY
		--Get the Data.
		INSERT INTO #configchange
		(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence, FilePath)
		SELECT SUBSTRING(ISNULL(TextData, ' '), 1, 500)
			, HostName
			, ApplicationName
			, DatabaseName
			, LoginName
			, SPID
			, StartTime
			, EventSequence
			, @LatestTraceFile AS FilePath
		FROM fn_trace_gettable(@LatestTraceFile, 1) fn
		WHERE (	LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configure%'
				OR LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configuration%'
				)	
			AND NOT(LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%insert into%#configchange%')
			AND NOT(EventSequence IN (SELECT EventSequence FROM DBA.dbo.Data_SQLConfigChanges WHERE FilePath = @LatestTraceFile))
		ORDER BY StartTime DESC
	END TRY
	BEGIN CATCH
	END CATCH

END

--Read the current trace file.
IF @SpecifiedFilePath IS NULL
BEGIN

	--Get the Data.
	INSERT INTO #configchange
	(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence, FilePath)
	SELECT SUBSTRING(ISNULL(TextData, ' '), 1, 500)
		, HostName
		, ApplicationName
		, DatabaseName
		, LoginName
		, SPID
		, StartTime
		, EventSequence
		, @CurrentTraceFile AS FilePath
	FROM fn_trace_gettable(@CurrentTraceFile, 1) fn
	WHERE (	LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configure%'
			OR LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configuration%'
			)	
		AND NOT(LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%insert into%#configchange%')
		AND NOT(EventSequence IN (SELECT EventSequence FROM DBA.dbo.Data_SQLConfigChanges WHERE FilePath = @CurrentTraceFile))
	ORDER BY StartTime DESC
	
END


--Put the data into permanent storage.
INSERT INTO Data_SQLConfigChanges
(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence, FilePath)
SELECT TextData
	, HostName
	, ApplicationName
	, DatabaseName
	, LoginName
	, SPID
	, DateStart
	, EventSequence
	, FilePath
FROM #configchange

--Cleanup.	
IF OBJECT_ID('tempdb..#configchange') IS NOT NULL
BEGIN
	DROP TABLE #configchange
END


GO

EXEC DBA.dbo.sp_GetSQLConfigChanges