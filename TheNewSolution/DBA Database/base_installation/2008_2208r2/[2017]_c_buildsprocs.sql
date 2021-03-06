USE [DBA]
GO
/****** Object:  StoredProcedure [dbo].[sp_AskBrent]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[sp_AskBrent]
    @Question NVARCHAR(MAX) = NULL ,
    @AsOf DATETIME = NULL ,
	@ExpertMode TINYINT = 0 ,
    @Seconds TINYINT = 5 ,
    @OutputType VARCHAR(20) = 'TABLE' ,
    @OutputDatabaseName NVARCHAR(128) = NULL ,
    @OutputSchemaName NVARCHAR(256) = NULL ,
    @OutputTableName NVARCHAR(256) = NULL ,
    @OutputXMLasNVARCHAR TINYINT = 0 ,
    @Version INT = NULL OUTPUT,
    @VersionDate DATETIME = NULL OUTPUT
    WITH EXECUTE AS CALLER, RECOMPILE
AS 
BEGIN
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*
sp_AskBrent (TM)

(C) 2016, Brent Ozar Unlimited. 
See http://BrentOzar.com/go/eula for the End User Licensing Agreement.

Sure, the server needs tuning - but why is it slow RIGHT NOW?
sp_AskBrent performs quick checks for things like:

* Blocking queries that have been running a long time
* Backups, restores, DBCCs
* Recently cleared plan cache
* Transactions that are rolling back

To learn more, visit http://www.BrentOzar.com/askbrent/ where you can download
new versions for free, watch training videos on how it works, get more info on
the findings, and more.  To contribute code and see your name in the change
log, email your improvements & checks to Help@BrentOzar.com.

Known limitations of this version:
 - No support for SQL Server 2000 or compatibility mode 80.
 - If a temp table called #CustomPerfmonCounters exists for any other session,
   but not our session, this stored proc will fail with an error saying the
   temp table #CustomPerfmonCounters doesn't exist.

Unknown limitations of this version:
 - None. Like Zombo.com, the only limit is yourself.

Changes in v9 - Nov 3, 2016
 - Changed date format to accommodate the British. They gave us Gordon Ramsay,
   so it's the least I could do. Many folks reported this one.

Changes in v8 - October 21, 2016
 - Whoops! Left an extra line in check 8 that failed on SQL 2005.

Changes in v7 - October 21, 2016
 - Updated many of the links to point to newly published pages.
 - Performance tuning Check 8 (sleeping connections with open transactions).
   Went from >1 minute at StackExchange to <10 seconds.

Changes in v6 - October 11, 2016
 - Time travel enabled. Can log to database using the @Output* parameters, and
   you can go back in time with the @AsOf parameter.
 - Bug fixing for SQL Server 2005 compatibility.

Changes in v5 - September 16, 2016
 - Enabled @Question again.
 - Bail out of plan cache analysis if we're more than 10 seconds behind.

Changes in v4 - August 25, 2016
 - Added plan cache analysis.
 - Fixed checkid 8 (sleeping query with open transactions) for SQL 2005/08/R2.
 - Refactored a little for readability.
 - Added QueryPlan to the default results because the plan cache stuff is cool.

Changes in v3 - August 23, 2016
 - Added @OutputType = 'SCHEMA', which returns the version number and a list
   of columns for a CREATE TABLE definition for the default outputs. We don't
   include the actual CREATE TABLE part because you might want to use a table
   variable or whatever.
 - Added @OutputXMLasNVARCHAR. If 1, then the QueryPlan is outputted as an
   NVARCHAR(MAX) instead of XML. This helps if you want to insert the
   sp_AskBrent results into a temp table. For instructions, visit:

Changes in v2 - August 9, 2016
 - Added @Seconds to control the sampling time.
 - @ExpertMode now returns all work tables with no thresholds.
 - Added basic wait stats, file stats, Perfmon checks.

Changes in v1 - July 11, 2016
 - Initial bug-filled release. We Output:
	@logincreate VARCHAR(MAX) - the script that creates the indicated login.
	
********************************************/

SET NOCOUNT ON

--Clean up Inputs, make sure the user exists.
--If the input name is an empty string then set it to NULL.
IF LTRIM(RTRIM(ISNULL(@LoginName, ''))) = ''
BEGIN
	SET @LoginName = NULL
END

--Make sure the requested login exists.
IF NOT EXISTS (	SELECT * 
				FROM sys.server_principals 
				WHERE name = ISNULL(@LoginName, '')
					AND type IN ('G','U','S')
				)
