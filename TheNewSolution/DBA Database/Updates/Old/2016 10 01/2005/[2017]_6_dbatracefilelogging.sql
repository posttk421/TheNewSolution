USE DBA
GO

IF OBJECT_ID('DBA.dbo.sp_GetSqlTrcInfo') IS NOT NULL
BEGIN 
	DROP PROCEDURE sp_GetSqlTrcInfo
END

IF OBJECT_ID('DBA.dbo.fn_GetSQLTraceFiles') IS NOT NULL
BEGIN 
	DROP FUNCTION fn_GetSQLTraceFiles
END

IF OBJECT_ID('DBA.dbo.Data_SQLTrace') IS NOT NULL
BEGIN 
	DROP TABLE Data_SQLTrace
END

IF OBJECT_ID('DBA.dbo.Mnt_SQLTraceFile') IS NOT NULL
BEGIN 
	DROP TABLE Mnt_SQLTraceFile
END

GO

CREATE TABLE Data_SQLTrace
	(
	ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, TextData VARCHAR(500) NULL
	, HostName VARCHAR(155) NULL
	, ApplicationName VARCHAR(255) NULL
	, DatabaseName VARCHAR(155) NULL
	, LoginName VARCHAR(155) NULL
	, SPID INT NULL
	, DateStart DATETIME NULL
	, EventSequence INT NULL
	, ObjectID INT NULL
	, ObjectID2 BIGINT  NULL
	, ObjectName NVARCHAR(500) NULL
	, ObjectType INT NULL
	, FileID UNIQUEIDENTIFIER NULL
	, EventCategory_Desc VARCHAR(100) NULL
	, GatheringNotes VARCHAR(MAX) NULL
	)

CREATE CLUSTERED INDEX IX_Data_SQLTrace_DateStart_EventSequence ON Data_SQLTrace (DateStart, EventSequence)

GO

CREATE TABLE Mnt_SQLTraceFile
	(
	FileID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY
	, FilePath VARCHAR(500) NOT NULL
	, Start_Time DATETIME NULL
	, DateLastRead DATETIME NULL
	, IsValid BIT NOT NULL DEFAULT 1
	)


CREATE NONCLUSTERED INDEX NIX_Mnt_SQLTraceFile_Start_Time ON Mnt_SQLTraceFile (Start_Time) INCLUDE (FilePath)

GO

IF OBJECT_ID('DBA.dbo.Data_SQLConfigChanges') IS NOT NULL
BEGIN

	--Get as many old trace files as possible...
	INSERT INTO Mnt_SQLTraceFile
	(FilePath, Start_Time, DateLastRead)
	SELECT FilePath, MIN(DateStart), MAX(DateStart)
	FROM Data_SQLConfigChanges
	GROUP BY FilePath
	ORDER BY MIN(DateStart)

	--Save over as much data as possible...
	INSERT INTO Data_SQLTrace
	(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence, FileID)
	SELECT D.TextData
		, D.HostName
		, D.ApplicationName
		, D.DatabaseName
		, D.LoginName
		, D.SPID
		, D.DateStart
		, D.EventSequence
		, M.FileID
	FROM Data_SQLConfigChanges D
		LEFT OUTER JOIN Mnt_SQLTraceFile M ON M.FilePath = D.FilePath
	ORDER BY DateStart, EventSequence

END

GO

CREATE FUNCTION fn_GetSQLTraceFiles()
RETURNS @TraceFiles TABLE
	(
	FilePath VARCHAR(500) NULL
	, Start_Time DATETIME NULL
	)
