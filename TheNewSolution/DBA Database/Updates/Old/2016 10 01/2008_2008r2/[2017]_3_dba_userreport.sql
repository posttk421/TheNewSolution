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
	DateActivity DATE NULL
	, ServerName SYSNAME NOT NULL DEFAULT @@SERVERNAME
	, UserName VARCHAR(500) NULL
	, UserType CHAR(2) NULL
	, UserIsListed BIT NULL
	, HostAddress VARCHAR(500) NULL
	, [Status] VARCHAR(20) NULL
	, Time_Earliest TIME NULL
	, Time_Latest TIME NULL
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
DECLARE @DateStart DATE

--1. Set values.
SET @DateStart = ISNULL((SELECT MAX(DateActivity) FROM Data_SQLUserFrequency), '1/1/1900')

--2. Cleanup old data/check for running multiple times in same day.
--If the last time it was run is the same as today then delete.
IF @DateStart = CAST(GETDATE() AS DATE)
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
	, E.EarliestTime
	, E.LatestTime
	, E.CountForDay
FROM (
		SELECT CAST(D.LogDate AS DATE) AS DateLog
			, UserName
			, HostAddress
			, [Status]
			, MIN(CAST(D.LogDate AS TIME)) AS EarliestTime
			, MAX(CAST(D.LogDate AS TIME)) AS LatestTime
			, COUNT(D.LogDate) AS CountForDay
		FROM Data_SQLLog D 
		WHERE D.ProcessInfo = 'Logon'
			AND UserName IS NOT NULL
			AND D.LogDate >= @DateStart
		GROUP BY CAST(D.LogDate AS DATE)
			, UserName
			, HostAddress
			, [Status]
		) E
		LEFT OUTER JOIN sys.server_principals P ON LOWER(P.name) = LOWER(E.UserName)

GO

EXEC sp_GetSqlUsrFreqncy