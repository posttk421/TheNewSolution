USE DBA
GO

IF OBJECT_ID('DBA.dbo.sp_GetSqlUsrFreqncy') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetSqlUsrFreqncy
END

IF OBJECT_ID('DBA.dbo.Data_SQLUserFrequency') IS NOT NULL
BEGIN
	DROP TABLE Data_SQLUserFrequency
END

GO

CREATE TABLE Data_SQLUserFrequency
	(
	DateActivity DATETIME NULL
	, ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, UserName VARCHAR(500) NULL
	, UserType CHAR(2) NULL
	, UserIsListed BIT NULL
	, HostAddress VARCHAR(500) NULL
	, [Status] VARCHAR(20) NULL
	, Time_Earliest VARCHAR(20) NULL
	, Time_Latest VARCHAR(20) NULL
	, CountForDay INT NULL
	)

CREATE CLUSTERED INDEX IX_Data_SQLUserFrequency_DateActivity_UserName ON Data_SQLUserFrequency (DateActivity, UserName)

GO

CREATE PROCEDURE sp_GetSqlUsrFreqncy
AS

/**************************************
Name:		sp_GetSqlUsrFreqncy
Author:		Dustin Marzolf
Created:	02/08/2017

Purpose: To harvest login data from Data_SQLLog and summarize it for easier reporting

Inputs: NONE
Outputs: NONE

**************************************/

--0. Declare Variables
DECLARE @DateStart DATETIME

--1. Set values.
SET @DateStart = ISNULL((SELECT DBA.dbo.fnTrimTime(MAX(DateActivity)) FROM Data_SQLUserFrequency WHERE DateActivity IS NOT NULL), '1/1/1900')

--2. Cleanup old data/check for running multiple times in same day.
--If the last time it was run is the same as today then delete.
IF @DateStart = DBA.dbo.fnTrimTime(GETDATE())
BEGIN
	DELETE FROM Data_SQLUserFrequency
	WHERE DateActivity = @DateStart
END

--Delete yesterday's data because it may be stale
SET @DateStart = DATEADD(DAY, -1, @DateStart)

DELETE FROM Data_SQLUserFrequency
WHERE DateActivity >= @DateStart

-- 3. Insert the data into the storage table.
INSERT INTO Data_SQLUserFrequency
(DateActivity, UserName, UserType, UserIsListed, HostAddress
	, [Status], Time_Earliest, Time_Latest, CountForDay)
SELECT E.DateLog
	, E.UserName
	, P.[type]
	, UserIsListed = CASE WHEN P.principal_id IS NULL THEN 0 ELSE 1 END
	, E.HostAddress
	, E.[Status]
	, DBA.dbo.fn_FrmtTime(E.EarliestTime, 1)
	, DBA.dbo.fn_FrmtTime(E.LatestTime, 1)
	, E.CountForDay
FROM (
		SELECT DBA.dbo.fnTrimTime(D.LogDate) AS DateLog
			, UserName
			, HostAddress
			, [Status]
			, MIN(D.LogDate) AS EarliestTime
			, MAX(D.LogDate) AS LatestTime
			, COUNT(D.LogDate) AS CountForDay
		FROM Data_SQLLog D 
		WHERE D.ProcessInfo = 'Logon'
			AND UserName IS NOT NULL
			AND D.LogDate >= @DateStart
		GROUP BY DBA.dbo.fnTrimTime(D.LogDate)
			, UserName
			, HostAddress
			, [Status]
		) E
		LEFT OUTER JOIN sys.server_principals P ON LOWER(P.name) = LOWER(E.UserName)

GO

EXEC sp_GetSqlUsrFreqncy