BEGIN 
	
	--Return 
	SET @Script = '-- Specified user: ' + ISNULL(@LoginName, '<no login specified>') + ' does not exist.'
	RETURN 
	
END

/******************************************************************************************/
--Begin actual work
--This Section deals with the actual login creation settings, SID, PWD, Default Database and Language, etc.
/******************************************************************************************/

--Variables Needed to formulate creation string...
DECLARE @LoginSID VARBINARY(85)
DECLARE @SID_String VARCHAR(514)
DECLARE @LoginPWD VARBINARY(256)
DECLARE @PWD_String VARCHAR(514)
DECLARE @LoginType CHAR(1)
DECLARE @is_disabled BIT
DECLARE @default_database_name SYSNAME
DECLARE @default_language_name SYSNAME
DECLARE @is_policy_checked BIT
DECLARE @is_expiration_checked BIT
DECLARE @createdDateTime DATETIME

SELECT @LoginSID = P.[sid]
	, @LoginType = P.[type]
	, @is_disabled = P.is_disabled 
	, @default_database_name = P.default_database_name 
	, @default_language_name = P.default_language_name 
	, @createdDateTime = P.create_date 
FROM sys.server_principals P
WHERE P.name = @LoginName

/** Some Output **/
SET @Script = ''
SET @Script = @Script + '/*************/'
SET @Script = @Script + CHAR(13) + '/** Login Creation Script for: ' + @LoginName + ' **/'
SET @Script = @Script + CHAR(13) + '/** Created On: ' + DBA.dbo.fn_FrmtDate(@createdDateTime, 0) + ' ' + DBA.dbo.fn_FrmtTime(@createdDateTime, 0) + ' **/'
SET @Script = @Script + CHAR(13) + '/*************/' + CHAR(13)

/** Output Enabled/Disabled **/
SET @Script = @Script + CHAR(13)	
				+ '-- Login [' + @LoginName + '] IS '
				+ CASE	WHEN @is_disabled = 1 THEN 'DISABLED'
						ELSE 'ENABLED'
						END

--If the login is a SQL Login, then do a lot of stuff...
IF @LoginType = 'S'
BEGIN
	
	SET @LoginPWD = CAST(LOGINPROPERTY(@LoginName, 'PasswordHash') AS VARBINARY(256))
	
	EXEC sp_HexaDecimal @LoginPWD, @PWD_String OUT	
	EXEC sp_HexaDecimal @LoginSID, @SID_String OUT
	
	SELECT @is_policy_checked = S.is_policy_checked
		, @is_expiration_checked = S.is_expiration_checked
	FROM sys.sql_logins S
	
	/** Create Script **/
	SET @Script = @Script + CHAR(13) + CHAR(13)
					+ 'CREATE LOGIN ' + QUOTENAME(@LoginName)
					+ CHAR(13) + CHAR(9) + 'WITH PASSWORD = ' + @PWD_String + ' HASHED'
					+ CHAR(13) + CHAR(9) + ', SID = ' + @SID_String
					+ CHAR(13) + CHAR(9) + ', DEFAULT_DATABASE = [' + @default_database_name + ']'
					+ CHAR(13) + CHAR(9) + ', DEFAULT_LANGUAGE = [' + @default_language_name + ']'
					+ CHAR(13) + CHAR(9) + ', CHECK_POLICY ' + CASE WHEN @is_policy_checked = 0 THEN '=OFF' ELSE '=ON' END
					+ CHAR(13) + CHAR(9) + ', CHECK_EXPIRATION ' + CASE WHEN @is_expiration_checked = 0 THEN '=OFF' ELSE '=ON' END
					
	SET @Script = @Script + CHAR(13) + CHAR(13)
					+ 'ALTER LOGIN [' + @LoginName + ']'
					+ CHAR(13) + CHAR(9) + 'WITH DEFAULT_DATABASE = [' + @default_database_name + ']'
					+ CHAR(13) + CHAR(9) + ', DEFAULT_LANGUAGE = [' + @default_language_name + ']'
		
END
ELSE
BEGIN

	--The login is a NT login (or group).
	SET @Script = @Script + CHAR(13) + CHAR(13)
					+ 'CREATE LOGIN ' + QUOTENAME(@LoginName) + ' FROM WINDOWS'
					+ CHAR(13) + CHAR(9) + ', DEFAULT_DATABASE = [' + @default_database_name + ']'

END

/******************************************************************************************/
--This section deals with the Server Roles that belong to that login...
/******************************************************************************************/

DECLARE @ServerRoles TABLE
	(
	ServerRole SYSNAME
	, MemberName SYSNAME
	, MemberSID VARBINARY(85)
	)
	
