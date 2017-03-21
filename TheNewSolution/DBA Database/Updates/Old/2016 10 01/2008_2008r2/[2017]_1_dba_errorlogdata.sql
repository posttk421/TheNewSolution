USE DBA
GO

IF OBJECT_ID('DBA.dbo.sp_GetSqlErrLog') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetSqlErrLog
END

IF OBJECT_ID('DBA.dbo.Data_SQLLog') IS NOT NULL
BEGIN
	DROP TABLE Data_SQLLog
END

GO

CREATE TABLE Data_SQLLog
	(
	ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, LogDate DATETIME
	, ProcessInfo VARCHAR(10)
	, [Text] VARCHAR(8000)
	, UserName VARCHAR(500) NULL
	, HostAddress VARCHAR(500) NULL
	, [Status] VARCHAR(20) NULL
	)

GO

CREATE CLUSTERED INDEX IX_Data_SQLLog_ServerName_LogDate ON Data_SQLLog (LogDate)

GO

CREATE PROCEDURE sp_GetSqlErrLog
AS

/**************************************
Name:		sp_GetSqlErrLog
Author:		Dustin Marzolf
Created:	02/08/2017

Purpose: To get all the data in the SQL Error Logs, place the data in a table for long term analysis, etc.

Inputs:		None
Outputs:	None

******************************************/

--0. Necessary Variables.
DECLARE @StartDate DATETIME
DECLARE @ArchiveNumber INT

--1. Determine when we last did this.

SET @StartDate = ISNULL((SELECT MAX(LogDate) FROM DBA.dbo.Data_SQLLog WHERE LogDate IS NOT NULL), '1/1/1900')

--2. Get a list of all log files.
IF OBJECT_ID('tempdb..#LogFiles') IS NOT NULL
BEGIN
	DROP TABLE #LogFiles;
END

CREATE TABLE #LogFiles
	(
	ArchiveNumber INT NULL
	, DateLog DATETIME NULL
	, LogFileSize BIGINT NULL
	)

INSERT INTO #LogFiles (ArchiveNumber, DateLog, LogFileSize)
EXEC master.sys.xp_enumerrorlogs;

--3. Iterate over each Log file that is newer than the Start Date
--		If Start Date is NULL then loop through all available.

DECLARE curLogFiles CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT ArchiveNumber
	FROM #LogFiles F
	WHERE ArchiveNumber = 0
		OR DateLog >= @StartDate
	ORDER BY DateLog ASC

OPEN curLogFiles;

FETCH NEXT FROM curLogFiles
INTO @ArchiveNumber;

WHILE @@FETCH_STATUS = 0
BEGIN

	--Temp to hold LogData.
	IF OBJECT_ID('tempdb..#LogData') IS NOT NULL
	BEGIN
		DROP TABLE #LogData;
	END

	CREATE TABLE #LogData 
		(
		LogDate DATETIME
		, ProcessInfo VARCHAR(10)
		, [Text] VARCHAR(8000)
		, UserName VARCHAR(500) NULL
		, HostAddress VARCHAR(500) NULL
		, [Status] VARCHAR(20) NULL
		);

	--Get the data from the log file.
	INSERT INTO #LogData (LogDate, ProcessInfo, [Text])
	EXEC sp_readerrorlog @ArchiveNumber;

	--Remove unnecessary Data.
	DELETE FROM #LogData
	WHERE LogDate <= DATEADD(MINUTE, -5, @StartDate)

	DELETE FROM #LogData
	WHERE EXISTS (	SELECT LogDate, ProcessInfo, [Text] 
					FROM Data_SQLLog 
					WHERE LogDate BETWEEN DATEADD(MINUTE, -5, @StartDate) AND  DATEADD(MINUTE, 5, @StartDate)
					)

	--Get UserName, HostAddress, Status for login data.
	UPDATE #LogData
	SET UserName = SUBSTRING([Text], CHARINDEX('''', [Text]) + 1, (CHARINDEX('''', [Text], CHARINDEX('''', [Text]) + 1) - CHARINDEX('''', [Text]) - 1))
		, HostAddress = SUBSTRING([Text], CHARINDEX('[', [Text]) + 1, (CHARINDEX(']', [Text], CHARINDEX('[', [Text]) + 1) - CHARINDEX('[', [Text]) - 1))
		, [Status] = CASE	WHEN [Text] LIKE 'Login failed%' THEN 'Failed'
							WHEN [Text] LIKE 'Login succeeded%' THEN 'Succeeded'
							ELSE NULL
							END
	WHERE ProcessInfo = 'Logon'
		AND (
			[Text] LIKE 'Login failed%'
			OR [Text] LIKE 'Login succeeded%'
			)

	--Put the data into the final destination table.
	INSERT INTO Data_SQLLog
	(LogDate, ProcessInfo, [Text], UserName, HostAddress, [Status])
	SELECT LogDate, ProcessInfo, [Text], UserName, HostAddress, [Status]
	FROM #LogData

	--Get next Archive Number
	FETCH NEXT FROM curLogFiles
	INTO @ArchiveNumber;

END --END WHILE @@FETCH_STATUS = 0

--Cleanup curLogFiles
CLOSE curLogFiles;
DEALLOCATE curLogFiles;

--Cleanup Temp Objects.
IF OBJECT_ID('tempdb..#LogFiles') IS NOT NULL
BEGIN
	DROP TABLE #LogFiles;
END
	
IF OBJECT_ID('tempdb..#LogData') IS NOT NULL
BEGIN
	DROP TABLE #LogData;
END

GO