AS
BEGIN

	/***********************************
	Name: fn_GetSQLTraceFiles
	Author: Dustin Marzolf
	Created: 11/1/2016

	Purpose: To return a table of trace files to read.

	Inputs: NONE
	Outputs: TABLE showing FilePath and Start_Time

	Notes: This function will look at the sys.traces table and attempt to determine
		what the names of the prior trace files were.  It assumes that trace files
		will be named with a number at the end and that the max_files is accurate.
		So if the last file was named log_5252, it would return that one as well as
		log_5251, log_5250, etc.

	*************************************/

	--0. Necessary variables.
	DECLARE @CurrentFullNameAndPath VARCHAR(500)
	DECLARE @MaxFiles INT
	DECLARE @TempName VARCHAR(100)
	DECLARE @CurrentFileNumber INT
	DECLARE @CurrentFileName VARCHAR(100)
	DECLARE @CurrentPath VARCHAR(500)
	DECLARE @i INT
	DECLARE @OldestStart DATETIME

	--1. Get the latest trace file name.
	SELECT TOP 1 
		@CurrentFullNameAndPath = [path]
		, @MaxFiles = max_files
	FROM sys.traces
	ORDER BY start_time
		
	--2. Parse the name to determine the various pieces of it.
	--Path, File Number, File Name, etc.
	SET @CurrentFileName = REVERSE(left(REVERSE(@CurrentFullNameAndPath), CHARINDEX('\', REVERSE(@CurrentFullNameAndPath)) -1))
	SET @CurrentPath = REPLACE(@CurrentFullNameAndPath, @CurrentFileName, '')
	SET @TempName = REPLACE(@CurrentFileName, '.trc', '')
	SET @CurrentFileNumber = CAST(REVERSE(left(REVERSE(@TempName), CHARINDEX('_', REVERSE(@TempName)) -1)) AS INT)
	SET @TempName = REPLACE(@CurrentFileName, CAST(@CurrentFileNumber AS VARCHAR(10)) + '.trc', '')
	SET @i = 1

	--3. Cycle through all possible names...
	WHILE @i <= @MaxFiles AND @CurrentFileNumber > 0
	BEGIN

		INSERT INTO @TraceFiles (FilePath)
		VALUES (@CurrentPath + @TempName + CAST(@CurrentFileNumber AS VARCHAR(10)) + '.trc')

		SET @CurrentFileNumber = @CurrentFileNumber - 1

		SET @i = @i + 1

	END

	--4. Make sure we get all of them (in case sys.traces contains more than one file).
	INSERT INTO @TraceFiles (FilePath)
	SELECT T.[path]
	FROM sys.traces T
	WHERE NOT(T.[path] IN (SELECT FilePath FROM @TraceFiles))

	--5. Get ancillary data about the trace files.
	UPDATE @TraceFiles
	SET Start_Time = T.start_time
	FROM @TraceFiles F
		INNER JOIN sys.traces T ON T.[path] = F.FilePath

	--6. Set the start times for files we determined by programmatic means
	SET @OldestStart = (SELECT MIN(Start_Time) FROM @TraceFiles)

	IF @OldestStart IS NOT NULL
	BEGIN
		SET @OldestStart = DATEADD(MINUTE, -1, @OldestStart)
	END

	IF @OldestStart IS NULL
	BEGIN
		SET @OldestStart = GETDATE()
	END
	
	UPDATE @TraceFiles
	SET Start_Time = @OldestStart
	WHERE Start_Time IS NULL
						
	--7. Return.
	RETURN;

END

GO

CREATE PROCEDURE sp_GetSqlTrcInfo
AS

/*******************************************
Name:	sp_GetSqlTrcInfo
Author: Dustin Marzolf
Create: 02/08/2017

Purpose: Read SQL Trace data and gather interesting bits

Inputs:	 NONE
Outputs: NONE

Notes:

	This process works by looking at the trace file used by SQL.  It attempts to gather data
	on the following events.  More events can be added later.

	You can query sys.trace_events for a list of all traces.

	Event 22 - Configuration Changes
	Event 92, 93 - Auto-Growth Events
	Event 164,46,47 - Object Creation, Deletion and Alteration
	Event 162 - User Error Messages
	Event 213 - Database Suspect Data Page
	Event 20 - Login Failures

**********************************************/

/****
Phase 1 - Manage the Trace Files
*****/

BEGIN TRY
	
	INSERT INTO Mnt_SQLTraceFile
	(FilePath, Start_Time)
	SELECT FilePath, Start_Time FROM fn_GetSQLTraceFiles() F
	WHERE NOT(F.FilePath IN (SELECT M.FilePath FROM Mnt_SQLTraceFile M))

END TRY
BEGIN CATCH

	INSERT INTO Mnt_SQLTraceFile
	(FilePath, Start_Time)
	SELECT [path], start_time
	FROM sys.traces T
	WHERE NOT(T.[path] IN (SELECT M.FilePath FROM Mnt_SQLTraceFile M))

END CATCH

/*****
Phase 2 - Get the Actual Trace Events
******/
DECLARE @DateStart DATETIME
DECLARE @FileID UNIQUEIDENTIFIER
DECLARE @FilePath VARCHAR(500)

SET @DateStart = ISNULL((SELECT MAX(DateLastRead) FROM Mnt_SQLTraceFile), '1/1/1900')

DECLARE curTraceFile CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT FileID, FilePath
	FROM Mnt_SQLTraceFile
	WHERE IsValid = 1
		AND (DateLastRead IS NULL
			OR DateLastRead >= @DateStart
			)
	ORDER BY Start_Time

OPEN curTraceFile

FETCH NEXT FROM curTraceFile
INTO @FileID, @FilePath

WHILE @@FETCH_STATUS = 0
BEGIN

	--Temp table to hold data...
	IF OBJECT_ID('tempdb..#TraceData') IS NOT NULL
	BEGIN
		DROP TABLE #TraceData
	END

	CREATE TABLE #TraceData
		(
		TextData VARCHAR(500) NULL
		, HostName VARCHAR(155) NULL
		, ApplicationName VARCHAR(255) NULL
		, DatabaseName VARCHAR(155) NULL
		, LoginName VARCHAR(155) NULL
		, SPID INT NULL
		, DateStart DATETIME NULL
		, EventSequence INT NULL
		, ObjectID INT NULL
		, ObjectID2 BIGINT  NULL
		, ObjectName NVARCHAR(500) NULL
		, ObjectType INT NULL
		, GatheringNotes VARCHAR(MAX) NULL
		, EventCategory_Desc VARCHAR(100) NULL
		)

	BEGIN TRY

		INSERT INTO #TraceData
		(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence
			, ObjectID, ObjectID2, ObjectName, ObjectType, GatheringNotes, EventCategory_Desc)
		SELECT SUBSTRING(ISNULL(TextData, ' '), 1, 500)
			, HostName
			, ApplicationName
			, DatabaseName
			, LoginName
			, SPID
			, StartTime
			, EventSequence
			, ObjectID
			, ObjectID2
			, ObjectName
			, ObjectType
			, GatheringNotes = CASE WHEN fn.EventClass = 92 THEN 'Data File Growth, ' + CAST((fn.IntegerData * 8)/1024.0 AS VARCHAR(50)) + ' MB, ' + CAST(fn.duration/1000000.0 AS VARCHAR(50)) + ' Seconds.'
									WHEN fn.EventClass = 93 THEN 'Log File Growth, ' + CAST((fn.IntegerData * 8)/1024.0 AS VARCHAR(50)) + ' MB, ' + CAST(fn.duration/1000000.0 AS VARCHAR(50)) + ' Seconds.'
									END
			, EventCategory_Desc = TE.name
		FROM fn_trace_gettable(@FilePath, 1) fn
			LEFT OUTER JOIN sys.trace_events TE ON TE.trace_event_id = fn.EventClass
		WHERE NOT(EventSequence IN (SELECT T.EventSequence FROM Data_SQLTrace T WHERE FileID = @FileID))
			AND (
					(
						fn.EventClass = 22
						AND fn.DatabaseName = 'master'
						AND LOWER(CAST(TextData AS VARCHAR(MAX))) LIKE '%configuration%'
					)
					OR
					(
						fn.EventClass IN (92,93)
					)
					OR
					(
						fn.EventClass IN (164,46,47)
						AND fn.DatabaseName <> 'tempdb'
					)
					OR
					(
						fn.EventClass = 162
					)
					OR
					(
						fn.EventClass = 213
					)
					OR
					(
						fn.EventClass = 20
					)
				)

		INSERT INTO Data_SQLTrace
		(TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence
			, ObjectID, ObjectID2, ObjectName, ObjectType, GatheringNotes, EventCategory_Desc, FileID)
		SELECT TextData, HostName, ApplicationName, DatabaseName, LoginName, SPID, DateStart, EventSequence
			, ObjectID, ObjectID2, ObjectName, ObjectType, GatheringNotes, EventCategory_Desc, @FileID
		FROM #TraceData
		ORDER BY DateStart
				
	END TRY
	BEGIN CATCH

		-- The file was unable to be read, so it doesn't exist anymore.
		UPDATE Mnt_SQLTraceFile
		SET IsValid = 0
		WHERE FileID = @FileID

	END CATCH
	
	--Update Trace File Statistics.
	UPDATE Mnt_SQLTraceFile
	SET DateLastRead = GETDATE()
	WHERE FileID = @FileID
	
	--Next record...
	FETCH NEXT FROM curTraceFile
	INTO @FileID, @FilePath

	--Wait 1 second...
	WAITFOR DELAY '00:00:01'

END --Looping through curTraceFile

--Cleanup.
CLOSE curTraceFile
DEALLOCATE curTraceFile

IF OBJECT_ID('tempdb..#TraceData') IS NOT NULL
BEGIN
	DROP TABLE #TraceData
END

--Additional Actions.
DECLARE @DbName VARCHAR(100)

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT DISTINCT DatabaseName
	FROM Data_SQLTrace 
	WHERE DateStart >= @DateStart 
		AND EventCategory_Desc IN ('Data File Auto Grow', 'Log File Auto Grow')

OPEN curDB

FETCH NEXT FROM curDB 
INTO @DbName

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC sp_GetMntDBFile @DbName

END

CLOSE curDB
DEALLOCATE curDB

GO