INSERT INTO @ServerRoles EXEC sp_helpsrvrolemember

/** Output to script... **/
SET @Script = @Script + CHAR(13) + CHAR(13)
SET @Script = @Script + '/** Server Roles **/'

--Test if there are any server roles for this login...
IF EXISTS(SELECT 1 FROM @ServerRoles WHERE MemberName = @LoginName)
BEGIN

	SET @Script = @Script + CHAR(13)

	DECLARE @ServerRole SYSNAME
	DECLARE curRoles CURSOR LOCAL STATIC FORWARD_ONLY
	
	FOR SELECT ServerRole 
		FROM @ServerRoles
		WHERE MemberName = @LoginName
		
	OPEN curRoles
	
	FETCH NEXT FROM curRoles
	INTO @ServerRole
	
	WHILE @@FETCH_STATUS = 0
	BEGIN
	
		/** Output to Script **/
		SET @Script = @Script 
						+ CHAR(13) + '-- Role: ' + @ServerRole
						+ CHAR(13) + 'EXEC sp_addsrvrolemember ' + QUOTENAME(@LoginName, '''') + ', ' + QUOTENAME(@ServerRole, '''')
	
		FETCH NEXT FROM curRoles
		INTO @ServerRole
		
	END
	
	--Cleanup.
	CLOSE curRoles
	DEALLOCATE curRoles

END
ELSE
BEGIN

	--There are no roles defined for this login.
	SET @Script = @Script + CHAR(13) + CHAR(13)
					+ '-- Login [' + @LoginName + '] does not have any defined server roles.'

END


GO
/****** Object:  StoredProcedure [dbo].[sp_logMsg]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[sp_logMsg]
	(
	@MessageSeverity INT
	, @MessageType VARCHAR(50)
	, @MessageShort VARCHAR(200)
	, @MessageLong VARCHAR(MAX)
	, @GeneratedBy VARCHAR(100)
	, @DateMessage DATETIME = NULL
	)
AS

/******************

Name: sp_logMsg

Author: Dustin Marzolf

Created: 1/31/2016

Purpose: To ease logging messages from various processes.

Updated: 4/26/2016 - Dustin Marzolf
	Added ability to e-mail messages on severity 4 items as they occurred.
	Added logic to check for duplicate messages and not log them if they occurr within
		a short timeframe.

Updated: 5/9/2016 - Dustin
	Added @DateMessage parameter, allowing to specify when a message was created.
		Default value is NULL and will then be set to the current date/time if NULL.
		Useful when scanning through the agent job history and you want to put in the 
		date/time the message occurred rather than when it was logged.

Inputs:
	@MessageSeverity INT - The severity of the message, 0-4 are approved values (see notes)
	@MessageType VARCHAR(50) - The message type (see notes for pre-approved types)
	@MessageShort VARCHAR(200) - The short description of the message.
	@Messagelong VARCHAR(MAX) - The long description of the message.
	@GeneratedBy VARCHAR(100) - The name of the originating process.
	
Output:
	None

Update 11/8/2016 - Dustin Marzolf
	Added @FromAddress to be generated programmatically.  Will now always show the servername 
		when e-mail is sent from this procedure.

*******************/

/**************
Notes

@MessageSeverity INT

The message severity is designed to indiate how severe the message is.  The following is the approved values.
Supported values are IntMin to IntMax, recommended values are listed below.

0 - Informational: The system is talking to itself, use for recording that a process ran at a certain time and no issues were found, etc.

1 - Low: an issue was discovered, but it's potential impact to the security, integrity and functionality of the database
	is limited.  Examples include notifications about indexes not being defragmented, etc.

2 - Medium: medium severity items.

3 - High: highly critical items.

4 - Critical: Extemely critical issues.  Examples include full disks, and other issues that would immediately affect the security, integrity and functionality 
	of the database.  Critical Issues will be logged but an e-mail will also attempt to be sent regarding the issue.  
	
If provided value is NULL, will default to 0 (Informational)
If provided value is negative, will use the absolute value (unsigned)
	
============================================================

@MessgeType VARCHAR(50)

An indication about the type of message.  Examples are listed below.  When recording a message, try and re-use types if appropriate.

--Find all types used before:
SELECT DISTINCT MessageType FROM Info_Message ORDER BY MessageType

Types:
- LoginSecurity
- PhysicalDisk
- LinkedServer

If value is NULL or blank, will be set to <Unknown>

============================================================

@GeneratedBy VARCHAR(100)

If value is NULL or blank, will be set to the SYSTEM_USER (owner of current thread) variable.

***************/

--Fix data
IF @MessageSeverity IS NULL
BEGIN
	SET @MessageSeverity = 0
END
SET @MessageSeverity = ABS(@MessageSeverity)

IF ISNULL(@MessageType, '') = ''
BEGIN
	SET @MessageType = '<Unknown>'
END

IF ISNULL(@GeneratedBy, '') = ''
BEGIN
	SET @GeneratedBy = '<' + ISNULL(CAST(SYSTEM_USER AS VARCHAR(100)), 'Unknown') + '>'
END

IF @DateMessage IS NULL
BEGIN
	SET @DateMessage = GETDATE()
END

/** Test to see if this is a duplicate or not.
	Try to avoid duplicating messages in the log if they are the same.  
	5 Minute expiration....
	**/
DECLARE @IsDuplicate BIT
DECLARE @LastMessage DATETIME
SET @IsDuplicate = 0

SET @LastMessage = (	SELECT TOP 1 I.DateMessage
						FROM Info_Message I
						WHERE I.DateMessage >= DATEADD(HOUR, -1, @DateMessage)
							AND I.MessageSeverity = @MessageSeverity
							AND I.MessageType = @MessageType
							AND I.GeneratedBy = @GeneratedBy
							AND I.MessageShort = @MessageShort
							AND SUBSTRING(ISNULL(I.MessageLong, '  '), 0, 500) = SUBSTRING(ISNULL(@MessageLong, '  '), 0, 500)
						ORDER BY I.DateMessage DESC
						)
						
IF DATEDIFF(MINUTE, ISNULL(@LastMessage, '1/1/2010'), @DateMessage) <= 5
BEGIN
	SET @IsDuplicate = 1
END

IF @IsDuplicate = 0
BEGIN

	--Begin inserting data.
	INSERT INTO Info_Message (MessageSeverity, MessageType, MessageShort, MessageLong, GeneratedBy, DateMessage)
	VALUES (@MessageSeverity, @MessageType, @MessageShort, @MessageLong, @GeneratedBy, @DateMessage)
	
END

/** If the message severity if 4 then send a message.
	**/
IF @MessageSeverity = 4 AND @IsDuplicate = 0
BEGIN

	DECLARE @ProfileName SYSNAME 
	DECLARE @CRCL CHAR(2)
	DECLARE @MessageSubject VARCHAR(MAX) 
	DECLARE @MessageBody VARCHAR(MAX) 
	
	SET @ProfileName = (	SELECT TOP 1 P.name 
							FROM msdb.dbo.sysmail_profile P 
							ORDER BY CASE	WHEN P.name LIKE '%DBA%' THEN 1 
											ELSE 2 
											END
										, P.name
							)
							
	SET @CRCL = CHAR(13) + CHAR(10)						
	SET @MessageSubject = 'INFO MESSAGE: ' + @@SERVERNAME + ' Severity 4 Message - ' + @MessageType
	
	SET @MessageBody = 'Server: ' + @@SERVERNAME
						+ @CRCL + 'Generated: ' + DBA.dbo.fn_FrmtDate(@DateMessage, 0) + ' ' + DBA.dbo.fn_FrmtTime(@DateMessage, 0)
						+ @CRCL + 'User: ' + @GeneratedBy
						+ @CRCL + 'Severity: ' + CAST(@MessageSeverity AS VARCHAR(10))
						+ @CRCL + 'Message Type: ' + @MessageType
						+ @CRCL + 'Message Short: ' + ISNULL(@MessageShort, '')
						+ @CRCL
						+ @CRCL + 'Message Details Begin'
						+ @CRCL + '====================='
						+ @CRCL
						+ @CRCL + ISNULL(@MessageLong, '')
	
	IF @ProfileName IS NOT NULL
	BEGIN
	
		DECLARE @FromAddress NVARCHAR(500)
		SET @FromAddress = (@@SERVERNAME + ' <MSSQLAdmins@americanrailcar.com>')
	
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @ProfileName
			, @recipients = 'dustin.marzolf@setbasedmanagement.com
			, @from_address = @FromAddress
			, @subject = @MessageSubject
			, @body = @MessageBody;
	
	END

END





GO
/****** Object:  StoredProcedure [dbo].[sp_SetPwrShllMod]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_SetPwrShllMod]
	( 
	@ModuleName VARCHAR(100)
	, @ModuleText VARCHAR(MAX)
	)
AS

/*************************************

Name: SetPowershellModule

Author: Dustin Marzolf

Created: 1/18/2016

Inputs:
	@ModuleName - The name of the module to add or update
	@ModuleText - The text of the module to be updated
	
Outputs:
	None
	
This stored procedure will either insert or update the table
with the new text for the module.

*****************************************/

IF ISNULL(	(SELECT COUNT(P.ModuleName) 
			FROM PowershellModule P 
			WHERE P.ModuleName = @ModuleName
			), 0) >= 1
BEGIN

	--Update the module text and the date last updated.
	--Also prevents blind updates from working.
	UPDATE PowershellModule
	SET ModuleText = @ModuleText
		, DateLastUpdated = GETDATE()
	WHERE ModuleName = @ModuleName
		AND ModuleText <> @ModuleText

END
ELSE
BEGIN

	--Insert the new module definition.
	INSERT INTO PowershellModule
	(ModuleName, ModuleText, DateLastUpdated)
	VALUES
	(@ModuleName, @ModuleText, GETDATE())

END


GO
/****** Object:  StoredProcedure [dbo].[sp_TstlinkedSrvr]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_TstlinkedSrvr]
	( 
	@SrvrName SYSNAME = NULL
	, @IsTestConnection BIT = 0
	, @OnlyReturnFailed BIT = 0
	)
AS

/*********************
Name: sp_TstlinkedSrvr

Author: Dustin Marzolf
Created: 4/10/2016

Purpose: To test the linked servers to see if they work.

Inputs:
	@SrvrName SYSNAME = NULL - The name of the linked server you want to test.
		Leave it at NULL to test all.  
	
	@IsTestConnection BIT = 0 - If it should test the connection.  
		0/false will NOT test.  1/true will test.  Significantly increases the time
		it takes to test.
	
	@OnlyReturnFailed BIT = 0 - If you want to only return the failed connections.
		Only useful if you have set @IsTestConnection to 1.  
		
Outputs:

	Returns a table containing
		- linked server name
		- is working (NULL if not tested, 0 failed, 1 passed)
		- datasource (remote server name)
		- provider (how is it connecting)
		
NOTES: due to how SQL does some error handling, you cannot put these results into a
temp table for later processing, or insert into a table, etc.  This must be run from
an interactive command prompt.  Unless you have found a better way. 
	
**********************/
	
/** Fix Inputs **/

IF @IsTestConnection IS NULL
BEGIN
	SET @IsTestConnection = 0
END

IF @SrvrName = ''
BEGIN
	SET @SrvrName = NULL
END

IF @OnlyReturnFailed IS NULL OR @IsTestConnection = 0
BEGIN
	SET @OnlyReturnFailed = 0
END

/** Needed local variables **/

DECLARE @ResultSet TABLE
	(
	ServerName SYSNAME NULL
	, IsWorking BIT NULL
	, DataSource VARCHAR(200) NULL
	, Provider VARCHAR(200) NULL
	)
	
DECLARE @SName SYSNAME
DECLARE @IsWorking BIT
DECLARE @DataSource VARCHAR(200)
DECLARE @Provider VARCHAR(200)

/** Begin processing **/
	
DECLARE curLinked CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT S.name
		, S.data_source
		, S.provider
	FROM sys.servers S
	WHERE S.server_id <> 0
		AND (S.name = @SrvrName
			OR @SrvrName IS NULL)
	
OPEN curLinked

FETCH NEXT FROM curLinked
INTO @SName, @DataSource, @Provider

WHILE @@FETCH_STATUS = 0
BEGIN

	--Only if we are testing the connections.
	IF @IsTestConnection = 1
	BEGIN
	
		SET @IsWorking = NULL
		DECLARE @r INT

		--This fails rather spectacularly when it fails.  
		BEGIN TRY
			EXEC @r = sp_TstlinkedSrvr @SName;
		END TRY
		BEGIN CATCH
			SET @r = -1;
			PRINT XACT_STATE();
			PRINT ERROR_MESSAGE();
		END CATCH
		
		--Determine if it's working or not.
		IF ISNULL(@r, 1) = 0
		BEGIN
			SET @IsWorking = 1
		END
		ELSE
		BEGIN
			SET @IsWorking = 0
		END
	
	END
	
	--Store the results.
	INSERT INTO @ResultSet
	(ServerName, IsWorking, DataSource, Provider)
	VALUES
	(@SName, @IsWorking, @DataSource, @Provider)
	
	--Get the next server.
	FETCH NEXT FROM curLinked
	INTO @SName, @DataSource, @Provider
	
END

--Cleanup.
CLOSE curLinked
DEALLOCATE curLinked

/** Return the data **/

SELECT ServerName
	, IsWorking
	, DataSource
	, Provider 
FROM @ResultSet
WHERE (ISNULL(@OnlyReturnFailed, 0) = 0
		OR IsWorking = 0)
ORDER BY ServerName

GO
