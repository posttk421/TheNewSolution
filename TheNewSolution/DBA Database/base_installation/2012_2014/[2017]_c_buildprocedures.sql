USE [DBA]
GO
/****** Object:  StoredProcedure [dbo].[sp_agntJobHist]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[sp_agntJobHist]
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
	, DBA.dbo.fnJOBrunToDateTime(H.run_date, H.run_time)
	, DBA.dbo.fnJOBDurationToSeconds(H.run_duration)
FROM msdb.dbo.sysjobhistory H
WHERE DBA.dbo.fnJOBrunToDateTime(H.run_date, H.run_time) >= @LastGathered
	AND H.run_status <> 4

--Find failed jobs.
DECLARE @JobID VARCHAR(200)
DECLARE @StepID VARCHAR(10)
DECLARE @JobName VARCHAR(200)
DECLARE @StepMessage VARCHAR(MAX)
DECLARE @LogMessage VARCHAR(MAX)
DECLARE @DateStarted DATETIME
DECLARE @DBAOnlySeverity4 BIT

SET @DBAOnlySeverity4 = CAST((SELECT ISNULL(DBA.dbo.fnGetOptionValue('Server', 'AgentJobError_ONLY_DBA'), '0')) AS BIT)

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
/****** Object:  StoredProcedure [dbo].[sp_auditlogindb]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_auditlogindb]
AS

/*************************
Name: sp_auditlogindb

Author: Dustin Marzolf
Created: 3/18/2016
 Output:
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
SET @Script = @Script + CHAR(13) + '/** Created On: ' + DBA.dbo.fnFormatDate(@createdDateTime, 0) + ' ' + DBA.dbo.fn_FrmtTime(@createdDateTime, 0) + ' **/'
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
/****** Object:  StoredProcedure [dbo].[sp_SetPwrShllMod]    Script Date: 8/7/2016 8:17:53 AM ******/
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
/****** Object:  StoredProcedure [dbo].[sp_TstlinkedSrvr]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_TstlinkedSrvr]
	( 
	@ServerName SYSNAME = NULL
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
	@ServerName SYSNAME = NULL - The name of the linked server you want to test.
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

IF @ServerName = ''
BEGIN
	SET @ServerName = NULL
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
		AND (S.name = @ServerName
			OR @ServerName IS NULL)
	
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
/****** Object:  StoredProcedure [dbo].[sp_AskBrent]    Script Date: 8/7/2016 8:17:53 AM ******/
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
 - Initial bug-filled release. We purposely left extra errors on here so
   you could email bug reports to Help@BrentOzar.com, thereby increasing
   your self-esteem. It's all about you.
*/


SELECT @Version = 9, @VersionDate = '20161103'

DECLARE @StringToExecute NVARCHAR(4000),
	@OurSessionID INT,
	@LineFeed NVARCHAR(10),
	@StockWarningHeader NVARCHAR(500),
	@StockWarningFooter NVARCHAR(100),
	@StockDetailsHeader NVARCHAR(100),
	@StockDetailsFooter NVARCHAR(100),
	@StartSampleTime DATETIME,
	@FinishSampleTime DATETIME;

/* Sanitize our inputs */
SELECT
	@OutputDatabaseName = QUOTENAME(@OutputDatabaseName),
	@OutputSchemaName = QUOTENAME(@OutputSchemaName),
	@OutputTableName = QUOTENAME(@OutputTableName),
	@LineFeed = CHAR(13) + CHAR(10),
	@StartSampleTime = GETDATE(),
	@FinishSampleTime = DATEADD(ss, @Seconds, GETDATE()),
	@OurSessionID = @@SPID;

IF @OutputType = 'SCHEMA'
BEGIN
	SELECT @Version AS Version,
	FieldList = '[Priority] TINYINT, [FindingsGroup] VARCHAR(50), [Finding] VARCHAR(200), [URL] VARCHAR(200), [Details] NVARCHAR(4000), [HowToStopIt] NVARCHAR(MAX), [QueryPlan] XML, [QueryText] NVARCHAR(MAX)'

END
ELSE IF @AsOf IS NOT NULL AND @OutputDatabaseName IS NOT NULL AND @OutputSchemaName IS NOT NULL AND @OutputTableName IS NOT NULL
BEGIN
	/* They want to look into the past. */

		SET @StringToExecute = N' IF EXISTS(SELECT * FROM '
			+ @OutputDatabaseName
			+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
			+ @OutputSchemaName + ''') SELECT CheckDate, [Priority], [FindingsGroup], [Finding], [URL], CAST([Details] AS [XML]) AS Details,'
			+ '[HowToStopIt], [CheckID], [StartTime], [LoginName], [NTUserName], [OriginalLoginName], [ProgramName], [HostName], [DatabaseID],'
			+ '[DatabaseName], [OpenTransactionCount], [QueryPlan], [QueryText] FROM '
			+ @OutputDatabaseName + '.'
			+ @OutputSchemaName + '.'
			+ @OutputTableName
			+ ' WHERE CheckDate >= DATEADD(mi, -15, ''' + CAST(@AsOf AS NVARCHAR(100)) + ''')'
			+ ' AND CheckDate <= DATEADD(mi, 15, ''' + CAST(@AsOf AS NVARCHAR(100)) + ''')'
			+ ' /*ORDER BY CheckDate, Priority , FindingsGroup , Finding , Details*/;';
		EXEC(@StringToExecute);


END /* IF @AsOf IS NOT NULL AND @OutputDatabaseName IS NOT NULL AND @OutputSchemaName IS NOT NULL AND @OutputTableName IS NOT NULL */
ELSE IF @Question IS NULL /* IF @OutputType = 'SCHEMA' */
BEGIN


	/*
	We start by creating #AskBrentResults. It's a temp table that will storef
	the results from our checks. Throughout the rest of this stored procedure,
	we're running a series of checks looking for dangerous things inside the SQL
	Server. When we find a problem, we insert rows into #BlitzResults. At the
	end, we return these results to the end user.

	#AskBrentResults has a CheckID field, but there's no Check table. As we do
	checks, we insert data into this table, and we manually put in the CheckID.
	We (Brent Ozar Unlimited) maintain a list of the checks by ID#. You can
	download that from http://www.BrentOzar.com/askbrent/documentation/ if you
	want to build a tool that relies on the output of sp_AskBrent.
	*/

	IF OBJECT_ID('tempdb..#AskBrentResults') IS NOT NULL 
		DROP TABLE #AskBrentResults;
	CREATE TABLE #AskBrentResults
		(
		  ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
		  CheckID INT NOT NULL,
		  Priority TINYINT NOT NULL,
		  FindingsGroup VARCHAR(50) NOT NULL,
		  Finding VARCHAR(200) NOT NULL,
		  URL VARCHAR(200) NOT NULL,
		  Details NVARCHAR(4000) NULL,
		  HowToStopIt [XML] NULL,
		  QueryPlan [XML] NULL,
		  QueryText NVARCHAR(MAX) NULL,
		  StartTime DATETIME NULL,
		  LoginName NVARCHAR(128) NULL,
		  NTUserName NVARCHAR(128) NULL,
		  OriginalLoginName NVARCHAR(128) NULL,
		  ProgramName NVARCHAR(128) NULL,
		  HostName NVARCHAR(128) NULL,
		  DatabaseID INT NULL,
		  DatabaseName NVARCHAR(128) NULL,
		  OpenTransactionCount INT NULL
		);

	IF OBJECT_ID('tempdb..#WaitStats') IS NOT NULL 
		DROP TABLE #WaitStats;
	CREATE TABLE #WaitStats (Pass TINYINT NOT NULL, wait_type NVARCHAR(60), wait_time_ms BIGINT, signal_wait_time_ms BIGINT, waiting_tasks_count BIGINT, SampleTime DATETIME);

	IF OBJECT_ID('tempdb..#FileStats') IS NOT NULL 
		DROP TABLE #FileStats;
	CREATE TABLE #FileStats ( 
		ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
		Pass TINYINT NOT NULL,
		SampleTime DATETIME NOT NULL,
		DatabaseID INT NOT NULL,
		FileID INT NOT NULL,
		DatabaseName NVARCHAR(256) ,
		FileLogicalName NVARCHAR(256) ,
		TypeDesc NVARCHAR(60) ,
		SizeOnDiskMB BIGINT ,
		io_stall_read_ms BIGINT ,
		num_of_reads BIGINT ,
		bytes_read BIGINT ,
		io_stall_write_ms BIGINT ,
		num_of_writes BIGINT ,
		bytes_written BIGINT, 
		PhysicalName NVARCHAR(520) ,
		avg_stall_read_ms INT ,
		avg_stall_write_ms INT
	);

	IF OBJECT_ID('tempdb..#QueryStats') IS NOT NULL 
		DROP TABLE #QueryStats;
	CREATE TABLE #QueryStats ( 
		ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
		Pass TINYINT NOT NULL,
		SampleTime DATETIME NOT NULL,
		[sql_handle] VARBINARY(64),
		statement_start_offset INT,
		statement_end_offset INT,
		plan_generation_num BIGINT,
		plan_handle VARBINARY(64),
		execution_count BIGINT,
		total_worker_time BIGINT,
		total_physical_reads BIGINT,
		total_logical_writes BIGINT,
		total_logical_reads BIGINT,
		total_clr_time BIGINT,
		total_elapsed_time BIGINT,
		creation_time DATETIME,
		query_hash BINARY(8),
		query_plan_hash BINARY(8),
		Points TINYINT
	);

	IF OBJECT_ID('tempdb..#PerfmonStats') IS NOT NULL 
		DROP TABLE #PerfmonStats;
	CREATE TABLE #PerfmonStats ( 
		ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
		Pass TINYINT NOT NULL,
		SampleTime DATETIME NOT NULL,
		[object_name] NVARCHAR(128) NOT NULL,
		[counter_name] NVARCHAR(128) NOT NULL,
		[instance_name] NVARCHAR(128) NULL,
		[cntr_value] BIGINT NULL,
		[cntr_type] INT NOT NULL,
		[value_delta] BIGINT NULL,
		[value_per_second] DECIMAL(18,2) NULL
	);

	IF OBJECT_ID('tempdb..#PerfmonCounters') IS NOT NULL 
		DROP TABLE #PerfmonCounters;
	CREATE TABLE #PerfmonCounters ( 
		ID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
		[object_name] NVARCHAR(128) NOT NULL,
		[counter_name] NVARCHAR(128) NOT NULL,
		[instance_name] NVARCHAR(128) NULL
	);

	SET @StockWarningHeader = '<?ClickToSeeCommmand -- ' + @LineFeed + @LineFeed 
		+ 'WARNING: Running this command may result in data loss or an outage.' + @LineFeed
		+ 'This tool is meant as a shortcut to help generate scripts for DBAs.' + @LineFeed
		+ 'It is not a substitute for database training and experience.' + @LineFeed
		+ 'Now, having said that, here''s the details:' + @LineFeed + @LineFeed;

	SELECT @StockWarningFooter = @LineFeed + @LineFeed + '-- ?>',
		@StockDetailsHeader = '<?ClickToSeeDetails -- ' + @LineFeed,
		@StockDetailsFooter = @LineFeed + ' -- ?>';

	/* Build a list of queries that were run in the last 10 seconds.
	   We're looking for the death-by-a-thousand-small-cuts scenario
	   where a query is constantly running, and it doesn't have that
	   big of an impact individually, but it has a ton of impact
	   overall. We're going to build this list, and then after we
	   finish our @Seconds sample, we'll compare our plan cache to
	   this list to see what ran the most. */

	/* Populate #QueryStats. SQL 2005 doesn't have query hash or query plan hash. */
	IF @@VERSION LIKE 'Microsoft SQL Server 2005%'
		SET @StringToExecute = N'INSERT INTO #QueryStats ([sql_handle], Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, Points)
									SELECT [sql_handle], 1 AS Pass, GETDATE(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, NULL AS query_hash, NULL AS query_plan_hash, 0
									FROM sys.dm_exec_query_stats qs
									WHERE qs.last_execution_time >= (DATEADD(ss, -10, GETDATE()));';
	ELSE
		SET @StringToExecute = N'INSERT INTO #QueryStats ([sql_handle], Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, Points)
									SELECT [sql_handle], 1 AS Pass, GETDATE(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, 0
									FROM sys.dm_exec_query_stats qs
									WHERE qs.last_execution_time >= (DATEADD(ss, -10, GETDATE()));';
	EXEC(@StringToExecute);

	IF EXISTS (SELECT * 
					FROM tempdb.sys.all_objects obj
					INNER JOIN tempdb.sys.all_columns col1 ON obj.object_id = col1.object_id AND col1.name = 'object_name'
					INNER JOIN tempdb.sys.all_columns col2 ON obj.object_id = col2.object_id AND col2.name = 'counter_name'
					INNER JOIN tempdb.sys.all_columns col3 ON obj.object_id = col3.object_id AND col3.name = 'instance_name'
					WHERE obj.name LIKE '%CustomPerfmonCounters%') 
		BEGIN
		SET @StringToExecute = 'INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) SELECT [object_name],[counter_name],[instance_name] FROM #CustomPerfmonCounters'
		EXEC(@StringToExecute);
		END
	ELSE
		BEGIN
		/* Add our default Perfmon counters */
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Forwarded Records/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Page compression attempts/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Page Splits/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Skipped Ghosted Records/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Table Lock Escalations/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Access Methods','Worktables Created/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Page life expectancy', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Page reads/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Page writes/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Readahead pages/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Target pages', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Total pages', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Databases','', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Buffer Manager','Active Transactions','_Total')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Databases','Log Growths', '_Total')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Databases','Log Shrinks', '_Total')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Exec Statistics','Distributed Query', 'Execs in progress')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Exec Statistics','DTC calls', 'Execs in progress')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Exec Statistics','Extended Procedures', 'Execs in progress')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Exec Statistics','OLEDB calls', 'Execs in progress')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:General Statistics','Active Temp Tables', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:General Statistics','Logins/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:General Statistics','Logouts/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:General Statistics','Mars Deadlocks', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:General Statistics','Processes blocked', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Locks','Number of Deadlocks/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:Memory Manager','Memory Grants Pending', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Errors','Errors/sec', '_Total')
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','Batch Requests/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','Forced Parameterizations/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','Guided plan executions/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','SQL Attention rate', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','SQL Compilations/sec', NULL)
		INSERT INTO #PerfmonCounters ([object_name],[counter_name],[instance_name]) VALUES ('SQLServer:SQL Statistics','SQL Re-Compilations/sec', NULL)
		END

	/* Populate #FileStats, #PerfmonStats, #WaitStats with DMV data. 
		After we finish doing our checks, we'll take another sample and compare them. */
	INSERT #WaitStats(Pass, SampleTime, wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count)
	SELECT
		1 AS Pass,
		GETDATE() AS SampleTime,
		os.wait_type,
		SUM(os.wait_time_ms) OVER (PARTITION BY os.wait_type) as sum_wait_time_ms,
		SUM(os.signal_wait_time_ms) OVER (PARTITION BY os.wait_type ) as sum_signal_wait_time_ms,
		SUM(os.waiting_tasks_count) OVER (PARTITION BY os.wait_type) AS sum_waiting_tasks
	FROM sys.dm_os_wait_stats os
	WHERE
		os.wait_type not in (
			'REQUEST_FOR_DEADLOCK_SEARCH',
			'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
			'SQLTRACE_BUFFER_FLUSH',
			'LAZYWRITER_SLEEP',
			'XE_TIMER_EVENT',
			'XE_DISPATCHER_WAIT',
			'FT_IFTS_SCHEDULER_IDLE_WAIT',
			'LOGMGR_QUEUE',
			'CHECKPOINT_QUEUE',
			'BROKER_TO_FLUSH',
			'BROKER_TASK_STOP',
			'BROKER_EVENTHANDLER',
			'SLEEP_TASK',
			'WAITFOR',
			'DBMIRROR_DBM_MUTEX',
			'DBMIRROR_EVENTS_QUEUE',
			'DBMIRRORING_CMD',
			'DISPATCHER_QUEUE_SEMAPHORE',
			'BROKER_RECEIVE_WAITFOR',
			'CLR_AUTO_EVENT',
			'DIRTY_PAGE_POLL',
			'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
			'ONDEMAND_TASK_QUEUE',
			'FT_IFTSHC_MUTEX',
			'CLR_MANUAL_EVENT',
			'SP_SERVER_DIAGNOSTICS_SLEEP',
			'HADR_CLUSAPI_CALL',
			'HADR_LOGCAPTURE_WAIT',
			'HADR_TIMER_TASK',
			'HADR_WORK_QUEUE'
		)
	ORDER BY sum_wait_time_ms DESC;


	INSERT INTO #FileStats (Pass, SampleTime, DatabaseID, FileID, DatabaseName, FileLogicalName, SizeOnDiskMB, io_stall_read_ms ,
		num_of_reads, [bytes_read] , io_stall_write_ms,num_of_writes, [bytes_written], PhysicalName, TypeDesc)
	SELECT 
		1 AS Pass,
		GETDATE() AS SampleTime,
		mf.[database_id],
		mf.[file_id],
		DB_NAME(vfs.database_id) AS [db_name], 
		mf.name + N' [' + mf.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS + N']' AS file_logical_name ,
		CAST(( ( vfs.size_on_disk_bytes / 1024.0 ) / 1024.0 ) AS INT) AS size_on_disk_mb ,
		vfs.io_stall_read_ms ,
		vfs.num_of_reads ,
		vfs.[num_of_bytes_read],
		vfs.io_stall_write_ms ,
		vfs.num_of_writes ,
		vfs.[num_of_bytes_written],
		mf.physical_name,
		mf.type_desc
	FROM sys.dm_io_virtual_file_stats (NULL, NULL) AS vfs
	INNER JOIN sys.master_files AS mf ON vfs.file_id = mf.file_id
		AND vfs.database_id = mf.database_id
	WHERE vfs.num_of_reads > 0
		OR vfs.num_of_writes > 0;

	INSERT INTO #PerfmonStats (Pass, SampleTime, [object_name],[counter_name],[instance_name],[cntr_value],[cntr_type])
	SELECT 		1 AS Pass,
		GETDATE() AS SampleTime, RTRIM(dmv.object_name), RTRIM(dmv.counter_name), RTRIM(dmv.instance_name), dmv.cntr_value, dmv.cntr_type
		FROM #PerfmonCounters counters
		INNER JOIN sys.dm_os_performance_counters dmv ON counters.counter_name = RTRIM(dmv.counter_name)
			AND counters.[object_name] = RTRIM(dmv.[object_name])
			AND (counters.[instance_name] IS NULL OR counters.[instance_name] = RTRIM(dmv.[instance_name]))

	/* Maintenance Tasks Running - Backup Running - CheckID 1 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount)
	SELECT 1 AS CheckID,
		1 AS Priority,
		'Maintenance Tasks Running' AS FindingGroup,
		'Backup Running' AS Finding,
		'http://BrentOzar.com/askbrent/backups/' AS URL,
		@StockDetailsHeader + 'Backup of ' + DB_NAME(db.resource_database_id) + ' database (' + (SELECT CAST(CAST(SUM(size * 8.0 / 1024 / 1024) AS BIGINT) AS NVARCHAR) FROM sys.master_files WHERE database_id = db.resource_database_id) + 'GB) is ' + CAST(r.percent_complete AS NVARCHAR(100)) + '% complete, has been running since ' + CAST(r.start_time AS NVARCHAR(100)) + '. ' AS Details,
		CAST(@StockWarningHeader + 'KILL ' + CAST(r.session_id AS NVARCHAR(100)) + ';' + @StockWarningFooter AS XML) AS HowToStopIt,
		pl.query_plan AS QueryPlan,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		0 AS OpenTransactionCount
	FROM sys.dm_exec_requests r
	INNER JOIN sys.dm_exec_connections c ON r.session_id = c.session_id
	INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
	INNER JOIN (
	SELECT DISTINCT request_session_id, resource_database_id
	FROM    sys.dm_tran_locks
	WHERE resource_type = N'DATABASE'
	AND     request_mode = N'S'
	AND     request_status = N'GRANT'
	AND     request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) pl
	WHERE r.command LIKE 'BACKUP%';


	/* If there's a backup running, add details explaining how long full backup has been taking in the last month. */
	UPDATE #AskBrentResults
	SET Details = Details + ' Over the last 60 days, the full backup usually takes ' + CAST((SELECT AVG(DATEDIFF(mi, bs.backup_start_date, bs.backup_finish_date)) FROM msdb.dbo.backupset bs WHERE abr.DatabaseName = bs.database_name AND bs.type = 'D' AND bs.backup_start_date > DATEADD(dd, -60, GETDATE()) AND bs.backup_finish_date IS NOT NULL) AS NVARCHAR(100)) + ' minutes.'
	FROM #AskBrentResults abr
	WHERE abr.CheckID = 1 AND EXISTS (SELECT * FROM msdb.dbo.backupset bs WHERE bs.type = 'D' AND bs.backup_start_date > DATEADD(dd, -60, GETDATE()) AND bs.backup_finish_date IS NOT NULL AND abr.DatabaseName = bs.database_name AND DATEDIFF(mi, bs.backup_start_date, bs.backup_finish_date) > 1)



	/* Maintenance Tasks Running - DBCC Running - CheckID 2 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount)
	SELECT 2 AS CheckID,
		1 AS Priority,
		'Maintenance Tasks Running' AS FindingGroup,
		'DBCC Running' AS Finding,
		'http://BrentOzar.com/askbrent/dbcc/' AS URL,
		@StockDetailsHeader + 'Corruption check of ' + DB_NAME(db.resource_database_id) + ' database (' + (SELECT CAST(CAST(SUM(size * 8.0 / 1024 / 1024) AS BIGINT) AS NVARCHAR) FROM sys.master_files WHERE database_id = db.resource_database_id) + 'GB) has been running since ' + CAST(r.start_time AS NVARCHAR(100)) + '. ' AS Details,
		CAST(@StockWarningHeader + 'KILL ' + CAST(r.session_id AS NVARCHAR(100)) + ';' + @StockWarningFooter AS XML) AS HowToStopIt,
		pl.query_plan AS QueryPlan,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		0 AS OpenTransactionCount
	FROM sys.dm_exec_requests r
	INNER JOIN sys.dm_exec_connections c ON r.session_id = c.session_id
	INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
	INNER JOIN (SELECT DISTINCT l.request_session_id, l.resource_database_id
	FROM    sys.dm_tran_locks l
	INNER JOIN sys.databases d ON l.resource_database_id = d.database_id
	WHERE l.resource_type = N'DATABASE'
	AND     l.request_mode = N'S'
	AND    l.request_status = N'GRANT'
	AND    l.request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) pl
	WHERE r.command LIKE 'DBCC%';


	/* Maintenance Tasks Running - Restore Running - CheckID 3 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount)
	SELECT 3 AS CheckID,
		1 AS Priority,
		'Maintenance Tasks Running' AS FindingGroup,
		'Restore Running' AS Finding,
		'http://BrentOzar.com/askbrent/backups/' AS URL,
		@StockDetailsHeader + 'Restore of ' + DB_NAME(db.resource_database_id) + ' database (' + (SELECT CAST(CAST(SUM(size * 8.0 / 1024 / 1024) AS BIGINT) AS NVARCHAR) FROM sys.master_files WHERE database_id = db.resource_database_id) + 'GB) is ' + CAST(r.percent_complete AS NVARCHAR(100)) + '% complete, has been running since ' + CAST(r.start_time AS NVARCHAR(100)) + '. ' AS Details,
		CAST(@StockWarningHeader + 'KILL ' + CAST(r.session_id AS NVARCHAR(100)) + ';' + @StockWarningFooter AS XML) AS HowToStopIt,
		pl.query_plan AS QueryPlan,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		0 AS OpenTransactionCount
	FROM sys.dm_exec_requests r
	INNER JOIN sys.dm_exec_connections c ON r.session_id = c.session_id
	INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
	INNER JOIN (
	SELECT DISTINCT request_session_id, resource_database_id
	FROM    sys.dm_tran_locks
	WHERE resource_type = N'DATABASE'
	AND     request_mode = N'S'
	AND     request_status = N'GRANT'
	AND     request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) pl
	WHERE r.command LIKE 'RESTORE%';


	/* SQL Server Internal Maintenance - Database File Growing - CheckID 4 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount)
	SELECT 4 AS CheckID,
		1 AS Priority,
		'SQL Server Internal Maintenance' AS FindingGroup,
		'Database File Growing' AS Finding,
		'http://BrentOzar.com/go/instant' AS URL,
		@StockDetailsHeader + 'SQL Server is waiting for Windows to provide storage space for a database restore, a data file growth, or a log file growth. This task has been running since ' + CAST(r.start_time AS NVARCHAR(100)) + '.' + @LineFeed + 'Check the query plan (expert mode) to identify the database involved.' AS Details,
		CAST(@StockWarningHeader + 'Unfortunately, you can''t stop this, but you can prevent it next time. Check out http://BrentOzar.com/go/instant for details.' + @StockWarningFooter AS XML) AS HowToStopIt,
		pl.query_plan AS QueryPlan,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		NULL AS DatabaseID,
		NULL AS DatabaseName,
		0 AS OpenTransactionCount
	FROM sys.dm_os_waiting_tasks t
	INNER JOIN sys.dm_exec_connections c ON t.session_id = c.session_id
	INNER JOIN sys.dm_exec_requests r ON t.session_id = r.session_id
	INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
	CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) pl
	WHERE t.wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER'


	/* Query Problems - Long-Running Query Blocking Others - CheckID 5 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount)
	SELECT 5 AS CheckID,
		1 AS Priority,
		'Query Problems' AS FindingGroup,
		'Long-Running Query Blocking Others' AS Finding,
		'http://BrentOzar.com/go/blocking' AS URL,
		@StockDetailsHeader + 'Query in ' + DB_NAME(db.resource_database_id) + ' has been running since ' + CAST(r.start_time AS NVARCHAR(100)) + '. ' + @LineFeed + @LineFeed
			+ CAST(COALESCE((SELECT TOP 1 [text] FROM sys.dm_exec_sql_text(rBlocker.sql_handle)),
			(SELECT TOP 1 [text] FROM master..sysprocesses spBlocker CROSS APPLY ::fn_get_sql(spBlocker.sql_handle) WHERE spBlocker.spid = tBlocked.blocking_session_id), '') AS NVARCHAR(2000)) AS Details,
		CAST(@StockWarningHeader + 'KILL ' + CAST(tBlocked.blocking_session_id AS NVARCHAR(100)) + ';' + @StockWarningFooter AS XML) AS HowToStopIt,
		(SELECT TOP 1 query_plan FROM sys.dm_exec_query_plan(rBlocker.plan_handle)) AS QueryPlan,
		COALESCE((SELECT TOP 1 [text] FROM sys.dm_exec_sql_text(rBlocker.sql_handle)),
			(SELECT TOP 1 [text] FROM master..sysprocesses spBlocker CROSS APPLY ::fn_get_sql(spBlocker.sql_handle) WHERE spBlocker.spid = tBlocked.blocking_session_id)) AS QueryText,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		0 AS OpenTransactionCount
	FROM sys.dm_exec_sessions s
	INNER JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
	INNER JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
	INNER JOIN sys.dm_os_waiting_tasks tBlocked ON tBlocked.session_id = s.session_id AND tBlocked.session_id <> s.session_id
	INNER JOIN (
	SELECT DISTINCT request_session_id, resource_database_id
	FROM    sys.dm_tran_locks
	WHERE resource_type = N'DATABASE'
	AND     request_mode = N'S'
	AND     request_status = N'GRANT'
	AND     request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	LEFT OUTER JOIN sys.dm_exec_requests rBlocker ON tBlocked.blocking_session_id = rBlocker.session_id
	  WHERE NOT EXISTS (SELECT * FROM sys.dm_os_waiting_tasks tBlocker WHERE tBlocker.session_id = tBlocked.blocking_session_id AND tBlocker.blocking_session_id IS NOT NULL)
	  AND s.last_request_start_time < DATEADD(SECOND, -30, GETDATE())

	/* Query Problems - Plan Cache Erased Recently */
	IF DATEADD(mi, -15, GETDATE()) < (SELECT TOP 1 creation_time FROM sys.dm_exec_query_stats ORDER BY creation_time)
	BEGIN
		INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
		SELECT TOP 1 7 AS CheckID,
			50 AS Priority,
			'Query Problems' AS FindingGroup,
			'Plan Cache Erased Recently' AS Finding,
			'http://BrentOzar.com/askbrent/plan-cache-erased-recently/' AS URL,
			@StockDetailsHeader + 'The oldest query in the plan cache was created at ' + CAST(creation_time AS NVARCHAR(50)) + '. ' + @LineFeed + @LineFeed
				+ 'This indicates that someone ran DBCC FREEPROCCACHE at that time,' + @LineFeed
				+ 'Giving SQL Server temporary amnesia. Now, as queries come in,' + @LineFeed
				+ 'SQL Server has to use a lot of CPU power in order to build execution' + @LineFeed
				+ 'plans and put them in cache again. This causes high CPU loads.' AS Details,
			CAST(@StockWarningHeader + 'Find who did that, and stop them from doing it again.' + @StockWarningFooter AS XML) AS HowToStopIt
		FROM sys.dm_exec_query_stats 
		ORDER BY creation_time	
	END;


	/* Query Problems - Sleeping Query with Open Transactions - CheckID 8 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, QueryText, OpenTransactionCount)
	SELECT 8 AS CheckID,
		50 AS Priority,
		'Query Problems' AS FindingGroup,
		'Sleeping Query with Open Transactions' AS Finding,
		'http://www.brentozar.com/askbrent/sleeping-query-with-open-transactions/' AS URL,
		@StockDetailsHeader + 'Database: ' + DB_NAME(db.resource_database_id) + @LineFeed + 'Host: ' + s.[host_name] + @LineFeed + 'Program: ' + s.[program_name] + @LineFeed + 'Asleep with open transactions and locks since ' + CAST(s.last_request_end_time AS NVARCHAR(100)) + '. ' AS Details,
		CAST(@StockWarningHeader + 'KILL ' + CAST(s.session_id AS NVARCHAR(100)) + ';' + @StockWarningFooter AS XML) AS HowToStopIt,
		s.last_request_start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		(SELECT TOP 1 [text] FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS QueryText,
		sessions_with_transactions.open_transaction_count AS OpenTransactionCount
	FROM (SELECT session_id, SUM(open_transaction_count) AS open_transaction_count FROM sys.dm_exec_requests WHERE open_transaction_count > 0 GROUP BY session_id) AS sessions_with_transactions
	INNER JOIN sys.dm_exec_sessions s ON sessions_with_transactions.session_id = s.session_id
	INNER JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
	INNER JOIN (
	SELECT DISTINCT request_session_id, resource_database_id
	FROM    sys.dm_tran_locks
	WHERE resource_type = N'DATABASE'
	AND     request_mode = N'S'
	AND     request_status = N'GRANT'
	AND     request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	WHERE s.status = 'sleeping'
	AND s.last_request_end_time < DATEADD(ss, -10, GETDATE())
	AND EXISTS(SELECT * FROM sys.dm_tran_locks WHERE request_session_id = s.session_id 
	AND NOT (resource_type = N'DATABASE' AND request_mode = N'S' AND request_status = N'GRANT' AND request_owner_type = N'SHARED_TRANSACTION_WORKSPACE'))


	/* Query Problems - Query Rolling Back - CheckID 9 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, StartTime, LoginName, NTUserName, ProgramName, HostName, DatabaseID, DatabaseName, QueryText)
	SELECT 9 AS CheckID,
		1 AS Priority,
		'Query Problems' AS FindingGroup,
		'Query Rolling Back' AS Finding,
		'http://BrentOzar.com/askbrent/rollback/' AS URL,
		@StockDetailsHeader + 'Rollback started at ' + CAST(r.start_time AS NVARCHAR(100)) + ', is ' + CAST(r.percent_complete AS NVARCHAR(100)) + '% complete.' AS Details,
		CAST(@StockWarningHeader + 'Unfortunately, you can''t stop this. Whatever you do, don''t restart the server in an attempt to fix it - SQL Server will keep rolling back.' + @StockWarningFooter AS XML) AS HowToStopIt,
		r.start_time AS StartTime,
		s.login_name AS LoginName,
		s.nt_user_name AS NTUserName,
		s.[program_name] AS ProgramName,
		s.[host_name] AS HostName,
		db.[resource_database_id] AS DatabaseID,
		DB_NAME(db.resource_database_id) AS DatabaseName,
		(SELECT TOP 1 [text] FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS QueryText
	FROM sys.dm_exec_sessions s 
	INNER JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
	INNER JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
	LEFT OUTER JOIN (
		SELECT DISTINCT request_session_id, resource_database_id
		FROM    sys.dm_tran_locks
		WHERE resource_type = N'DATABASE'
		AND     request_mode = N'S'
		AND     request_status = N'GRANT'
		AND     request_owner_type = N'SHARED_TRANSACTION_WORKSPACE') AS db ON s.session_id = db.request_session_id
	WHERE r.status = 'rollback'


	/* Server Performance - Page Life Expectancy Low - CheckID 10 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT 10 AS CheckID,
		50 AS Priority,
		'Server Performance' AS FindingGroup,
		'Page Life Expectancy Low' AS Finding,
		'http://BrentOzar.com/askbrent/page-life-expectancy/' AS URL,
		@StockDetailsHeader + 'SQL Server Buffer Manager:Page life expectancy is ' + CAST(c.cntr_value AS NVARCHAR(10)) + ' seconds.' + @LineFeed 
			+ 'This means SQL Server can only keep data pages in memory for that many seconds after reading those pages in from storage.' + @LineFeed 
			+ 'This is a symptom, not a cause - it indicates very read-intensive queries that need an index, or insufficient server memory.' AS Details,
		CAST(@StockWarningHeader + 'Add more memory to the server, or find the queries reading a lot of data, and make them more efficient (or fix them with indexes).' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM sys.dm_os_performance_counters c
	WHERE object_name LIKE 'SQLServer:Buffer Manager%'
	AND counter_name LIKE 'Page life expectancy%'
	AND cntr_value < 300



	/* End of checks. If we haven't waited @Seconds seconds, wait. */
	IF GETDATE() < @FinishSampleTime
		WAITFOR TIME @FinishSampleTime;


	/* Populate #FileStats, #PerfmonStats, #WaitStats with DMV data. In a second, we'll compare these. */
	INSERT #WaitStats(Pass, SampleTime, wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count)
	SELECT
		2 AS Pass,
		GETDATE() AS SampleTime,
		os.wait_type,
		SUM(os.wait_time_ms) OVER (PARTITION BY os.wait_type) as sum_wait_time_ms,
		SUM(os.signal_wait_time_ms) OVER (PARTITION BY os.wait_type ) as sum_signal_wait_time_ms,
		SUM(os.waiting_tasks_count) OVER (PARTITION BY os.wait_type) AS sum_waiting_tasks
	FROM sys.dm_os_wait_stats os
	WHERE
		os.wait_type not in (
			'REQUEST_FOR_DEADLOCK_SEARCH',
			'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
			'SQLTRACE_BUFFER_FLUSH',
			'LAZYWRITER_SLEEP',
			'XE_TIMER_EVENT',
			'XE_DISPATCHER_WAIT',
			'FT_IFTS_SCHEDULER_IDLE_WAIT',
			'LOGMGR_QUEUE',
			'CHECKPOINT_QUEUE',
			'BROKER_TO_FLUSH',
			'BROKER_TASK_STOP',
			'BROKER_EVENTHANDLER',
			'SLEEP_TASK',
			'WAITFOR',
			'DBMIRROR_DBM_MUTEX',
			'DBMIRROR_EVENTS_QUEUE',
			'DBMIRRORING_CMD',
			'DISPATCHER_QUEUE_SEMAPHORE',
			'BROKER_RECEIVE_WAITFOR',
			'CLR_AUTO_EVENT',
			'DIRTY_PAGE_POLL',
			'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
			'ONDEMAND_TASK_QUEUE',
			'FT_IFTSHC_MUTEX',
			'CLR_MANUAL_EVENT',
			'SP_SERVER_DIAGNOSTICS_SLEEP',
			'HADR_CLUSAPI_CALL',
			'HADR_LOGCAPTURE_WAIT',
			'HADR_TIMER_TASK',
			'HADR_WORK_QUEUE'
		)
	ORDER BY sum_wait_time_ms DESC;

	INSERT INTO #FileStats (Pass, SampleTime, DatabaseID, FileID, DatabaseName, FileLogicalName, SizeOnDiskMB, io_stall_read_ms ,
		num_of_reads, [bytes_read] , io_stall_write_ms,num_of_writes, [bytes_written], PhysicalName, TypeDesc, avg_stall_read_ms, avg_stall_write_ms)
	SELECT 		2 AS Pass,
		GETDATE() AS SampleTime,
		mf.[database_id],
		mf.[file_id],
		DB_NAME(vfs.database_id) AS [db_name], 
		mf.name + N' [' + mf.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS + N']' AS file_logical_name ,
		CAST(( ( vfs.size_on_disk_bytes / 1024.0 ) / 1024.0 ) AS INT) AS size_on_disk_mb ,
		vfs.io_stall_read_ms ,
		vfs.num_of_reads ,
		vfs.[num_of_bytes_read],
		vfs.io_stall_write_ms ,
		vfs.num_of_writes ,
		vfs.[num_of_bytes_written],
		mf.physical_name,
		mf.type_desc,
		0,
		0
	FROM sys.dm_io_virtual_file_stats (NULL, NULL) AS vfs
	INNER JOIN sys.master_files AS mf ON vfs.file_id = mf.file_id
		AND vfs.database_id = mf.database_id
	WHERE vfs.num_of_reads > 0
		OR vfs.num_of_writes > 0;

	INSERT INTO #PerfmonStats (Pass, SampleTime, [object_name],[counter_name],[instance_name],[cntr_value],[cntr_type])
	SELECT 		2 AS Pass,
		GETDATE() AS SampleTime,
		RTRIM(dmv.object_name), RTRIM(dmv.counter_name), RTRIM(dmv.instance_name), dmv.cntr_value, dmv.cntr_type
		FROM #PerfmonCounters counters
		INNER JOIN sys.dm_os_performance_counters dmv ON counters.counter_name = RTRIM(dmv.counter_name)
			AND counters.[object_name] = RTRIM(dmv.[object_name])
			AND (counters.[instance_name] IS NULL OR counters.[instance_name] = RTRIM(dmv.[instance_name]))

	/* Set the latencies and averages. We could do this with a CTE, but we're not ambitious today. */
	UPDATE fNow
	SET avg_stall_read_ms = ((fNow.io_stall_read_ms - fBase.io_stall_read_ms) / (fNow.num_of_reads - fBase.num_of_reads))
	FROM #FileStats fNow
	INNER JOIN #FileStats fBase ON fNow.DatabaseID = fBase.DatabaseID AND fNow.FileID = fBase.FileID AND fNow.SampleTime > fBase.SampleTime AND fNow.num_of_reads > fBase.num_of_reads AND fNow.io_stall_read_ms > fBase.io_stall_read_ms
	WHERE (fNow.num_of_reads - fBase.num_of_reads) > 0

	UPDATE fNow
	SET avg_stall_write_ms = ((fNow.io_stall_write_ms - fBase.io_stall_write_ms) / (fNow.num_of_writes - fBase.num_of_writes))
	FROM #FileStats fNow
	INNER JOIN #FileStats fBase ON fNow.DatabaseID = fBase.DatabaseID AND fNow.FileID = fBase.FileID AND fNow.SampleTime > fBase.SampleTime AND fNow.num_of_writes > fBase.num_of_writes AND fNow.io_stall_write_ms > fBase.io_stall_write_ms
	WHERE (fNow.num_of_writes - fBase.num_of_writes) > 0

	UPDATE pNow
		SET [value_delta] = pNow.cntr_value - pFirst.cntr_value,
			[value_per_second] = ((1.0 * pNow.cntr_value - pFirst.cntr_value) / DATEDIFF(ss, pFirst.SampleTime, pNow.SampleTime)) 
		FROM #PerfmonStats pNow
			INNER JOIN #PerfmonStats pFirst ON pFirst.[object_name] = pNow.[object_name] AND pFirst.counter_name = pNow.counter_name AND (pFirst.instance_name = pNow.instance_name OR (pFirst.instance_name IS NULL AND pNow.instance_name IS NULL))
				AND pNow.ID > pFirst.ID;


	/* If we're within 10 seconds of our projected finish time, do the plan cache analysis. */
	IF DATEDIFF(ss, @FinishSampleTime, GETDATE()) > 10 AND @ExpertMode = 0
		BEGIN
		
			INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			VALUES (18, 210, 'Query Stats', 'Plan Cache Analysis Skipped', 'http://BrentOzar.com/go/topqueries',
				@StockDetailsHeader + 'Due to excessive load, the plan cache analysis was skipped. To override this, use @ExpertMode = 1.')
		
		END
	ELSE /* IF DATEDIFF(ss, @FinishSampleTime, GETDATE()) > 10 AND @ExpertMode = 0 */
		BEGIN


		/* Populate #QueryStats. SQL 2005 doesn't have query hash or query plan hash. */
		IF @@VERSION LIKE 'Microsoft SQL Server 2005%'
			SET @StringToExecute = N'INSERT INTO #QueryStats ([sql_handle], Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, Points)
										SELECT [sql_handle], 2 AS Pass, GETDATE(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, NULL AS query_hash, NULL AS query_plan_hash, 0
										FROM sys.dm_exec_query_stats qs
										WHERE qs.last_execution_time >= ''' + CAST(@StartSampleTime AS NVARCHAR(100)) + ''';';
		ELSE
			SET @StringToExecute = N'INSERT INTO #QueryStats ([sql_handle], Pass, SampleTime, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, Points)
										SELECT [sql_handle], 2 AS Pass, GETDATE(), statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time, query_hash, query_plan_hash, 0
										FROM sys.dm_exec_query_stats qs
										WHERE qs.last_execution_time >= ''' + CAST(@StartSampleTime AS NVARCHAR(100)) + ''';';
		EXEC(@StringToExecute);

		/* Get the totals for the entire plan cache */
		INSERT INTO #QueryStats (Pass, SampleTime, execution_count, total_worker_time, total_physical_reads, total_logical_writes, total_logical_reads, total_clr_time, total_elapsed_time, creation_time)
		SELECT 0 AS Pass, GETDATE(), SUM(execution_count), SUM(total_worker_time), SUM(total_physical_reads), SUM(total_logical_writes), SUM(total_logical_reads), SUM(total_clr_time), SUM(total_elapsed_time), MIN(creation_time)
			FROM sys.dm_exec_query_stats qs;

		/* 
		Pick the most resource-intensive queries to review. Update the Points field
		in #QueryStats - if a query is in the top 10 for logical reads, CPU time,
		duration, or execution, add 1 to its points.
		*/
		WITH qsTop AS (
		SELECT TOP 10 qsNow.ID
		FROM #QueryStats qsNow
		  INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
		WHERE qsNow.total_elapsed_time > qsFirst.total_elapsed_time
			AND qsNow.Pass = 2
		ORDER BY (qsNow.total_elapsed_time - COALESCE(qsFirst.total_elapsed_time, 0)) DESC)
		UPDATE #QueryStats
			SET Points = Points + 1
			FROM #QueryStats qs
			INNER JOIN qsTop ON qs.ID = qsTop.ID;

		WITH qsTop AS (
		SELECT TOP 10 qsNow.ID
		FROM #QueryStats qsNow
		  INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
		WHERE qsNow.total_logical_reads > qsFirst.total_logical_reads
			AND qsNow.Pass = 2
		ORDER BY (qsNow.total_logical_reads - COALESCE(qsFirst.total_logical_reads, 0)) DESC)
		UPDATE #QueryStats
			SET Points = Points + 1
			FROM #QueryStats qs
			INNER JOIN qsTop ON qs.ID = qsTop.ID;

		WITH qsTop AS (
		SELECT TOP 10 qsNow.ID
		FROM #QueryStats qsNow
		  INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
		WHERE qsNow.total_worker_time > qsFirst.total_worker_time
			AND qsNow.Pass = 2
		ORDER BY (qsNow.total_worker_time - COALESCE(qsFirst.total_worker_time, 0)) DESC)
		UPDATE #QueryStats
			SET Points = Points + 1
			FROM #QueryStats qs
			INNER JOIN qsTop ON qs.ID = qsTop.ID;

		WITH qsTop AS (
		SELECT TOP 10 qsNow.ID
		FROM #QueryStats qsNow
		  INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
		WHERE qsNow.execution_count > qsFirst.execution_count
			AND qsNow.Pass = 2
		ORDER BY (qsNow.execution_count - COALESCE(qsFirst.execution_count, 0)) DESC)
		UPDATE #QueryStats
			SET Points = Points + 1
			FROM #QueryStats qs
			INNER JOIN qsTop ON qs.ID = qsTop.ID;

		/* Query Stats - CheckID 17 - Most Resource-Intensive Queries */
		INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText)
		SELECT 17, 210, 'Query Stats', 'Most Resource-Intensive Queries', 'http://BrentOzar.com/go/topqueries',
			@StockDetailsHeader + 'Query stats during the sample:' + @LineFeed +
			'Executions: ' + CAST(qsNow.execution_count - (COALESCE(qsFirst.execution_count, 0)) AS NVARCHAR(100)) + @LineFeed +
			'Elapsed Time: ' + CAST(qsNow.total_elapsed_time - (COALESCE(qsFirst.total_elapsed_time, 0)) AS NVARCHAR(100)) + @LineFeed +
			'CPU Time: ' + CAST(qsNow.total_worker_time - (COALESCE(qsFirst.total_worker_time, 0)) AS NVARCHAR(100)) + @LineFeed +
			'Logical Reads: ' + CAST(qsNow.total_logical_reads - (COALESCE(qsFirst.total_logical_reads, 0)) AS NVARCHAR(100)) + @LineFeed +
			'Logical Writes: ' + CAST(qsNow.total_logical_writes - (COALESCE(qsFirst.total_logical_writes, 0)) AS NVARCHAR(100)) + @LineFeed +
			'CLR Time: ' + CAST(qsNow.total_clr_time - (COALESCE(qsFirst.total_clr_time, 0)) AS NVARCHAR(100)) + @LineFeed +
			@LineFeed + @LineFeed + 'Query stats since ' + CONVERT(NVARCHAR(100), qsNow.creation_time ,121) + @LineFeed +
			'Executions: ' + CAST(qsNow.execution_count AS NVARCHAR(100)) + 
					CASE qsTotal.execution_count WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.execution_count / qsTotal.execution_count AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			'Elapsed Time: ' + CAST(qsNow.total_elapsed_time AS NVARCHAR(100)) + 
					CASE qsTotal.total_elapsed_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_elapsed_time / qsTotal.total_elapsed_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			'CPU Time: ' + CAST(qsNow.total_worker_time AS NVARCHAR(100)) + 
					CASE qsTotal.total_worker_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_worker_time / qsTotal.total_worker_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			'Logical Reads: ' + CAST(qsNow.total_logical_reads AS NVARCHAR(100)) +
					CASE qsTotal.total_logical_reads WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_logical_reads / qsTotal.total_logical_reads AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			'Logical Writes: ' + CAST(qsNow.total_logical_writes AS NVARCHAR(100)) + 
					CASE qsTotal.total_logical_writes WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_logical_writes / qsTotal.total_logical_writes AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			'CLR Time: ' + CAST(qsNow.total_clr_time AS NVARCHAR(100)) + 
					CASE qsTotal.total_clr_time WHEN 0 THEN '' ELSE (' - Percent of Server Total: ' + CAST(CAST(100.0 * qsNow.total_clr_time / qsTotal.total_clr_time AS DECIMAL(6,2)) AS NVARCHAR(100)) + '%') END + @LineFeed +
			--@LineFeed + @LineFeed + 'Query hash: ' + CAST(qsNow.query_hash AS NVARCHAR(100)) + @LineFeed +
			--@LineFeed + @LineFeed + 'Query plan hash: ' + CAST(qsNow.query_plan_hash AS NVARCHAR(100)) + 
			@LineFeed AS Details,
			CAST(@StockWarningHeader + 'See the URL for tuning tips on why this query may be consuming resources.' + @StockWarningFooter AS XML) AS HowToStopIt,
			qp.query_plan, st.text
			FROM #QueryStats qsNow
				INNER JOIN #QueryStats qsTotal ON qsTotal.Pass = 0
				LEFT OUTER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
				CROSS APPLY sys.dm_exec_sql_text(qsNow.sql_handle) AS st 
				CROSS APPLY sys.dm_exec_query_plan(qsNow.plan_handle) AS qp
			WHERE qsNow.Points > 0 AND st.text IS NOT NULL AND qp.query_plan IS NOT NULL

		END /* IF DATEDIFF(ss, @FinishSampleTime, GETDATE()) > 10 AND @ExpertMode = 0 */
	

	/* Wait Stats - CheckID 6 */
	/* Compare the current wait stats to the sample we took at the start, and insert the top 10 waits. */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT TOP 10 6 AS CheckID,
		200 AS Priority,
		'Wait Stats' AS FindingGroup,
		wNow.wait_type AS Finding,
		N'http://www.brentozar.com/sql/wait-stats/#' + wNow.wait_type AS URL,
		@StockDetailsHeader + 'For ' + CAST(((wNow.wait_time_ms - COALESCE(wBase.wait_time_ms,0)) / 1000) AS NVARCHAR(100)) + ' seconds over the last ' + CAST(@Seconds AS NVARCHAR(10)) + ' seconds, SQL Server was waiting on this particular bottleneck.' + @LineFeed + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'See the URL for more details on how to mitigate this wait type.' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM #WaitStats wNow
	LEFT OUTER JOIN #WaitStats wBase ON wNow.wait_type = wBase.wait_type AND wNow.SampleTime > wBase.SampleTime
	WHERE wNow.wait_time_ms > (wBase.wait_time_ms + (.5 * @Seconds * 1000)) /* Only look for things we've actually waited on for half of the time or more */
	AND wNow.wait_type NOT IN ('REQUEST_FOR_DEADLOCK_SEARCH','SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_BUFFER_FLUSH',
	'LAZYWRITER_SLEEP','XE_TIMER_EVENT','XE_DISPATCHER_WAIT','FT_IFTS_SCHEDULER_IDLE_WAIT','LOGMGR_QUEUE','CHECKPOINT_QUEUE',
	'BROKER_TO_FLUSH','BROKER_TASK_STOP','BROKER_EVENTHANDLER','BROKER_TRANSMITTER','SLEEP_TASK','WAITFOR','DBMIRROR_DBM_MUTEX',
	'DBMIRROR_EVENTS_QUEUE','DBMIRRORING_CMD','DISPATCHER_QUEUE_SEMAPHORE','BROKER_RECEIVE_WAITFOR','CLR_AUTO_EVENT',
	'DIRTY_PAGE_POLL','CLR_SEMAPHORE','HADR_FILESTREAM_IOMGR_IOCOMPLETION','ONDEMAND_TASK_QUEUE','FT_IFTSHC_MUTEX',
	'CLR_MANUAL_EVENT','SP_SERVER_DIAGNOSTICS_SLEEP','DBMIRROR_WORKER_QUEUE','DBMIRROR_DBM_EVENT')
	ORDER BY (wNow.wait_time_ms - COALESCE(wBase.wait_time_ms,0)) DESC;

	/* Server Performance - Slow Data File Reads - CheckID 11 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, DatabaseID, DatabaseName)
	SELECT TOP 10 11 AS CheckID,
		50 AS Priority,
		'Server Performance' AS FindingGroup,
		'Slow Data File Reads' AS Finding,
		'http://BrentOzar.com/go/slow/' AS URL,
		@StockDetailsHeader + 'File: ' + fNow.PhysicalName + @LineFeed 
			+ 'Number of reads during the sample: ' + CAST((fNow.num_of_reads - fBase.num_of_reads) AS NVARCHAR(20)) + @LineFeed 
			+ 'Seconds spent waiting on storage for these reads: ' + CAST(((fNow.io_stall_read_ms - fBase.io_stall_read_ms) / 1000.0) AS NVARCHAR(20)) + @LineFeed 
			+ 'Average read latency during the sample: ' + CAST(((fNow.io_stall_read_ms - fBase.io_stall_read_ms) / (fNow.num_of_reads - fBase.num_of_reads) ) AS NVARCHAR(20)) + ' milliseconds' + @LineFeed 
			+ 'Microsoft guidance for data file read speed: 20ms or less.' + @LineFeed + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'See the URL for more details on how to mitigate this wait type.' + @StockWarningFooter AS XML) AS HowToStopIt,
		fNow.DatabaseID,
		fNow.DatabaseName
	FROM #FileStats fNow
	INNER JOIN #FileStats fBase ON fNow.DatabaseID = fBase.DatabaseID AND fNow.FileID = fBase.FileID AND fNow.SampleTime > fBase.SampleTime AND fNow.num_of_reads > fBase.num_of_reads AND fNow.io_stall_read_ms > (fBase.io_stall_read_ms + 1000)
	WHERE (fNow.io_stall_read_ms - fBase.io_stall_read_ms) / (fNow.num_of_reads - fBase.num_of_reads) > 100
		AND fNow.TypeDesc = 'ROWS'
	ORDER BY (fNow.io_stall_read_ms - fBase.io_stall_read_ms) / (fNow.num_of_reads - fBase.num_of_reads) DESC;

	/* Server Performance - Slow Log File Writes - CheckID 12 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, DatabaseID, DatabaseName)
	SELECT TOP 10 12 AS CheckID,
		50 AS Priority,
		'Server Performance' AS FindingGroup,
		'Slow Log File Writes' AS Finding,
		'http://BrentOzar.com/go/slow/' AS URL,
		@StockDetailsHeader + 'File: ' + fNow.PhysicalName + @LineFeed 
			+ 'Number of writes during the sample: ' + CAST((fNow.num_of_writes - fBase.num_of_writes) AS NVARCHAR(20)) + @LineFeed 
			+ 'Seconds spent waiting on storage for these writes: ' + CAST(((fNow.io_stall_write_ms - fBase.io_stall_write_ms) / 1000.0) AS NVARCHAR(20)) + @LineFeed 
			+ 'Average write latency during the sample: ' + CAST(((fNow.io_stall_write_ms - fBase.io_stall_write_ms) / (fNow.num_of_writes - fBase.num_of_writes) ) AS NVARCHAR(20)) + ' milliseconds' + @LineFeed 
			+ 'Microsoft guidance for log file write speed: 3ms or less.' + @LineFeed + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'See the URL for more details on how to mitigate this wait type.' + @StockWarningFooter AS XML) AS HowToStopIt,
		fNow.DatabaseID,
		fNow.DatabaseName
	FROM #FileStats fNow
	INNER JOIN #FileStats fBase ON fNow.DatabaseID = fBase.DatabaseID AND fNow.FileID = fBase.FileID AND fNow.SampleTime > fBase.SampleTime AND fNow.num_of_writes > fBase.num_of_writes AND fNow.io_stall_write_ms > (fBase.io_stall_write_ms + 1000)
	WHERE (fNow.io_stall_write_ms - fBase.io_stall_write_ms) / (fNow.num_of_writes - fBase.num_of_writes) > 100
		AND fNow.TypeDesc = 'LOG'
	ORDER BY (fNow.io_stall_write_ms - fBase.io_stall_write_ms) / (fNow.num_of_writes - fBase.num_of_writes) DESC;


	/* SQL Server Internal Maintenance - Log File Growing - CheckID 13 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT 13 AS CheckID,
		1 AS Priority,
		'SQL Server Internal Maintenance' AS FindingGroup,
		'Log File Growing' AS Finding,
		'http://BrentOzar.com/askbrent/file-growing/' AS URL,
		@StockDetailsHeader + 'Number of growths during the sample: ' + CAST(ps.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'Determined by sampling Perfmon counter ' + ps.object_name + ' - ' + ps.counter_name + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'Pre-grow data and log files during maintenance windows so that they do not grow during production loads.' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM #PerfmonStats ps
	WHERE ps.Pass = 2
		AND object_name = 'SQLServer:Databases'
		AND counter_name = 'Log Growths'
		AND value_delta > 0


	/* SQL Server Internal Maintenance - Log File Shrinking - CheckID 14 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT 14 AS CheckID,
		1 AS Priority,
		'SQL Server Internal Maintenance' AS FindingGroup,
		'Log File Shrinking' AS Finding,
		'http://BrentOzar.com/askbrent/file-shrinking/' AS URL,
		@StockDetailsHeader + 'Number of shrinks during the sample: ' + CAST(ps.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'Determined by sampling Perfmon counter ' + ps.object_name + ' - ' + ps.counter_name + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'Pre-grow data and log files during maintenance windows so that they do not grow during production loads.' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM #PerfmonStats ps
	WHERE ps.Pass = 2
		AND object_name = 'SQLServer:Databases'
		AND counter_name = 'Log Shrinks'
		AND value_delta > 0

	/* Query Problems - Compilations/Sec High - CheckID 15 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT 15 AS CheckID,
		50 AS Priority,
		'Query Problems' AS FindingGroup,
		'Compilations/Sec High' AS Finding,
		'http://BrentOzar.com/askbrent/compilations/' AS URL,
		@StockDetailsHeader + 'Number of batch requests during the sample: ' + CAST(ps.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'Number of compilations during the sample: ' + CAST(psComp.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'For OLTP environments, Microsoft recommends that 90% of batch requests should hit the plan cache, and not be compiled from scratch. We are exceeding that threshold.' + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'Find out why plans are not being reused, and consider enabling Forced Parameterization. See the URL for more details.' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM #PerfmonStats ps
		INNER JOIN #PerfmonStats psComp ON psComp.Pass = 2 AND psComp.object_name = 'SQLServer:SQL Statistics' AND psComp.counter_name = 'SQL Compilations/sec' AND psComp.value_delta > 0
	WHERE ps.Pass = 2
		AND ps.object_name = 'SQLServer:SQL Statistics'
		AND ps.counter_name = 'Batch Requests/sec'
		AND ps.value_delta > 100 /* Ignore servers sitting idle */
		AND (psComp.value_delta * 10) > ps.value_delta /* Compilations are more than 10% of batch requests per second */

	/* Query Problems - Re-Compilations/Sec High - CheckID 16 */
	INSERT INTO #AskBrentResults (CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt)
	SELECT 16 AS CheckID,
		50 AS Priority,
		'Query Problems' AS FindingGroup,
		'Re-Compilations/Sec High' AS Finding,
		'http://BrentOzar.com/askbrent/recompilations/' AS URL,
		@StockDetailsHeader + 'Number of batch requests during the sample: ' + CAST(ps.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'Number of recompilations during the sample: ' + CAST(psComp.value_delta AS NVARCHAR(20)) + @LineFeed 
			+ 'More than 10% of our queries are being recompiled. This is typically due to statistics changing on objects.' + @LineFeed AS Details,
		CAST(@StockWarningHeader + 'Find out which objects are changing so quickly that they hit the stats update threshold. See the URL for more details.' + @StockWarningFooter AS XML) AS HowToStopIt
	FROM #PerfmonStats ps
		INNER JOIN #PerfmonStats psComp ON psComp.Pass = 2 AND psComp.object_name = 'SQLServer:SQL Statistics' AND psComp.counter_name = 'SQL Re-Compilations/sec' AND psComp.value_delta > 0
	WHERE ps.Pass = 2
		AND ps.object_name = 'SQLServer:SQL Statistics'
		AND ps.counter_name = 'Batch Requests/sec'
		AND ps.value_delta > 100 /* Ignore servers sitting idle */
		AND (psComp.value_delta * 10) > ps.value_delta /* Recompilations are more than 10% of batch requests per second */


	/* If we didn't find anything, apologize. */
	IF NOT EXISTS (SELECT * FROM #AskBrentResults)
	BEGIN

		INSERT  INTO #AskBrentResults
				( CheckID ,
				  Priority ,
				  FindingsGroup ,
				  Finding ,
				  URL ,
				  Details
				)
		VALUES  ( -1 ,
				  255 ,
				  'No Problems Found' ,
				  'From Brent Ozar Unlimited' ,
				  'http://www.BrentOzar.com/askbrent/' ,
				  @StockDetailsHeader + 'Try running our more in-depth checks: http://www.BrentOzar.com/blitz/' + @LineFeed + 'or there may not be an unusual SQL Server performance problem. ' + @StockDetailsFooter
				);
		
	END /*IF NOT EXISTS (SELECT * FROM #AskBrentResults) */
	ELSE /* We found stuff, so add credits */
	BEGIN
		/* Close out the XML field Details by adding a footer */
		UPDATE #AskBrentResults
		  SET Details = Details + @StockDetailsFooter;

		/* Add credits for the nice folks who put so much time into building and maintaining this for free: */                    
		INSERT  INTO #AskBrentResults
				( CheckID ,
				  Priority ,
				  FindingsGroup ,
				  Finding ,
				  URL ,
				  Details
				)
		VALUES  ( -1 ,
				  255 ,
				  'Thanks!' ,
				  'From Brent Ozar Unlimited' ,
				  'http://www.BrentOzar.com/askbrent/' ,
				  '<?Thanks --' + @LineFeed + 'Thanks from the Brent Ozar Unlimited team.  We hope you found this tool useful, and if you need help relieving your SQL Server pains, email us at Help@BrentOzar.com. ' + @LineFeed + '-- ?>'
				);

		INSERT  INTO #AskBrentResults
				( CheckID ,
				  Priority ,
				  FindingsGroup ,
				  Finding ,
				  URL ,
				  Details

				)
		VALUES  ( -1 ,
				  0 ,
				  'sp_AskBrent (TM) v' + CAST(@Version AS VARCHAR(20)) + ' as of ' + CAST(CONVERT(DATETIME, @VersionDate, 102) AS VARCHAR(100)),
				  'From Brent Ozar Unlimited' ,
				  'http://www.BrentOzar.com/askbrent/' ,
				  '<?Thanks --' + @LineFeed + 'Thanks from the Brent Ozar Unlimited team.  We hope you found this tool useful, and if you need help relieving your SQL Server pains, email us at Help@BrentOzar.com.' + @LineFeed + ' -- ?>'
				);

	END /* ELSE  We found stuff, so add credits */

	/* @OutputTableName lets us export the results to a permanent table */
	IF @OutputDatabaseName IS NOT NULL
		AND @OutputSchemaName IS NOT NULL
		AND @OutputTableName IS NOT NULL
		AND EXISTS ( SELECT *
					 FROM   sys.databases
					 WHERE  QUOTENAME([name]) = @OutputDatabaseName) 
	BEGIN
		SET @StringToExecute = 'USE '
			+ @OutputDatabaseName
			+ '; IF EXISTS(SELECT * FROM '
			+ @OutputDatabaseName
			+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
			+ @OutputSchemaName
			+ ''') AND NOT EXISTS (SELECT * FROM '
			+ @OutputDatabaseName
			+ '.INFORMATION_SCHEMA.TABLES WHERE QUOTENAME(TABLE_SCHEMA) = '''
			+ @OutputSchemaName + ''' AND QUOTENAME(TABLE_NAME) = '''
			+ @OutputTableName + ''') CREATE TABLE '
			+ @OutputSchemaName + '.'
			+ @OutputTableName
			+ ' (ID INT IDENTITY(1,1) NOT NULL, 
				ServerName NVARCHAR(128), 
				CheckDate DATETIME, 
				AskBrentVersion INT,
				CheckID INT NOT NULL,
				Priority TINYINT NOT NULL,
				FindingsGroup VARCHAR(50) NOT NULL,
				Finding VARCHAR(200) NOT NULL,
				URL VARCHAR(200) NOT NULL,
				Details NVARCHAR(4000) NULL,
				HowToStopIt [XML] NULL,
				QueryPlan [XML] NULL,
				QueryText NVARCHAR(MAX) NULL,
				StartTime DATETIME NULL,
				LoginName NVARCHAR(128) NULL,
				NTUserName NVARCHAR(128) NULL,
				OriginalLoginName NVARCHAR(128) NULL,
				ProgramName NVARCHAR(128) NULL,
				HostName NVARCHAR(128) NULL,
				DatabaseID INT NULL,
				DatabaseName NVARCHAR(128) NULL,
				OpenTransactionCount INT NULL,
				CONSTRAINT [PK_' + CAST(NEWID() AS CHAR(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));'

		EXEC(@StringToExecute);
		SET @StringToExecute = N' IF EXISTS(SELECT * FROM '
			+ @OutputDatabaseName
			+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
			+ @OutputSchemaName + ''') INSERT '
			+ @OutputDatabaseName + '.'
			+ @OutputSchemaName + '.'
			+ @OutputTableName
			+ ' (ServerName, CheckDate, AskBrentVersion, CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText, StartTime, LoginName, NTUserName, OriginalLoginName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount) SELECT '''
			+ CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128))
			+ ''', GETDATE(), ' + CAST(@Version AS NVARCHAR(128))
			+ ', CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText, StartTime, LoginName, NTUserName, OriginalLoginName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount FROM #AskBrentResults ORDER BY Priority , FindingsGroup , Finding , Details';
		EXEC(@StringToExecute);
	END
	ELSE IF (SUBSTRING(@OutputTableName, 2, 2) = '##')
	BEGIN
		SET @StringToExecute = N' IF (OBJECT_ID(''tempdb..'
			+ @OutputTableName
			+ ''') IS NOT NULL) DROP TABLE ' + @OutputTableName + ';'
			+ 'CREATE TABLE '
			+ @OutputTableName
			+ ' (ID INT IDENTITY(1,1) NOT NULL, 
				ServerName NVARCHAR(128), 
				CheckDate DATETIME, 
				AskBrentVersion INT,
				CheckID INT NOT NULL,
				Priority TINYINT NOT NULL,
				FindingsGroup VARCHAR(50) NOT NULL,
				Finding VARCHAR(200) NOT NULL,
				URL VARCHAR(200) NOT NULL,
				Details NVARCHAR(4000) NULL,
				HowToStopIt [XML] NULL,
				QueryPlan [XML] NULL,
				QueryText NVARCHAR(MAX) NULL,
				StartTime DATETIME NULL,
				LoginName NVARCHAR(128) NULL,
				NTUserName NVARCHAR(128) NULL,
				OriginalLoginName NVARCHAR(128) NULL,
				ProgramName NVARCHAR(128) NULL,
				HostName NVARCHAR(128) NULL,
				DatabaseID INT NULL,
				DatabaseName NVARCHAR(128) NULL,
				OpenTransactionCount INT NULL,
				CONSTRAINT [PK_' + CAST(NEWID() AS CHAR(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));'
			+ ' INSERT '
			+ @OutputTableName
			+ ' (ServerName, CheckDate, AskBrentVersion, CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText, StartTime, LoginName, NTUserName, OriginalLoginName, ProgramName, HostName, DatabaseID, DatabaseName, Op) SELECT '''
			+ CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128))
			+ ''', GETDATE(), ' + CAST(@Version AS NVARCHAR(128))
			+ ', CheckID, Priority, FindingsGroup, Finding, URL, Details, HowToStopIt, QueryPlan, QueryText, StartTime, LoginName, NTUserName, OriginalLoginName, ProgramName, HostName, DatabaseID, DatabaseName, OpenTransactionCount FROM #AskBrentResults ORDER BY Priority , FindingsGroup , Finding , Details';
		EXEC(@StringToExecute);
	END
	ELSE IF (SUBSTRING(@OutputTableName, 2, 1) = '#')
	BEGIN
		RAISERROR('Due to the nature of Dymamic SQL, only global (i.e. double pound (##)) temp tables are supported for @OutputTableName', 16, 0)
	END


	DECLARE @separator AS VARCHAR(1);
	IF @OutputType = 'RSV' 
		SET @separator = CHAR(31);
	ELSE 
		SET @separator = ',';

	IF @OutputType = 'COUNT' 
	BEGIN
		SELECT  COUNT(*) AS Warnings
		FROM    #AskBrentResults
	END
	ELSE 
		IF @OutputType IN ( 'CSV', 'RSV' ) 
		BEGIN

			SELECT  Result = CAST([Priority] AS NVARCHAR(100))
					+ @separator + CAST(CheckID AS NVARCHAR(100))
					+ @separator + COALESCE([FindingsGroup],
											'(N/A)') + @separator
					+ COALESCE([Finding], '(N/A)') + @separator
					+ COALESCE(DatabaseName, '(N/A)') + @separator
					+ COALESCE([URL], '(N/A)') + @separator
					+ COALESCE([Details], '(N/A)')
			FROM    #AskBrentResults
			ORDER BY Priority ,
					FindingsGroup ,
					Finding ,
					Details;
		END
		ELSE IF @ExpertMode = 0 AND @OutputXMLasNVARCHAR = 0
		BEGIN
			SELECT  [Priority] ,
					[FindingsGroup] ,
					[Finding] ,
					[URL] ,
					CAST([Details] AS [XML]) AS Details,
					[HowToStopIt],
					[QueryText],
					[QueryPlan]
			FROM    #AskBrentResults
			ORDER BY Priority ,
					FindingsGroup ,
					Finding ,
					ID;
		END
		ELSE IF @ExpertMode = 0 AND @OutputXMLasNVARCHAR = 1
		BEGIN
			SELECT  [Priority] ,
					[FindingsGroup] ,
					[Finding] ,
					[URL] ,
					CAST([Details] AS NVARCHAR(MAX)) AS Details,
					CAST([HowToStopIt] AS NVARCHAR(MAX)) AS HowToStopIt,
					CAST([QueryText] AS NVARCHAR(MAX)) AS QueryText,
					CAST([QueryPlan] AS NVARCHAR(MAX)) AS QueryPlan
			FROM    #AskBrentResults
			ORDER BY Priority ,
					FindingsGroup ,
					Finding ,
					ID;
		END
		ELSE IF @ExpertMode = 1
		BEGIN
			SELECT  [Priority] ,
					[FindingsGroup] ,
					[Finding] ,
					[URL] ,
					CAST([Details] AS [XML]) AS Details,
					[HowToStopIt] ,
					[CheckID] ,
					[StartTime],
					[LoginName],
					[NTUserName],
					[OriginalLoginName],
					[ProgramName],
					[HostName],
					[DatabaseID],
					[DatabaseName],
					[OpenTransactionCount],
					[QueryPlan],
					[QueryText]
			FROM    #AskBrentResults
			ORDER BY Priority ,
					FindingsGroup ,
					Finding ,
					ID;

			-------------------------
			--What happened: #WaitStats
			-------------------------
			;with max_batch as (
				select max(SampleTime) as SampleTime
				from #WaitStats
			)
			SELECT
				'WAIT STATS' as Pattern,
				b.SampleTime as [Sample Ended],
				datediff(ss,wd1.SampleTime, wd2.SampleTime) as [Seconds Sample],
				wd1.wait_type,
				c.[Wait Time (Seconds)],
				c.[Signal Wait Time (Seconds)],
				CASE WHEN c.[Wait Time (Seconds)] > 0
				 THEN CAST(100.*(c.[Signal Wait Time (Seconds)]/c.[Wait Time (Seconds)]) as NUMERIC(4,1))
				ELSE 0 END AS [Percent Signal Waits],
				(wd2.waiting_tasks_count - wd1.waiting_tasks_count) AS [Number of Waits],
				CASE WHEN (wd2.waiting_tasks_count - wd1.waiting_tasks_count) > 0
				THEN
					cast((wd2.wait_time_ms-wd1.wait_time_ms)/
						(1.0*(wd2.waiting_tasks_count - wd1.waiting_tasks_count)) as numeric(10,1))
				ELSE 0 END AS [Avg ms Per Wait]
			FROM  max_batch b
			JOIN #WaitStats wd2 on
				wd2.SampleTime =b.SampleTime
			JOIN #WaitStats wd1 ON 
				wd1.wait_type=wd2.wait_type AND
				wd2.SampleTime > wd1.SampleTime
			CROSS APPLY (SELECT
				cast((wd2.wait_time_ms-wd1.wait_time_ms)/1000. as numeric(10,1)) as [Wait Time (Seconds)],
				cast((wd2.signal_wait_time_ms - wd1.signal_wait_time_ms)/1000. as numeric(10,1)) as [Signal Wait Time (Seconds)]) AS c
			WHERE (wd2.waiting_tasks_count - wd1.waiting_tasks_count) > 0
				and wd2.wait_time_ms-wd1.wait_time_ms > 0
			ORDER BY [Wait Time (Seconds)] DESC;


			-------------------------
			--What happened: #FileStats
			-------------------------
			WITH readstats as (
				SELECT 'PHYSICAL READS' as Pattern,
				ROW_NUMBER() over (order by wd2.avg_stall_read_ms desc) as StallRank,
				wd2.SampleTime as [Sample Time], 
				datediff(ss,wd1.SampleTime, wd2.SampleTime) as [Sample (seconds)],
				wd1.DatabaseName ,
				wd1.FileLogicalName AS [File Name],
				UPPER(SUBSTRING(wd1.PhysicalName, 1, 2)) AS [Drive] ,
				wd1.SizeOnDiskMB ,
				( wd2.num_of_reads - wd1.num_of_reads ) AS [# Reads/Writes],
				CASE WHEN wd2.num_of_reads - wd1.num_of_reads > 0
				  THEN CAST(( wd2.bytes_read - wd1.bytes_read)/1024./1024. AS NUMERIC(21,1)) 
				  ELSE 0 
				END AS [MB Read/Written],
				wd2.avg_stall_read_ms AS [Avg Stall (ms)],
				wd1.PhysicalName AS [file physical name]
			FROM #FileStats wd2
				JOIN #FileStats wd1 ON wd2.SampleTime > wd1.SampleTime
				  AND wd1.DatabaseID = wd2.DatabaseID
				  AND wd1.FileID = wd2.FileID
			),
			writestats as (
				SELECT 
				'PHYSICAL WRITES' as Pattern,
				ROW_NUMBER() over (order by wd2.avg_stall_write_ms desc) as StallRank,
				wd2.SampleTime as [Sample Time], 
				datediff(ss,wd1.SampleTime, wd2.SampleTime) as [Sample (seconds)],
				wd1.DatabaseName ,
				wd1.FileLogicalName AS [File Name],
				UPPER(SUBSTRING(wd1.PhysicalName, 1, 2)) AS [Drive] ,
				wd1.SizeOnDiskMB ,
				( wd2.num_of_writes - wd1.num_of_writes ) AS [# Reads/Writes],
				CASE WHEN wd2.num_of_writes - wd1.num_of_writes > 0
				  THEN CAST(( wd2.bytes_written - wd1.bytes_written)/1024./1024. AS NUMERIC(21,1)) 
				  ELSE 0 
				END AS [MB Read/Written],
				wd2.avg_stall_write_ms AS [Avg Stall (ms)],
				wd1.PhysicalName AS [file physical name]
			FROM #FileStats wd2
				JOIN #FileStats wd1 ON wd2.SampleTime > wd1.SampleTime
				  AND wd1.DatabaseID = wd2.DatabaseID
				  AND wd1.FileID = wd2.FileID
			)
			SELECT 
				Pattern, [Sample Time], [Sample (seconds)], [File Name], [Drive],  [# Reads/Writes],[MB Read/Written],[Avg Stall (ms)], [file physical name]
			from readstats
			where StallRank <=5 and [MB Read/Written] > 0
			union all
			SELECT Pattern, [Sample Time], [Sample (seconds)], [File Name], [Drive],  [# Reads/Writes],[MB Read/Written],[Avg Stall (ms)], [file physical name]
			from writestats
			where StallRank <=5 and [MB Read/Written] > 0;


			-------------------------
			--What happened: #PerfmonStats
			-------------------------

			SELECT 'PERFMON' AS Pattern, pLast.[object_name], pLast.counter_name, pLast.instance_name, 
				pFirst.SampleTime AS FirstSampleTime, pFirst.cntr_value AS FirstSampleValue,
				pLast.SampleTime AS LastSampleTime, pLast.cntr_value AS LastSampleValue,
				pLast.cntr_value - pFirst.cntr_value AS ValueDelta,
				((1.0 * pLast.cntr_value - pFirst.cntr_value) / DATEDIFF(ss, pFirst.SampleTime, pLast.SampleTime)) AS ValuePerSecond
				FROM #PerfmonStats pLast
					INNER JOIN #PerfmonStats pFirst ON pFirst.[object_name] = pLast.[object_name] AND pFirst.counter_name = pLast.counter_name AND (pFirst.instance_name = pLast.instance_name OR (pFirst.instance_name IS NULL AND pLast.instance_name IS NULL))
					AND pLast.ID > pFirst.ID
				ORDER BY Pattern, pLast.[object_name], pLast.counter_name, pLast.instance_name


			-------------------------
			--What happened: #FileStats
			-------------------------
			SELECT qsNow.*, qsFirst.*
			FROM #QueryStats qsNow
			  INNER JOIN #QueryStats qsFirst ON qsNow.[sql_handle] = qsFirst.[sql_handle] AND qsNow.statement_start_offset = qsFirst.statement_start_offset AND qsNow.statement_end_offset = qsFirst.statement_end_offset AND qsNow.plan_generation_num = qsFirst.plan_generation_num AND qsNow.plan_handle = qsFirst.plan_handle AND qsFirst.Pass = 1
			WHERE qsNow.Pass = 2
		END

	DROP TABLE #AskBrentResults;


END /* IF @Question IS NULL */
ELSE IF @Question IS NOT NULL 

/* We're playing Magic SQL 8 Ball, so give them an answer. */
BEGIN
	IF OBJECT_ID('tempdb..#BrentAnswers') IS NOT NULL 
		DROP TABLE #BrentAnswers;
	CREATE TABLE #BrentAnswers(Answer VARCHAR(200) NOT NULL);
	INSERT INTO #BrentAnswers VALUES ('It sounds like a SAN problem.');
	INSERT INTO #BrentAnswers VALUES ('You know what you need? Bacon.');
	INSERT INTO #BrentAnswers VALUES ('Talk to the developers about that.');
	INSERT INTO #BrentAnswers VALUES ('Let''s post that on StackOverflow.com and find out.');
	INSERT INTO #BrentAnswers VALUES ('Have you tried adding an index?');
	INSERT INTO #BrentAnswers VALUES ('Have you tried dropping an index?');
	INSERT INTO #BrentAnswers VALUES ('You can''t prove anything.');
	INSERT INTO #BrentAnswers VALUES ('If you watched our Tuesday webcasts, you''d already know the answer to that.');
	INSERT INTO #BrentAnswers VALUES ('Please phrase the question in the form of an answer.');
	INSERT INTO #BrentAnswers VALUES ('Outlook not so good. Access even worse.');
	INSERT INTO #BrentAnswers VALUES ('Did you try asking the rubber duck? http://www.codinghorror.com/blog/2012/03/rubber-duck-problem-solving.html');
	INSERT INTO #BrentAnswers VALUES ('Oooo, I read about that once.');
	INSERT INTO #BrentAnswers VALUES ('I feel your pain.');
	INSERT INTO #BrentAnswers VALUES ('http://LMGTFY.com');
	INSERT INTO #BrentAnswers VALUES ('No comprende Ingles, senor.');
	INSERT INTO #BrentAnswers VALUES ('I don''t have that problem on my Mac.');
	INSERT INTO #BrentAnswers VALUES ('Is Priority Boost on?');
	INSERT INTO #BrentAnswers VALUES ('Have you tried rebooting your machine?');
	INSERT INTO #BrentAnswers VALUES ('Try defragging your cursors.');
	INSERT INTO #BrentAnswers VALUES ('Why are you wearing that? Do you have a job interview later or something?');
	INSERT INTO #BrentAnswers VALUES ('I''m ashamed that you don''t know the answer to that question.');
	INSERT INTO #BrentAnswers VALUES ('What do I look like, a Microsoft Certified Master? Oh, wait...');
	INSERT INTO #BrentAnswers VALUES ('Duh, Debra.');
	SELECT TOP 1 Answer FROM #BrentAnswers ORDER BY NEWID();
END

END /* ELSE IF @OutputType = 'SCHEMA' */


SET NOCOUNT OFF;


GO
/****** Object:  StoredProcedure [dbo].[sp_Blitz]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_Blitz]
    @CheckUserDatabaseObjects TINYINT = 1 ,
    @CheckProcedureCache TINYINT = 0 ,
    @OutputType VARCHAR(20) = 'TABLE' ,
    @OutputProcedureCache TINYINT = 0 ,
    @CheckProcedureCacheFilter VARCHAR(10) = NULL ,
    @CheckServerInfo TINYINT = 0 ,
    @SkipChecksServer NVARCHAR(256) = NULL ,
    @SkipChecksDatabase NVARCHAR(256) = NULL ,
    @SkipChecksSchema NVARCHAR(256) = NULL ,
    @SkipChecksTable NVARCHAR(256) = NULL ,
    @IgnorePrioritiesBelow INT = NULL ,
    @IgnorePrioritiesAbove INT = NULL ,
    @OutputDatabaseName NVARCHAR(128) = NULL ,
    @OutputSchemaName NVARCHAR(256) = NULL ,
    @OutputTableName NVARCHAR(256) = NULL ,
    @OutputXMLasNVARCHAR TINYINT = 0 ,
    @Version INT = NULL OUTPUT,
    @VersionDate DATETIME = NULL OUTPUT
AS 
    SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	/*
	sp_Blitz (TM) v30 - Oct 12, 2016
    
	(C) 2016, Brent Ozar Unlimited. 
	See http://BrentOzar.com/go/eula for the End User Licensing Agreement.

	To learn more, visit http://www.BrentOzar.com/blitz where you can download
	new versions for free, watch training videos on how it works, get more info on
	the findings, and more.  To contribute code and see your name in the change
	log, email your improvements & checks to Help@BrentOzar.com.

	Sample execution call with the most common parameters:

	EXEC [master].[dbo].[sp_Blitz]
		@CheckUserDatabaseObjects = 1 ,
		@CheckProcedureCache = 0 ,
		@OutputType = 'TABLE' ,
		@OutputProcedureCache = 0 ,
		@CheckProcedureCacheFilter = NULL,
		@CheckServerInfo = 1

	Known limitations of this version:
	 - No support for SQL Server 2000 or compatibility mode 80.
	 - If a database name has a question mark in it, some tests will fail.  Gotta
	   love that unsupported sp_MSforeachdb.
	 - If you have offline databases, sp_Blitz fails the first time you run it,
	   but does work the second time. (Hoo, boy, this will be fun to fix.)

	Unknown limitations of this version:
	 - None.  (If we knew them, they'd be known.  Duh.)

	Changes in v30 - October 12, 2016
	 - Doug Lane @TheDougLane:
		- Fixed bug in check 99 for unusual editions so that it doesn't alert
		  on BI Edition, since that's the same as Standard Edition.
		- Fixed bug in check 32 so that it won't alert on SSRS ReportServer
		  database triggers, which are actually MS-shipped but aren't marked
		  with the is_ms_shipped flag.
	 - Ross Whitehead @RWhitehead99 fixed a bug in check 111 (broken log shipping) 
	   so that it doesn't alert on database mirrors.
	 - Russell Hart @Rus_Hart fixed a bug with the @VersionDate format that broke
	   in British English language settings.

	Changes in v29 - August 23, 2016
	 - Added @OutputType = 'SCHEMA', which returns the version number and a list
	   of columns for a CREATE TABLE definition for the default outputs. We don't
	   include the actual CREATE TABLE part because you might want to use a table
	   variable or whatever.
	 - Added @OutputXMLasNVARCHAR. If 1, then the QueryPlan is outputted as an
	   NVARCHAR(MAX) instead of XML. This helps if you want to insert the
	   sp_Blitz results into a temp table. For instructions, visit:
	   http://www.brentozar.com/blitz/documentation/

	Changes in v28 - August 21, 2016
	 - Tom Meyer improved several backup checks so that they'll work if the master
	   and msdb databases have different collations, like if someone restores
	   msdb from another server with a different collation. (Please don't do that.)
	 - Fixed a bug in the VLF check that added a trailing space in the URL. This
	   broke the PDF output in the Windows app.

	Changes in v27 - August 6, 2016
	 - Whoops! Even more bug fixes in check 114. Thanks, Andy Jarman!

	Changes in v26 - August 2, 2016
	 - Whoops! Improved check 114 to skip SQL Server 2005, since the necessary
	   DMVs don't exist there. Thanks, Conan Farrell.

	Changes in v25 - August 2, 2016
	 - Andrew Jarman was the first to catch a bug in check 70 for named instances.
	 - David Todd suggested a tweak to make it easier to deploy this stored proc
	   in other databases.
	 - Added check for Adam Machanic's make_parallel function (115).
	 - Added check for basic NUMA config (114).
	 - Added check for backup compression defaulted to off (116), suggested by
	   David Todd.
	 - Added check for forced grants in sys.dm_exec_query_resource_semaphores,
	   indicating memory pressure is affecting query performance (117).

    Changes in v24 - June 23, 2016
	 - Alin Selicean @AlinSelicean:
	   - debugged check 72 for non-aligned partitioned indexes.
	   - improved check 70 for the @@servername variable.
	 - Andreas Schubert debugged check 14 to remove duplicate results.
	 - Josh Duewer added check 112 looking for change tracking.
	 - Justin Dearing @Zippy1981 improved @OutputTableName to export the results
	   to a global temp table.
	 - Katie Vetter improved check 6 for jobs owned by <> SA, by removing the join
	   to sys.server_principals and using a function for the name instead.
	 - Kevin Frazier improved check 106 by removing extra copy/paste code.
	 - Mike Eastland added check 111 looking for broken log shipping subscribers.
	 - Added check 110 for memory nodes offline.
	 - Added check 113 for full text indexes not crawled in the last week.
	 - Changed VLF threshold from 50 to 1,000. We were getting a lot of questions
	   about databases with 51-100 VLFs, and that's just not a real performance
	   killer. To minimize false alarms, we cranked the threshold way up. Let's
	   get you focused on making sure your databases are backed up first.
	 - Fixed bugs in @SkipChecks tables. Man, there's no way any of you were
	   using that thing, because it was chock full of nuts.
	 - Added basic SQL Server 2016 compatibility.

	Changes in v23 - June 2, 2016:
	 - Katherine Villyard @geekg0dd3ss caught bug in check 72 (non-aligned 
	   partitioned indexes) that wasn't honoring @CheckUserDatabaseObjects.
	 - Paul Olson http://www.SQLsprawl.com wrote check 106 to show how much
	   history is being kept in the default traces, and where they are. Only runs
	   if @CheckServerInfo = 1.
	 - Randall Stone suggested ignoring ReportServer% databases in the collation
	   checks. Prior versions of the checks were only ignoring default name
	   instances of SSRS.
	 - Added checks for "poison" wait types: THREADPOOL, RESOURCE_SEMAPHORE, and
	   RESOURCE_SEMAPHORE_QUERY_COMPILE. Any occurrence of these waits often
	   indicates a killer performance issue. Checks 107-109.
	 - Non-default sp_configure options used to be CheckID 22 for all possible
	   sp_configure settings. Now we use the range 1,000-1,999 for sp_configure.
	   This way, if you're writing a tool that outputs specific advice for each
	   CheckID, you can get more specific with the advice based on which
	   sp_configure option has been changed.
	 - Fixed various typos.

	Changes in v22 - May 6, 2016:
	 - Fixed new v21 case sensitivity bug reported by several users.
	 - Cleaned up some typos in script output.

	Changes in v21 - April 25, 2016:
	 - Easier readability - cleaned up the code with Red Gate SQL Prompt, plus
	   added comments explaining what's happening.
	 - Added @OutputDatabaseName, @OutputSchemaName, @OutputTableName. If set, the 
	   #BlitzResults table is saved into that. Only outputs the check results, not
	   the plan cache. Suggested by Robbert Hof and Andy Bassitt.
	 - Alin Selicean @AlinSelicean:
	   - Added check 100 looking for disabled remote access to the DAC.
	   - Added check 101 looking for disabled CPU schedulers due to licensing or
		 affinity masking.
	 - Chris Leavitt coded check 103 looking for virtualization.
	 - Mike Eastland suggested check 102 for databases in unusual states - suspect,
	   recovering, emergency, etc.
	 - Russell Hart coded check 104 looking for logins with CONTROL SERVER perms.
	 - Added check 105 looking for extended stored procedures in master.
	 - Moved temp table creation up to the top of the sproc while trying to fix an
	   issue with offline databases. I like it up there, so leaving it. Didn't fix
	   the issue, but ah well.
	 - Moved the old changes to http://www.BrentOzar.com/blitz/changelog/

	For prior changes, see http://www.BrentOzar.com/blitz/changelog/
	*/


	SELECT @Version = 30, @VersionDate = '20161012'

	IF @OutputType = 'SCHEMA'
	BEGIN
		SELECT @Version AS Version,
		FieldList = '[Priority] TINYINT, [FindingsGroup] VARCHAR(50), [Finding] VARCHAR(200), [DatabaseName] NVARCHAR(128), [URL] VARCHAR(200), [Details] NVARCHAR(4000), [QueryPlan] NVARCHAR(MAX), [QueryPlanFiltered] NVARCHAR(MAX), [CheckID] INT'

	END
	ELSE /* IF @OutputType = 'SCHEMA' */
	BEGIN

		/*
		We start by creating #BlitzResults. It's a temp table that will store all of
		the results from our checks. Throughout the rest of this stored procedure,
		we're running a series of checks looking for dangerous things inside the SQL
		Server. When we find a problem, we insert rows into #BlitzResults. At the
		end, we return these results to the end user.

		#BlitzResults has a CheckID field, but there's no Check table. As we do
		checks, we insert data into this table, and we manually put in the CheckID.
		We (Brent Ozar Unlimited) maintain a list of the checks by ID#. You can
		download that from http://www.BrentOzar.com/blitz/documentation/ - you'll
		see why it can help shortly.
		*/
		DECLARE @StringToExecute NVARCHAR(4000)
			,@curr_tracefilename NVARCHAR(500) 
			,@base_tracefilename NVARCHAR(500) 
			,@indx int ;

		select @curr_tracefilename = [path] from sys.traces where is_default = 1 ;
		set @curr_tracefilename = reverse(@curr_tracefilename);
		select @indx = patindex('%\%', @curr_tracefilename) ;
		set @curr_tracefilename = reverse(@curr_tracefilename) ;
		set @base_tracefilename = left( @curr_tracefilename,len(@curr_tracefilename) - @indx) + '\log.trc' ;

		IF OBJECT_ID('tempdb..#BlitzResults') IS NOT NULL 
			DROP TABLE #BlitzResults;
		CREATE TABLE #BlitzResults
			(
			  ID INT IDENTITY(1, 1) ,
			  CheckID INT ,
			  DatabaseName NVARCHAR(128) ,
			  Priority TINYINT ,
			  FindingsGroup VARCHAR(50) ,
			  Finding VARCHAR(200) ,
			  URL VARCHAR(200) ,
			  Details NVARCHAR(4000) ,
			  QueryPlan [XML] NULL ,
			  QueryPlanFiltered [NVARCHAR](MAX) NULL
			);

		/*
		You can build your own table with a list of checks to skip. For example, you
		might have some databases that you don't care about, or some checks you don't
		want to run. Then, when you run sp_Blitz, you can specify these parameters:
		@SkipChecksDatabase = 'DBAtools',
		@SkipChecksSchema = 'dbo',
		@SkipChecksTable = 'BlitzChecksToSkip'
		Pass in the database, schema, and table that contains the list of checks you
		want to skip. This part of the code checks those parameters, gets the list,
		and then saves those in a temp table. As we run each check, we'll see if we
		need to skip it.
		
		Really anal-retentive users will note that the @SkipChecksServer parameter is
		not used. YET. We added that parameter in so that we could avoid changing the
		stored proc's surface area (interface) later.
		*/
		IF OBJECT_ID('tempdb..#SkipChecks') IS NOT NULL 
			DROP TABLE #SkipChecks;
		CREATE TABLE #SkipChecks
			(
			  DatabaseName NVARCHAR(128) ,
			  CheckID INT ,
			  ServerName NVARCHAR(128)
			);
		CREATE CLUSTERED INDEX IX_CheckID_DatabaseName ON #SkipChecks(CheckID, DatabaseName);

		IF @SkipChecksTable IS NOT NULL
			AND @SkipChecksSchema IS NOT NULL
			AND @SkipChecksDatabase IS NOT NULL 
			BEGIN
				SET @StringToExecute = 'INSERT INTO #SkipChecks(DatabaseName, CheckID, ServerName )
				SELECT DISTINCT DatabaseName, CheckID, ServerName
				FROM ' + QUOTENAME(@SkipChecksDatabase) + '.' + QUOTENAME(@SkipChecksSchema) + '.' + QUOTENAME(@SkipChecksTable)
					+ ' WHERE ServerName IS NULL OR ServerName = SERVERPROPERTY(''ServerName'');'
				EXEC(@StringToExecute)
			END


		/* 
		That's the end of the SkipChecks stuff.
		The next several tables are used by various checks later.
		*/
		IF OBJECT_ID('tempdb..#ConfigurationDefaults') IS NOT NULL 
			DROP TABLE #ConfigurationDefaults;
		CREATE TABLE #ConfigurationDefaults
			(
			  name NVARCHAR(128) ,
			  DefaultValue BIGINT,
			  CheckID INT
			);

		IF OBJECT_ID('tempdb..#DBCCs') IS NOT NULL 
			DROP TABLE #DBCCs;
		CREATE TABLE #DBCCs
			(
			  ID INT IDENTITY(1, 1)
					 PRIMARY KEY ,
			  ParentObject VARCHAR(255) ,
			  Object VARCHAR(255) ,
			  Field VARCHAR(255) ,
			  Value VARCHAR(255) ,
			  DbName NVARCHAR(128) NULL
			)


		IF OBJECT_ID('tempdb..#LogInfo2012') IS NOT NULL 
			DROP TABLE #LogInfo2012;
		CREATE TABLE #LogInfo2012
			(
			  recoveryunitid INT ,
			  FileID SMALLINT ,
			  FileSize BIGINT ,
			  StartOffset BIGINT ,
			  FSeqNo BIGINT ,
			  [Status] TINYINT ,
			  Parity TINYINT ,
			  CreateLSN NUMERIC(38)
			);

		IF OBJECT_ID('tempdb..#LogInfo') IS NOT NULL 
			DROP TABLE #LogInfo;
		CREATE TABLE #LogInfo
			(
			  FileID SMALLINT ,
			  FileSize BIGINT ,
			  StartOffset BIGINT ,
			  FSeqNo BIGINT ,
			  [Status] TINYINT ,
			  Parity TINYINT ,
			  CreateLSN NUMERIC(38)
			);

		IF OBJECT_ID('tempdb..#partdb') IS NOT NULL 
			DROP TABLE #partdb;
		CREATE TABLE #partdb
			(
			  dbname NVARCHAR(128) ,
			  objectname NVARCHAR(200) ,
			  type_desc NVARCHAR(128)
			)

		IF OBJECT_ID('tempdb..#TraceStatus') IS NOT NULL 
			DROP TABLE #TraceStatus;
		CREATE TABLE #TraceStatus
			(
			  TraceFlag VARCHAR(10) ,
			  status BIT ,
			  Global BIT ,
			  Session BIT
			);

		IF OBJECT_ID('tempdb..#driveInfo') IS NOT NULL 
			DROP TABLE #driveInfo;
		CREATE TABLE #driveInfo
			(
			  drive NVARCHAR ,
			  SIZE DECIMAL(18, 2)
			)


		IF OBJECT_ID('tempdb..#dm_exec_query_stats') IS NOT NULL 
			DROP TABLE #dm_exec_query_stats;
		CREATE TABLE #dm_exec_query_stats
			(
			  [id] [int] NOT NULL
						 IDENTITY(1, 1) ,
			  [sql_handle] [varbinary](64) NOT NULL ,
			  [statement_start_offset] [int] NOT NULL ,
			  [statement_end_offset] [int] NOT NULL ,
			  [plan_generation_num] [bigint] NOT NULL ,
			  [plan_handle] [varbinary](64) NOT NULL ,
			  [creation_time] [datetime] NOT NULL ,
			  [last_execution_time] [datetime] NOT NULL ,
			  [execution_count] [bigint] NOT NULL ,
			  [total_worker_time] [bigint] NOT NULL ,
			  [last_worker_time] [bigint] NOT NULL ,
			  [min_worker_time] [bigint] NOT NULL ,
			  [max_worker_time] [bigint] NOT NULL ,
			  [total_physical_reads] [bigint] NOT NULL ,
			  [last_physical_reads] [bigint] NOT NULL ,
			  [min_physical_reads] [bigint] NOT NULL ,
			  [max_physical_reads] [bigint] NOT NULL ,
			  [total_logical_writes] [bigint] NOT NULL ,
			  [last_logical_writes] [bigint] NOT NULL ,
			  [min_logical_writes] [bigint] NOT NULL ,
			  [max_logical_writes] [bigint] NOT NULL ,
			  [total_logical_reads] [bigint] NOT NULL ,
			  [last_logical_reads] [bigint] NOT NULL ,
			  [min_logical_reads] [bigint] NOT NULL ,
			  [max_logical_reads] [bigint] NOT NULL ,
			  [total_clr_time] [bigint] NOT NULL ,
			  [last_clr_time] [bigint] NOT NULL ,
			  [min_clr_time] [bigint] NOT NULL ,
			  [max_clr_time] [bigint] NOT NULL ,
			  [total_elapsed_time] [bigint] NOT NULL ,
			  [last_elapsed_time] [bigint] NOT NULL ,
			  [min_elapsed_time] [bigint] NOT NULL ,
			  [max_elapsed_time] [bigint] NOT NULL ,
			  [query_hash] [binary](8) NULL ,
			  [query_plan_hash] [binary](8) NULL ,
			  [query_plan] [xml] NULL ,
			  [query_plan_filtered] [nvarchar](MAX) NULL ,
			  [text] [nvarchar](MAX) COLLATE SQL_Latin1_General_CP1_CI_AS
									 NULL ,
			  [text_filtered] [nvarchar](MAX) COLLATE SQL_Latin1_General_CP1_CI_AS
											  NULL
			)


		/* If we're outputting CSV, don't bother checking the plan cache because we cannot export plans. */
		IF @OutputType = 'CSV' 
			SET @CheckProcedureCache = 0;

		/* Sanitize our inputs */
		SELECT
			@OutputDatabaseName = QUOTENAME(@OutputDatabaseName),
			@OutputSchemaName = QUOTENAME(@OutputSchemaName),
			@OutputTableName = QUOTENAME(@OutputTableName)



		/* 
		Whew! we're finally done with the setup, and we can start doing checks.
		First, let's make sure we're actually supposed to do checks on this server.
		The user could have passed in a SkipChecks table that specified to skip ALL
		checks on this server, so let's check for that:
		*/
		IF ( ( SERVERPROPERTY('ServerName') NOT IN ( SELECT ServerName
													 FROM   #SkipChecks
													 WHERE  DatabaseName IS NULL
															AND CheckID IS NULL ) )
			 OR ( @SkipChecksTable IS NULL )
		   ) 
			BEGIN

				/*
				Our very first check! We'll put more comments in this one just to
				explain exactly how it works. First, we check to see if we're
				supposed to skip CheckID 1 (that's the check we're working on.)
				*/
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 1 ) 
					BEGIN

						/*
						Below, we check master.sys.databases looking for databases
						that haven't had a backup in the last week. If we find any,
						we insert them into #BlitzResults, the temp table that
						tracks our server's problems. Note that if the check does
						NOT find any problems, we don't save that. We're only
						saving the problems, not the successful checks.
						*/
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  1 AS CheckID ,
										d.[name] AS DatabaseName ,
										1 AS Priority ,
										'Backup' AS FindingsGroup ,
										'Backups Not Performed Recently' AS Finding ,
										'http://BrentOzar.com/go/nobak' AS URL ,
										'Database ' + d.Name + ' last backed up: '
										+ CAST(COALESCE(MAX(b.backup_finish_date),
														' never ') AS VARCHAR(200)) AS Details
								FROM    master.sys.databases d
										LEFT OUTER JOIN msdb.dbo.backupset b ON d.name COLLATE SQL_Latin1_General_CP1_CI_AS = b.database_name COLLATE SQL_Latin1_General_CP1_CI_AS
																  AND b.type = 'D'
																  AND b.server_name = SERVERPROPERTY('ServerName') /*Backupset ran on current server */
								WHERE   d.database_id <> 2  /* Bonus points if you know what that means */
										AND d.state <> 1 /* Not currently restoring, like log shipping databases */
										AND d.is_in_standby = 0 /* Not a log shipping target database */
										AND d.source_database_id IS NULL /* Excludes database snapshots */
										AND d.name NOT IN ( SELECT DISTINCT
																  DatabaseName
															FROM  #SkipChecks
															WHERE CheckID IS NULL )
										/* 
										The above NOT IN filters out the databases we're not supposed to check.
										*/
								GROUP BY d.name
								HAVING  MAX(b.backup_finish_date) <= DATEADD(dd,
																  -7, GETDATE());
						/* 
						And there you have it. The rest of this stored procedure works the same
						way: it asks:
						- Should I skip this check?
						- If not, do I find problems?
						- Insert the results into #BlitzResults
						This particular check is just a little bit fancy - it also has a second
						query below that checks for databases that have NEVER been backed up.
						We use CheckID #1 for both of these just because they represent the same
						problem - a database that needs a backup.
						*/

						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  1 AS CheckID ,
										d.name AS DatabaseName ,
										1 AS Priority ,
										'Backup' AS FindingsGroup ,
										'Backups Not Performed Recently' AS Finding ,
										'http://BrentOzar.com/go/nobak' AS URL ,
										( 'Database ' + d.Name
										  + ' never backed up.' ) AS Details
								FROM    master.sys.databases d
								WHERE   d.database_id <> 2 /* Bonus points if you know what that means */
										AND d.state <> 1 /* Not currently restoring, like log shipping databases */
										AND d.is_in_standby = 0 /* Not a log shipping target database */
										AND d.source_database_id IS NULL /* Excludes database snapshots */
										AND d.name NOT IN ( SELECT DISTINCT
																  DatabaseName
															FROM  #SkipChecks
															WHERE CheckID IS NULL )
										AND NOT EXISTS ( SELECT *
														 FROM   msdb.dbo.backupset b
														 WHERE  d.name COLLATE SQL_Latin1_General_CP1_CI_AS = b.database_name COLLATE SQL_Latin1_General_CP1_CI_AS
																AND b.type = 'D'
																AND b.server_name = SERVERPROPERTY('ServerName') /*Backupset ran on current server */)

					END

				/* 
				And that's the end of CheckID #1.

				CheckID #2 is a little simpler because it only involves one query, and it's
				more typical for queries that people contribute. But keep reading, because
				the next check gets more complex again.
				*/
	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 2 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										2 AS CheckID ,
										d.name AS DatabaseName ,
										1 AS Priority ,
										'Backup' AS FindingsGroup ,
										'Full Recovery Mode w/o Log Backups' AS Finding ,
										'http://BrentOzar.com/go/biglogs' AS URL ,
										( 'Database ' + ( d.Name COLLATE database_default )
										  + ' is in ' + d.recovery_model_desc
										  + ' recovery mode but has not had a log backup in the last week.' ) AS Details
								FROM    master.sys.databases d
								WHERE   d.recovery_model IN ( 1, 2 )
										AND d.database_id NOT IN ( 2, 3 )
										AND d.source_database_id IS NULL
										AND d.state <> 1 /* Not currently restoring, like log shipping databases */
										AND d.is_in_standby = 0 /* Not a log shipping target database */
										AND d.source_database_id IS NULL /* Excludes database snapshots */
										AND d.name NOT IN ( SELECT DISTINCT
																  DatabaseName
															FROM  #SkipChecks
															WHERE CheckID IS NULL )
										AND NOT EXISTS ( SELECT *
														 FROM   msdb.dbo.backupset b
														 WHERE  d.name COLLATE SQL_Latin1_General_CP1_CI_AS = b.database_name COLLATE SQL_Latin1_General_CP1_CI_AS
																AND b.type = 'L'
																AND b.backup_finish_date >= DATEADD(dd,
																  -7, GETDATE()) );
					END


				/* 
				Next up, we've got CheckID 8. (These don't have to go in order.) This one
				won't work on SQL Server 2005 because it relies on a new DMV that didn't
				exist prior to SQL Server 2008. This means we have to check the SQL Server
				version first, then build a dynamic string with the query we want to run:			
				*/

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 8 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, Priority, 
							FindingsGroup, 
							Finding, URL, 
							Details)
					  SELECT 8 AS CheckID, 
					  150 AS Priority, 
					  ''Security'' AS FindingsGroup, 
					  ''Server Audits Running'' AS Finding, 
					  ''http://BrentOzar.com/go/audits'' AS URL,
					  (''SQL Server built-in audit functionality is being used by server audit: '' + [name]) AS Details FROM sys.dm_server_audit_status'
								EXECUTE(@StringToExecute)
							END;
					END

				/* 
				But what if you need to run a query in every individual database?
				Check out CheckID 99 below. Yes, it uses sp_MSforeachdb, and no,
				we're not happy about that. sp_MSforeachdb is known to have a lot
				of issues, like skipping databases sometimes. However, this is the
				only built-in option that we have. If you're writing your own code
				for database maintenance, consider Aaron Bertrand's alternative:
				http://www.mssqltips.com/sqlservertip/2201/making-a-more-reliable-and-flexible-spmsforeachdb/
				We don't include that as part of sp_Blitz, of course, because
				copying and distributing copyrighted code from others without their
				written permission isn't a good idea.
				*/
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 99 ) 
					BEGIN
						EXEC dbo.sp_MSforeachdb 'USE [?];  IF EXISTS (SELECT * FROM  sys.tables WITH (NOLOCK) WHERE name = ''sysmergepublications'' ) IF EXISTS ( SELECT * FROM sysmergepublications WITH (NOLOCK) WHERE retention = 0)   INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 99, DB_NAME(), 110, ''Performance'', ''Infinite merge replication metadata retention period'', ''http://BrentOzar.com/go/merge'', (''The ['' + DB_NAME() + ''] database has merge replication metadata retention period set to infinite - this can be the case of significant performance issues.'')';
					END
				/*
				Note that by using sp_MSforeachdb, we're running the query in all
				databases. We're not checking #SkipChecks here for each database to
				see if we should run the check in this database. That means we may
				still run a skipped check if it involves sp_MSforeachdb. We just
				don't output those results in the last step.

				And that's the basic idea! You can read through the rest of the
				checks if you like - some more exciting stuff happens closer to the
				end of the stored proc, where we start doing things like checking
				the plan cache, but those aren't as cleanly commented.

				If you'd like to contribute your own check, use one of the check
				formats shown above and email it to Help@BrentOzar.com. You don't
				have to pick a CheckID or a link - we'll take care of that when we
				test and publish the code. Thanks!
				*/


				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 93 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										93 AS CheckID ,
										1 AS Priority ,
										'Backup' AS FindingsGroup ,
										'Backing Up to Same Drive Where Databases Reside' AS Finding ,
										'http://BrentOzar.com/go/backup' AS URL ,
										'Drive '
										+ UPPER(LEFT(bmf.physical_device_name, 3))
										+ ' houses both database files AND backups taken in the last two weeks. This represents a serious risk if that array fails.' Details
								FROM    msdb.dbo.backupmediafamily AS bmf
										INNER JOIN msdb.dbo.backupset AS bs ON bmf.media_set_id = bs.media_set_id
																  AND bs.backup_start_date >= ( DATEADD(dd,
																  -14, GETDATE()) )
								WHERE   UPPER(LEFT(bmf.physical_device_name COLLATE SQL_Latin1_General_CP1_CI_AS, 3)) IN (
										SELECT DISTINCT
												UPPER(LEFT(mf.physical_name COLLATE SQL_Latin1_General_CP1_CI_AS, 3))
										FROM    sys.master_files AS mf )
					END


				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 3 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT TOP 1
										3 AS CheckID ,
										'msdb' ,
										200 AS Priority ,
										'Backup' AS FindingsGroup ,
										'MSDB Backup History Not Purged' AS Finding ,
										'http://BrentOzar.com/go/history' AS URL ,
										( 'Database backup history retained back to '
										  + CAST(bs.backup_start_date AS VARCHAR(20)) ) AS Details
								FROM    msdb.dbo.backupset bs
								WHERE   bs.backup_start_date <= DATEADD(dd, -60,
																  GETDATE())
								ORDER BY backup_set_id ASC;
					END
	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 4 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  4 AS CheckID ,
										10 AS Priority ,
										'Security' AS FindingsGroup ,
										'Sysadmins' AS Finding ,
										'http://BrentOzar.com/go/sa' AS URL ,
										( 'Login [' + l.name
										  + '] is a sysadmin - meaning they can do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' ) AS Details
								FROM    master.sys.syslogins l
								WHERE   l.sysadmin = 1
										AND l.name <> SUSER_SNAME(0x01)
										AND l.denylogin = 0;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 5 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  5 AS CheckID ,
										10 AS Priority ,
										'Security' AS FindingsGroup ,
										'Security Admins' AS Finding ,
										'http://BrentOzar.com/go/sa' AS URL ,
										( 'Login [' + l.name
										  + '] is a security admin - meaning they can give themselves permission to do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' ) AS Details
								FROM    master.sys.syslogins l
								WHERE   l.securityadmin = 1
										AND l.name <> SUSER_SNAME(0x01)
										AND l.denylogin = 0;
					END

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 104 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( [CheckID] ,
								  [Priority] ,
								  [FindingsGroup] ,
								  [Finding] ,
								  [URL] ,
								  [Details]
								)
								SELECT  104 AS [CheckID] ,
										10 AS [Priority] ,
										'Security' AS [FindingsGroup] ,
										'Login Can Control Server' AS [Finding] ,
										'http://BrentOzar.com/go/sa' AS [URL] ,
										'Login [' + pri.[name]
										+ '] has the CONTROL SERVER permission - meaning they can do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' AS [Details]
								FROM    sys.server_principals AS pri
								WHERE   pri.[principal_id] IN (
										SELECT  p.[grantee_principal_id]
										FROM    sys.server_permissions AS p
										WHERE   p.[state] IN ( 'G', 'W' )
												AND p.[class] = 100
												AND p.[type] = 'CL' )
										AND pri.[name] NOT LIKE '##%##'
					END    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 6 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  6 AS CheckID ,
										200 AS Priority ,
										'Security' AS FindingsGroup ,
										'Jobs Owned By Users' AS Finding ,
										'http://BrentOzar.com/go/owners' AS URL ,
										( 'Job [' + j.name + '] is owned by ['
										  + SUSER_SNAME(j.owner_sid)
										  + '] - meaning if their login is disabled or not available due to Active Directory problems, the job will stop working.' ) AS Details
								FROM    msdb.dbo.sysjobs j
								WHERE   j.enabled = 1
										AND SUSER_SNAME(j.owner_sid) <> SUSER_SNAME(0x01);
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 7 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  7 AS CheckID ,
										10 AS Priority ,
										'Security' AS FindingsGroup ,
										'Stored Procedure Runs at Startup' AS Finding ,
										'http://BrentOzar.com/go/startup' AS URL ,
										( 'Stored procedure [master].['
										  + r.SPECIFIC_SCHEMA + '].['
										  + r.SPECIFIC_NAME
										  + '] runs automatically when SQL Server starts up.  Make sure you know exactly what this stored procedure is doing, because it could pose a security risk.' ) AS Details
								FROM    master.INFORMATION_SCHEMA.ROUTINES r
								WHERE   OBJECTPROPERTY(OBJECT_ID(ROUTINE_NAME),
													   'ExecIsStartup') = 1;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 9 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, 
							Priority, 
							FindingsGroup, 
							Finding, 
							URL, 
							Details)
					  SELECT 9 AS CheckID, 
					  200 AS Priority, 
					  ''Surface Area'' AS FindingsGroup, 
					  ''Endpoints Configured'' AS Finding, 
					  ''http://BrentOzar.com/go/endpoints/'' AS URL,
					  (''SQL Server endpoints are configured.  These can be used for database mirroring or Service Broker, but if you do not need them, avoid leaving them enabled.  Endpoint name: '' + [name]) AS Details FROM sys.endpoints WHERE type <> 2'
								EXECUTE(@StringToExecute)
							END;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 10 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, 
							Priority, 
							FindingsGroup, 
							Finding, 
							URL, 
							Details)
					  SELECT 10 AS CheckID, 
					  100 AS Priority, 
					  ''Performance'' AS FindingsGroup, 
					  ''Resource Governor Enabled'' AS Finding, 
					  ''http://BrentOzar.com/go/rg'' AS URL,
					  (''Resource Governor is enabled.  Queries may be throttled.  Make sure you understand how the Classifier Function is configured.'') AS Details FROM sys.resource_governor_configuration WHERE is_enabled = 1'
								EXECUTE(@StringToExecute)
							END;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 11 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, 
							Priority, 
							FindingsGroup, 
							Finding, 
							URL, 
							Details)
					  SELECT 11 AS CheckID, 
					  100 AS Priority, 
					  ''Performance'' AS FindingsGroup, 
					  ''Server Triggers Enabled'' AS Finding, 
					  ''http://BrentOzar.com/go/logontriggers/'' AS URL,
					  (''Server Trigger ['' + [name] ++ ''] is enabled, so it runs every time someone logs in.  Make sure you understand what that trigger is doing - the less work it does, the better.'') AS Details FROM sys.server_triggers WHERE is_disabled = 0 AND is_ms_shipped = 0'
								EXECUTE(@StringToExecute)
							END;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 12 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  12 AS CheckID ,
										[name] AS DatabaseName ,
										10 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Auto-Close Enabled' AS Finding ,
										'http://BrentOzar.com/go/autoclose' AS URL ,
										( 'Database [' + [name]
										  + '] has auto-close enabled.  This setting can dramatically decrease performance.' ) AS Details
								FROM    sys.databases
								WHERE   is_auto_close_on = 1
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 13 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  13 AS CheckID ,
										[name] AS DatabaseName ,
										10 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Auto-Shrink Enabled' AS Finding ,
										'http://BrentOzar.com/go/autoshrink' AS URL ,
										( 'Database [' + [name]
										  + '] has auto-shrink enabled.  This setting can dramatically decrease performance.' ) AS Details
								FROM    sys.databases
								WHERE   is_auto_shrink_on = 1
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks );
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 14 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, 
							DatabaseName,
							Priority, 
							FindingsGroup, 
							Finding, 
							URL, 
							Details)
					  SELECT 14 AS CheckID, 
					  [name] as DatabaseName,
					  50 AS Priority, 
					  ''Reliability'' AS FindingsGroup, 
					  ''Page Verification Not Optimal'' AS Finding, 
					  ''http://BrentOzar.com/go/torn'' AS URL,
					  (''Database ['' + [name] + ''] has '' + [page_verify_option_desc] + '' for page verification.  SQL Server may have a harder time recognizing and recovering from storage corruption.  Consider using CHECKSUM instead.'') COLLATE database_default AS Details
					  FROM sys.databases 
					  WHERE page_verify_option < 2 
					  AND name <> ''tempdb''
					  and name not in (select distinct DatabaseName from #SkipChecks)'
								EXECUTE(@StringToExecute)
							END;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 15 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  15 AS CheckID ,
										[name] AS DatabaseName ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Auto-Create Stats Disabled' AS Finding ,
										'http://BrentOzar.com/go/acs' AS URL ,
										( 'Database [' + [name]
										  + '] has auto-create-stats disabled.  SQL Server uses statistics to build better execution plans, and without the ability to automatically create more, performance may suffer.' ) AS Details
								FROM    sys.databases
								WHERE   is_auto_create_stats_on = 0
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 16 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  16 AS CheckID ,
										[name] AS DatabaseName ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Auto-Update Stats Disabled' AS Finding ,
										'http://BrentOzar.com/go/aus' AS URL ,
										( 'Database [' + [name]
										  + '] has auto-update-stats disabled.  SQL Server uses statistics to build better execution plans, and without the ability to automatically update them, performance may suffer.' ) AS Details
								FROM    sys.databases
								WHERE   is_auto_update_stats_on = 0
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 17 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  17 AS CheckID ,
										[name] AS DatabaseName ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Stats Updated Asynchronously' AS Finding ,
										'http://BrentOzar.com/go/asyncstats' AS URL ,
										( 'Database [' + [name]
										  + '] has auto-update-stats-async enabled.  When SQL Server gets a query for a table with out-of-date statistics, it will run the query with the stats it has - while updating stats to make later queries better. The initial run of the query may suffer, though.' ) AS Details
								FROM    sys.databases
								WHERE   is_auto_update_stats_async_on = 1
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 18 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  18 AS CheckID ,
										[name] AS DatabaseName ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Forced Parameterization On' AS Finding ,
										'http://BrentOzar.com/go/forced' AS URL ,
										( 'Database [' + [name]
										  + '] has forced parameterization enabled.  SQL Server will aggressively reuse query execution plans even if the applications do not parameterize their queries.  This can be a performance booster with some programming languages, or it may use universally bad execution plans when better alternatives are available for certain parameters.' ) AS Details
								FROM    sys.databases
								WHERE   is_parameterization_forced = 1
										AND name NOT IN ( SELECT  DatabaseName
														  FROM    #SkipChecks )
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 19 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  19 AS CheckID ,
										[name] AS DatabaseName ,
										200 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Replication In Use' AS Finding ,
										'http://BrentOzar.com/go/repl' AS URL ,
										( 'Database [' + [name]
										  + '] is a replication publisher, subscriber, or distributor.' ) AS Details
								FROM    sys.databases
								WHERE   name NOT IN ( SELECT DISTINCT
																DatabaseName
													  FROM      #SkipChecks )
										AND is_published = 1
										OR is_subscribed = 1
										OR is_merge_published = 1
										OR is_distributor = 1;
					END

	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 20 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  20 AS CheckID ,
										[name] AS DatabaseName ,
										110 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Date Correlation On' AS Finding ,
										'http://BrentOzar.com/go/corr' AS URL ,
										( 'Database [' + [name]
										  + '] has date correlation enabled.  This is not a default setting, and it has some performance overhead.  It tells SQL Server that date fields in two tables are related, and SQL Server maintains statistics showing that relation.' ) AS Details
								FROM    sys.databases
								WHERE   is_date_correlation_on = 1
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 21 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
							(CheckID, 
							DatabaseName,
							Priority, 
							FindingsGroup, 
							Finding, 
							URL, 
							Details)
					  SELECT 21 AS CheckID,
					  [name] as DatabaseName, 
					  20 AS Priority, 
					  ''Encryption'' AS FindingsGroup, 
					  ''Database Encrypted'' AS Finding, 
					  ''http://BrentOzar.com/go/tde'' AS URL,
					  (''Database ['' + [name] + ''] has Transparent Data Encryption enabled.  Make absolutely sure you have backed up the certificate and private key, or else you will not be able to restore this database.'') AS Details 
					  FROM sys.databases 
					  WHERE is_encrypted = 1
					  and name not in (select distinct DatabaseName from #SkipChecks)'
								EXECUTE(@StringToExecute)
							END;
					END
	    
				/* 
				Believe it or not, SQL Server doesn't track the default values
				for sp_configure options! We'll make our own list here.
				*/
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'access check cache bucket count', 0, 1001 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'access check cache quota', 0, 1002 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Ad Hoc Distributed Queries', 0, 1003 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'affinity I/O mask', 0, 1004 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'affinity mask', 0, 1005 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Agent XPs', 0, 1006 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'allow updates', 0, 1007 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'awe enabled', 0, 1008 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'blocked process threshold', 0, 1009 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'c2 audit mode', 0, 1010 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'clr enabled', 0, 1011 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'cost threshold for parallelism', 5, 1012 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'cross db ownership chaining', 0, 1013 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'cursor threshold', -1, 1014 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Database Mail XPs', 0, 1015 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'default full-text language', 1033, 1016 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'default language', 0, 1017 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'default trace enabled', 1, 1018 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'disallow results from triggers', 0, 1019 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'fill factor (%)', 0, 1020 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'ft crawl bandwidth (max)', 100, 1021 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'ft crawl bandwidth (min)', 0, 1022 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'ft notify bandwidth (max)', 100, 1023 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'ft notify bandwidth (min)', 0, 1024 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'index create memory (KB)', 0, 1025 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'in-doubt xact resolution', 0, 1026 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'lightweight pooling', 0, 1027 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'locks', 0, 1028 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'max degree of parallelism', 0, 1029 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'max full-text crawl range', 4, 1030 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'max server memory (MB)', 2147483647, 1031 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'max text repl size (B)', 65536, 1032 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'max worker threads', 0, 1033 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'media retention', 0, 1034 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'min memory per query (KB)', 1024, 1035 );
				/* Accepting both 0 and 16 below because both have been seen in the wild as defaults. */
				IF EXISTS ( SELECT  *
							FROM    sys.configurations
							WHERE   name = 'min server memory (MB)'
									AND value_in_use IN ( 0, 16 ) ) 
					INSERT  INTO #ConfigurationDefaults
							SELECT  'min server memory (MB)' ,
									CAST(value_in_use AS BIGINT), 1036
							FROM    sys.configurations
							WHERE   name = 'min server memory (MB)'
				ELSE 
					INSERT  INTO #ConfigurationDefaults
					VALUES  ( 'min server memory (MB)', 0, 1036 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'nested triggers', 1, 1037 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'network packet size (B)', 4096, 1038 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Ole Automation Procedures', 0, 1039 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'open objects', 0, 1040 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'optimize for ad hoc workloads', 0, 1041 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'PH timeout (s)', 60, 1042 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'precompute rank', 0, 1043 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'priority boost', 0, 1044 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'query governor cost limit', 0, 1045 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'query wait (s)', -1, 1046 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'recovery interval (min)', 0, 1047 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'remote access', 1, 1048 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'remote admin connections', 0, 1049 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'remote proc trans', 0, 1050 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'remote query timeout (s)', 600, 1051 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Replication XPs', 0, 1052 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'RPC parameter data validation', 0, 1053 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'scan for startup procs', 0, 1054 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'server trigger recursion', 1, 1055 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'set working set size', 0, 1056 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'show advanced options', 0, 1057 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'SMO and DMO XPs', 1, 1058 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'SQL Mail XPs', 0, 1059 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'transform noise words', 0, 1060 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'two digit year cutoff', 2049, 1061 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'user connections', 0, 1062 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'user options', 0, 1063 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'Web Assistant Procedures', 0, 1064 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'xp_cmdshell', 0, 1065 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'affinity64 mask', 0, 1066 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'affinity64 I/O mask', 0, 1067 );
				INSERT  INTO #ConfigurationDefaults
				VALUES  ( 'contained database authentication', 0, 1068 );
				/* SQL Server 2012 also changes a configuration default */
				IF @@VERSION LIKE '%Microsoft SQL Server 2005%'
					OR @@VERSION LIKE '%Microsoft SQL Server 2008%' 
					BEGIN 
						INSERT  INTO #ConfigurationDefaults
						VALUES  ( 'remote login timeout (s)', 20, 1069 );
					END
				ELSE 
					BEGIN
						INSERT  INTO #ConfigurationDefaults
						VALUES  ( 'remote login timeout (s)', 10, 1070 );
					END

	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 22 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  cd.CheckID ,
										200 AS Priority ,
										'Non-Default Server Config' AS FindingsGroup ,
										cr.name AS Finding ,
										'http://BrentOzar.com/go/conf' AS URL ,
										( 'This sp_configure option has been changed.  Its default value is '
										  + COALESCE(CAST(cd.[DefaultValue] AS VARCHAR(100)),
													 '(unknown)')
										  + ' and it has been set to '
										  + CAST(cr.value_in_use AS VARCHAR(100))
										  + '.' ) AS Details
								FROM    sys.configurations cr
										INNER JOIN #ConfigurationDefaults cd ON cd.name = cr.name
										LEFT OUTER JOIN #ConfigurationDefaults cdUsed ON cdUsed.name = cr.name
																  AND cdUsed.DefaultValue = cr.value_in_use
								WHERE   cdUsed.name IS NULL;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 24 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										24 AS CheckID ,
										DB_NAME(database_id) AS DatabaseName ,
										20 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'System Database on C Drive' AS Finding ,
										'http://BrentOzar.com/go/cdrive' AS URL ,
										( 'The ' + DB_NAME(database_id)
										  + ' database has a file on the C drive.  Putting system databases on the C drive runs the risk of crashing the server when it runs out of space.' ) AS Details
								FROM    sys.master_files
								WHERE   UPPER(LEFT(physical_name, 1)) = 'C'
										AND DB_NAME(database_id) IN ( 'master',
																  'model', 'msdb' );
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 25 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT TOP 1
										25 AS CheckID ,
										'tempdb' ,
										100 AS Priority ,
										'Performance' AS FindingsGroup ,
										'TempDB on C Drive' AS Finding ,
										'http://BrentOzar.com/go/cdrive' AS URL ,
										CASE WHEN growth > 0
											 THEN ( 'The tempdb database has files on the C drive.  TempDB frequently grows unpredictably, putting your server at risk of running out of C drive space and crashing hard.  C is also often much slower than other drives, so performance may be suffering.' )
											 ELSE ( 'The tempdb database has files on the C drive.  TempDB is not set to Autogrow, hopefully it is big enough.  C is also often much slower than other drives, so performance may be suffering.' )
										END AS Details
								FROM    sys.master_files
								WHERE   UPPER(LEFT(physical_name, 1)) = 'C'
										AND DB_NAME(database_id) = 'tempdb';
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 26 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										26 AS CheckID ,
										DB_NAME(database_id) AS DatabaseName ,
										20 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'User Databases on C Drive' AS Finding ,
										'http://BrentOzar.com/go/cdrive' AS URL ,
										( 'The ' + DB_NAME(database_id)
										  + ' database has a file on the C drive.  Putting databases on the C drive runs the risk of crashing the server when it runs out of space.' ) AS Details
								FROM    sys.master_files
								WHERE   UPPER(LEFT(physical_name, 1)) = 'C'
										AND DB_NAME(database_id) NOT IN ( 'master',
																  'model', 'msdb',
																  'tempdb' )
										AND DB_NAME(database_id) NOT IN (
										SELECT DISTINCT
												DatabaseName
										FROM    #SkipChecks )
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 27 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  27 AS CheckID ,
										'master' AS DatabaseName ,
										200 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Tables in the Master Database' AS Finding ,
										'http://BrentOzar.com/go/mastuser' AS URL ,
										( 'The ' + name
										  + ' table in the master database was created by end users on '
										  + CAST(create_date AS VARCHAR(20))
										  + '. Tables in the master database may not be restored in the event of a disaster.' ) AS Details
								FROM    master.sys.tables
								WHERE   is_ms_shipped = 0;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 28 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  28 AS CheckID ,
										200 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Tables in the MSDB Database' AS Finding ,
										'http://BrentOzar.com/go/msdbuser' AS URL ,
										( 'The ' + name
										  + ' table in the msdb database was created by end users on '
										  + CAST(create_date AS VARCHAR(20))
										  + '. Tables in the msdb database may not be restored in the event of a disaster.' ) AS Details
								FROM    msdb.sys.tables
								WHERE   is_ms_shipped = 0;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 29 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  29 AS CheckID ,
										200 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Tables in the Model Database' AS Finding ,
										'http://BrentOzar.com/go/model' AS URL ,
										( 'The ' + name
										  + ' table in the model database was created by end users on '
										  + CAST(create_date AS VARCHAR(20))
										  + '. Tables in the model database are automatically copied into all new databases.' ) AS Details
								FROM    model.sys.tables
								WHERE   is_ms_shipped = 0;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 30 ) 
					BEGIN
						IF ( SELECT COUNT(*)
							 FROM   msdb.dbo.sysalerts
							 WHERE  severity BETWEEN 19 AND 25
						   ) < 7 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  30 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'Not All Alerts Configured' AS Finding ,
											'http://BrentOzar.com/go/alert' AS URL ,
											( 'Not all SQL Server Agent alerts have been configured.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) AS Details;
					END

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 59 ) 
					BEGIN   
						IF EXISTS ( SELECT  *
									FROM    msdb.dbo.sysalerts
									WHERE   enabled = 1
											AND COALESCE(has_notification, 0) = 0
											AND job_id IS NULL ) 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  59 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'Alerts Configured without Follow Up' AS Finding ,
											'http://BrentOzar.com/go/alert' AS URL ,
											( 'SQL Server Agent alerts have been configured but they either do not notify anyone or else they do not take any action.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) AS Details;
					END
	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 96 ) 
					BEGIN
						IF NOT EXISTS ( SELECT  *
										FROM    msdb.dbo.sysalerts
										WHERE   message_id IN ( 823, 824, 825 ) ) 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  96 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'No Alerts for Corruption' AS Finding ,
											'http://BrentOzar.com/go/alert' AS URL ,
											( 'SQL Server Agent alerts do not exist for errors 823, 824, and 825.  These three errors can give you notification about early hardware failure. Enabling them can prevent you a lot of heartbreak.' ) AS Details;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 61 ) 
					BEGIN
						IF NOT EXISTS ( SELECT  *
										FROM    msdb.dbo.sysalerts
										WHERE   severity BETWEEN 19 AND 25 ) 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  61 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'No Alerts for Sev 19-25' AS Finding ,
											'http://BrentOzar.com/go/alert' AS URL ,
											( 'SQL Server Agent alerts do not exist for severity levels 19 through 25.  These are some very severe SQL Server errors. Knowing that these are happening may let you recover from errors faster.' ) AS Details;
					END

		--check for disabled alerts
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 98 ) 
					BEGIN
						IF EXISTS ( SELECT  name
									FROM    msdb.dbo.sysalerts
									WHERE   enabled = 0 ) 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  98 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'Alerts Disabled' AS Finding ,
											'http://www.BrentOzar.com/go/alerts/' AS URL ,
											( 'The following Alert is disabled, please review and enable if desired: '
											  + name ) AS Details
									FROM    msdb.dbo.sysalerts
									WHERE   enabled = 0
					END

	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 31 ) 
					BEGIN
						IF NOT EXISTS ( SELECT  *
										FROM    msdb.dbo.sysoperators
										WHERE   enabled = 1 ) 
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  31 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingsGroup ,
											'No Operators Configured/Enabled' AS Finding ,
											'http://BrentOzar.com/go/op' AS URL ,
											( 'No SQL Server Agent operators (emails) have been configured.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) AS Details;
					END
	    
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 33 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults 
					(CheckID, 
					DatabaseName, 
					Priority, 
					FindingsGroup, 
					Finding, 
					URL, 
					Details) 
		  SELECT DISTINCT 33, 
		  db_name(), 
		  200, 
		  ''Licensing'', 
		  ''Enterprise Edition Features In Use'', 
		  ''http://BrentOzar.com/go/ee'', 
		  (''The ['' + DB_NAME() + ''] database is using '' + feature_name + ''.  If this database is restored onto a Standard Edition server, the restore will fail.'') 
		  FROM [?].sys.dm_db_persisted_sku_features';
							END;
					END
	    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 34 ) 
					BEGIN
						IF EXISTS ( SELECT  *
									FROM    sys.all_objects
									WHERE   name = 'dm_db_mirroring_auto_page_repair' ) 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details)
		  SELECT DISTINCT
		  34 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''http://BrentOzar.com/go/repair'' AS URL ,
		  ( ''Database mirroring has automatically repaired at least one corrupt page in the last 30 days. For more information, query the DMV sys.dm_db_mirroring_auto_page_repair.'' ) AS Details
		  FROM    sys.dm_db_mirroring_auto_page_repair rp
		  INNER JOIN master.sys.databases db ON rp.database_id = db.database_id
		  WHERE   rp.modification_time >= DATEADD(dd, -30, GETDATE()) ;'
								EXECUTE(@StringToExecute)
							END;
					END

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 89 ) 
					BEGIN
						IF EXISTS ( SELECT  *
									FROM    sys.all_objects
									WHERE   name = 'dm_hadr_auto_page_repair' ) 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details)
		  SELECT DISTINCT
		  89 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''http://BrentOzar.com/go/repair'' AS URL ,
		  ( ''AlwaysOn has automatically repaired at least one corrupt page in the last 30 days. For more information, query the DMV sys.dm_hadr_auto_page_repair.'' ) AS Details
		  FROM    sys.dm_hadr_auto_page_repair rp
		  INNER JOIN master.sys.databases db ON rp.database_id = db.database_id
		  WHERE   rp.modification_time >= DATEADD(dd, -30, GETDATE()) ;'
								EXECUTE(@StringToExecute)
							END;
					END

	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 90 ) 
					BEGIN
						IF EXISTS ( SELECT  *
									FROM    msdb.sys.all_objects
									WHERE   name = 'suspect_pages' ) 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details)
		  SELECT DISTINCT
		  90 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''http://BrentOzar.com/go/repair'' AS URL ,
		  ( ''SQL Server has detected at least one corrupt page in the last 30 days. For more information, query the system table msdb.dbo.suspect_pages.'' ) AS Details
		  FROM    msdb.dbo.suspect_pages sp
		  INNER JOIN master.sys.databases db ON sp.database_id = db.database_id
		  WHERE   sp.last_update_date >= DATEADD(dd, -30, GETDATE()) ;'
								EXECUTE(@StringToExecute)
							END;
					END

	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 36 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										36 AS CheckID ,
										100 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Slow Storage Reads on Drive '
										+ UPPER(LEFT(mf.physical_name, 1)) AS Finding ,
										'http://BrentOzar.com/go/slow' AS URL ,
										'Reads are averaging longer than 100ms for at least one database on this drive.  For specific database file speeds, run the query from the information link.' AS Details
								FROM    sys.dm_io_virtual_file_stats(NULL, NULL)
										AS fs
										INNER JOIN sys.master_files AS mf ON fs.database_id = mf.database_id
																  AND fs.[file_id] = mf.[file_id]
								WHERE   ( io_stall_read_ms / ( 1.0 + num_of_reads ) ) > 100;
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 37 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										37 AS CheckID ,
										100 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Slow Storage Writes on Drive '
										+ UPPER(LEFT(mf.physical_name, 1)) AS Finding ,
										'http://BrentOzar.com/go/slow' AS URL ,
										'Writes are averaging longer than 20ms for at least one database on this drive.  For specific database file speeds, run the query from the information link.' AS Details
								FROM    sys.dm_io_virtual_file_stats(NULL, NULL)
										AS fs
										INNER JOIN sys.master_files AS mf ON fs.database_id = mf.database_id
																  AND fs.[file_id] = mf.[file_id]
								WHERE   ( io_stall_write_ms / ( 1.0
																+ num_of_writes ) ) > 20;
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 40 ) 
					BEGIN
						IF ( SELECT COUNT(*)
							 FROM   tempdb.sys.database_files
							 WHERE  type_desc = 'ROWS'
						   ) = 1 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  DatabaseName ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
								VALUES  ( 40 ,
										  'tempdb' ,
										  100 ,
										  'Performance' ,
										  'TempDB Only Has 1 Data File' ,
										  'http://BrentOzar.com/go/tempdb' ,
										  'TempDB is only configured with one data file.  More data files are usually required to alleviate SGAM contention.'
										);
							END;
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 41 ) 
					BEGIN   
						EXEC dbo.sp_MSforeachdb 'use [?]; 
		  INSERT INTO #BlitzResults 
		  (CheckID, 
		  DatabaseName, 
		  Priority, 
		  FindingsGroup, 
		  Finding, 
		  URL, 
		  Details) 
		  SELECT 41,
		  ''?'',
		  100, 
		  ''Performance'', 
		  ''Multiple Log Files on One Drive'', 
		  ''http://BrentOzar.com/go/manylogs'', 
		  (''The ['' + DB_NAME() + ''] database has multiple log files on the '' + LEFT(physical_name, 1) + '' drive. This is not a performance booster because log file access is sequential, not parallel.'') 
		  FROM [?].sys.database_files WHERE type_desc = ''LOG'' 
			AND ''?'' <> ''[tempdb]'' 
		  GROUP BY LEFT(physical_name, 1) 
		  HAVING COUNT(*) > 1';
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 42 ) 
					BEGIN
						EXEC dbo.sp_MSforeachdb 'use [?]; 
			INSERT INTO #BlitzResults 
			(CheckID, 
			DatabaseName,
			Priority, 
			FindingsGroup, 
			Finding, 
			URL, 
			Details) 
			SELECT DISTINCT 42, 
			''?'', 
			100, 
			''Performance'', 
			''Uneven File Growth Settings in One Filegroup'', 
			''http://BrentOzar.com/go/grow'',
			(''The ['' + DB_NAME() + ''] database has multiple data files in one filegroup, but they are not all set up to grow in identical amounts.  This can lead to uneven file activity inside the filegroup.'') 
			FROM [?].sys.database_files 
			WHERE type_desc = ''ROWS'' 
			GROUP BY data_space_id 
			HAVING COUNT(DISTINCT growth) > 1 OR COUNT(DISTINCT is_percent_growth) > 1';
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 44 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  44 AS CheckID ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Queries Forcing Order Hints' AS Finding ,
										'http://BrentOzar.com/go/hints' AS URL ,
										CAST(occurrence AS VARCHAR(10))
										+ ' instances of order hinting have been recorded since restart.  This means queries are bossing the SQL Server optimizer around, and if they don''t know what they''re doing, this can cause more harm than good.  This can also explain why DBA tuning efforts aren''t working.' AS Details
								FROM    sys.dm_exec_query_optimizer_info
								WHERE   counter = 'order hint'
										AND occurrence > 1
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 45 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  45 AS CheckID ,
										110 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Queries Forcing Join Hints' AS Finding ,
										'http://BrentOzar.com/go/hints' AS URL ,
										CAST(occurrence AS VARCHAR(10))
										+ ' instances of join hinting have been recorded since restart.  This means queries are bossing the SQL Server optimizer around, and if they don''t know what they''re doing, this can cause more harm than good.  This can also explain why DBA tuning efforts aren''t working.' AS Details
								FROM    sys.dm_exec_query_optimizer_info
								WHERE   counter = 'join hint'
										AND occurrence > 1
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 49 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT DISTINCT
										49 AS CheckID ,
										200 AS Priority ,
										'Informational' AS FindingsGroup ,
										'Linked Server Configured' AS Finding ,
										'http://BrentOzar.com/go/link' AS URL ,
										+CASE WHEN l.remote_name = 'sa'
											  THEN s.data_source
												   + ' is configured as a linked server. Check its security configuration as it is connecting with sa, because any user who queries it will get admin-level permissions.'
											  ELSE s.data_source
												   + ' is configured as a linked server. Check its security configuration to make sure it isn''t connecting with SA or some other bone-headed administrative login, because any user who queries it might get admin-level permissions.'
										 END AS Details
								FROM    sys.servers s
										INNER JOIN sys.linked_logins l ON s.server_id = l.server_id
								WHERE   s.is_linked = 1
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 50 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
		  SELECT  50 AS CheckID ,
		  100 AS Priority ,
		  ''Performance'' AS FindingsGroup ,
		  ''Max Memory Set Too High'' AS Finding ,
		  ''http://BrentOzar.com/go/max'' AS URL ,
		  ''SQL Server max memory is set to ''
			+ CAST(c.value_in_use AS VARCHAR(20))
			+ '' megabytes, but the server only has ''
			+ CAST(( CAST(m.total_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20))
			+ '' megabytes.  SQL Server may drain the system dry of memory, and under certain conditions, this can cause Windows to swap to disk.'' AS Details
		  FROM    sys.dm_os_sys_memory m
		  INNER JOIN sys.configurations c ON c.name = ''max server memory (MB)''
		  WHERE   CAST(m.total_physical_memory_kb AS BIGINT) < ( CAST(c.value_in_use AS BIGINT) * 1024 )'
								EXECUTE(@StringToExecute)
							END;
					END
	        
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 51 ) 
					BEGIN
						IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
							AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
		  SELECT  51 AS CheckID ,
		  1 AS Priority ,
		  ''Performance'' AS FindingsGroup ,
		  ''Memory Dangerously Low'' AS Finding ,
		  ''http://BrentOzar.com/go/max'' AS URL ,
		  ''The server has '' + CAST(( CAST(m.total_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20)) + '' megabytes of physical memory, but only '' + CAST(( CAST(m.available_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20))
			+ '' megabytes are available.  As the server runs out of memory, there is danger of swapping to disk, which will kill performance.'' AS Details
		  FROM    sys.dm_os_sys_memory m
		  WHERE   CAST(m.available_physical_memory_kb AS BIGINT) < 262144'
								EXECUTE(@StringToExecute)
							END;
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 53 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT TOP 1
										53 AS CheckID ,
										200 AS Priority ,
										'High Availability' AS FindingsGroup ,
										'Cluster Node' AS Finding ,
										'http://BrentOzar.com/go/node' AS URL ,
										'This is a node in a cluster.' AS Details
								FROM    sys.dm_os_cluster_nodes
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 55 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  55 AS CheckID ,
										[name] AS DatabaseName ,
										200 AS Priority ,
										'Security' AS FindingsGroup ,
										'Database Owner <> SA' AS Finding ,
										'http://BrentOzar.com/go/owndb' AS URL ,
										( 'Database name: ' + [name] + '   '
										  + 'Owner name: ' + SUSER_SNAME(owner_sid) ) AS Details
								FROM    sys.databases
								WHERE   SUSER_SNAME(owner_sid) <> SUSER_SNAME(0x01)
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks );
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 57 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  57 AS CheckID ,
										10 AS Priority ,
										'Security' AS FindingsGroup ,
										'SQL Agent Job Runs at Startup' AS Finding ,
										'http://BrentOzar.com/go/startup' AS URL ,
										( 'Job [' + j.name
										  + '] runs automatically when SQL Server Agent starts up.  Make sure you know exactly what this job is doing, because it could pose a security risk.' ) AS Details
								FROM    msdb.dbo.sysschedules sched
										JOIN msdb.dbo.sysjobschedules jsched ON sched.schedule_id = jsched.schedule_id
										JOIN msdb.dbo.sysjobs j ON jsched.job_id = j.job_id
								WHERE   sched.freq_type = 64;
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 58 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  58 AS CheckID ,
										d.[name] AS DatabaseName ,
										200 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'Database Collation Mismatch' AS Finding ,
										'http://BrentOzar.com/go/collate' AS URL ,
										( 'Database ' + d.NAME + ' has collation '
										  + d.collation_name
										  + '; Server collation is '
										  + CONVERT(VARCHAR(100), SERVERPROPERTY('collation')) ) AS Details
								FROM    master.sys.databases d
								WHERE   d.collation_name <> SERVERPROPERTY('collation')
										AND d.name NOT IN ( SELECT DISTINCT
																  DatabaseName
															FROM  #SkipChecks )
										AND d.name NOT LIKE 'ReportServer%'
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 82 ) 
					BEGIN
						EXEC sp_MSforeachdb 'use [?]; 
		INSERT INTO #BlitzResults 
		(CheckID, 
		DatabaseName,
		Priority, 
		FindingsGroup, 
		Finding, 
		URL, Details)
		SELECT  DISTINCT 82 AS CheckID, 
		''?'' as DatabaseName,
		100 AS Priority, 
		''Performance'' AS FindingsGroup, 
		''File growth set to percent'', 
		''http://brentozar.com/go/percentgrowth'' AS URL,
		''The ['' + DB_NAME() + ''] database is using percent filegrowth settings. This can lead to out of control filegrowth.''
		FROM    [?].sys.database_files 
		WHERE   is_percent_growth = 1 ';
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 97 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  97 AS CheckID ,
										100 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Unusual SQL Server Edition' AS Finding ,
										'http://BrentOzar.com/go/workgroup' AS URL ,
										( 'This server is using '
										  + CAST(SERVERPROPERTY('edition') AS VARCHAR(100))
										  + ', which is capped at low amounts of CPU and memory.' ) AS Details
								WHERE   CAST(SERVERPROPERTY('edition') AS VARCHAR(100)) NOT LIKE '%Standard%'
										AND CAST(SERVERPROPERTY('edition') AS VARCHAR(100)) NOT LIKE '%Enterprise%'
										AND CAST(SERVERPROPERTY('edition') AS VARCHAR(100)) NOT LIKE '%Developer%'
										AND CAST(SERVERPROPERTY('edition') AS VARCHAR(100)) NOT LIKE '%Business Intelligence%'
					END
	            
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 62 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  62 AS CheckID ,
										[name] AS DatabaseName ,
										200 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Old Compatibility Level' AS Finding ,
										'http://BrentOzar.com/go/compatlevel' AS URL ,
										( 'Database ' + [name]
										  + ' is compatibility level '
										  + CAST(compatibility_level AS VARCHAR(20))
										  + ', which may cause unwanted results when trying to run queries that have newer T-SQL features.' ) AS Details
								FROM    sys.databases
								WHERE   name NOT IN ( SELECT DISTINCT
																DatabaseName
													  FROM      #SkipChecks )
										AND compatibility_level <> ( SELECT
																  compatibility_level
																  FROM
																  sys.databases
																  WHERE
																  [name] = 'model'
																  )
					END

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 94 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  94 AS CheckID ,
										50 AS [Priority] ,
										'Reliability' AS FindingsGroup ,
										'Agent Jobs Without Failure Emails' AS Finding ,
										'http://BrentOzar.com/go/alerts' AS URL ,
										'The job ' + [name]
										+ ' has not been set up to notify an operator if it fails.' AS Details
								FROM    msdb.[dbo].[sysjobs] j
										INNER JOIN ( SELECT DISTINCT
															[job_id]
													 FROM   [msdb].[dbo].[sysjobschedules]
													 WHERE  next_run_date > 0
												   ) s ON j.job_id = s.job_id
								WHERE   j.enabled = 1
										AND j.notify_email_operator_id = 0
										AND j.notify_netsend_operator_id = 0
										AND j.notify_page_operator_id = 0        
					END


				IF EXISTS ( SELECT  1
							FROM    sys.configurations
							WHERE   name = 'remote admin connections'
									AND value_in_use = 0 )
					AND NOT EXISTS ( SELECT 1
									 FROM   #SkipChecks
									 WHERE  DatabaseName IS NULL AND CheckID = 100 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  100 AS CheckID ,
										50 AS Priority ,
										'Reliability' AS FindingGroup ,
										'Remote DAC Disabled' AS Finding ,
										'http://BrentOzar.com/go/dac' AS URL ,
										'Remote access to the Dedicated Admin Connection (DAC) is not enabled. The DAC can make remote troubleshooting much easier when SQL Server is unresponsive.'
					END


				IF EXISTS ( SELECT  *
							FROM    sys.dm_os_schedulers
							WHERE   is_online = 0 )
					AND NOT EXISTS ( SELECT 1
									 FROM   #SkipChecks
									 WHERE  DatabaseName IS NULL AND CheckID = 101 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  101 AS CheckID ,
										50 AS Priority ,
										'Performance' AS FindingGroup ,
										'CPU Schedulers Offline' AS Finding ,
										'http://BrentOzar.com/go/schedulers' AS URL ,
										'Some CPU cores are not accessible to SQL Server due to affinity masking or licensing problems.'
					END


					IF NOT EXISTS ( SELECT  1
									FROM    #SkipChecks
									WHERE   DatabaseName IS NULL AND CheckID = 110 ) 
								AND EXISTS (SELECT * FROM master.sys.all_objects WHERE name = 'dm_os_memory_nodes')
						BEGIN
							SET @StringToExecute = 'IF EXISTS (SELECT  *
												FROM sys.dm_os_nodes n
												INNER JOIN sys.dm_os_memory_nodes m ON n.memory_node_id = m.memory_node_id
												WHERE n.node_state_desc = ''OFFLINE'')
												INSERT  INTO #BlitzResults
														( CheckID ,
														  Priority ,
														  FindingsGroup ,
														  Finding ,
														  URL ,
														  Details
														)
														SELECT  110 AS CheckID ,
																50 AS Priority ,
																''Performance'' AS FindingGroup ,
																''Memory Nodes Offline'' AS Finding ,
																''http://BrentOzar.com/go/schedulers'' AS URL ,
																''Due to affinity masking or licensing problems, some of the memory may not be available.''';
									EXECUTE(@StringToExecute);
						END


				IF EXISTS ( SELECT  *
							FROM    sys.databases
							WHERE   state > 1 )
					AND NOT EXISTS ( SELECT 1
									 FROM   #SkipChecks
									 WHERE  DatabaseName IS NULL AND CheckID = 102 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  102 AS CheckID ,
										[name] ,
										20 AS Priority ,
										'Reliability' AS FindingGroup ,
										'Unusual Database State: ' + [state_desc] AS Finding ,
										'http://BrentOzar.com/go/repair' AS URL ,
										'This database may not be online.'
								FROM    sys.databases
								WHERE   state > 1
					END

				IF EXISTS ( SELECT  *
							FROM    master.sys.extended_procedures )
					AND NOT EXISTS ( SELECT 1
									 FROM   #SkipChecks
									 WHERE  DatabaseName IS NULL AND CheckID = 105 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  105 AS CheckID ,
										'master' ,
										50 AS Priority ,
										'Reliability' AS FindingGroup ,
										'Extended Stored Procedures in Master' AS Finding ,
										'http://BrentOzar.com/go/clr' AS URL ,
										'The [' + name
										+ '] extended stored procedure is in the master database. CLR may be in use, and the master database now needs to be part of your backup/recovery planning.'
								FROM    master.sys.extended_procedures
					END



					IF ( SELECT SUM([wait_time_ms]) AS total_wait_ms FROM sys.[dm_os_wait_stats] WHERE wait_type = 'THREADPOOL' ) > 5000
						AND NOT EXISTS ( SELECT 1
										 FROM   #SkipChecks
										 WHERE  DatabaseName IS NULL AND CheckID = 102 ) 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  107 AS CheckID ,
											100 AS Priority ,
											'Performance' AS FindingGroup ,
											'Poison Wait Detected: THREADPOOL'  AS Finding ,
											'http://BrentOzar.com/go/poison' AS URL ,
											CAST(SUM([wait_time_ms]) AS VARCHAR(100)) + ' milliseconds of this wait have been recorded. This wait often indicates killer performance problems.'
									FROM sys.[dm_os_wait_stats] 
									WHERE wait_type = 'THREADPOOL'
									GROUP BY wait_type
						END

					IF ( SELECT SUM([wait_time_ms]) AS total_wait_ms FROM sys.[dm_os_wait_stats] WHERE wait_type = 'RESOURCE_SEMAPHORE' ) > 5000
						AND NOT EXISTS ( SELECT 1
										 FROM   #SkipChecks
										 WHERE  DatabaseName IS NULL AND CheckID = 102 ) 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  108 AS CheckID ,
											100 AS Priority ,
											'Performance' AS FindingGroup ,
											'Poison Wait Detected: RESOURCE_SEMAPHORE'  AS Finding ,
											'http://BrentOzar.com/go/poison' AS URL ,
											CAST(SUM([wait_time_ms]) AS VARCHAR(100)) + ' milliseconds of this wait have been recorded. This wait often indicates killer performance problems.'
									FROM sys.[dm_os_wait_stats] 
									WHERE wait_type = 'RESOURCE_SEMAPHORE'
									GROUP BY wait_type
						END


					IF ( SELECT SUM([wait_time_ms]) AS total_wait_ms FROM sys.[dm_os_wait_stats] WHERE wait_type = 'RESOURCE_SEMAPHORE_QUERY_COMPILE' ) > 5000
						AND NOT EXISTS ( SELECT 1
										 FROM   #SkipChecks
										 WHERE  DatabaseName IS NULL AND CheckID = 102 ) 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  109 AS CheckID ,
											100 AS Priority ,
											'Performance' AS FindingGroup ,
											'Poison Wait Detected: RESOURCE_SEMAPHORE_QUERY_COMPILE'  AS Finding ,
											'http://BrentOzar.com/go/poison' AS URL ,
											CAST(SUM([wait_time_ms]) AS VARCHAR(100)) + ' milliseconds of this wait have been recorded. This wait often indicates killer performance problems.'
									FROM sys.[dm_os_wait_stats] 
									WHERE wait_type = 'RESOURCE_SEMAPHORE_QUERY_COMPILE'
									GROUP BY wait_type
						END


						IF NOT EXISTS ( SELECT 1
										 FROM   #SkipChecks
										 WHERE  DatabaseName IS NULL AND CheckID = 111 ) 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  DatabaseName ,
									  URL ,
									  Details
									)
									SELECT  111 AS CheckID ,
											50 AS Priority ,
											'Reliability' AS FindingGroup ,
											'Possibly Broken Log Shipping'  AS Finding ,
											d.[name] ,
											'http://BrentOzar.com/go/shipping' AS URL ,
											d.[name] + ' is in a restoring state, but has not had a backup applied in the last two days. This is a possible indication of a broken transaction log shipping setup.'
											FROM [master].sys.databases d
											INNER JOIN [master].sys.database_mirroring dm ON d.database_id = dm.database_id
												AND dm.mirroring_role IS NULL
											WHERE ( d.[state] = 1
											OR (d.[state] = 0 AND d.[is_in_standby] = 1) )
											AND NOT EXISTS(SELECT * FROM msdb.dbo.restorehistory rh 
											INNER JOIN msdb.dbo.backupset bs ON rh.backup_set_id = bs.backup_set_id
											WHERE d.[name] COLLATE SQL_Latin1_General_CP1_CI_AS = rh.destination_database_name COLLATE SQL_Latin1_General_CP1_CI_AS
											AND rh.restore_date >= DATEADD(dd, -2, GETDATE()))

						END


						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 112 ) 
									AND EXISTS (SELECT * FROM master.sys.all_objects WHERE name = 'change_tracking_databases')
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults 
									(CheckID, 
									Priority, 
									FindingsGroup, 
									Finding, 
									URL, 
									Details)
							  SELECT 112 AS CheckID, 
							  100 AS Priority, 
							  ''Performance'' AS FindingsGroup, 
							  ''Change Tracking Enabled'' AS Finding, 
							  ''http://BrentOzar.com/go/tracking'' AS URL,
							  ( d.[name] + '' has change tracking enabled. This is not a default setting, and it has some performance overhead. It keeps track of changes to rows in tables that have change tracking turned on.'' ) AS Details FROM sys.change_tracking_databases AS ctd INNER JOIN sys.databases AS d ON ctd.database_id = d.database_id';
										EXECUTE(@StringToExecute);
							END

						IF NOT EXISTS ( SELECT 1
										 FROM   #SkipChecks
										 WHERE  DatabaseName IS NULL AND CheckID = 116 ) 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  116 AS CheckID ,
											200 AS Priority ,
											'Informational' AS FindingGroup ,
											'Backup Compression Default Off'  AS Finding ,
											'http://BrentOzar.com/go/backup' AS URL ,
											'Backup compression is included with SQL Server 2008R2 & newer, even in Standard Edition. We recommend turning backup compression on by default so that ad-hoc backups will get compressed.'
											FROM sys.configurations
											WHERE configuration_id = 1579 AND CAST(value_in_use AS INT) = 0

						END

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 117 ) 
									AND EXISTS (SELECT * FROM master.sys.all_objects WHERE name = 'dm_exec_query_resource_semaphores')
							BEGIN
								SET @StringToExecute = 'IF 0 < (SELECT SUM([forced_grant_count]) FROM sys.dm_exec_query_resource_semaphores WHERE [forced_grant_count] IS NOT NULL)
								INSERT INTO #BlitzResults 
									(CheckID, 
									Priority, 
									FindingsGroup, 
									Finding, 
									URL, 
									Details)
							  SELECT 117 AS CheckID, 
							  100 AS Priority, 
							  ''Performance'' AS FindingsGroup, 
							  ''Memory Pressure Affecting Queries'' AS Finding, 
							  ''http://BrentOzar.com/go/grants'' AS URL,
							  CAST(SUM(forced_grant_count) AS NVARCHAR(100)) + '' forced grants reported in the DMV sys.dm_exec_query_resource_semaphores, indicating memory pressure has affected query runtimes.''
							  FROM sys.dm_exec_query_resource_semaphores WHERE [forced_grant_count] IS NOT NULL;'
										EXECUTE(@StringToExecute);
							END




	            
				IF @CheckUserDatabaseObjects = 1 
					BEGIN
	              
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 32 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
			INSERT INTO #BlitzResults 
			(CheckID, 
			DatabaseName,
			Priority, 
			FindingsGroup, 
			Finding, 
			URL, 
			Details) 
			SELECT DISTINCT 32, 
			''?'', 
			110, 
			''Performance'', 
			''Triggers on Tables'', 
			''http://BrentOzar.com/go/trig'', 
			(''The ['' + DB_NAME() + ''] database has triggers on the '' + s.name + ''.'' + o.name + '' table.'') 
			FROM [?].sys.triggers t INNER JOIN [?].sys.objects o ON t.parent_id = o.object_id 
			INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id WHERE t.is_ms_shipped = 0 AND DB_NAME() != ''ReportServer''';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 38 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
			INSERT INTO #BlitzResults 
			(CheckID, 
			DatabaseName,
			Priority, 
			FindingsGroup, 
			Finding, 
			URL, 
			Details) 
		  SELECT DISTINCT 38,
		  ''?'', 
		  110, 
		  ''Performance'', 
		  ''Active Tables Without Clustered Indexes'', 
		  ''http://BrentOzar.com/go/heaps'', 
		  (''The ['' + DB_NAME() + ''] database has heaps - tables without a clustered index - that are being actively queried.'') 
		  FROM [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id 
		  INNER JOIN [?].sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id 
		  INNER JOIN sys.databases sd ON sd.name = ''?'' 
		  LEFT OUTER JOIN [?].sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = sd.database_id 
		  WHERE i.type_desc = ''HEAP'' AND COALESCE(ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates) IS NOT NULL 
		  AND sd.name <> ''tempdb'' AND o.is_ms_shipped = 0 AND o.type <> ''S''';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 39 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
			INSERT INTO #BlitzResults 
			(CheckID, 
			DatabaseName,
			Priority, 
			FindingsGroup, 
			Finding, 
			URL, 
			Details) 
		  SELECT DISTINCT 39, 
		  ''?'',
		  110, 
		  ''Performance'', 
		  ''Inactive Tables Without Clustered Indexes'', 
		  ''http://BrentOzar.com/go/heaps'', 
		  (''The ['' + DB_NAME() + ''] database has heaps - tables without a clustered index - that have not been queried since the last restart.  These may be backup tables carelessly left behind.'') 
		  FROM [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id 
		  INNER JOIN [?].sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id 
		  INNER JOIN sys.databases sd ON sd.name = ''?'' 
		  LEFT OUTER JOIN [?].sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = sd.database_id 
		  WHERE i.type_desc = ''HEAP'' AND COALESCE(ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates) IS NULL 
		  AND sd.name <> ''tempdb'' AND o.is_ms_shipped = 0 AND o.type <> ''S''';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 46 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName, 
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT 46, 
		  ''?'',
		  100,  
		  ''Performance'', 
		  ''Leftover Fake Indexes From Wizards'', 
		  ''http://BrentOzar.com/go/hypo'', 
		  (''The index ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is a leftover hypothetical index from the Index Tuning Wizard or Database Tuning Advisor.  This index is not actually helping performance and should be removed.'') 
		  from [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id 
		  WHERE i.is_hypothetical = 1';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 47 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT 47, 
		  ''?'', 
		  100, 
		  ''Performance'', 
		  ''Indexes Disabled'', 
		  ''http://BrentOzar.com/go/ixoff'', 
		  (''The index ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is disabled.  This index is not actually helping performance and should either be enabled or removed.'') 
		  from [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id 
		  WHERE i.is_disabled = 1';
							END
	    
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 48 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT DISTINCT 48,
		  ''?'', 
		  100, 
		  ''Performance'', 
		  ''Foreign Keys Not Trusted'', 
		  ''http://BrentOzar.com/go/trust'', 
		  (''The ['' + DB_NAME() + ''] database has foreign keys that were probably disabled, data was changed, and then the key was enabled again.  Simply enabling the key is not enough for the optimizer to use this key - we have to alter the table using the WITH CHECK CHECK CONSTRAINT parameter.'') 
		  from [?].sys.foreign_keys i INNER JOIN [?].sys.objects o ON i.parent_object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id 
		  WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 56 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT 56,
		  ''?'', 
		  100, 
		  ''Performance'', 
		  ''Check Constraint Not Trusted'', 
		  ''http://BrentOzar.com/go/trust'', 
		  (''The check constraint ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is not trusted - meaning, it was disabled, data was changed, and then the constraint was enabled again.  Simply enabling the constraint is not enough for the optimizer to use this constraint - we have to alter the table using the WITH CHECK CHECK CONSTRAINT parameter.'') 
		  from [?].sys.check_constraints i INNER JOIN [?].sys.objects o ON i.parent_object_id = o.object_id 
		  INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id 
		  WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 95 ) 
							BEGIN
								IF @@VERSION NOT LIKE '%Microsoft SQL Server 2000%'
									AND @@VERSION NOT LIKE '%Microsoft SQL Server 2005%' 
									BEGIN
										EXEC dbo.sp_MSforeachdb 'USE [?]; 
			INSERT INTO #BlitzResults 
				  (CheckID, 
				  DatabaseName,
				  Priority, 
				  FindingsGroup, 
				  Finding, 
				  URL, 
				  Details) 
			SELECT TOP 1 95 AS CheckID,
			''?'' as DatabaseName, 
			110 AS Priority, 
			''Performance'' AS FindingsGroup, 
			''Plan Guides Enabled'' AS Finding, 
			''http://BrentOzar.com/go/guides'' AS URL, 
			(''Database ['' + DB_NAME() + ''] has query plan guides so a query will always get a specific execution plan. If you are having trouble getting query performance to improve, it might be due to a frozen plan. Review the DMV sys.plan_guides to learn more about the plan guides in place on this server.'') AS Details 
			FROM [?].sys.plan_guides WHERE is_disabled = 0'
									END;
							END
	              
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 60 ) 
							BEGIN
								EXEC sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details)
		  SELECT  DISTINCT 60 AS CheckID, 
		  ''?'' as DatabaseName,
		  100 AS Priority, 
		  ''Performance'' AS FindingsGroup, 
		  ''Fill Factor Changed'', 
		  ''http://brentozar.com/go/fillfactor'' AS URL,
		  ''The ['' + DB_NAME() + ''] database has objects with fill factor <> 0. This can cause memory and storage performance problems, but may also prevent page splits.''
		  FROM    [?].sys.indexes 
		  WHERE   fill_factor <> 0 AND fill_factor <> 100 AND is_disabled = 0 AND is_hypothetical = 0';
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 78 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT 78, 
		  ''?'',
		  100, 
		  ''Performance'', 
		  ''Stored Procedure WITH RECOMPILE'', 
		  ''http://BrentOzar.com/go/recompile'', 
		  (''['' + DB_NAME() + ''].['' + SPECIFIC_SCHEMA + ''].['' + SPECIFIC_NAME + ''] has WITH RECOMPILE in the stored procedure code, which may cause increased CPU usage due to constant recompiles of the code.'') 
		  from [?].INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_DEFINITION LIKE N''%WITH RECOMPILE%''';
							END

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 86 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 86, DB_NAME(), 20, ''Security'', ''Elevated Permissions on a Database'', ''http://BrentOzar.com/go/elevated'', (''In ['' + DB_NAME() + ''], user ['' + u.name + '']  has the role ['' + g.name + ''].  This user can perform tasks beyond just reading and writing data.'') FROM [?].dbo.sysmembers m inner join [?].dbo.sysusers u on m.memberuid = u.uid inner join sysusers g on m.groupuid = g.uid where u.name <> ''dbo'' and g.name in (''db_owner'' , ''db_accessAdmin'' , ''db_securityadmin'' , ''db_ddladmin'')';
							END


							/*Check for non-aligned indexes in partioned databases*/
	                  
										IF NOT EXISTS ( SELECT  1
														FROM    #SkipChecks
														WHERE   DatabaseName IS NULL AND CheckID = 72 ) 
											BEGIN
												EXEC dbo.sp_MSforeachdb 'USE [?]; 
								insert into #partdb(dbname, objectname, type_desc)
								SELECT distinct db_name(DB_ID()) as DBName,o.name Object_Name,ds.type_desc
								FROM sys.objects AS o JOIN sys.indexes AS i ON o.object_id = i.object_id 
								JOIN sys.data_spaces ds on ds.data_space_id = i.data_space_id
								LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s ON i.object_id = s.object_id AND i.index_id = s.index_id AND s.database_id = DB_ID()
								WHERE  o.type = ''u''
								 -- Clustered and Non-Clustered indexes
								AND i.type IN (1, 2) 
								AND o.object_id in 
								  (
									SELECT a.object_id from 
									  (SELECT ob.object_id, ds.type_desc from sys.objects ob JOIN sys.indexes ind on ind.object_id = ob.object_id join sys.data_spaces ds on ds.data_space_id = ind.data_space_id
									  GROUP BY ob.object_id, ds.type_desc ) a group by a.object_id having COUNT (*) > 1
								  )'
												INSERT  INTO #BlitzResults
														( CheckID ,
														  DatabaseName ,
														  Priority ,
														  FindingsGroup ,
														  Finding ,
														  URL ,
														  Details
														)
														SELECT DISTINCT
																72 AS CheckID ,
																dbname AS DatabaseName ,
																100 AS Priority ,
																'Performance' AS FindingsGroup ,
																'The partitioned database ' + dbname
																+ ' may have non-aligned indexes' AS Finding ,
																'http://BrentOzar.com/go/aligned' AS URL ,
																'Having non-aligned indexes on partitioned tables may cause inefficient query plans and CPU pressure' AS Details
														FROM    #partdb
														WHERE   dbname IS NOT NULL
																AND dbname NOT IN ( SELECT DISTINCT
																						  DatabaseName
																					FROM  #SkipChecks )
												DROP TABLE #partdb
											END


											IF NOT EXISTS ( SELECT  1
															FROM    #SkipChecks
															WHERE   DatabaseName IS NULL AND CheckID = 113 ) 
												BEGIN
													EXEC dbo.sp_MSforeachdb 'USE [?]; 
							  INSERT INTO #BlitzResults 
									(CheckID, 
									DatabaseName,
									Priority, 
									FindingsGroup, 
									Finding, 
									URL, 
									Details) 
							  SELECT DISTINCT 113,
							  ''?'', 
							  50, 
							  ''Reliability'', 
							  ''Full Text Indexes Not Updating'', 
							  ''http://BrentOzar.com/go/fulltext'', 
							  (''At least one full text index in this database has not been crawled in the last week.'') 
							  from [?].sys.fulltext_indexes i WHERE i.is_enabled = 1 AND i.crawl_end_date < DATEADD(dd, -7, GETDATE())';
												END

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 115 ) 
							BEGIN
								EXEC dbo.sp_MSforeachdb 'USE [?]; 
		  INSERT INTO #BlitzResults 
				(CheckID, 
				DatabaseName,
				Priority, 
				FindingsGroup, 
				Finding, 
				URL, 
				Details) 
		  SELECT 115, 
		  ''?'',
		  110, 
		  ''Performance'', 
		  ''Parallelism Rocket Surgery'', 
		  ''http://BrentOzar.com/go/makeparallel'', 
		  (''['' + DB_NAME() + ''] has a make_parallel function, indicating that an advanced developer may be manhandling SQL Server into forcing queries to go parallel.'') 
		  from [?].INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = ''make_parallel'' AND ROUTINE_TYPE = ''FUNCTION''';
							END


					END /* IF @CheckUserDatabaseObjects = 1 */

				IF @CheckProcedureCache = 1 
					BEGIN
	        
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 35 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
										SELECT  35 AS CheckID ,
												100 AS Priority ,
												'Performance' AS FindingsGroup ,
												'Single-Use Plans in Procedure Cache' AS Finding ,
												'http://BrentOzar.com/go/single' AS URL ,
												( CAST(COUNT(*) AS VARCHAR(10))
												  + ' query plans are taking up memory in the procedure cache. This may be wasted memory if we cache plans for queries that never get called again. This may be a good use case for SQL Server 2008''s Optimize for Ad Hoc or for Forced Parameterization.' ) AS Details
										FROM    sys.dm_exec_cached_plans AS cp
										WHERE   cp.usecounts = 1
												AND cp.objtype = 'Adhoc'
												AND EXISTS ( SELECT
																  1
															 FROM sys.configurations
															 WHERE
																  name = 'optimize for ad hoc workloads'
																  AND value_in_use = 0 )
										HAVING  COUNT(*) > 1;
							END


		  /* Set up the cache tables. Different on 2005 since it doesn't support query_hash, query_plan_hash. */
						IF @@VERSION LIKE '%Microsoft SQL Server 2005%' 
							BEGIN
								IF @CheckProcedureCacheFilter = 'CPU'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			  FROM sys.dm_exec_query_stats qs
			  ORDER BY qs.total_worker_time DESC)
			  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			  FROM queries qs
			  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
			  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

								IF @CheckProcedureCacheFilter = 'Reads'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_logical_reads DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
									END

								IF @CheckProcedureCacheFilter = 'ExecCount'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.execution_count DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

								IF @CheckProcedureCacheFilter = 'Duration'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			FROM sys.dm_exec_query_stats qs
			ORDER BY qs.total_elapsed_time DESC)
			INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			FROM queries qs
			LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
			WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

							END;
						IF @@VERSION LIKE '%Microsoft SQL Server 2008%'
							OR @@VERSION LIKE '%Microsoft SQL Server 2012%' 
							OR @@VERSION LIKE '%Microsoft SQL Server 2016%' 
							BEGIN
								IF @CheckProcedureCacheFilter = 'CPU'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_worker_time DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

								IF @CheckProcedureCacheFilter = 'Reads'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_logical_reads DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

								IF @CheckProcedureCacheFilter = 'ExecCount'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.execution_count DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

								IF @CheckProcedureCacheFilter = 'Duration'
									OR @CheckProcedureCacheFilter IS NULL 
									BEGIN
										SET @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_elapsed_time DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL;'
										EXECUTE(@StringToExecute)
									END

		/* Populate the query_plan_filtered field. Only works in 2005SP2+, but we're just doing it in 2008 to be safe. */
								UPDATE  #dm_exec_query_stats
								SET     query_plan_filtered = qp.query_plan
								FROM    #dm_exec_query_stats qs
										CROSS APPLY sys.dm_exec_text_query_plan(qs.plan_handle,
																  qs.statement_start_offset,
																  qs.statement_end_offset)
										AS qp 

							END;

		/* Populate the additional query_plan, text, and text_filtered fields */
						UPDATE  #dm_exec_query_stats
						SET     query_plan = qp.query_plan ,
								[text] = st.[text] ,
								text_filtered = SUBSTRING(st.text,
														  ( qs.statement_start_offset
															/ 2 ) + 1,
														  ( ( CASE qs.statement_end_offset
																WHEN -1
																THEN DATALENGTH(st.text)
																ELSE qs.statement_end_offset
															  END
															  - qs.statement_start_offset )
															/ 2 ) + 1)
						FROM    #dm_exec_query_stats qs
								CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
								CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle)
								AS qp

		/* Dump instances of our own script. We're not trying to tune ourselves. */
						DELETE  #dm_exec_query_stats
						WHERE   text LIKE '%sp_Blitz%'
								OR text LIKE '%#BlitzResults%'

		/* Look for implicit conversions */
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 63 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details ,
										  QueryPlan ,
										  QueryPlanFiltered
										)
										SELECT  63 AS CheckID ,
												120 AS Priority ,
												'Query Plans' AS FindingsGroup ,
												'Implicit Conversion' AS Finding ,
												'http://BrentOzar.com/go/implicit' AS URL ,
												( 'One of the top resource-intensive queries is comparing two fields that are not the same datatype.' ) AS Details ,
												qs.query_plan ,
												qs.query_plan_filtered
										FROM    #dm_exec_query_stats qs
										WHERE   COALESCE(qs.query_plan_filtered,
														 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%CONVERT_IMPLICIT%'
												AND COALESCE(qs.query_plan_filtered,
															 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%PhysicalOp="Index Scan"%'
							END
	            
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 64 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details ,
										  QueryPlan ,
										  QueryPlanFiltered
										)
										SELECT  64 AS CheckID ,
												120 AS Priority ,
												'Query Plans' AS FindingsGroup ,
												'Implicit Conversion Affecting Cardinality' AS Finding ,
												'http://BrentOzar.com/go/implicit' AS URL ,
												( 'One of the top resource-intensive queries has an implicit conversion that is affecting cardinality estimation.' ) AS Details ,
												qs.query_plan ,
												qs.query_plan_filtered
										FROM    #dm_exec_query_stats qs
										WHERE   COALESCE(qs.query_plan_filtered,
														 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%<PlanAffectingConvert ConvertIssue="Cardinality Estimate" Expression="CONVERT_IMPLICIT%'
							END

		/* Look for missing indexes */
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 65 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details ,
										  QueryPlan ,
										  QueryPlanFiltered
										)
										SELECT  65 AS CheckID ,
												120 AS Priority ,
												'Query Plans' AS FindingsGroup ,
												'Missing Index' AS Finding ,
												'http://BrentOzar.com/go/missingindex' AS URL ,
												( 'One of the top resource-intensive queries may be dramatically improved by adding an index.' ) AS Details ,
												qs.query_plan ,
												qs.query_plan_filtered
										FROM    #dm_exec_query_stats qs
										WHERE   COALESCE(qs.query_plan_filtered,
														 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%MissingIndexGroup%'
							END

		/* Look for cursors */
	                    
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 66 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details ,
										  QueryPlan ,
										  QueryPlanFiltered
										)
										SELECT  66 AS CheckID ,
												120 AS Priority ,
												'Query Plans' AS FindingsGroup ,
												'Cursor' AS Finding ,
												'http://BrentOzar.com/go/cursor' AS URL ,
												( 'One of the top resource-intensive queries is using a cursor.' ) AS Details ,
												qs.query_plan ,
												qs.query_plan_filtered
										FROM    #dm_exec_query_stats qs
										WHERE   COALESCE(qs.query_plan_filtered,
														 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%<StmtCursor%'
							END
	    
		/* Look for scalar user-defined functions */
	                    
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 67 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details ,
										  QueryPlan ,
										  QueryPlanFiltered
										)
										SELECT  67 AS CheckID ,
												120 AS Priority ,
												'Query Plans' AS FindingsGroup ,
												'Scalar UDFs' AS Finding ,
												'http://BrentOzar.com/go/functions' AS URL ,
												( 'One of the top resource-intensive queries is using a user-defined scalar function that may inhibit parallelism.' ) AS Details ,
												qs.query_plan ,
												qs.query_plan_filtered
										FROM    #dm_exec_query_stats qs
										WHERE   COALESCE(qs.query_plan_filtered,
														 CAST(qs.query_plan AS NVARCHAR(MAX))) LIKE '%<UserDefinedFunction%'
							END
	    
					END /* IF @CheckProcedureCache = 1 */

		/*Check for the last good DBCC CHECKDB date */
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 68 ) 
					BEGIN
						EXEC sp_MSforeachdb N'USE [?];
		INSERT #DBCCs
			(ParentObject, 
			Object, 
			Field, 
			Value)
		EXEC (''DBCC DBInfo() With TableResults, NO_INFOMSGS'');
		UPDATE #DBCCs SET DbName = N''?'' WHERE DbName IS NULL;';

						WITH    DB2
								  AS ( SELECT DISTINCT
												Field ,
												Value ,
												DbName
									   FROM     #DBCCs
									   WHERE    Field = 'dbi_dbccLastKnownGood'
									 )
							INSERT  INTO #BlitzResults
									( CheckID ,
									  DatabaseName ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  68 AS CheckID ,
											DB2.DbName AS DatabaseName ,
											50 AS PRIORITY ,
											'Reliability' AS FindingsGroup ,
											'Last good DBCC CHECKDB over 2 weeks old' AS Finding ,
											'http://BrentOzar.com/go/checkdb' AS URL ,
											'Database [' + DB2.DbName + ']'
											+ CASE DB2.Value
												WHEN '1900-01-01 12:00:00 AM'
												THEN ' never had a successful DBCC CHECKDB.'
												ELSE ' last had a successful DBCC CHECKDB run on '
													 + DB2.Value + '.'
											  END
											+ ' This check should be run regularly to catch any database corruption as soon as possible.'
											+ ' Note: you can restore a backup of a busy production database to a test server and run DBCC CHECKDB '
											+ ' against that to minimize impact. If you do that, you can ignore this warning.' AS Details
									FROM    DB2
									WHERE   DB2.DbName NOT IN ( SELECT DISTINCT
																  DatabaseName
																FROM
																  #SkipChecks )
											AND CONVERT(DATETIME, DB2.Value, 121) < DATEADD(DD,
																  -14,
																  CURRENT_TIMESTAMP)
					END

		/*Check for high VLF count: this will omit any database snapshots*/
	                    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 69 ) 
					BEGIN
						IF @@VERSION LIKE 'Microsoft SQL Server 2012%' OR @@VERSION LIKE 'Microsoft SQL Server 2016%'
							BEGIN
								EXEC sp_MSforeachdb N'USE [?];    
		  INSERT INTO #LogInfo2012 
		  EXEC sp_executesql N''DBCC LogInfo() WITH NO_INFOMSGS'';      
		  IF    @@ROWCOUNT > 999            
		  BEGIN
			INSERT  INTO #BlitzResults                        
			( CheckID   
			,DatabaseName                      
			,Priority                          
			,FindingsGroup                          
			,Finding                          
			,URL                          
			,Details)                  
			SELECT      69 
			,DB_NAME()                             
			,100                              
			,''Performance''                              
			,''High VLF Count''                              
			,''http://BrentOzar.com/go/vlf''                              
			,''The ['' + DB_NAME() + ''] database has '' +  CAST(COUNT(*) as VARCHAR(20)) + '' virtual log files (VLFs). This may be slowing down startup, restores, and even inserts/updates/deletes.''  
			FROM #LogInfo2012
			WHERE EXISTS (SELECT name FROM master.sys.databases 
					WHERE source_database_id is null) ;            
		  END                       
		TRUNCATE TABLE #LogInfo2012;'
								DROP TABLE #LogInfo2012;
							END
						ELSE
							BEGIN
								EXEC sp_MSforeachdb N'USE [?];    
		  INSERT INTO #LogInfo 
		  EXEC sp_executesql N''DBCC LogInfo() WITH NO_INFOMSGS'';      
		  IF    @@ROWCOUNT > 999            
		  BEGIN
			INSERT  INTO #BlitzResults                        
			( CheckID 
			,DatabaseName                         
			,Priority                          
			,FindingsGroup                          
			,Finding                          
			,URL                          
			,Details)                  
			SELECT      69
			,DB_NAME()                              
			,100                              
			,''Performance''                              
			,''High VLF Count''                              
			,''http://BrentOzar.com/go/vlf''                              
			,''The ['' + DB_NAME() + ''] database has '' +  CAST(COUNT(*) as VARCHAR(20)) + '' virtual log files (VLFs). This may be slowing down startup, restores, and even inserts/updates/deletes.''  
			FROM #LogInfo
			WHERE EXISTS (SELECT name FROM master.sys.databases 
			WHERE source_database_id is null);            
		  END                       
		  TRUNCATE TABLE #LogInfo;'
								DROP TABLE #LogInfo;
							END
					END
		/*Verify that the servername is set */          
	/*Verify that the servername is set */          
			IF NOT EXISTS ( SELECT  1
							FROM    #SkipChecks
							WHERE   DatabaseName IS NULL AND CheckID = 70 ) 
				BEGIN
					IF @@SERVERNAME IS NULL 
						BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  70 AS CheckID ,
											200 AS Priority ,
											'Configuration' AS FindingsGroup ,
											'@@Servername Not Set' AS Finding ,
											'http://BrentOzar.com/go/servername' AS URL ,
											'@@Servername variable is null. You can fix it by executing: "sp_addserver ''<LocalServerName>'', local"' AS Details
						END;

					IF  /* @@SERVERNAME IS set */
						(@@SERVERNAME IS NOT NULL 
						AND 
						/* not a named instance */
						CHARINDEX('\',CAST(SERVERPROPERTY('ServerName') AS NVARCHAR)) = 0
						AND
						/* not clustered, when computername may be different than the servername */
						SERVERPROPERTY('IsClustered') = 0
						AND
						/* @@SERVERNAME is different than the computer name */
						@@SERVERNAME <> CAST(ISNULL(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),@@SERVERNAME) AS NVARCHAR) )
						 BEGIN
							INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  70 AS CheckID ,
											200 AS Priority ,
											'Configuration' AS FindingsGroup ,
											'@@Servername Not Correct' AS Finding ,
											'http://BrentOzar.com/go/servername' AS URL ,
											'The @@Servername is different than the computer name, which may trigger certificate errors.' AS Details
						END;

				END    
		/*Check to see if a failsafe operator has been configured*/   
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 73 ) 
					BEGIN

						DECLARE @AlertInfo TABLE
							(
							  FailSafeOperator NVARCHAR(255) ,
							  NotificationMethod INT ,
							  ForwardingServer NVARCHAR(255) ,
							  ForwardingSeverity INT ,
							  PagerToTemplate NVARCHAR(255) ,
							  PagerCCTemplate NVARCHAR(255) ,
							  PagerSubjectTemplate NVARCHAR(255) ,
							  PagerSendSubjectOnly NVARCHAR(255) ,
							  ForwardAlways INT
							)
						INSERT  INTO @AlertInfo
								EXEC [master].[dbo].[sp_MSgetalertinfo] @includeaddresses = 0
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  73 AS CheckID ,
										50 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'No failsafe operator configured' AS Finding ,
										'http://BrentOzar.com/go/failsafe' AS URL ,
										( 'No failsafe operator is configured on this server.  This is a good idea just in-case there are issues with the [msdb] database that prevents alerting.' ) AS Details
								FROM    @AlertInfo
								WHERE   FailSafeOperator IS NULL;
					END
	    
		/*Identify globally enabled trace flags*/
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 74 ) 
					BEGIN
						INSERT  INTO #TraceStatus
								EXEC ( ' DBCC TRACESTATUS(-1) WITH NO_INFOMSGS'
									)
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  74 AS CheckID ,
										200 AS Priority ,
										'Global Trace Flag' AS FindingsGroup ,
										'TraceFlag On' AS Finding ,
										'http://www.BrentOzar.com/go/traceflags/' AS URL ,
										'Trace flag ' + T.TraceFlag
										+ ' is enabled globally.' AS Details
								FROM    #TraceStatus T
					END
	    
		/*Check for transaction log file larger than data file */             
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 75 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  75 AS CheckID ,
										DB_NAME(a.database_id) ,
										50 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'Transaction Log Larger than Data File' AS Finding ,
										'http://BrentOzar.com/go/biglog' AS URL ,
										'The database [' + DB_NAME(a.database_id)
										+ '] has a transaction log file larger than a data file. This may indicate that transaction log backups are not being performed or not performed often enough.' AS Details
								FROM    sys.master_files a
								WHERE   a.type = 1
										AND DB_NAME(a.database_id) NOT IN (
										SELECT DISTINCT
												DatabaseName
										FROM    #SkipChecks )
										AND a.size > 125000 /* Size is measured in pages here, so this gets us log files over 1GB. */
										AND a.size > ( SELECT   SUM(b.size)
													   FROM     sys.master_files b
													   WHERE    a.database_id = b.database_id
																AND b.type = 0
													 )
										AND a.database_id IN (
										SELECT  database_id
										FROM    sys.databases
										WHERE   source_database_id IS NULL )
					END
	    
		/*Check for collation conflicts between user databases and tempdb */          
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 76 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  76 AS CheckID ,
										name AS DatabaseName ,
										50 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'Collation for ' + name
										+ ' different than tempdb collation' AS Finding ,
										'http://BrentOzar.com/go/collate' AS URL ,
										'Collation differences between user databases and tempdb can cause conflicts especially when comparing string values' AS Details
								FROM    sys.databases
							WHERE   name NOT IN ( 'master', 'model', 'msdb')
										AND name NOT LIKE 'ReportServer%'
										AND name NOT IN ( SELECT DISTINCT
																  DatabaseName
														  FROM    #SkipChecks )
										AND collation_name <> ( SELECT
																  collation_name
																FROM
																  sys.databases
																WHERE
																  name = 'tempdb'
															  )
					END
	                    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 77 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  DatabaseName ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  77 AS CheckID ,
										dSnap.[name] AS DatabaseName ,
										50 AS Priority ,
										'Reliability' AS FindingsGroup ,
										'Database Snapshot Online' AS Finding ,
										'http://BrentOzar.com/go/snapshot' AS URL ,
										'Database [' + dSnap.[name]
										+ '] is a snapshot of ['
										+ dOriginal.[name]
										+ ']. Make sure you have enough drive space to maintain the snapshot as the original database grows.' AS Details
								FROM    sys.databases dSnap
										INNER JOIN sys.databases dOriginal ON dSnap.source_database_id = dOriginal.database_id
																  AND dSnap.name NOT IN (
																  SELECT DISTINCT
																  DatabaseName
																  FROM
																  #SkipChecks )
					END
	                    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 79 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  79 AS CheckID ,
										100 AS Priority ,
										'Performance' AS FindingsGroup ,
										'Shrink Database Job' AS Finding ,
										'http://BrentOzar.com/go/autoshrink' AS URL ,
										'In the [' + j.[name] + '] job, step ['
										+ step.[step_name]
										+ '] has SHRINKDATABASE or SHRINKFILE, which may be causing database fragmentation.' AS Details
								FROM    msdb.dbo.sysjobs j
										INNER JOIN msdb.dbo.sysjobsteps step ON j.job_id = step.job_id
								WHERE   step.command LIKE N'%SHRINKDATABASE%'
										OR step.command LIKE N'%SHRINKFILE%'
					END
	                    
				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 80 ) 
					BEGIN
						EXEC dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 80, DB_NAME(), 50, ''Reliability'', ''Max File Size Set'', ''http://BrentOzar.com/go/maxsize'', (''The ['' + DB_NAME() + ''] database file '' + name + '' has a max file size set to '' + CAST(CAST(max_size AS BIGINT) * 8 / 1024 AS VARCHAR(100)) + ''MB. If it runs out of space, the database will stop working even though there may be drive space available.'') FROM sys.database_files WHERE max_size <> 268435456 AND max_size <> -1 AND type <> 2';
					END

				IF NOT EXISTS ( SELECT  1
								FROM    #SkipChecks
								WHERE   DatabaseName IS NULL AND CheckID = 81 ) 
					BEGIN
						INSERT  INTO #BlitzResults
								( CheckID ,
								  Priority ,
								  FindingsGroup ,
								  Finding ,
								  URL ,
								  Details
								)
								SELECT  81 AS CheckID ,
										200 AS Priority ,
										'Non-Active Server Config' AS FindingsGroup ,
										cr.name AS Finding ,
										'http://www.BrentOzar.com/blitz/sp_configure/' AS URL ,
										( 'This sp_configure option isn''t running under its set value.  Its set value is '
										  + CAST(cr.[Value] AS VARCHAR(100))
										  + ' and its running value is '
										  + CAST(cr.value_in_use AS VARCHAR(100))
										  + '. When someone does a RECONFIGURE or restarts the instance, this setting will start taking effect.' ) AS Details
								FROM    sys.configurations cr
								WHERE   cr.value <> cr.value_in_use;
					END
	                    

				IF @CheckServerInfo = 1 
					BEGIN

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 83 ) 
							BEGIN
								IF EXISTS ( SELECT  *
											FROM    sys.all_objects
											WHERE   name = 'dm_server_services' ) 
									BEGIN
										SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
				SELECT  83 AS CheckID ,
				250 AS Priority ,
				''Server Info'' AS FindingsGroup ,
				''Services'' AS Finding ,
				'''' AS URL ,
				N''Service: '' + servicename + N'' runs under service account '' + service_account + N''. Last startup time: '' + COALESCE(CAST(CAST(last_startup_time AS DATETIME) AS VARCHAR(50)), ''not shown.'') + ''. Startup type: '' + startup_type_desc + N'', currently '' + status_desc + ''.'' 
				FROM sys.dm_server_services;'
										EXECUTE(@StringToExecute);
									END
							END

			/* Check 84 - SQL Server 2012 */              
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 84 ) 
							BEGIN
								IF EXISTS ( SELECT  *
											FROM    sys.all_objects o
													INNER JOIN sys.all_columns c ON o.object_id = c.object_id
											WHERE   o.name = 'dm_os_sys_info'
													AND c.name = 'physical_memory_kb' ) 
									BEGIN
										SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  84 AS CheckID ,
			250 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Hardware'' AS Finding ,
			'''' AS URL ,
			''Logical processors: '' + CAST(cpu_count AS VARCHAR(50)) + ''. Physical memory: '' + CAST( CAST(ROUND((physical_memory_kb / 1024.0 / 1024), 1) AS INT) AS VARCHAR(50)) + ''GB.''
			FROM sys.dm_os_sys_info';
										EXECUTE(@StringToExecute);
									END

			/* Check 84 - SQL Server 2008 */
								IF EXISTS ( SELECT  *
											FROM    sys.all_objects o
													INNER JOIN sys.all_columns c ON o.object_id = c.object_id
											WHERE   o.name = 'dm_os_sys_info'
													AND c.name = 'physical_memory_in_bytes' ) 
									BEGIN
										SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  84 AS CheckID ,
			250 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Hardware'' AS Finding ,
			'''' AS URL ,
			''Logical processors: '' + CAST(cpu_count AS VARCHAR(50)) + ''. Physical memory: '' + CAST( CAST(ROUND((physical_memory_in_bytes / 1024.0 / 1024 / 1024), 1) AS INT) AS VARCHAR(50)) + ''GB.''
			FROM sys.dm_os_sys_info';
										EXECUTE(@StringToExecute);
									END
							END

		                
						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 85 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
										SELECT  85 AS CheckID ,
												250 AS Priority ,
												'Server Info' AS FindingsGroup ,
												'SQL Server Service' AS Finding ,
												'' AS URL ,
												N'Version: '
												+ CAST(SERVERPROPERTY('productversion') AS NVARCHAR(100))
												+ N'. Patch Level: '
												+ CAST(SERVERPROPERTY('productlevel') AS NVARCHAR(100))
												+ N'. Edition: '
												+ CAST(SERVERPROPERTY('edition') AS VARCHAR(100))
												+ N'. AlwaysOn Enabled: '
												+ CAST(COALESCE(SERVERPROPERTY('IsHadrEnabled'),
																0) AS VARCHAR(100))
												+ N'. AlwaysOn Mgr Status: '
												+ CAST(COALESCE(SERVERPROPERTY('HadrManagerStatus'),
																0) AS VARCHAR(100))
							END


						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 88 ) 
							BEGIN
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
										SELECT  88 AS CheckID ,
												250 AS Priority ,
												'Server Info' AS FindingsGroup ,
												'SQL Server Last Restart' AS Finding ,
												'' AS URL ,
												CAST(create_date AS VARCHAR(100))
										FROM    sys.databases
										WHERE   database_id = 2
							END

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 92 ) 
							BEGIN
								INSERT  INTO #driveInfo
										( drive, SIZE )
										EXEC master..xp_fixeddrives

								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
										SELECT  92 AS CheckID ,
												250 AS Priority ,
												'Server Info' AS FindingsGroup ,
												'Drive ' + i.drive + ' Space' AS Finding ,
												'' AS URL ,
												CAST(i.SIZE AS VARCHAR)
												+ 'MB free on ' + i.drive
												+ ' drive' AS Details
										FROM    #driveInfo AS i
								DROP TABLE #driveInfo
							END


						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 103 )
							AND EXISTS ( SELECT *
										 FROM   sys.all_objects o
												INNER JOIN sys.all_columns c ON o.object_id = c.object_id
										 WHERE  o.name = 'dm_os_sys_info'
												AND c.name = 'virtual_machine_type_desc' ) 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
									SELECT 103 AS CheckID,
									250 AS Priority,
									''Server Info'' AS FindingsGroup,
									''Virtual Server'' AS Finding,
									''http://BrentOzar.com/go/virtual'' AS URL,
									''Type: ('' + virtual_machine_type_desc + '')'' AS Details
									FROM sys.dm_os_sys_info
									WHERE virtual_machine_type <> 0';
								EXECUTE(@StringToExecute);
							END

						IF NOT EXISTS ( SELECT  1
										FROM    #SkipChecks
										WHERE   DatabaseName IS NULL AND CheckID = 114 )
							AND EXISTS ( SELECT *
										 FROM   sys.all_objects o
										 WHERE  o.name = 'dm_os_memory_nodes' )
							AND EXISTS ( SELECT *
										 FROM   sys.all_objects o
										 INNER JOIN sys.all_columns c ON o.object_id = c.object_id
										 WHERE  o.name = 'dm_os_nodes' 
                                	 		AND c.name = 'processor_group' ) 
							BEGIN
								SET @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
										SELECT  114 AS CheckID ,
												250 AS Priority ,
												''Server Info'' AS FindingsGroup ,
												''Hardware - NUMA Config'' AS Finding ,
												'''' AS URL ,
												''Node: '' + CAST(n.node_id AS NVARCHAR(10)) + '' State: '' + node_state_desc 
												+ '' Online schedulers: '' + CAST(n.online_scheduler_count AS NVARCHAR(10)) + '' Processor Group: '' + CAST(n.processor_group AS NVARCHAR(10)) 
												+ '' Memory node: '' + CAST(n.memory_node_id AS NVARCHAR(10)) + '' Memory VAS Reserved GB: '' + CAST(CAST((m.virtual_address_space_reserved_kb / 1024.0 / 1024) AS INT) AS NVARCHAR(100))
										FROM sys.dm_os_nodes n
										INNER JOIN sys.dm_os_memory_nodes m ON n.memory_node_id = m.memory_node_id
										WHERE n.node_state_desc NOT LIKE ''%DAC%''
										ORDER BY n.node_id'
								EXECUTE(@StringToExecute);
							END


							IF NOT EXISTS ( SELECT  1
											FROM    #SkipChecks
											WHERE   DatabaseName IS NULL AND CheckID = 106 )
											AND (select convert(int,value_in_use) from sys.configurations where name = 'default trace enabled' ) = 1
							BEGIN
		
								INSERT  INTO #BlitzResults
										( CheckID ,
										  Priority ,
										  FindingsGroup ,
										  Finding ,
										  URL ,
										  Details
										)
										SELECT  
												 106 AS CheckID 
												,250 AS Priority 
												,'Server Info' AS FindingsGroup 
												,'Default Trace Contents' AS Finding 
												,'http://BrentOzar.com/go/trace' AS URL 
												,'The default trace holds '+cast(DATEDIFF(hour,MIN(StartTime),GETDATE())as varchar)+' hours of data'
												+' between '+cast(Min(StartTime) as varchar)+' and '+cast(GETDATE()as varchar)
												+('. The default trace files are located in: '+left( @curr_tracefilename,len(@curr_tracefilename) - @indx)
												) as Details
										FROM    ::fn_trace_gettable( @base_tracefilename, default )
										WHERE EventClass BETWEEN 65500 and 65600
							END /* CheckID 106 */



					END /* IF @CheckServerInfo = 1 */
			END /* IF ( ( SERVERPROPERTY('ServerName') NOT IN ( SELECT ServerName */


				/* Delete priorites they wanted to skip. */
				IF @IgnorePrioritiesAbove IS NOT NULL 
					DELETE  #BlitzResults
					WHERE   [Priority] > @IgnorePrioritiesAbove AND CheckID <> -1;
		
				IF @IgnorePrioritiesBelow IS NOT NULL 
					DELETE  #BlitzResults
					WHERE   [Priority] < @IgnorePrioritiesBelow AND CheckID <> -1;

				/* Delete checks they wanted to skip. */
				IF @SkipChecksTable IS NOT NULL 
					BEGIN 
						DELETE  FROM #BlitzResults
						WHERE   DatabaseName IN ( SELECT    DatabaseName
												  FROM      #SkipChecks 
												  WHERE CheckID IS NULL
												  AND (ServerName IS NULL OR ServerName = SERVERPROPERTY('ServerName')));
						DELETE  FROM #BlitzResults
						WHERE   CheckID IN ( SELECT    CheckID
												  FROM      #SkipChecks 
												  WHERE DatabaseName IS NULL
												  AND (ServerName IS NULL OR ServerName = SERVERPROPERTY('ServerName')));
						DELETE r FROM #BlitzResults r
							INNER JOIN #SkipChecks c ON r.DatabaseName = c.DatabaseName and r.CheckID = c.CheckID
												  AND (ServerName IS NULL OR ServerName = SERVERPROPERTY('ServerName'));
					END



				/* Add credits for the nice folks who put so much time into building and maintaining this for free: */                    
				INSERT  INTO #BlitzResults
						( CheckID ,
						  Priority ,
						  FindingsGroup ,
						  Finding ,
						  URL ,
						  Details
						)
				VALUES  ( -1 ,
						  255 ,
						  'Thanks!' ,
						  'From Brent Ozar Unlimited' ,
						  'http://www.BrentOzar.com/blitz/' ,
						  'Thanks from the Brent Ozar Unlimited team.  We hope you found this tool useful, and if you need help relieving your SQL Server pains, email us at Help@BrentOzar.com.'
						);

				INSERT  INTO #BlitzResults
						( CheckID ,
						  Priority ,
						  FindingsGroup ,
						  Finding ,
						  URL ,
						  Details

						)
				VALUES  ( -1 ,
						  0 ,
						  'sp_Blitz (TM) v' + CAST(@Version AS VARCHAR(20)) + ' as of ' + CAST(CONVERT(DATETIME, @VersionDate, 102) AS VARCHAR(100)),
						  'From Brent Ozar Unlimited' ,
						  'http://www.BrentOzar.com/blitz/' ,
						  'Thanks from the Brent Ozar Unlimited team.  We hope you found this tool useful, and if you need help relieving your SQL Server pains, email us at Help@BrentOzar.com.'

						);


				/* @OutputTableName lets us export the results to a permanent table */
				IF @OutputDatabaseName IS NOT NULL
					AND @OutputSchemaName IS NOT NULL
					AND @OutputTableName IS NOT NULL
					AND EXISTS ( SELECT *
								 FROM   sys.databases
								 WHERE  QUOTENAME([name]) = @OutputDatabaseName) 
					BEGIN
						SET @StringToExecute = 'USE '
							+ @OutputDatabaseName
							+ '; IF EXISTS(SELECT * FROM '
							+ @OutputDatabaseName
							+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
							+ @OutputSchemaName
							+ ''') AND NOT EXISTS (SELECT * FROM '
							+ @OutputDatabaseName
							+ '.INFORMATION_SCHEMA.TABLES WHERE QUOTENAME(TABLE_SCHEMA) = '''
							+ @OutputSchemaName + ''' AND QUOTENAME(TABLE_NAME) = '''
							+ @OutputTableName + ''') CREATE TABLE '
							+ @OutputSchemaName + '.'
							+ @OutputTableName
							+ ' (ID INT IDENTITY(1,1) NOT NULL, 
								ServerName NVARCHAR(128), 
								CheckDate DATETIME, 
								BlitzVersion INT,
								Priority TINYINT ,
								FindingsGroup VARCHAR(50) ,
								Finding VARCHAR(200) ,
								DatabaseName NVARCHAR(128),
								URL VARCHAR(200) ,
								Details NVARCHAR(4000) ,
								QueryPlan [XML] NULL ,
								QueryPlanFiltered [NVARCHAR](MAX) NULL,
								CheckID INT ,
								CONSTRAINT [PK_' + CAST(NEWID() AS CHAR(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));'
						EXEC(@StringToExecute);
						SET @StringToExecute = N' IF EXISTS(SELECT * FROM '
							+ @OutputDatabaseName
							+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
							+ @OutputSchemaName + ''') INSERT '
							+ @OutputDatabaseName + '.'
							+ @OutputSchemaName + '.'
							+ @OutputTableName
							+ ' (ServerName, CheckDate, BlitzVersion, CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered) SELECT '''
							+ CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128))
							+ ''', GETDATE(), ' + CAST(@Version AS NVARCHAR(128))
							+ ', CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered FROM #BlitzResults ORDER BY Priority , FindingsGroup , Finding , Details';
						EXEC(@StringToExecute);
					END
				ELSE IF (SUBSTRING(@OutputTableName, 2, 2) = '##')
					BEGIN
						SET @StringToExecute = N' IF (OBJECT_ID(''tempdb..'
							+ @OutputTableName
							+ ''') IS NOT NULL) DROP TABLE ' + @OutputTableName + ';'
							+ 'CREATE TABLE '
							+ @OutputTableName
							+ ' (ID INT IDENTITY(1,1) NOT NULL, 
								ServerName NVARCHAR(128), 
								CheckDate DATETIME, 
								BlitzVersion INT,
								Priority TINYINT ,
								FindingsGroup VARCHAR(50) ,
								Finding VARCHAR(200) ,
								DatabaseName NVARCHAR(128),
								URL VARCHAR(200) ,
								Details NVARCHAR(4000) ,
								QueryPlan [XML] NULL ,
								QueryPlanFiltered [NVARCHAR](MAX) NULL,
								CheckID INT ,
								CONSTRAINT [PK_' + CAST(NEWID() AS CHAR(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));'
							+ ' INSERT '
							+ @OutputTableName
							+ ' (ServerName, CheckDate, BlitzVersion, CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered) SELECT '''
							+ CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128))
							+ ''', GETDATE(), ' + CAST(@Version AS NVARCHAR(128))
							+ ', CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered FROM #BlitzResults ORDER BY Priority , FindingsGroup , Finding , Details';
						EXEC(@StringToExecute);
					END
				ELSE IF (SUBSTRING(@OutputTableName, 2, 1) = '#')
					BEGIN
						RAISERROR('Due to the nature of Dymamic SQL, only global (i.e. double pound (##)) temp tables are supported for @OutputTableName', 16, 0)
					END


				DECLARE @separator AS VARCHAR(1);
				IF @OutputType = 'RSV' 
					SET @separator = CHAR(31);
				ELSE 
					SET @separator = ',';

				IF @OutputType = 'COUNT' 
					BEGIN
						SELECT  COUNT(*) AS Warnings
						FROM    #BlitzResults
					END
				ELSE 
					IF @OutputType IN ( 'CSV', 'RSV' ) 
						BEGIN
				
							SELECT  Result = CAST([Priority] AS NVARCHAR(100))
									+ @separator + CAST(CheckID AS NVARCHAR(100))
									+ @separator + COALESCE([FindingsGroup],
															'(N/A)') + @separator
									+ COALESCE([Finding], '(N/A)') + @separator
									+ COALESCE(DatabaseName, '(N/A)') + @separator
									+ COALESCE([URL], '(N/A)') + @separator
									+ COALESCE([Details], '(N/A)')
							FROM    #BlitzResults
							ORDER BY Priority ,
									FindingsGroup ,
									Finding ,
									Details;
						END
					ELSE IF @OutputXMLasNVARCHAR = 1
						BEGIN
							SELECT  [Priority] ,
									[FindingsGroup] ,
									[Finding] ,
									[DatabaseName] ,
									[URL] ,
									[Details] ,
									CAST([QueryPlan] AS NVARCHAR(MAX)) AS QueryPlan,
									[QueryPlanFiltered] ,
									CheckID
							FROM    #BlitzResults
							ORDER BY Priority ,
									FindingsGroup ,
									Finding ,
									Details;
						END
					ELSE 
						BEGIN
							SELECT  [Priority] ,
									[FindingsGroup] ,
									[Finding] ,
									[DatabaseName] ,
									[URL] ,
									[Details] ,
									[QueryPlan] ,
									[QueryPlanFiltered] ,
									CheckID
							FROM    #BlitzResults
							ORDER BY Priority ,
									FindingsGroup ,
									Finding ,
									Details;
						END

				DROP TABLE #BlitzResults;

				IF @OutputProcedureCache = 1
					AND @CheckProcedureCache = 1 
					SELECT TOP 20
							total_worker_time / execution_count AS AvgCPU ,
							total_worker_time AS TotalCPU ,
							CAST(ROUND(100.00 * total_worker_time
									   / ( SELECT   SUM(total_worker_time)
										   FROM     sys.dm_exec_query_stats
										 ), 2) AS MONEY) AS PercentCPU ,
							total_elapsed_time / execution_count AS AvgDuration ,
							total_elapsed_time AS TotalDuration ,
							CAST(ROUND(100.00 * total_elapsed_time
									   / ( SELECT   SUM(total_elapsed_time)
										   FROM     sys.dm_exec_query_stats
										 ), 2) AS MONEY) AS PercentDuration ,
							total_logical_reads / execution_count AS AvgReads ,
							total_logical_reads AS TotalReads ,
							CAST(ROUND(100.00 * total_logical_reads
									   / ( SELECT   SUM(total_logical_reads)
										   FROM     sys.dm_exec_query_stats
										 ), 2) AS MONEY) AS PercentReads ,
							execution_count ,
							CAST(ROUND(100.00 * execution_count
									   / ( SELECT   SUM(execution_count)
										   FROM     sys.dm_exec_query_stats
										 ), 2) AS MONEY) AS PercentExecutions ,
							CASE WHEN DATEDIFF(mi, creation_time,
											   qs.last_execution_time) = 0 THEN 0
								 ELSE CAST(( 1.00 * execution_count / DATEDIFF(mi,
																  creation_time,
																  qs.last_execution_time) ) AS MONEY)
							END AS executions_per_minute ,
							qs.creation_time AS plan_creation_time ,
							qs.last_execution_time ,
							text ,
							text_filtered ,
							query_plan ,
							query_plan_filtered ,
							sql_handle ,
							query_hash ,
							plan_handle ,
							query_plan_hash
					FROM    #dm_exec_query_stats qs
					ORDER BY CASE UPPER(@CheckProcedureCacheFilter)
							   WHEN 'CPU' THEN total_worker_time
							   WHEN 'READS' THEN total_logical_reads
							   WHEN 'EXECCOUNT' THEN execution_count
							   WHEN 'DURATION' THEN total_elapsed_time
							   ELSE total_worker_time
							 END DESC

	END /* ELSE -- IF @OutputType = 'SCHEMA' */
    SET NOCOUNT OFF;


GO
/****** Object:  StoredProcedure [dbo].[sp_GetOrphUsrs]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetOrphUsrs]
	(
	@DatabaseName VARCHAR(200) = NULL
	)
AS

/**********************
Name: sp_GetOrphUsrs

Author: Dustin Marzolf
Created: 4/3/2016

Purpose: To get orphaned users and report on them.

Inputs:
	@DatabaseName VARCHAR(200) = NULL - The name of the database to check for orphaned users.	
		NULL value will look at all databases.
		
Outputs:
	A table showing the list of orphaned users.

************************/

DECLARE @DBName SYSNAME;
DECLARE @Query NVARCHAR(4000);

DECLARE @OrphanedUsers TABLE
	(
	DatabaseName SYSNAME NULL
	, UserName SYSNAME NULL
	, UserSID SYSNAME NULL
	, Fix VARCHAR(MAX) NULL
	);

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT D.name
	FROM sys.databases D
	WHERE D.[state] = 0
		AND (D.name = @DatabaseName
			OR @DatabaseName IS NULL
			);
			
OPEN curDB

FETCH NEXT FROM curDB
INTO @DBName

WHILE @@FETCH_STATUS = 0
BEGIN

	--Create the temporary table.
	IF OBJECT_ID('tempdb..#TempOrphanedUsers') IS NOT NULL
	BEGIN
		DROP TABLE #TempOrphanedUsers;
	END	
	
	CREATE TABLE #TempOrphanedUsers
		(
		UserName SYSNAME NULL
		, UserSID SYSNAME NULL
		);
		
	SET @Query = 'USE ' + QUOTENAME(@DBName) + ';'
		+ ' INSERT INTO #TempOrphanedUsers EXEC sp_change_users_login @Action=' + '''' + 'Report' + '''' + ';'
		
	--Execute the command.
	EXEC sp_executesql @Query;
	
	--Save the data.
	INSERT INTO @OrphanedUsers 
	(DatabaseName, UserName, UserSID)
	SELECT @DBName, U.UserName, U.UserSID
	FROM #TempOrphanedUsers U;

	--Get the next database name.
	FETCH NEXT FROM curDB
	INTO @DBName;

END --END WHILE @@FETCH_STATUS = 0 (looping through databases)

--Cleanup curDB
CLOSE curDB;
DEALLOCATE curDB;

--Cleanup temp table.
IF OBJECT_ID('tempdb..#TempOrphanedUsers') IS NOT NULL
BEGIN
	DROP TABLE #TempOrphanedUsers;
END	

--Create the Fix Command.
UPDATE @OrphanedUsers
SET Fix = 'USE ' + QUOTENAME(DatabaseName) + '; EXEC sp_change_users_login @Action=' + '''' + 'update_one' + ''''
													+ ', @UserNamePattern=' + '''' + UserName + ''''
													+ ', @LoginName=' + '''' + UserName + ''''
FROM @OrphanedUsers
WHERE UserName IN (SELECT name FROM sys.server_principals)

--Return the data.
SELECT DatabaseName, UserName, UserSID, Fix
FROM @OrphanedUsers
ORDER BY UserName, DatabaseName


GO
/****** Object:  StoredProcedure [dbo].[sp_GetSqlErrLog]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






CREATE PROCEDURE [dbo].[sp_GetSqlErrLog]
AS

/**************************************
Name:		sp_GetSqlErrLog
Author:		Dustin Marzolf
Created:	02/08/2017

Purpose: To get all the data in the SQL Error Logs, place the data in a table for long term analysis, etc.

Inputs:		None
Outputs:	None

UPDATE:
	12/6/2016 - Dustin Marzolf
		Added better logic to reduce temp DB load.

UPDATE:
	5/28/14 - Dustin Marzolf
		Improved handling where we had never run this before.

******************************************/

SET NOCOUNT ON

--0. Necessary Variables.
DECLARE @StartDate DATETIME
DECLARE @ArchiveNumber INT
DECLARE @RowCount BIGINT
DECLARE @LogStart DATETIME
DECLARE @LogEnd DATETIME
DECLARE @TempStart DATETIME
DECLARE @TempEnd DATETIME

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
	, DateEnd DATETIME NULL
	, DateStart DATETIME NULL
	, LogFileSize BIGINT NULL
	)

INSERT INTO #LogFiles (ArchiveNumber, DateEnd, LogFileSize)
EXEC master.sys.xp_enumerrorlogs;

--Determine the end date for each of the log files....
UPDATE #LogFiles
SET DateStart = ISNULL(D.DateEnd, DATEADD(WEEK, -1, D.DateEnd))
FROM #LogFiles C
	LEFT OUTER JOIN (SELECT L.ArchiveNumber
						, L.DateEnd
					FROM #LogFiles L
					) D ON D.ArchiveNumber = C.ArchiveNumber + 1

IF(YEAR(@StartDate) < 2000)
BEGIN
	SET @StartDate = (SELECT MIN(DateStart) FROM #LogFiles WHERE DateStart IS NOT NULL AND DateStart >= DATEADD(DAY, -90, GETDATE()))
END

--3. Iterate over each Log file that is newer than the Start Date
--		If Start Date is NULL then loop through all available.
DECLARE curLogFiles CURSOR LOCAL STATIC FORWARD_ONLY

FOR  SELECT ArchiveNumber
		, DateStart
		, DateEnd
	FROM #LogFiles F
	WHERE ArchiveNumber = 0
		OR @StartDate BETWEEN DateStart AND DateEnd
		OR DateEnd >= @StartDate
	ORDER BY ArchiveNumber DESC

OPEN curLogFiles;

FETCH NEXT FROM curLogFiles
INTO @ArchiveNumber, @LogStart, @LogEnd;

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @TempStart = NULL
	SET @TempEnd = NULL

	--PRINT 'Archive Log No: ' + CAST(@ArchiveNumber AS VARCHAR(10))

	WHILE ISNULL(@TempEnd, @LogStart) < @LogEnd
	BEGIN

		SET @TempStart = ISNULL(@TempEnd, @StartDate)
		SET @TempEnd = DATEADD(MINUTE, 15, @TempStart)

		IF @TempEnd > @LogEnd
		BEGIN
			SET @TempEnd = @LogEnd
		END

		--PRINT 'Start: ' + CONVERT(VARCHAR(40), @TempStart, 100)
		--PRINT 'End: ' + CONVERT(VARCHAR(40), @TempEnd, 100)

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
		--For the five minute interval....
		INSERT INTO #LogData (LogDate, ProcessInfo, [Text])
		EXEC master.dbo.xp_readerrorlog @ArchiveNumber, 1, NULL, NULL, @TempStart, @TempEnd, N'asc'

		--Update the data...
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

		--Put the data into the Log table, but only new records....
		MERGE INTO DBA.dbo.Data_SQLLog AS T
		USING (	SELECT LogDate, ProcessInfo, [Text], UserName, HostAddress, [Status]
				FROM #LogData) AS S
			ON T.LogDate = S.LogDate AND T.ProcessInfo = S.ProcessInfo AND T.[Text] = S.[Text] AND T.LogDate >= @TempStart
		WHEN NOT MATCHED BY TARGET THEN 
			INSERT (LogDate, ProcessInfo, [Text], UserName, HostAddress, [Status])
			VALUES (S.LogDate, S.ProcessInfo, S.[Text], S.UserName, S.HostAddress, S.[Status]);

	END --END WHILE @TempEnd < @LogEnd

	--Get next Archive Number
	FETCH NEXT FROM curLogFiles
	INTO @ArchiveNumber, @LogStart, @LogEnd

	--Give the system a chance to breathe....
	WAITFOR DELAY '12:00:00 AM';

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
/****** Object:  StoredProcedure [dbo].[sp_GetSqlTrcInfo]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[sp_GetSqlTrcInfo]
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
	WAITFOR DELAY '12:00:00 AM'

END --Looping through curTraceFile

--Cleanup.
CLOSE curTraceFile
DEALLOCATE curTraceFile

IF OBJECT_ID('tempdb..#TraceData') IS NOT NULL
BEGIN
	DROP TABLE #TraceData
END

--Additional Actions.
DECLARE @DatabaseName VARCHAR(100)

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT DISTINCT DatabaseName
	FROM Data_SQLTrace 
	WHERE DateStart >= @DateStart 
		AND EventCategory_Desc IN ('Data File Auto Grow', 'Log File Auto Grow')

OPEN curDB

FETCH NEXT FROM curDB 
INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC sp_GetMntDBFile @DatabaseName

END

CLOSE curDB
DEALLOCATE curDB




GO
/****** Object:  StoredProcedure [dbo].[sp_GetSqlUsrFreqncy]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetSqlUsrFreqncy]
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
/****** Object:  StoredProcedure [dbo].[sp_WhoIsActive]    Script Date: 8/7/2016 8:17:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*********************************************************************************************
Who Is Active? v11.11 (2012-03-22)
(C) 2007-2012, Adam Machanic

Feedback: mailto:amachanic@gmail.com
Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx
"Beta" Builds: http://sqlblog.com/files/folders/beta/tags/who+is+active/default.aspx

Donate! Support this project: http://tinyurl.com/WhoIsActiveDonate

License: 
	Who is Active? is free to download and use for personal, educational, and internal 
	corporate purposes, provided that this header is preserved. Redistribution or sale 
	of Who is Active?, in whole or in part, is prohibited without the author's express 
	written consent.
*********************************************************************************************/
CREATE PROC [dbo].[sp_WhoIsActive]
(
--~
	--Filters--Both inclusive and exclusive
	--Set either filter to '' to disable
	--Valid filter types are: session, program, database, login, and host
	--Session is a session ID, and either 0 or '' can be used to indicate "all" sessions
	--All other filter types support % or _ as wildcards
	@filter sysname = '',
	@filter_type VARCHAR(10) = 'session',
	@not_filter sysname = '',
	@not_filter_type VARCHAR(10) = 'session',

	--Retrieve data about the calling session?
	@show_own_spid BIT = 0,

	--Retrieve data about system sessions?
	@show_system_spids BIT = 0,

	--Controls how sleeping SPIDs are handled, based on the idea of levels of interest
	--0 does not pull any sleeping SPIDs
	--1 pulls only those sleeping SPIDs that also have an open transaction
	--2 pulls all sleeping SPIDs
	@show_sleeping_spids TINYINT = 1,

	--If 1, gets the full stored procedure or running batch, when available
	--If 0, gets only the actual statement that is currently running in the batch or procedure
	@get_full_inner_text BIT = 0,

	--Get associated query plans for running tasks, if available
	--If @get_plans = 1, gets the plan based on the request's statement offset
	--If @get_plans = 2, gets the entire plan based on the request's plan_handle
	@get_plans TINYINT = 0,

	--Get the associated outer ad hoc query or stored procedure call, if available
	@get_outer_command BIT = 0,

	--Enables pulling transaction log write info and transaction duration
	@get_transaction_info BIT = 0,

	--Get information on active tasks, based on three interest levels
	--Level 0 does not pull any task-related information
	--Level 1 is a lightweight mode that pulls the top non-CXPACKET wait, giving preference to blockers
	--Level 2 pulls all available task-based metrics, including: 
	--number of active tasks, current wait stats, physical I/O, context switches, and blocker information
	@get_task_info TINYINT = 1,

	--Gets associated locks for each request, aggregated in an XML format
	@get_locks BIT = 0,

	--Get average time for past runs of an active query
	--(based on the combination of plan handle, sql handle, and offset)
	@get_avg_time BIT = 0,

	--Get additional non-performance-related information about the session or request
	--text_size, language, date_format, date_first, quoted_identifier, arithabort, ansi_null_dflt_on, 
	--ansi_defaults, ansi_warnings, ansi_padding, ansi_nulls, concat_null_yields_null, 
	--transaction_isolation_level, lock_timeout, deadlock_priority, row_count, command_type
	--
	--If a SQL Agent job is running, an subnode called agent_info will be populated with some or all of
	--the following: job_id, job_name, step_id, step_name, msdb_query_error (in the event of an error)
	--
	--If @get_task_info is set to 2 and a lock wait is detected, a subnode called block_info will be
	--populated with some or all of the following: lock_type, database_name, object_id, file_id, hobt_id, 
	--applock_hash, metadata_resource, metadata_class_id, object_name, schema_name
	@get_additional_info BIT = 0,

	--Walk the blocking chain and count the number of 
	--total SPIDs blocked all the way down by a given session
	--Also enables task_info Level 1, if @get_task_info is set to 0
	@find_block_leaders BIT = 0,

	--Pull deltas on various metrics
	--Interval in seconds to wait before doing the second data pull
	@delta_interval TINYINT = 0,

	--List of desired output columns, in desired order
	--Note that the final output will be the intersection of all enabled features and all 
	--columns in the list. Therefore, only columns associated with enabled features will 
	--actually appear in the output. Likewise, removing columns from this list may effectively
	--disable features, even if they are turned on
	--
	--Each element in this list must be one of the valid output column names. Names must be
	--delimited by square brackets. White space, formatting, and additional characters are
	--allowed, as long as the list contains exact matches of delimited valid column names.
	@output_column_list VARCHAR(8000) = '[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]',

	--Column(s) by which to sort output, optionally with sort directions. 
		--Valid column choices:
		--session_id, physical_io, reads, physical_reads, writes, tempdb_allocations,
		--tempdb_current, CPU, context_switches, used_memory, physical_io_delta, 
		--reads_delta, physical_reads_delta, writes_delta, tempdb_allocations_delta, 
		--tempdb_current_delta, CPU_delta, context_switches_delta, used_memory_delta, 
		--tasks, tran_start_time, open_tran_count, blocking_session_id, blocked_session_count,
		--percent_complete, host_name, login_name, database_name, start_time, login_time
		--
		--Note that column names in the list must be bracket-delimited. Commas and/or white
		--space are not required. 
	@sort_order VARCHAR(500) = '[start_time] ASC',

	--Formats some of the output columns in a more "human readable" form
	--0 disables outfput format
	--1 formats the output for variable-width fonts
	--2 formats the output for fixed-width fonts
	@format_output TINYINT = 1,

	--If set to a non-blank value, the script will attempt to insert into the specified 
	--destination table. Please note that the script will not verify that the table exists, 
	--or that it has the correct schema, before doing the insert.
	--Table can be specified in one, two, or three-part format
	@destination_table VARCHAR(4000) = '',

	--If set to 1, no data collection will happen and no result set will be returned; instead,
	--a CREATE TABLE statement will be returned via the @schema parameter, which will match 
	--the schema of the result set that would be returned by using the same collection of the
	--rest of the parameters. The CREATE TABLE statement will have a placeholder token of 
	--<table_name> in place of an actual table name.
	@return_schema BIT = 0,
	@schema VARCHAR(MAX) = NULL OUTPUT,

	--Help! What do I do?
	@help BIT = 0
--~
)
/*
OUTPUT COLUMNS
--------------
Formatted/Non:	[session_id] [smallint] NOT NULL
	Session ID (a.k.a. SPID)

Formatted:		[dd hh:mm:ss.mss] [varchar](15) NULL
Non-Formatted:	<not returned>
	For an active request, time the query has been running
	For a sleeping session, time since the last batch completed

Formatted:		[dd hh:mm:ss.mss (avg)] [varchar](15) NULL
Non-Formatted:	[avg_elapsed_time] [int] NULL
	(Requires @get_avg_time option)
	How much time has the active portion of the query taken in the past, on average?

Formatted:		[physical_io] [varchar](30) NULL
Non-Formatted:	[physical_io] [bigint] NULL
	Shows the number of physical I/Os, for active requests

Formatted:		[reads] [varchar](30) NULL
Non-Formatted:	[reads] [bigint] NULL
	For an active request, number of reads done for the current query
	For a sleeping session, total number of reads done over the lifetime of the session

Formatted:		[physical_reads] [varchar](30) NULL
Non-Formatted:	[physical_reads] [bigint] NULL
	For an active request, number of physical reads done for the current query
	For a sleeping session, total number of physical reads done over the lifetime of the session

Formatted:		[writes] [varchar](30) NULL
Non-Formatted:	[writes] [bigint] NULL
	For an active request, number of writes done for the current query
	For a sleeping session, total number of writes done over the lifetime of the session

Formatted:		[tempdb_allocations] [varchar](30) NULL
Non-Formatted:	[tempdb_allocations] [bigint] NULL
	For an active request, number of TempDB writes done for the current query
	For a sleeping session, total number of TempDB writes done over the lifetime of the session

Formatted:		[tempdb_current] [varchar](30) NULL
Non-Formatted:	[tempdb_current] [bigint] NULL
	For an active request, number of TempDB pages currently allocated for the query
	For a sleeping session, number of TempDB pages currently allocated for the session

Formatted:		[CPU] [varchar](30) NULL
Non-Formatted:	[CPU] [int] NULL
	For an active request, total CPU time consumed by the current query
	For a sleeping session, total CPU time consumed over the lifetime of the session

Formatted:		[context_switches] [varchar](30) NULL
Non-Formatted:	[context_switches] [bigint] NULL
	Shows the number of context switches, for active requests

Formatted:		[used_memory] [varchar](30) NOT NULL
Non-Formatted:	[used_memory] [bigint] NOT NULL
	For an active request, total memory consumption for the current query
	For a sleeping session, total current memory consumption

Formatted:		[physical_io_delta] [varchar](30) NULL
Non-Formatted:	[physical_io_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of physical I/Os reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[reads_delta] [varchar](30) NULL
Non-Formatted:	[reads_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of reads reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[physical_reads_delta] [varchar](30) NULL
Non-Formatted:	[physical_reads_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of physical reads reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[writes_delta] [varchar](30) NULL
Non-Formatted:	[writes_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of writes reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[tempdb_allocations_delta] [varchar](30) NULL
Non-Formatted:	[tempdb_allocations_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of TempDB writes reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[tempdb_current_delta] [varchar](30) NULL
Non-Formatted:	[tempdb_current_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the number of allocated TempDB pages reported on the first and second 
	collections. If the request started after the first collection, the value will be NULL

Formatted:		[CPU_delta] [varchar](30) NULL
Non-Formatted:	[CPU_delta] [int] NULL
	(Requires @delta_interval option)
	Difference between the CPU time reported on the first and second collections. 
	If the request started after the first collection, the value will be NULL

Formatted:		[context_switches_delta] [varchar](30) NULL
Non-Formatted:	[context_switches_delta] [bigint] NULL
	(Requires @delta_interval option)
	Difference between the context switches count reported on the first and second collections
	If the request started after the first collection, the value will be NULL

Formatted:		[used_memory_delta] [varchar](30) NULL
Non-Formatted:	[used_memory_delta] [bigint] NULL
	Difference between the memory usage reported on the first and second collections
	If the request started after the first collection, the value will be NULL

Formatted:		[tasks] [varchar](30) NULL
Non-Formatted:	[tasks] [smallint] NULL
	Number of worker tasks currently allocated, for active requests

Formatted/Non:	[status] [varchar](30) NOT NULL
	Activity status for the session (running, sleeping, etc)

Formatted/Non:	[wait_info] [nvarchar](4000) NULL
	Aggregates wait information, in the following format:
		(Ax: Bms/Cms/Dms)E
	A is the number of waiting tasks currently waiting on resource type E. B/C/D are wait
	times, in milliseconds. If only one thread is waiting, its wait time will be shown as B.
	If two tasks are waiting, each of their wait times will be shown (B/C). If three or more 
	tasks are waiting, the minimum, average, and maximum wait times will be shown (B/C/D).
	If wait type E is a page latch wait and the page is of a "special" type (e.g. PFS, GAM, SGAM), 
	the page type will be identified.
	If wait type E is CXPACKET, the nodeId from the query plan will be identified

Formatted/Non:	[locks] [xml] NULL
	(Requires @get_locks option)
	Aggregates lock information, in XML format.
	The lock XML includes the lock mode, locked object, and aggregates the number of requests. 
	Attempts are made to identify locked objects by name

Formatted/Non:	[tran_start_time] [datetime] NULL
	(Requires @get_transaction_info option)
	Date and time that the first transaction opened by a session caused a transaction log 
	write to occur.

Formatted/Non:	[tran_log_writes] [nvarchar](4000) NULL
	(Requires @get_transaction_info option)
	Aggregates transaction log write information, in the following format:
	A:wB (C kB)
	A is a database that has been touched by an active transaction
	B is the number of log writes that have been made in the database as a result of the transaction
	C is the number of log kilobytes consumed by the log records

Formatted:		[open_tran_count] [varchar](30) NULL
Non-Formatted:	[open_tran_count] [smallint] NULL
	Shows the number of open transactions the session has open

Formatted:		[sql_command] [xml] NULL
Non-Formatted:	[sql_command] [nvarchar](max) NULL
	(Requires @get_outer_command option)
	Shows the "outer" SQL command, i.e. the text of the batch or RPC sent to the server, 
	if available

Formatted:		[sql_text] [xml] NULL
Non-Formatted:	[sql_text] [nvarchar](max) NULL
	Shows the SQL text for active requests or the last statement executed
	for sleeping sessions, if available in either case.
	If @get_full_inner_text option is set, shows the full text of the batch.
	Otherwise, shows only the active statement within the batch.
	If the query text is locked, a special timeout message will be sent, in the following format:
		<timeout_exceeded />
	If an error occurs, an error message will be sent, in the following format:
		<error message="message" />

Formatted/Non:	[query_plan] [xml] NULL
	(Requires @get_plans option)
	Shows the query plan for the request, if available.
	If the plan is locked, a special timeout message will be sent, in the following format:
		<timeout_exceeded />
	If an error occurs, an error message will be sent, in the following format:
		<error message="message" />

Formatted/Non:	[blocking_session_id] [smallint] NULL
	When applicable, shows the blocking SPID

Formatted:		[blocked_session_count] [varchar](30) NULL
Non-Formatted:	[blocked_session_count] [smallint] NULL
	(Requires @find_block_leaders option)
	The total number of SPIDs blocked by this session,
	all the way down the blocking chain.

Formatted:		[percent_complete] [varchar](30) NULL
Non-Formatted:	[percent_complete] [real] NULL
	When applicable, shows the percent complete (e.g. for backups, restores, and some rollbacks)

Formatted/Non:	[host_name] [sysname] NOT NULL
	Shows the host name for the connection

Formatted/Non:	[login_name] [sysname] NOT NULL
	Shows the login name for the connection

Formatted/Non:	[database_name] [sysname] NULL
	Shows the connected database

Formatted/Non:	[program_name] [sysname] NULL
	Shows the reported program/application name

Formatted/Non:	[additional_info] [xml] NULL
	(Requires @get_additional_info option)
	Returns additional non-performance-related session/request information
	If the script finds a SQL Agent job running, the name of the job and job step will be reported
	If @get_task_info = 2 and the script finds a lock wait, the locked object will be reported

Formatted/Non:	[start_time] [datetime] NOT NULL
	For active requests, shows the time the request started
	For sleeping sessions, shows the time the last batch completed

Formatted/Non:	[login_time] [datetime] NOT NULL
	Shows the time that the session connected

Formatted/Non:	[request_id] [int] NULL
	For active requests, shows the request_id
	Should be 0 unless MARS is being used

Formatted/Non:	[collection_time] [datetime] NOT NULL
	Time that this script's final SELECT ran
*/
AS
BEGIN;
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET QUOTED_IDENTIFIER ON;
	SET ANSI_PADDING ON;
	SET CONCAT_NULL_YIELDS_NULL ON;
	SET ANSI_WARNINGS ON;
	SET NUMERIC_ROUNDABORT OFF;
	SET ARITHABORT ON;

	IF
		@filter IS NULL
		OR @filter_type IS NULL
		OR @not_filter IS NULL
		OR @not_filter_type IS NULL
		OR @show_own_spid IS NULL
		OR @show_system_spids IS NULL
		OR @show_sleeping_spids IS NULL
		OR @get_full_inner_text IS NULL
		OR @get_plans IS NULL
		OR @get_outer_command IS NULL
		OR @get_transaction_info IS NULL
		OR @get_task_info IS NULL
		OR @get_locks IS NULL
		OR @get_avg_time IS NULL
		OR @get_additional_info IS NULL
		OR @find_block_leaders IS NULL
		OR @delta_interval IS NULL
		OR @format_output IS NULL
		OR @output_column_list IS NULL
		OR @sort_order IS NULL
		OR @return_schema IS NULL
		OR @destination_table IS NULL
		OR @help IS NULL
	BEGIN;
		RAISERROR('Input parameters cannot be NULL', 16, 1);
		RETURN;
	END;
	
	IF @filter_type NOT IN ('session', 'program', 'database', 'login', 'host')
	BEGIN;
		RAISERROR('Valid filter types are: session, program, database, login, host', 16, 1);
		RETURN;
	END;
	
	IF @filter_type = 'session' AND @filter LIKE '%[^0123456789]%'
	BEGIN;
		RAISERROR('Session filters must be valid integers', 16, 1);
		RETURN;
	END;
	
	IF @not_filter_type NOT IN ('session', 'program', 'database', 'login', 'host')
	BEGIN;
		RAISERROR('Valid filter types are: session, program, database, login, host', 16, 1);
		RETURN;
	END;
	
	IF @not_filter_type = 'session' AND @not_filter LIKE '%[^0123456789]%'
	BEGIN;
		RAISERROR('Session filters must be valid integers', 16, 1);
		RETURN;
	END;
	
	IF @show_sleeping_spids NOT IN (0, 1, 2)
	BEGIN;
		RAISERROR('Valid values for @show_sleeping_spids are: 0, 1, or 2', 16, 1);
		RETURN;
	END;
	
	IF @get_plans NOT IN (0, 1, 2)
	BEGIN;
		RAISERROR('Valid values for @get_plans are: 0, 1, or 2', 16, 1);
		RETURN;
	END;

	IF @get_task_info NOT IN (0, 1, 2)
	BEGIN;
		RAISERROR('Valid values for @get_task_info are: 0, 1, or 2', 16, 1);
		RETURN;
	END;

	IF @format_output NOT IN (0, 1, 2)
	BEGIN;
		RAISERROR('Valid values for @format_output are: 0, 1, or 2', 16, 1);
		RETURN;
	END;
	
	IF @help = 1
	BEGIN;
		DECLARE 
			@header VARCHAR(MAX),
			@params VARCHAR(MAX),
			@outputs VARCHAR(MAX);

		SELECT 
			@header =
				REPLACE
				(
					REPLACE
					(
						CONVERT
						(
							VARCHAR(MAX),
							SUBSTRING
							(
								t.text, 
								CHARINDEX('/' + REPLICATE('*', 93), t.text) + 94,
								CHARINDEX(REPLICATE('*', 93) + '/', t.text) - (CHARINDEX('/' + REPLICATE('*', 93), t.text) + 94)
							)
						),
						CHAR(13)+CHAR(10),
						CHAR(13)
					),
					'	',
					''
				),
			@params =
				CHAR(13) +
					REPLACE
					(
						REPLACE
						(
							CONVERT
							(
								VARCHAR(MAX),
								SUBSTRING
								(
									t.text, 
									CHARINDEX('--~', t.text) + 5, 
									CHARINDEX('--~', t.text, CHARINDEX('--~', t.text) + 5) - (CHARINDEX('--~', t.text) + 5)
								)
							),
							CHAR(13)+CHAR(10),
							CHAR(13)
						),
						'	',
						''
					),
				@outputs = 
					CHAR(13) +
						REPLACE
						(
							REPLACE
							(
								REPLACE
								(
									CONVERT
									(
										VARCHAR(MAX),
										SUBSTRING
										(
											t.text, 
											CHARINDEX('OUTPUT COLUMNS'+CHAR(13)+CHAR(10)+'--------------', t.text) + 32,
											CHARINDEX('*/', t.text, CHARINDEX('OUTPUT COLUMNS'+CHAR(13)+CHAR(10)+'--------------', t.text) + 32) - (CHARINDEX('OUTPUT COLUMNS'+CHAR(13)+CHAR(10)+'--------------', t.text) + 32)
										)
									),
									CHAR(9),
									CHAR(255)
								),
								CHAR(13)+CHAR(10),
								CHAR(13)
							),
							'	',
							''
						) +
						CHAR(13)
		FROM sys.dm_exec_requests AS r
		CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
		WHERE
			r.session_id = @@SPID;

		WITH
		a0 AS
		(SELECT 1 AS n UNION ALL SELECT 1),
		a1 AS
		(SELECT 1 AS n FROM a0 AS a, a0 AS b),
		a2 AS
		(SELECT 1 AS n FROM a1 AS a, a1 AS b),
		a3 AS
		(SELECT 1 AS n FROM a2 AS a, a2 AS b),
		a4 AS
		(SELECT 1 AS n FROM a3 AS a, a3 AS b),
		numbers AS
		(
			SELECT TOP(LEN(@header) - 1)
				ROW_NUMBER() OVER
				(
					ORDER BY (SELECT NULL)
				) AS number
			FROM a4
			ORDER BY
				number
		)
		SELECT
			RTRIM(LTRIM(
				SUBSTRING
				(
					@header,
					number + 1,
					CHARINDEX(CHAR(13), @header, number + 1) - number - 1
				)
			)) AS [------header---------------------------------------------------------------------------------------------------------------]
		FROM numbers
		WHERE
			SUBSTRING(@header, number, 1) = CHAR(13);

		WITH
		a0 AS
		(SELECT 1 AS n UNION ALL SELECT 1),
		a1 AS
		(SELECT 1 AS n FROM a0 AS a, a0 AS b),
		a2 AS
		(SELECT 1 AS n FROM a1 AS a, a1 AS b),
		a3 AS
		(SELECT 1 AS n FROM a2 AS a, a2 AS b),
		a4 AS
		(SELECT 1 AS n FROM a3 AS a, a3 AS b),
		numbers AS
		(
			SELECT TOP(LEN(@params) - 1)
				ROW_NUMBER() OVER
				(
					ORDER BY (SELECT NULL)
				) AS number
			FROM a4
			ORDER BY
				number
		),
		tokens AS
		(
			SELECT 
				RTRIM(LTRIM(
					SUBSTRING
					(
						@params,
						number + 1,
						CHARINDEX(CHAR(13), @params, number + 1) - number - 1
					)
				)) AS token,
				number,
				CASE
					WHEN SUBSTRING(@params, number + 1, 1) = CHAR(13) THEN number
					ELSE COALESCE(NULLIF(CHARINDEX(',' + CHAR(13) + CHAR(13), @params, number), 0), LEN(@params)) 
				END AS param_group,
				ROW_NUMBER() OVER
				(
					PARTITION BY
						CHARINDEX(',' + CHAR(13) + CHAR(13), @params, number),
						SUBSTRING(@params, number+1, 1)
					ORDER BY 
						number
				) AS group_order
			FROM numbers
			WHERE
				SUBSTRING(@params, number, 1) = CHAR(13)
		),
		parsed_tokens AS
		(
			SELECT
				MIN
				(
					CASE
						WHEN token LIKE '@%' THEN token
						ELSE NULL
					END
				) AS parameter,
				MIN
				(
					CASE
						WHEN token LIKE '--%' THEN RIGHT(token, LEN(token) - 2)
						ELSE NULL
					END
				) AS description,
				param_group,
				group_order
			FROM tokens
			WHERE
				NOT 
				(
					token = '' 
					AND group_order > 1
				)
			GROUP BY
				param_group,
				group_order
		)
		SELECT
			CASE
				WHEN description IS NULL AND parameter IS NULL THEN '-------------------------------------------------------------------------'
				WHEN param_group = MAX(param_group) OVER() THEN parameter
				ELSE COALESCE(LEFT(parameter, LEN(parameter) - 1), '')
			END AS [------parameter----------------------------------------------------------],
			CASE
				WHEN description IS NULL AND parameter IS NULL THEN '----------------------------------------------------------------------------------------------------------------------'
				ELSE COALESCE(description, '')
			END AS [------description-----------------------------------------------------------------------------------------------------]
		FROM parsed_tokens
		ORDER BY
			param_group, 
			group_order;
		
		WITH
		a0 AS
		(SELECT 1 AS n UNION ALL SELECT 1),
		a1 AS
		(SELECT 1 AS n FROM a0 AS a, a0 AS b),
		a2 AS
		(SELECT 1 AS n FROM a1 AS a, a1 AS b),
		a3 AS
		(SELECT 1 AS n FROM a2 AS a, a2 AS b),
		a4 AS
		(SELECT 1 AS n FROM a3 AS a, a3 AS b),
		numbers AS
		(
			SELECT TOP(LEN(@outputs) - 1)
				ROW_NUMBER() OVER
				(
					ORDER BY (SELECT NULL)
				) AS number
			FROM a4
			ORDER BY
				number
		),
		tokens AS
		(
			SELECT 
				RTRIM(LTRIM(
					SUBSTRING
					(
						@outputs,
						number + 1,
						CASE
							WHEN 
								COALESCE(NULLIF(CHARINDEX(CHAR(13) + 'Formatted', @outputs, number + 1), 0), LEN(@outputs)) < 
								COALESCE(NULLIF(CHARINDEX(CHAR(13) + CHAR(255) COLLATE Latin1_General_Bin2, @outputs, number + 1), 0), LEN(@outputs))
								THEN COALESCE(NULLIF(CHARINDEX(CHAR(13) + 'Formatted', @outputs, number + 1), 0), LEN(@outputs)) - number - 1
							ELSE
								COALESCE(NULLIF(CHARINDEX(CHAR(13) + CHAR(255) COLLATE Latin1_General_Bin2, @outputs, number + 1), 0), LEN(@outputs)) - number - 1
						END
					)
				)) AS token,
				number,
				COALESCE(NULLIF(CHARINDEX(CHAR(13) + 'Formatted', @outputs, number + 1), 0), LEN(@outputs)) AS output_group,
				ROW_NUMBER() OVER
				(
					PARTITION BY 
						COALESCE(NULLIF(CHARINDEX(CHAR(13) + 'Formatted', @outputs, number + 1), 0), LEN(@outputs))
					ORDER BY
						number
				) AS output_group_order
			FROM numbers
			WHERE
				SUBSTRING(@outputs, number, 10) = CHAR(13) + 'Formatted'
				OR SUBSTRING(@outputs, number, 2) = CHAR(13) + CHAR(255) COLLATE Latin1_General_Bin2
		),
		output_tokens AS
		(
			SELECT 
				*,
				CASE output_group_order
					WHEN 2 THEN MAX(CASE output_group_order WHEN 1 THEN token ELSE NULL END) OVER (PARTITION BY output_group)
					ELSE ''
				END COLLATE Latin1_General_Bin2 AS column_info
			FROM tokens
		)
		SELECT
			CASE output_group_order
				WHEN 1 THEN '-----------------------------------'
				WHEN 2 THEN 
					CASE
						WHEN CHARINDEX('Formatted/Non:', column_info) = 1 THEN
							SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info)+1, CHARINDEX(']', column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info)+2) - CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info))
						ELSE
							SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info)+2, CHARINDEX(']', column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info)+2) - CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info)-1)
					END
				ELSE ''
			END AS formatted_column_name,
			CASE output_group_order
				WHEN 1 THEN '-----------------------------------'
				WHEN 2 THEN 
					CASE
						WHEN CHARINDEX('Formatted/Non:', column_info) = 1 THEN
							SUBSTRING(column_info, CHARINDEX(']', column_info)+2, LEN(column_info))
						ELSE
							SUBSTRING(column_info, CHARINDEX(']', column_info)+2, CHARINDEX('Non-Formatted:', column_info, CHARINDEX(']', column_info)+2) - CHARINDEX(']', column_info)-3)
					END
				ELSE ''
			END AS formatted_column_type,
			CASE output_group_order
				WHEN 1 THEN '---------------------------------------'
				WHEN 2 THEN 
					CASE
						WHEN CHARINDEX('Formatted/Non:', column_info) = 1 THEN ''
						ELSE
							CASE
								WHEN SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1, 1) = '<' THEN
									SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1, CHARINDEX('>', column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1) - CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info)))
								ELSE
									SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1, CHARINDEX(']', column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1) - CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info)))
							END
					END
				ELSE ''
			END AS unformatted_column_name,
			CASE output_group_order
				WHEN 1 THEN '---------------------------------------'
				WHEN 2 THEN 
					CASE
						WHEN CHARINDEX('Formatted/Non:', column_info) = 1 THEN ''
						ELSE
							CASE
								WHEN SUBSTRING(column_info, CHARINDEX(CHAR(255) COLLATE Latin1_General_Bin2, column_info, CHARINDEX('Non-Formatted:', column_info))+1, 1) = '<' THEN ''
								ELSE
									SUBSTRING(column_info, CHARINDEX(']', column_info, CHARINDEX('Non-Formatted:', column_info))+2, CHARINDEX('Non-Formatted:', column_info, CHARINDEX(']', column_info)+2) - CHARINDEX(']', column_info)-3)
							END
					END
				ELSE ''
			END AS unformatted_column_type,
			CASE output_group_order
				WHEN 1 THEN '----------------------------------------------------------------------------------------------------------------------'
				ELSE REPLACE(token, CHAR(255) COLLATE Latin1_General_Bin2, '')
			END AS [------description-----------------------------------------------------------------------------------------------------]
		FROM output_tokens
		WHERE
			NOT 
			(
				output_group_order = 1 
				AND output_group = LEN(@outputs)
			)
		ORDER BY
			output_group,
			CASE output_group_order
				WHEN 1 THEN 99
				ELSE output_group_order
			END;

		RETURN;
	END;

	WITH
	a0 AS
	(SELECT 1 AS n UNION ALL SELECT 1),
	a1 AS
	(SELECT 1 AS n FROM a0 AS a, a0 AS b),
	a2 AS
	(SELECT 1 AS n FROM a1 AS a, a1 AS b),
	a3 AS
	(SELECT 1 AS n FROM a2 AS a, a2 AS b),
	a4 AS
	(SELECT 1 AS n FROM a3 AS a, a3 AS b),
	numbers AS
	(
		SELECT TOP(LEN(@output_column_list))
			ROW_NUMBER() OVER
			(
				ORDER BY (SELECT NULL)
			) AS number
		FROM a4
		ORDER BY
			number
	),
	tokens AS
	(
		SELECT 
			'|[' +
				SUBSTRING
				(
					@output_column_list,
					number + 1,
					CHARINDEX(']', @output_column_list, number) - number - 1
				) + '|]' AS token,
			number
		FROM numbers
		WHERE
			SUBSTRING(@output_column_list, number, 1) = '['
	),
	ordered_columns AS
	(
		SELECT
			x.column_name,
			ROW_NUMBER() OVER
			(
				PARTITION BY
					x.column_name
				ORDER BY
					tokens.number,
					x.default_order
			) AS r,
			ROW_NUMBER() OVER
			(
				ORDER BY
					tokens.number,
					x.default_order
			) AS s
		FROM tokens
		JOIN
		(
			SELECT '[session_id]' AS column_name, 1 AS default_order
			UNION ALL
			SELECT '[dd hh:mm:ss.mss]', 2
			WHERE
				@format_output IN (1, 2)
			UNION ALL
			SELECT '[dd hh:mm:ss.mss (avg)]', 3
			WHERE
				@format_output IN (1, 2)
				AND @get_avg_time = 1
			UNION ALL
			SELECT '[avg_elapsed_time]', 4
			WHERE
				@format_output = 0
				AND @get_avg_time = 1
			UNION ALL
			SELECT '[physical_io]', 5
			WHERE
				@get_task_info = 2
			UNION ALL
			SELECT '[reads]', 6
			UNION ALL
			SELECT '[physical_reads]', 7
			UNION ALL
			SELECT '[writes]', 8
			UNION ALL
			SELECT '[tempdb_allocations]', 9
			UNION ALL
			SELECT '[tempdb_current]', 10
			UNION ALL
			SELECT '[CPU]', 11
			UNION ALL
			SELECT '[context_switches]', 12
			WHERE
				@get_task_info = 2
			UNION ALL
			SELECT '[used_memory]', 13
			UNION ALL
			SELECT '[physical_io_delta]', 14
			WHERE
				@delta_interval > 0	
				AND @get_task_info = 2
			UNION ALL
			SELECT '[reads_delta]', 15
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[physical_reads_delta]', 16
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[writes_delta]', 17
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[tempdb_allocations_delta]', 18
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[tempdb_current_delta]', 19
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[CPU_delta]', 20
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[context_switches_delta]', 21
			WHERE
				@delta_interval > 0
				AND @get_task_info = 2
			UNION ALL
			SELECT '[used_memory_delta]', 22
			WHERE
				@delta_interval > 0
			UNION ALL
			SELECT '[tasks]', 23
			WHERE
				@get_task_info = 2
			UNION ALL
			SELECT '[status]', 24
			UNION ALL
			SELECT '[wait_info]', 25
			WHERE
				@get_task_info > 0
				OR @find_block_leaders = 1
			UNION ALL
			SELECT '[locks]', 26
			WHERE
				@get_locks = 1
			UNION ALL
			SELECT '[tran_start_time]', 27
			WHERE
				@get_transaction_info = 1
			UNION ALL
			SELECT '[tran_log_writes]', 28
			WHERE
				@get_transaction_info = 1
			UNION ALL
			SELECT '[open_tran_count]', 29
			UNION ALL
			SELECT '[sql_command]', 30
			WHERE
				@get_outer_command = 1
			UNION ALL
			SELECT '[sql_text]', 31
			UNION ALL
			SELECT '[query_plan]', 32
			WHERE
				@get_plans >= 1
			UNION ALL
			SELECT '[blocking_session_id]', 33
			WHERE
				@get_task_info > 0
				OR @find_block_leaders = 1
			UNION ALL
			SELECT '[blocked_session_count]', 34
			WHERE
				@find_block_leaders = 1
			UNION ALL
			SELECT '[percent_complete]', 35
			UNION ALL
			SELECT '[host_name]', 36
			UNION ALL
			SELECT '[login_name]', 37
			UNION ALL
			SELECT '[database_name]', 38
			UNION ALL
			SELECT '[program_name]', 39
			UNION ALL
			SELECT '[additional_info]', 40
			WHERE
				@get_additional_info = 1
			UNION ALL
			SELECT '[start_time]', 41
			UNION ALL
			SELECT '[login_time]', 42
			UNION ALL
			SELECT '[request_id]', 43
			UNION ALL
			SELECT '[collection_time]', 44
		) AS x ON 
			x.column_name LIKE token ESCAPE '|'
	)
	SELECT
		@output_column_list =
			STUFF
			(
				(
					SELECT
						',' + column_name as [text()]
					FROM ordered_columns
					WHERE
						r = 1
					ORDER BY
						s
					FOR XML
						PATH('')
				),
				1,
				1,
				''
			);
	
	IF COALESCE(RTRIM(@output_column_list), '') = ''
	BEGIN;
		RAISERROR('No valid column matches found in @output_column_list or no columns remain due to selected options.', 16, 1);
		RETURN;
	END;
	
	IF @destination_table <> ''
	BEGIN;
		SET @destination_table = 
			--database
			COALESCE(QUOTENAME(PARSENAME(@destination_table, 3)) + '.', '') +
			--schema
			COALESCE(QUOTENAME(PARSENAME(@destination_table, 2)) + '.', '') +
			--table
			COALESCE(QUOTENAME(PARSENAME(@destination_table, 1)), '');
			
		IF COALESCE(RTRIM(@destination_table), '') = ''
		BEGIN;
			RAISERROR('Destination table not properly formatted.', 16, 1);
			RETURN;
		END;
	END;

	WITH
	a0 AS
	(SELECT 1 AS n UNION ALL SELECT 1),
	a1 AS
	(SELECT 1 AS n FROM a0 AS a, a0 AS b),
	a2 AS
	(SELECT 1 AS n FROM a1 AS a, a1 AS b),
	a3 AS
	(SELECT 1 AS n FROM a2 AS a, a2 AS b),
	a4 AS
	(SELECT 1 AS n FROM a3 AS a, a3 AS b),
	numbers AS
	(
		SELECT TOP(LEN(@sort_order))
			ROW_NUMBER() OVER
			(
				ORDER BY (SELECT NULL)
			) AS number
		FROM a4
		ORDER BY
			number
	),
	tokens AS
	(
		SELECT 
			'|[' +
				SUBSTRING
				(
					@sort_order,
					number + 1,
					CHARINDEX(']', @sort_order, number) - number - 1
				) + '|]' AS token,
			SUBSTRING
			(
				@sort_order,
				CHARINDEX(']', @sort_order, number) + 1,
				COALESCE(NULLIF(CHARINDEX('[', @sort_order, CHARINDEX(']', @sort_order, number)), 0), LEN(@sort_order)) - CHARINDEX(']', @sort_order, number)
			) AS next_chunk,
			number
		FROM numbers
		WHERE
			SUBSTRING(@sort_order, number, 1) = '['
	),
	ordered_columns AS
	(
		SELECT
			x.column_name +
				CASE
					WHEN tokens.next_chunk LIKE '%asc%' THEN ' ASC'
					WHEN tokens.next_chunk LIKE '%desc%' THEN ' DESC'
					ELSE ''
				END AS column_name,
			ROW_NUMBER() OVER
			(
				PARTITION BY
					x.column_name
				ORDER BY
					tokens.number
			) AS r,
			tokens.number
		FROM tokens
		JOIN
		(
			SELECT '[session_id]' AS column_name
			UNION ALL
			SELECT '[physical_io]'
			UNION ALL
			SELECT '[reads]'
			UNION ALL
			SELECT '[physical_reads]'
			UNION ALL
			SELECT '[writes]'
			UNION ALL
			SELECT '[tempdb_allocations]'
			UNION ALL
			SELECT '[tempdb_current]'
			UNION ALL
			SELECT '[CPU]'
			UNION ALL
			SELECT '[context_switches]'
			UNION ALL
			SELECT '[used_memory]'
			UNION ALL
			SELECT '[physical_io_delta]'
			UNION ALL
			SELECT '[reads_delta]'
			UNION ALL
			SELECT '[physical_reads_delta]'
			UNION ALL
			SELECT '[writes_delta]'
			UNION ALL
			SELECT '[tempdb_allocations_delta]'
			UNION ALL
			SELECT '[tempdb_current_delta]'
			UNION ALL
			SELECT '[CPU_delta]'
			UNION ALL
			SELECT '[context_switches_delta]'
			UNION ALL
			SELECT '[used_memory_delta]'
			UNION ALL
			SELECT '[tasks]'
			UNION ALL
			SELECT '[tran_start_time]'
			UNION ALL
			SELECT '[open_tran_count]'
			UNION ALL
			SELECT '[blocking_session_id]'
			UNION ALL
			SELECT '[blocked_session_count]'
			UNION ALL
			SELECT '[percent_complete]'
			UNION ALL
			SELECT '[host_name]'
			UNION ALL
			SELECT '[login_name]'
			UNION ALL
			SELECT '[database_name]'
			UNION ALL
			SELECT '[start_time]'
			UNION ALL
			SELECT '[login_time]'
		) AS x ON 
			x.column_name LIKE token ESCAPE '|'
	)
	SELECT
		@sort_order = COALESCE(z.sort_order, '')
	FROM
	(
		SELECT
			STUFF
			(
				(
					SELECT
						',' + column_name as [text()]
					FROM ordered_columns
					WHERE
						r = 1
					ORDER BY
						number
					FOR XML
						PATH('')
				),
				1,
				1,
				''
			) AS sort_order
	) AS z;

	CREATE TABLE #sessions
	(
		recursion SMALLINT NOT NULL,
		session_id SMALLINT NOT NULL,
		request_id INT NOT NULL,
		session_number INT NOT NULL,
		elapsed_time INT NOT NULL,
		avg_elapsed_time INT NULL,
		physical_io BIGINT NULL,
		reads BIGINT NULL,
		physical_reads BIGINT NULL,
		writes BIGINT NULL,
		tempdb_allocations BIGINT NULL,
		tempdb_current BIGINT NULL,
		CPU INT NULL,
		thread_CPU_snapshot BIGINT NULL,
		context_switches BIGINT NULL,
		used_memory BIGINT NOT NULL, 
		tasks SMALLINT NULL,
		status VARCHAR(30) NOT NULL,
		wait_info NVARCHAR(4000) NULL,
		locks XML NULL,
		transaction_id BIGINT NULL,
		tran_start_time DATETIME NULL,
		tran_log_writes NVARCHAR(4000) NULL,
		open_tran_count SMALLINT NULL,
		sql_command XML NULL,
		sql_handle VARBINARY(64) NULL,
		statement_start_offset INT NULL,
		statement_end_offset INT NULL,
		sql_text XML NULL,
		plan_handle VARBINARY(64) NULL,
		query_plan XML NULL,
		blocking_session_id SMALLINT NULL,
		blocked_session_count SMALLINT NULL,
		percent_complete REAL NULL,
		host_name sysname NULL,
		login_name sysname NOT NULL,
		database_name sysname NULL,
		program_name sysname NULL,
		additional_info XML NULL,
		start_time DATETIME NOT NULL,
		login_time DATETIME NULL,
		last_request_start_time DATETIME NULL,
		PRIMARY KEY CLUSTERED (session_id, request_id, recursion) WITH (IGNORE_DUP_KEY = ON),
		UNIQUE NONCLUSTERED (transaction_id, session_id, request_id, recursion) WITH (IGNORE_DUP_KEY = ON)
	);

	IF @return_schema = 0
	BEGIN;
		--Disable unnecessary autostats on the table
		CREATE STATISTICS s_session_id ON #sessions (session_id)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_request_id ON #sessions (request_id)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_transaction_id ON #sessions (transaction_id)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_session_number ON #sessions (session_number)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_status ON #sessions (status)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_start_time ON #sessions (start_time)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_last_request_start_time ON #sessions (last_request_start_time)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;
		CREATE STATISTICS s_recursion ON #sessions (recursion)
		WITH SAMPLE 0 ROWS, NORECOMPUTE;

		DECLARE @recursion SMALLINT;
		SET @recursion = 
			CASE @delta_interval
				WHEN 0 THEN 1
				ELSE -1
			END;

		DECLARE @first_collection_ms_ticks BIGINT;
		DECLARE @last_collection_start DATETIME;

		--Used for the delta pull
		REDO:;
		
		IF 
			@get_locks = 1 
			AND @recursion = 1
			AND @output_column_list LIKE '%|[locks|]%' ESCAPE '|'
		BEGIN;
			SELECT
				y.resource_type,
				y.database_name,
				y.object_id,
				y.file_id,
				y.page_type,
				y.hobt_id,
				y.allocation_unit_id,
				y.index_id,
				y.schema_id,
				y.principal_id,
				y.request_mode,
				y.request_status,
				y.session_id,
				y.resource_description,
				y.request_count,
				s.request_id,
				s.start_time,
				CONVERT(sysname, NULL) AS object_name,
				CONVERT(sysname, NULL) AS index_name,
				CONVERT(sysname, NULL) AS schema_name,
				CONVERT(sysname, NULL) AS principal_name,
				CONVERT(NVARCHAR(2048), NULL) AS query_error
			INTO #locks
			FROM
			(
				SELECT
					sp.spid AS session_id,
					CASE sp.status
						WHEN 'sleeping' THEN CONVERT(INT, 0)
						ELSE sp.request_id
					END AS request_id,
					CASE sp.status
						WHEN 'sleeping' THEN sp.last_batch
						ELSE COALESCE(req.start_time, sp.last_batch)
					END AS start_time,
					sp.dbid
				FROM sys.sysprocesses AS sp
				OUTER APPLY
				(
					SELECT TOP(1)
						CASE
							WHEN 
							(
								sp.hostprocess > ''
								OR r.total_elapsed_time < 0
							) THEN
								r.start_time
							ELSE
								DATEADD
								(
									ms, 
									1000 * (DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())) / 500) - DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())), 
									DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())
								)
						END AS start_time
					FROM sys.dm_exec_requests AS r
					WHERE
						r.session_id = sp.spid
						AND r.request_id = sp.request_id
				) AS req
				WHERE
					--Process inclusive filter
					1 =
						CASE
							WHEN @filter <> '' THEN
								CASE @filter_type
									WHEN 'session' THEN
										CASE
											WHEN
												CONVERT(SMALLINT, @filter) = 0
												OR sp.spid = CONVERT(SMALLINT, @filter)
													THEN 1
											ELSE 0
										END
									WHEN 'program' THEN
										CASE
											WHEN sp.program_name LIKE @filter THEN 1
											ELSE 0
										END
									WHEN 'login' THEN
										CASE
											WHEN sp.loginame LIKE @filter THEN 1
											ELSE 0
										END
									WHEN 'host' THEN
										CASE
											WHEN sp.hostname LIKE @filter THEN 1
											ELSE 0
										END
									WHEN 'database' THEN
										CASE
											WHEN DB_NAME(sp.dbid) LIKE @filter THEN 1
											ELSE 0
										END
									ELSE 0
								END
							ELSE 1
						END
					--Process exclusive filter
					AND 0 =
						CASE
							WHEN @not_filter <> '' THEN
								CASE @not_filter_type
									WHEN 'session' THEN
										CASE
											WHEN sp.spid = CONVERT(SMALLINT, @not_filter) THEN 1
											ELSE 0
										END
									WHEN 'program' THEN
										CASE
											WHEN sp.program_name LIKE @not_filter THEN 1
											ELSE 0
										END
									WHEN 'login' THEN
										CASE
											WHEN sp.loginame LIKE @not_filter THEN 1
											ELSE 0
										END
									WHEN 'host' THEN
										CASE
											WHEN sp.hostname LIKE @not_filter THEN 1
											ELSE 0
										END
									WHEN 'database' THEN
										CASE
											WHEN DB_NAME(sp.dbid) LIKE @not_filter THEN 1
											ELSE 0
										END
									ELSE 0
								END
							ELSE 0
						END
					AND 
					(
						@show_own_spid = 1
						OR sp.spid <> @@SPID
					)
					AND 
					(
						@show_system_spids = 1
						OR sp.hostprocess > ''
					)
					AND sp.ecid = 0
			) AS s
			INNER HASH JOIN
			(
				SELECT
					x.resource_type,
					x.database_name,
					x.object_id,
					x.file_id,
					CASE
						WHEN x.page_no = 1 OR x.page_no % 8088 = 0 THEN 'PFS'
						WHEN x.page_no = 2 OR x.page_no % 511232 = 0 THEN 'GAM'
						WHEN x.page_no = 3 OR x.page_no % 511233 = 0 THEN 'SGAM'
						WHEN x.page_no = 6 OR x.page_no % 511238 = 0 THEN 'DCM'
						WHEN x.page_no = 7 OR x.page_no % 511239 = 0 THEN 'BCM'
						WHEN x.page_no IS NOT NULL THEN '*'
						ELSE NULL
					END AS page_type,
					x.hobt_id,
					x.allocation_unit_id,
					x.index_id,
					x.schema_id,
					x.principal_id,
					x.request_mode,
					x.request_status,
					x.session_id,
					x.request_id,
					CASE
						WHEN COALESCE(x.object_id, x.file_id, x.hobt_id, x.allocation_unit_id, x.index_id, x.schema_id, x.principal_id) IS NULL THEN NULLIF(resource_description, '')
						ELSE NULL
					END AS resource_description,
					COUNT(*) AS request_count
				FROM
				(
					SELECT
						tl.resource_type +
							CASE
								WHEN tl.resource_subtype = '' THEN ''
								ELSE '.' + tl.resource_subtype
							END AS resource_type,
						COALESCE(DB_NAME(tl.resource_database_id), N'(null)') AS database_name,
						CONVERT
						(
							INT,
							CASE
								WHEN tl.resource_type = 'OBJECT' THEN tl.resource_associated_entity_id
								WHEN tl.resource_description LIKE '%object_id = %' THEN
									(
										SUBSTRING
										(
											tl.resource_description, 
											(CHARINDEX('object_id = ', tl.resource_description) + 12), 
											COALESCE
											(
												NULLIF
												(
													CHARINDEX(',', tl.resource_description, CHARINDEX('object_id = ', tl.resource_description) + 12),
													0
												), 
												DATALENGTH(tl.resource_description)+1
											) - (CHARINDEX('object_id = ', tl.resource_description) + 12)
										)
									)
								ELSE NULL
							END
						) AS object_id,
						CONVERT
						(
							INT,
							CASE 
								WHEN tl.resource_type = 'FILE' THEN CONVERT(INT, tl.resource_description)
								WHEN tl.resource_type IN ('PAGE', 'EXTENT', 'RID') THEN LEFT(tl.resource_description, CHARINDEX(':', tl.resource_description)-1)
								ELSE NULL
							END
						) AS file_id,
						CONVERT
						(
							INT,
							CASE
								WHEN tl.resource_type IN ('PAGE', 'EXTENT', 'RID') THEN 
									SUBSTRING
									(
										tl.resource_description, 
										CHARINDEX(':', tl.resource_description) + 1, 
										COALESCE
										(
											NULLIF
											(
												CHARINDEX(':', tl.resource_description, CHARINDEX(':', tl.resource_description) + 1), 
												0
											), 
											DATALENGTH(tl.resource_description)+1
										) - (CHARINDEX(':', tl.resource_description) + 1)
									)
								ELSE NULL
							END
						) AS page_no,
						CASE
							WHEN tl.resource_type IN ('PAGE', 'KEY', 'RID', 'HOBT') THEN tl.resource_associated_entity_id
							ELSE NULL
						END AS hobt_id,
						CASE
							WHEN tl.resource_type = 'ALLOCATION_UNIT' THEN tl.resource_associated_entity_id
							ELSE NULL
						END AS allocation_unit_id,
						CONVERT
						(
							INT,
							CASE
								WHEN
									/*TODO: Deal with server principals*/ 
									tl.resource_subtype <> 'SERVER_PRINCIPAL' 
									AND tl.resource_description LIKE '%index_id or stats_id = %' THEN
									(
										SUBSTRING
										(
											tl.resource_description, 
											(CHARINDEX('index_id or stats_id = ', tl.resource_description) + 23), 
											COALESCE
											(
												NULLIF
												(
													CHARINDEX(',', tl.resource_description, CHARINDEX('index_id or stats_id = ', tl.resource_description) + 23), 
													0
												), 
												DATALENGTH(tl.resource_description)+1
											) - (CHARINDEX('index_id or stats_id = ', tl.resource_description) + 23)
										)
									)
								ELSE NULL
							END 
						) AS index_id,
						CONVERT
						(
							INT,
							CASE
								WHEN tl.resource_description LIKE '%schema_id = %' THEN
									(
										SUBSTRING
										(
											tl.resource_description, 
											(CHARINDEX('schema_id = ', tl.resource_description) + 12), 
											COALESCE
											(
												NULLIF
												(
													CHARINDEX(',', tl.resource_description, CHARINDEX('schema_id = ', tl.resource_description) + 12), 
													0
												), 
												DATALENGTH(tl.resource_description)+1
											) - (CHARINDEX('schema_id = ', tl.resource_description) + 12)
										)
									)
								ELSE NULL
							END 
						) AS schema_id,
						CONVERT
						(
							INT,
							CASE
								WHEN tl.resource_description LIKE '%principal_id = %' THEN
									(
										SUBSTRING
										(
											tl.resource_description, 
											(CHARINDEX('principal_id = ', tl.resource_description) + 15), 
											COALESCE
											(
												NULLIF
												(
													CHARINDEX(',', tl.resource_description, CHARINDEX('principal_id = ', tl.resource_description) + 15), 
													0
												), 
												DATALENGTH(tl.resource_description)+1
											) - (CHARINDEX('principal_id = ', tl.resource_description) + 15)
										)
									)
								ELSE NULL
							END
						) AS principal_id,
						tl.request_mode,
						tl.request_status,
						tl.request_session_id AS session_id,
						tl.request_request_id AS request_id,

						/*TODO: Applocks, other resource_descriptions*/
						RTRIM(tl.resource_description) AS resource_description,
						tl.resource_associated_entity_id
						/*********************************************/
					FROM 
					(
						SELECT 
							request_session_id,
							CONVERT(VARCHAR(120), resource_type) COLLATE Latin1_General_Bin2 AS resource_type,
							CONVERT(VARCHAR(120), resource_subtype) COLLATE Latin1_General_Bin2 AS resource_subtype,
							resource_database_id,
							CONVERT(VARCHAR(512), resource_description) COLLATE Latin1_General_Bin2 AS resource_description,
							resource_associated_entity_id,
							CONVERT(VARCHAR(120), request_mode) COLLATE Latin1_General_Bin2 AS request_mode,
							CONVERT(VARCHAR(120), request_status) COLLATE Latin1_General_Bin2 AS request_status,
							request_request_id
						FROM sys.dm_tran_locks
					) AS tl
				) AS x
				GROUP BY
					x.resource_type,
					x.database_name,
					x.object_id,
					x.file_id,
					CASE
						WHEN x.page_no = 1 OR x.page_no % 8088 = 0 THEN 'PFS'
						WHEN x.page_no = 2 OR x.page_no % 511232 = 0 THEN 'GAM'
						WHEN x.page_no = 3 OR x.page_no % 511233 = 0 THEN 'SGAM'
						WHEN x.page_no = 6 OR x.page_no % 511238 = 0 THEN 'DCM'
						WHEN x.page_no = 7 OR x.page_no % 511239 = 0 THEN 'BCM'
						WHEN x.page_no IS NOT NULL THEN '*'
						ELSE NULL
					END,
					x.hobt_id,
					x.allocation_unit_id,
					x.index_id,
					x.schema_id,
					x.principal_id,
					x.request_mode,
					x.request_status,
					x.session_id,
					x.request_id,
					CASE
						WHEN COALESCE(x.object_id, x.file_id, x.hobt_id, x.allocation_unit_id, x.index_id, x.schema_id, x.principal_id) IS NULL THEN NULLIF(resource_description, '')
						ELSE NULL
					END
			) AS y ON
				y.session_id = s.session_id
				AND y.request_id = s.request_id
			OPTION (HASH GROUP);

			--Disable unnecessary autostats on the table
			CREATE STATISTICS s_database_name ON #locks (database_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_object_id ON #locks (object_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_hobt_id ON #locks (hobt_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_allocation_unit_id ON #locks (allocation_unit_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_index_id ON #locks (index_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_schema_id ON #locks (schema_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_principal_id ON #locks (principal_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_request_id ON #locks (request_id)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_start_time ON #locks (start_time)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_resource_type ON #locks (resource_type)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_object_name ON #locks (object_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_schema_name ON #locks (schema_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_page_type ON #locks (page_type)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_request_mode ON #locks (request_mode)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_request_status ON #locks (request_status)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_resource_description ON #locks (resource_description)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_index_name ON #locks (index_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_principal_name ON #locks (principal_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
		END;
		
		DECLARE 
			@sql VARCHAR(MAX), 
			@sql_n NVARCHAR(MAX);

		SET @sql = 
			CONVERT(VARCHAR(MAX), '') +
			'DECLARE @blocker BIT;
			SET @blocker = 0;
			DECLARE @i INT;
			SET @i = 2147483647;

			DECLARE @sessions TABLE
			(
				session_id SMALLINT NOT NULL,
				request_id INT NOT NULL,
				login_time DATETIME,
				last_request_end_time DATETIME,
				status VARCHAR(30),
				statement_start_offset INT,
				statement_end_offset INT,
				sql_handle BINARY(20),
				host_name NVARCHAR(128),
				login_name NVARCHAR(128),
				program_name NVARCHAR(128),
				database_id SMALLINT,
				memory_usage INT,
				open_tran_count SMALLINT, 
				' +
				CASE
					WHEN 
					(
						@get_task_info <> 0 
						OR @find_block_leaders = 1 
					) THEN
						'wait_type NVARCHAR(32),
						wait_resource NVARCHAR(256),
						wait_time BIGINT, 
						'
					ELSE 
						''
				END +
				'blocked SMALLINT,
				is_user_process BIT,
				cmd VARCHAR(32),
				PRIMARY KEY CLUSTERED (session_id, request_id) WITH (IGNORE_DUP_KEY = ON)
			);

			DECLARE @blockers TABLE
			(
				session_id INT NOT NULL PRIMARY KEY
			);

			BLOCKERS:;

			INSERT @sessions
			(
				session_id,
				request_id,
				login_time,
				last_request_end_time,
				status,
				statement_start_offset,
				statement_end_offset,
				sql_handle,
				host_name,
				login_name,
				program_name,
				database_id,
				memory_usage,
				open_tran_count, 
				' +
				CASE
					WHEN 
					(
						@get_task_info <> 0
						OR @find_block_leaders = 1 
					) THEN
						'wait_type,
						wait_resource,
						wait_time, 
						'
					ELSE
						''
				END +
				'blocked,
				is_user_process,
				cmd 
			)
			SELECT TOP(@i)
				spy.session_id,
				spy.request_id,
				spy.login_time,
				spy.last_request_end_time,
				spy.status,
				spy.statement_start_offset,
				spy.statement_end_offset,
				spy.sql_handle,
				spy.host_name,
				spy.login_name,
				spy.program_name,
				spy.database_id,
				spy.memory_usage,
				spy.open_tran_count,
				' +
				CASE
					WHEN 
					(
						@get_task_info <> 0  
						OR @find_block_leaders = 1 
					) THEN
						'spy.wait_type,
						CASE
							WHEN
								spy.wait_type LIKE N''PAGE%LATCH_%''
								OR spy.wait_type = N''CXPACKET''
								OR spy.wait_type LIKE N''LATCH[_]%''
								OR spy.wait_type = N''OLEDB'' THEN
									spy.wait_resource
							ELSE
								NULL
						END AS wait_resource,
						spy.wait_time, 
						'
					ELSE
						''
				END +
				'spy.blocked,
				spy.is_user_process,
				spy.cmd
			FROM
			(
				SELECT TOP(@i)
					spx.*, 
					' +
					CASE
						WHEN 
						(
							@get_task_info <> 0 
							OR @find_block_leaders = 1 
						) THEN
							'ROW_NUMBER() OVER
							(
								PARTITION BY
									spx.session_id,
									spx.request_id
								ORDER BY
									CASE
										WHEN spx.wait_type LIKE N''LCK[_]%'' THEN 
											1
										ELSE
											99
									END,
									spx.wait_time DESC,
									spx.blocked DESC
							) AS r 
							'
						ELSE 
							'1 AS r 
							'
					END +
				'FROM
				(
					SELECT TOP(@i)
						sp0.session_id,
						sp0.request_id,
						sp0.login_time,
						sp0.last_request_end_time,
						LOWER(sp0.status) AS status,
						CASE
							WHEN sp0.cmd = ''CREATE INDEX'' THEN
								0
							ELSE
								sp0.stmt_start
						END AS statement_start_offset,
						CASE
							WHEN sp0.cmd = N''CREATE INDEX'' THEN
								-1
							ELSE
								COALESCE(NULLIF(sp0.stmt_end, 0), -1)
						END AS statement_end_offset,
						sp0.sql_handle,
						sp0.host_name,
						sp0.login_name,
						sp0.program_name,
						sp0.database_id,
						sp0.memory_usage,
						sp0.open_tran_count, 
						' +
						CASE
							WHEN 
							(
								@get_task_info <> 0 
								OR @find_block_leaders = 1 
							) THEN
								'CASE
									WHEN sp0.wait_time > 0 AND sp0.wait_type <> N''CXPACKET'' THEN
										sp0.wait_type
									ELSE
										NULL
								END AS wait_type,
								CASE
									WHEN sp0.wait_time > 0 AND sp0.wait_type <> N''CXPACKET'' THEN 
										sp0.wait_resource
									ELSE
										NULL
								END AS wait_resource,
								CASE
									WHEN sp0.wait_type <> N''CXPACKET'' THEN
										sp0.wait_time
									ELSE
										0
								END AS wait_time, 
								'
							ELSE
								''
						END +
						'sp0.blocked,
						sp0.is_user_process,
						sp0.cmd
					FROM
					(
						SELECT TOP(@i)
							sp1.session_id,
							sp1.request_id,
							sp1.login_time,
							sp1.last_request_end_time,
							sp1.status,
							sp1.cmd,
							sp1.stmt_start,
							sp1.stmt_end,
							MAX(NULLIF(sp1.sql_handle, 0x00)) OVER (PARTITION BY sp1.session_id, sp1.request_id) AS sql_handle,
							sp1.host_name,
							MAX(sp1.login_name) OVER (PARTITION BY sp1.session_id, sp1.request_id) AS login_name,
							sp1.program_name,
							sp1.database_id,
							MAX(sp1.memory_usage)  OVER (PARTITION BY sp1.session_id, sp1.request_id) AS memory_usage,
							MAX(sp1.open_tran_count)  OVER (PARTITION BY sp1.session_id, sp1.request_id) AS open_tran_count,
							sp1.wait_type,
							sp1.wait_resource,
							sp1.wait_time,
							sp1.blocked,
							sp1.hostprocess,
							sp1.is_user_process
						FROM
						(
							SELECT TOP(@i)
								sp2.spid AS session_id,
								CASE sp2.status
									WHEN ''sleeping'' THEN
										CONVERT(INT, 0)
									ELSE
										sp2.request_id
								END AS request_id,
								MAX(sp2.login_time) AS login_time,
								MAX(sp2.last_batch) AS last_request_end_time,
								MAX(CONVERT(VARCHAR(30), RTRIM(sp2.status)) COLLATE Latin1_General_Bin2) AS status,
								MAX(CONVERT(VARCHAR(32), RTRIM(sp2.cmd)) COLLATE Latin1_General_Bin2) AS cmd,
								MAX(sp2.stmt_start) AS stmt_start,
								MAX(sp2.stmt_end) AS stmt_end,
								MAX(sp2.sql_handle) AS sql_handle,
								MAX(CONVERT(sysname, RTRIM(sp2.hostname)) COLLATE SQL_Latin1_General_CP1_CI_AS) AS host_name,
								MAX(CONVERT(sysname, RTRIM(sp2.loginame)) COLLATE SQL_Latin1_General_CP1_CI_AS) AS login_name,
								MAX
								(
									CASE
										WHEN blk.queue_id IS NOT NULL THEN
											N''Service Broker
												database_id: '' + CONVERT(NVARCHAR, blk.database_id) +
												N'' queue_id: '' + CONVERT(NVARCHAR, blk.queue_id)
										ELSE
											CONVERT
											(
												sysname,
												RTRIM(sp2.program_name)
											)
									END COLLATE SQL_Latin1_General_CP1_CI_AS
								) AS program_name,
								MAX(sp2.dbid) AS database_id,
								MAX(sp2.memusage) AS memory_usage,
								MAX(sp2.open_tran) AS open_tran_count,
								RTRIM(sp2.lastwaittype) AS wait_type,
								RTRIM(sp2.waitresource) AS wait_resource,
								MAX(sp2.waittime) AS wait_time,
								COALESCE(NULLIF(sp2.blocked, sp2.spid), 0) AS blocked,
								MAX
								(
									CASE
										WHEN blk.session_id = sp2.spid THEN
											''blocker''
										ELSE
											RTRIM(sp2.hostprocess)
									END
								) AS hostprocess,
								CONVERT
								(
									BIT,
									MAX
									(
										CASE
											WHEN sp2.hostprocess > '''' THEN
												1
											ELSE
												0
										END
									)
								) AS is_user_process
							FROM
							(
								SELECT TOP(@i)
									session_id,
									CONVERT(INT, NULL) AS queue_id,
									CONVERT(INT, NULL) AS database_id
								FROM @blockers

								UNION ALL

								SELECT TOP(@i)
									CONVERT(SMALLINT, 0),
									CONVERT(INT, NULL) AS queue_id,
									CONVERT(INT, NULL) AS database_id
								WHERE
									@blocker = 0

								UNION ALL

								SELECT TOP(@i)
									CONVERT(SMALLINT, spid),
									queue_id,
									database_id
								FROM sys.dm_broker_activated_tasks
								WHERE
									@blocker = 0
							) AS blk
							INNER JOIN sys.sysprocesses AS sp2 ON
								sp2.spid = blk.session_id
								OR
								(
									blk.session_id = 0
									AND @blocker = 0
								)
							' +
							CASE 
								WHEN 
								(
									@get_task_info = 0 
									AND @find_block_leaders = 0
								) THEN
									'WHERE
										sp2.ecid = 0 
									' 
								ELSE
									''
							END +
							'GROUP BY
								sp2.spid,
								CASE sp2.status
									WHEN ''sleeping'' THEN
										CONVERT(INT, 0)
									ELSE
										sp2.request_id
								END,
								RTRIM(sp2.lastwaittype),
								RTRIM(sp2.waitresource),
								COALESCE(NULLIF(sp2.blocked, sp2.spid), 0)
						) AS sp1
					) AS sp0
					WHERE
						@blocker = 1
						OR
						(1=1 
						' +
							--inclusive filter
							CASE
								WHEN @filter <> '' THEN
									CASE @filter_type
										WHEN 'session' THEN
											CASE
												WHEN CONVERT(SMALLINT, @filter) <> 0 THEN
													'AND sp0.session_id = CONVERT(SMALLINT, @filter) 
													'
												ELSE
													''
											END
										WHEN 'program' THEN
											'AND sp0.program_name LIKE @filter 
											'
										WHEN 'login' THEN
											'AND sp0.login_name LIKE @filter 
											'
										WHEN 'host' THEN
											'AND sp0.host_name LIKE @filter 
											'
										WHEN 'database' THEN
											'AND DB_NAME(sp0.database_id) LIKE @filter 
											'
										ELSE
											''
									END
								ELSE
									''
							END +
							--exclusive filter
							CASE
								WHEN @not_filter <> '' THEN
									CASE @not_filter_type
										WHEN 'session' THEN
											CASE
												WHEN CONVERT(SMALLINT, @not_filter) <> 0 THEN
													'AND sp0.session_id <> CONVERT(SMALLINT, @not_filter) 
													'
												ELSE
													''
											END
										WHEN 'program' THEN
											'AND sp0.program_name NOT LIKE @not_filter 
											'
										WHEN 'login' THEN
											'AND sp0.login_name NOT LIKE @not_filter 
											'
										WHEN 'host' THEN
											'AND sp0.host_name NOT LIKE @not_filter 
											'
										WHEN 'database' THEN
											'AND DB_NAME(sp0.database_id) NOT LIKE @not_filter 
											'
										ELSE
											''
									END
								ELSE
									''
							END +
							CASE @show_own_spid
								WHEN 1 THEN
									''
								ELSE
									'AND sp0.session_id <> @@spid 
									'
							END +
							CASE 
								WHEN @show_system_spids = 0 THEN
									'AND sp0.hostprocess > '''' 
									' 
								ELSE
									''
							END +
							CASE @show_sleeping_spids
								WHEN 0 THEN
									'AND sp0.status <> ''sleeping'' 
									'
								WHEN 1 THEN
									'AND
									(
										sp0.status <> ''sleeping''
										OR sp0.open_tran_count > 0
									)
									'
								ELSE
									''
							END +
						')
				) AS spx
			) AS spy
			WHERE
				spy.r = 1; 
			' + 
			CASE @recursion
				WHEN 1 THEN 
					'IF @@ROWCOUNT > 0
					BEGIN;
						INSERT @blockers
						(
							session_id
						)
						SELECT TOP(@i)
							blocked
						FROM @sessions
						WHERE
							NULLIF(blocked, 0) IS NOT NULL

						EXCEPT

						SELECT TOP(@i)
							session_id
						FROM @sessions; 
						' +

						CASE
							WHEN
							(
								@get_task_info > 0
								OR @find_block_leaders = 1
							) THEN
								'IF @@ROWCOUNT > 0
								BEGIN;
									SET @blocker = 1;
									GOTO BLOCKERS;
								END; 
								'
							ELSE 
								''
						END +
					'END; 
					'
				ELSE 
					''
			END +
			'SELECT TOP(@i)
				@recursion AS recursion,
				x.session_id,
				x.request_id,
				DENSE_RANK() OVER
				(
					ORDER BY
						x.session_id
				) AS session_number,
				' +
				CASE
					WHEN @output_column_list LIKE '%|[dd hh:mm:ss.mss|]%' ESCAPE '|' THEN 
						'x.elapsed_time '
					ELSE 
						'0 '
				END + 
					'AS elapsed_time, 
					' +
				CASE
					WHEN
						(
							@output_column_list LIKE '%|[dd hh:mm:ss.mss (avg)|]%' ESCAPE '|' OR 
							@output_column_list LIKE '%|[avg_elapsed_time|]%' ESCAPE '|'
						)
						AND @recursion = 1
							THEN 
								'x.avg_elapsed_time / 1000 '
					ELSE 
						'NULL '
				END + 
					'AS avg_elapsed_time, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[physical_io|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[physical_io_delta|]%' ESCAPE '|'
							THEN 
								'x.physical_io '
					ELSE 
						'NULL '
				END + 
					'AS physical_io, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[reads|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[reads_delta|]%' ESCAPE '|'
							THEN 
								'x.reads '
					ELSE 
						'0 '
				END + 
					'AS reads, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[physical_reads|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[physical_reads_delta|]%' ESCAPE '|'
							THEN 
								'x.physical_reads '
					ELSE 
						'0 '
				END + 
					'AS physical_reads, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[writes|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[writes_delta|]%' ESCAPE '|'
							THEN 
								'x.writes '
					ELSE 
						'0 '
				END + 
					'AS writes, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[tempdb_allocations|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[tempdb_allocations_delta|]%' ESCAPE '|'
							THEN 
								'x.tempdb_allocations '
					ELSE 
						'0 '
				END + 
					'AS tempdb_allocations, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[tempdb_current|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[tempdb_current_delta|]%' ESCAPE '|'
							THEN 
								'x.tempdb_current '
					ELSE 
						'0 '
				END + 
					'AS tempdb_current, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[CPU|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[CPU_delta|]%' ESCAPE '|'
							THEN
								'x.CPU '
					ELSE
						'0 '
				END + 
					'AS CPU, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[CPU_delta|]%' ESCAPE '|'
						AND @get_task_info = 2
							THEN 
								'x.thread_CPU_snapshot '
					ELSE 
						'0 '
				END + 
					'AS thread_CPU_snapshot, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[context_switches|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[context_switches_delta|]%' ESCAPE '|'
							THEN 
								'x.context_switches '
					ELSE 
						'NULL '
				END + 
					'AS context_switches, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[used_memory|]%' ESCAPE '|'
						OR @output_column_list LIKE '%|[used_memory_delta|]%' ESCAPE '|'
							THEN 
								'x.used_memory '
					ELSE 
						'0 '
				END + 
					'AS used_memory, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[tasks|]%' ESCAPE '|'
						AND @recursion = 1
							THEN 
								'x.tasks '
					ELSE 
						'NULL '
				END + 
					'AS tasks, 
					' +
				CASE
					WHEN 
						(
							@output_column_list LIKE '%|[status|]%' ESCAPE '|' 
							OR @output_column_list LIKE '%|[sql_command|]%' ESCAPE '|'
						)
						AND @recursion = 1
							THEN 
								'x.status '
					ELSE 
						''''' '
				END + 
					'AS status, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[wait_info|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								CASE @get_task_info
									WHEN 2 THEN
										'COALESCE(x.task_wait_info, x.sys_wait_info) '
									ELSE
										'x.sys_wait_info '
								END
					ELSE 
						'NULL '
				END + 
					'AS wait_info, 
					' +
				CASE
					WHEN 
						(
							@output_column_list LIKE '%|[tran_start_time|]%' ESCAPE '|' 
							OR @output_column_list LIKE '%|[tran_log_writes|]%' ESCAPE '|' 
						)
						AND @recursion = 1
							THEN 
								'x.transaction_id '
					ELSE 
						'NULL '
				END + 
					'AS transaction_id, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[open_tran_count|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.open_tran_count '
					ELSE 
						'NULL '
				END + 
					'AS open_tran_count, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[sql_text|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.sql_handle '
					ELSE 
						'NULL '
				END + 
					'AS sql_handle, 
					' +
				CASE
					WHEN 
						(
							@output_column_list LIKE '%|[sql_text|]%' ESCAPE '|' 
							OR @output_column_list LIKE '%|[query_plan|]%' ESCAPE '|' 
						)
						AND @recursion = 1
							THEN 
								'x.statement_start_offset '
					ELSE 
						'NULL '
				END + 
					'AS statement_start_offset, 
					' +
				CASE
					WHEN 
						(
							@output_column_list LIKE '%|[sql_text|]%' ESCAPE '|' 
							OR @output_column_list LIKE '%|[query_plan|]%' ESCAPE '|' 
						)
						AND @recursion = 1
							THEN 
								'x.statement_end_offset '
					ELSE 
						'NULL '
				END + 
					'AS statement_end_offset, 
					' +
				'NULL AS sql_text, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[query_plan|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.plan_handle '
					ELSE 
						'NULL '
				END + 
					'AS plan_handle, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[blocking_session_id|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'NULLIF(x.blocking_session_id, 0) '
					ELSE 
						'NULL '
				END + 
					'AS blocking_session_id, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[percent_complete|]%' ESCAPE '|'
						AND @recursion = 1
							THEN 
								'x.percent_complete '
					ELSE 
						'NULL '
				END + 
					'AS percent_complete, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[host_name|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.host_name '
					ELSE 
						''''' '
				END + 
					'AS host_name, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[login_name|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.login_name '
					ELSE 
						''''' '
				END + 
					'AS login_name, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[database_name|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'DB_NAME(x.database_id) '
					ELSE 
						'NULL '
				END + 
					'AS database_name, 
					' +
				CASE
					WHEN 
						@output_column_list LIKE '%|[program_name|]%' ESCAPE '|' 
						AND @recursion = 1
							THEN 
								'x.program_name '
					ELSE 
						''''' '
				END + 
					'AS program_name, 
					' +
				CASE
					WHEN
						@output_column_list LIKE '%|[additional_info|]%' ESCAPE '|'
						AND @recursion = 1
							THEN
								'(
									SELECT TOP(@i)
										x.text_size,
										x.language,
										x.date_format,
										x.date_first,
										CASE x.quoted_identifier
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS quoted_identifier,
										CASE x.arithabort
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS arithabort,
										CASE x.ansi_null_dflt_on
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS ansi_null_dflt_on,
										CASE x.ansi_defaults
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS ansi_defaults,
										CASE x.ansi_warnings
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS ansi_warnings,
										CASE x.ansi_padding
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS ansi_padding,
										CASE ansi_nulls
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS ansi_nulls,
										CASE x.concat_null_yields_null
											WHEN 0 THEN ''OFF''
											WHEN 1 THEN ''ON''
										END AS concat_null_yields_null,
										CASE x.transaction_isolation_level
											WHEN 0 THEN ''Unspecified''
											WHEN 1 THEN ''ReadUncomitted''
											WHEN 2 THEN ''ReadCommitted''
											WHEN 3 THEN ''Repeatable''
											WHEN 4 THEN ''Serializable''
											WHEN 5 THEN ''Snapshot''
										END AS transaction_isolation_level,
										x.lock_timeout,
										x.deadlock_priority,
										x.row_count,
										x.command_type, 
										' +
										CASE
											WHEN @output_column_list LIKE '%|[program_name|]%' ESCAPE '|' THEN
												'(
													SELECT TOP(1)
														CONVERT(uniqueidentifier, CONVERT(XML, '''').value(''xs:hexBinary( substring(sql:column("agent_info.job_id_string"), 0) )'', ''binary(16)'')) AS job_id,
														agent_info.step_id,
														(
															SELECT TOP(1)
																NULL
															FOR XML
																PATH(''job_name''),
																TYPE
														),
														(
															SELECT TOP(1)
																NULL
															FOR XML
																PATH(''step_name''),
																TYPE
														)
													FROM
													(
														SELECT TOP(1)
															SUBSTRING(x.program_name, CHARINDEX(''0x'', x.program_name) + 2, 32) AS job_id_string,
															SUBSTRING(x.program_name, CHARINDEX('': Step '', x.program_name) + 7, CHARINDEX('')'', x.program_name, CHARINDEX('': Step '', x.program_name)) - (CHARINDEX('': Step '', x.program_name) + 7)) AS step_id
														WHERE
															x.program_name LIKE N''SQLAgent - TSQL JobStep (Job 0x%''
													) AS agent_info
													FOR XML
														PATH(''agent_job_info''),
														TYPE
												),
												'
											ELSE ''
										END +
										CASE
											WHEN @get_task_info = 2 THEN
												'CONVERT(XML, x.block_info) AS block_info, 
												'
											ELSE
												''
										END +
										'x.host_process_id 
									FOR XML
										PATH(''additional_info''),
										TYPE
								) '
					ELSE
						'NULL '
				END + 
					'AS additional_info, 
				x.start_time, 
					' +
				CASE
					WHEN
						@output_column_list LIKE '%|[login_time|]%' ESCAPE '|'
						AND @recursion = 1
							THEN
								'x.login_time '
					ELSE 
						'NULL '
				END + 
					'AS login_time, 
				x.last_request_start_time
			FROM
			(
				SELECT TOP(@i)
					y.*,
					CASE
						WHEN DATEDIFF(day, y.start_time, GETDATE()) > 24 THEN
							DATEDIFF(second, GETDATE(), y.start_time)
						ELSE DATEDIFF(ms, y.start_time, GETDATE())
					END AS elapsed_time,
					COALESCE(tempdb_info.tempdb_allocations, 0) AS tempdb_allocations,
					COALESCE
					(
						CASE
							WHEN tempdb_info.tempdb_current < 0 THEN 0
							ELSE tempdb_info.tempdb_current
						END,
						0
					) AS tempdb_current, 
					' +
					CASE
						WHEN 
							(
								@get_task_info <> 0
								OR @find_block_leaders = 1
							) THEN
								'N''('' + CONVERT(NVARCHAR, y.wait_duration_ms) + N''ms)'' +
									y.wait_type +
										CASE
											WHEN y.wait_type LIKE N''PAGE%LATCH_%'' THEN
												N'':'' +
												COALESCE(DB_NAME(CONVERT(INT, LEFT(y.resource_description, CHARINDEX(N'':'', y.resource_description) - 1))), N''(null)'') +
												N'':'' +
												SUBSTRING(y.resource_description, CHARINDEX(N'':'', y.resource_description) + 1, LEN(y.resource_description) - CHARINDEX(N'':'', REVERSE(y.resource_description)) - CHARINDEX(N'':'', y.resource_description)) +
												N''('' +
													CASE
														WHEN
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) = 1 OR
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) % 8088 = 0
																THEN 
																	N''PFS''
														WHEN
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) = 2 OR
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) % 511232 = 0
																THEN 
																	N''GAM''
														WHEN
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) = 3 OR
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) % 511233 = 0
																THEN
																	N''SGAM''
														WHEN
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) = 6 OR
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) % 511238 = 0 
																THEN 
																	N''DCM''
														WHEN
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) = 7 OR
															CONVERT(INT, RIGHT(y.resource_description, CHARINDEX(N'':'', REVERSE(y.resource_description)) - 1)) % 511239 = 0 
																THEN 
																	N''BCM''
														ELSE 
															N''*''
													END +
												N'')''
											WHEN y.wait_type = N''CXPACKET'' THEN
												N'':'' + SUBSTRING(y.resource_description, CHARINDEX(N''nodeId'', y.resource_description) + 7, 4)
											WHEN y.wait_type LIKE N''LATCH[_]%'' THEN
												N'' ['' + LEFT(y.resource_description, COALESCE(NULLIF(CHARINDEX(N'' '', y.resource_description), 0), LEN(y.resource_description) + 1) - 1) + N'']''
											WHEN
												y.wait_type = N''OLEDB''
												AND y.resource_description LIKE N''%(SPID=%)'' THEN
													N''['' + LEFT(y.resource_description, CHARINDEX(N''(SPID='', y.resource_description) - 2) +
														N'':'' + SUBSTRING(y.resource_description, CHARINDEX(N''(SPID='', y.resource_description) + 6, CHARINDEX(N'')'', y.resource_description, (CHARINDEX(N''(SPID='', y.resource_description) + 6)) - (CHARINDEX(N''(SPID='', y.resource_description) + 6)) + '']''
											ELSE
												N''''
										END COLLATE Latin1_General_Bin2 AS sys_wait_info, 
										'
							ELSE
								''
						END +
						CASE
							WHEN @get_task_info = 2 THEN
								'tasks.physical_io,
								tasks.context_switches,
								tasks.tasks,
								tasks.block_info,
								tasks.wait_info AS task_wait_info,
								tasks.thread_CPU_snapshot,
								'
							ELSE
								'' 
					END +
					CASE 
						WHEN NOT (@get_avg_time = 1 AND @recursion = 1) THEN
							'CONVERT(INT, NULL) '
						ELSE 
							'qs.total_elapsed_time / qs.execution_count '
					END + 
						'AS avg_elapsed_time 
				FROM
				(
					SELECT TOP(@i)
						sp.session_id,
						sp.request_id,
						COALESCE(r.logical_reads, s.logical_reads) AS reads,
						COALESCE(r.reads, s.reads) AS physical_reads,
						COALESCE(r.writes, s.writes) AS writes,
						COALESCE(r.CPU_time, s.CPU_time) AS CPU,
						sp.memory_usage + COALESCE(r.granted_query_memory, 0) AS used_memory,
						LOWER(sp.status) AS status,
						COALESCE(r.sql_handle, sp.sql_handle) AS sql_handle,
						COALESCE(r.statement_start_offset, sp.statement_start_offset) AS statement_start_offset,
						COALESCE(r.statement_end_offset, sp.statement_end_offset) AS statement_end_offset,
						' +
						CASE
							WHEN 
							(
								@get_task_info <> 0
								OR @find_block_leaders = 1 
							) THEN
								'sp.wait_type COLLATE Latin1_General_Bin2 AS wait_type,
								sp.wait_resource COLLATE Latin1_General_Bin2 AS resource_description,
								sp.wait_time AS wait_duration_ms, 
								'
							ELSE
								''
						END +
						'NULLIF(sp.blocked, 0) AS blocking_session_id,
						r.plan_handle,
						NULLIF(r.percent_complete, 0) AS percent_complete,
						sp.host_name,
						sp.login_name,
						sp.program_name,
						s.host_process_id,
						COALESCE(r.text_size, s.text_size) AS text_size,
						COALESCE(r.language, s.language) AS language,
						COALESCE(r.date_format, s.date_format) AS date_format,
						COALESCE(r.date_first, s.date_first) AS date_first,
						COALESCE(r.quoted_identifier, s.quoted_identifier) AS quoted_identifier,
						COALESCE(r.arithabort, s.arithabort) AS arithabort,
						COALESCE(r.ansi_null_dflt_on, s.ansi_null_dflt_on) AS ansi_null_dflt_on,
						COALESCE(r.ansi_defaults, s.ansi_defaults) AS ansi_defaults,
						COALESCE(r.ansi_warnings, s.ansi_warnings) AS ansi_warnings,
						COALESCE(r.ansi_padding, s.ansi_padding) AS ansi_padding,
						COALESCE(r.ansi_nulls, s.ansi_nulls) AS ansi_nulls,
						COALESCE(r.concat_null_yields_null, s.concat_null_yields_null) AS concat_null_yields_null,
						COALESCE(r.transaction_isolation_level, s.transaction_isolation_level) AS transaction_isolation_level,
						COALESCE(r.lock_timeout, s.lock_timeout) AS lock_timeout,
						COALESCE(r.deadlock_priority, s.deadlock_priority) AS deadlock_priority,
						COALESCE(r.row_count, s.row_count) AS row_count,
						COALESCE(r.command, sp.cmd) AS command_type,
						COALESCE
						(
							CASE
								WHEN
								(
									s.is_user_process = 0
									AND r.total_elapsed_time >= 0
								) THEN
									DATEADD
									(
										ms,
										1000 * (DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())) / 500) - DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())),
										DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())
									)
							END,
							NULLIF(COALESCE(r.start_time, sp.last_request_end_time), CONVERT(DATETIME, ''19000101'', 112)),
							(
								SELECT TOP(1)
									DATEADD(second, -(ms_ticks / 1000), GETDATE())
								FROM sys.dm_os_sys_info
							)
						) AS start_time,
						sp.login_time,
						CASE
							WHEN s.is_user_process = 1 THEN
								s.last_request_start_time
							ELSE
								COALESCE
								(
									DATEADD
									(
										ms,
										1000 * (DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())) / 500) - DATEPART(ms, DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())),
										DATEADD(second, -(r.total_elapsed_time / 1000), GETDATE())
									),
									s.last_request_start_time
								)
						END AS last_request_start_time,
						r.transaction_id,
						sp.database_id,
						sp.open_tran_count
					FROM @sessions AS sp
					LEFT OUTER LOOP JOIN sys.dm_exec_sessions AS s ON
						s.session_id = sp.session_id
						AND s.login_time = sp.login_time
					LEFT OUTER LOOP JOIN sys.dm_exec_requests AS r ON
						sp.status <> ''sleeping''
						AND r.session_id = sp.session_id
						AND r.request_id = sp.request_id
						AND
						(
							(
								s.is_user_process = 0
								AND sp.is_user_process = 0
							)
							OR
							(
								r.start_time = s.last_request_start_time
								AND s.last_request_end_time = sp.last_request_end_time
							)
						)
				) AS y
				' + 
				CASE 
					WHEN @get_task_info = 2 THEN
						CONVERT(VARCHAR(MAX), '') +
						'LEFT OUTER HASH JOIN
						(
							SELECT TOP(@i)
								task_nodes.task_node.value(''(session_id/text())[1]'', ''SMALLINT'') AS session_id,
								task_nodes.task_node.value(''(request_id/text())[1]'', ''INT'') AS request_id,
								task_nodes.task_node.value(''(physical_io/text())[1]'', ''BIGINT'') AS physical_io,
								task_nodes.task_node.value(''(context_switches/text())[1]'', ''BIGINT'') AS context_switches,
								task_nodes.task_node.value(''(tasks/text())[1]'', ''INT'') AS tasks,
								task_nodes.task_node.value(''(block_info/text())[1]'', ''NVARCHAR(4000)'') AS block_info,
								task_nodes.task_node.value(''(waits/text())[1]'', ''NVARCHAR(4000)'') AS wait_info,
								task_nodes.task_node.value(''(thread_CPU_snapshot/text())[1]'', ''BIGINT'') AS thread_CPU_snapshot
							FROM
							(
								SELECT TOP(@i)
									CONVERT
									(
										XML,
										REPLACE
										(
											CONVERT(NVARCHAR(MAX), tasks_raw.task_xml_raw) COLLATE Latin1_General_Bin2,
											N''</waits></tasks><tasks><waits>'',
											N'', ''
										)
									) AS task_xml
								FROM
								(
									SELECT TOP(@i)
										CASE waits.r
											WHEN 1 THEN
												waits.session_id
											ELSE
												NULL
										END AS [session_id],
										CASE waits.r
											WHEN 1 THEN
												waits.request_id
											ELSE
												NULL
										END AS [request_id],											
										CASE waits.r
											WHEN 1 THEN
												waits.physical_io
											ELSE
												NULL
										END AS [physical_io],
										CASE waits.r
											WHEN 1 THEN
												waits.context_switches
											ELSE
												NULL
										END AS [context_switches],
										CASE waits.r
											WHEN 1 THEN
												waits.thread_CPU_snapshot
											ELSE
												NULL
										END AS [thread_CPU_snapshot],
										CASE waits.r
											WHEN 1 THEN
												waits.tasks
											ELSE
												NULL
										END AS [tasks],
										CASE waits.r
											WHEN 1 THEN
												waits.block_info
											ELSE
												NULL
										END AS [block_info],
										REPLACE
										(
											REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
											REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
											REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
												CONVERT
												(
													NVARCHAR(MAX),
													N''('' +
														CONVERT(NVARCHAR, num_waits) + N''x: '' +
														CASE num_waits
															WHEN 1 THEN
																CONVERT(NVARCHAR, min_wait_time) + N''ms''
															WHEN 2 THEN
																CASE
																	WHEN min_wait_time <> max_wait_time THEN
																		CONVERT(NVARCHAR, min_wait_time) + N''/'' + CONVERT(NVARCHAR, max_wait_time) + N''ms''
																	ELSE
																		CONVERT(NVARCHAR, max_wait_time) + N''ms''
																END
															ELSE
																CASE
																	WHEN min_wait_time <> max_wait_time THEN
																		CONVERT(NVARCHAR, min_wait_time) + N''/'' + CONVERT(NVARCHAR, avg_wait_time) + N''/'' + CONVERT(NVARCHAR, max_wait_time) + N''ms''
																	ELSE 
																		CONVERT(NVARCHAR, max_wait_time) + N''ms''
																END
														END +
													N'')'' + wait_type COLLATE Latin1_General_Bin2
												),
												NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
												NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
												NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),
											NCHAR(0),
											N''''
										) AS [waits]
									FROM
									(
										SELECT TOP(@i)
											w1.*,
											ROW_NUMBER() OVER
											(
												PARTITION BY
													w1.session_id,
													w1.request_id
												ORDER BY
													w1.block_info DESC,
													w1.num_waits DESC,
													w1.wait_type
											) AS r
										FROM
										(
											SELECT TOP(@i)
												task_info.session_id,
												task_info.request_id,
												task_info.physical_io,
												task_info.context_switches,
												task_info.thread_CPU_snapshot,
												task_info.num_tasks AS tasks,
												CASE
													WHEN task_info.runnable_time IS NOT NULL THEN
														''RUNNABLE''
													ELSE
														wt2.wait_type
												END AS wait_type,
												NULLIF(COUNT(COALESCE(task_info.runnable_time, wt2.waiting_task_address)), 0) AS num_waits,
												MIN(COALESCE(task_info.runnable_time, wt2.wait_duration_ms)) AS min_wait_time,
												AVG(COALESCE(task_info.runnable_time, wt2.wait_duration_ms)) AS avg_wait_time,
												MAX(COALESCE(task_info.runnable_time, wt2.wait_duration_ms)) AS max_wait_time,
												MAX(wt2.block_info) AS block_info
											FROM
											(
												SELECT TOP(@i)
													t.session_id,
													t.request_id,
													SUM(CONVERT(BIGINT, t.pending_io_count)) OVER (PARTITION BY t.session_id, t.request_id) AS physical_io,
													SUM(CONVERT(BIGINT, t.context_switches_count)) OVER (PARTITION BY t.session_id, t.request_id) AS context_switches, 
													' +
													CASE
														WHEN @output_column_list LIKE '%|[CPU_delta|]%' ESCAPE '|'
															THEN
																'SUM(tr.usermode_time + tr.kernel_time) OVER (PARTITION BY t.session_id, t.request_id) '
														ELSE
															'CONVERT(BIGINT, NULL) '
													END + 
														' AS thread_CPU_snapshot, 
													COUNT(*) OVER (PARTITION BY t.session_id, t.request_id) AS num_tasks,
													t.task_address,
													t.task_state,
													CASE
														WHEN
															t.task_state = ''RUNNABLE''
															AND w.runnable_time > 0 THEN
																w.runnable_time
														ELSE
															NULL
													END AS runnable_time
												FROM sys.dm_os_tasks AS t
												CROSS APPLY
												(
													SELECT TOP(1)
														sp2.session_id
													FROM @sessions AS sp2
													WHERE
														sp2.session_id = t.session_id
														AND sp2.request_id = t.request_id
														AND sp2.status <> ''sleeping''
												) AS sp20
												LEFT OUTER HASH JOIN
												(
													SELECT TOP(@i)
														(
															SELECT TOP(@i)
																ms_ticks
															FROM sys.dm_os_sys_info
														) -
															w0.wait_resumed_ms_ticks AS runnable_time,
														w0.worker_address,
														w0.thread_address,
														w0.task_bound_ms_ticks
													FROM sys.dm_os_workers AS w0
													WHERE
														w0.state = ''RUNNABLE''
														OR @first_collection_ms_ticks >= w0.task_bound_ms_ticks
												) AS w ON
													w.worker_address = t.worker_address 
												' +
												CASE
													WHEN @output_column_list LIKE '%|[CPU_delta|]%' ESCAPE '|'
														THEN
															'LEFT OUTER HASH JOIN sys.dm_os_threads AS tr ON
																tr.thread_address = w.thread_address
																AND @first_collection_ms_ticks >= w.task_bound_ms_ticks
															'
													ELSE
														''
												END +
											') AS task_info
											LEFT OUTER HASH JOIN
											(
												SELECT TOP(@i)
													wt1.wait_type,
													wt1.waiting_task_address,
													MAX(wt1.wait_duration_ms) AS wait_duration_ms,
													MAX(wt1.block_info) AS block_info
												FROM
												(
													SELECT DISTINCT TOP(@i)
														wt.wait_type +
															CASE
																WHEN wt.wait_type LIKE N''PAGE%LATCH_%'' THEN
																	'':'' +
																	COALESCE(DB_NAME(CONVERT(INT, LEFT(wt.resource_description, CHARINDEX(N'':'', wt.resource_description) - 1))), N''(null)'') +
																	N'':'' +
																	SUBSTRING(wt.resource_description, CHARINDEX(N'':'', wt.resource_description) + 1, LEN(wt.resource_description) - CHARINDEX(N'':'', REVERSE(wt.resource_description)) - CHARINDEX(N'':'', wt.resource_description)) +
																	N''('' +
																		CASE
																			WHEN
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) = 1 OR
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) % 8088 = 0
																					THEN 
																						N''PFS''
																			WHEN
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) = 2 OR
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) % 511232 = 0 
																					THEN 
																						N''GAM''
																			WHEN
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) = 3 OR
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) % 511233 = 0 
																					THEN 
																						N''SGAM''
																			WHEN
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) = 6 OR
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) % 511238 = 0 
																					THEN 
																						N''DCM''
																			WHEN
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) = 7 OR
																				CONVERT(INT, RIGHT(wt.resource_description, CHARINDEX(N'':'', REVERSE(wt.resource_description)) - 1)) % 511239 = 0
																					THEN 
																						N''BCM''
																			ELSE
																				N''*''
																		END +
																	N'')''
																WHEN wt.wait_type = N''CXPACKET'' THEN
																	N'':'' + SUBSTRING(wt.resource_description, CHARINDEX(N''nodeId'', wt.resource_description) + 7, 4)
																WHEN wt.wait_type LIKE N''LATCH[_]%'' THEN
																	N'' ['' + LEFT(wt.resource_description, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description), 0), LEN(wt.resource_description) + 1) - 1) + N'']''
																ELSE 
																	N''''
															END COLLATE Latin1_General_Bin2 AS wait_type,
														CASE
															WHEN
															(
																wt.blocking_session_id IS NOT NULL
																AND wt.wait_type LIKE N''LCK[_]%''
															) THEN
																(
																	SELECT TOP(@i)
																		x.lock_type,
																		REPLACE
																		(
																			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
																			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
																			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
																				DB_NAME
																				(
																					CONVERT
																					(
																						INT,
																						SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''dbid='', wt.resource_description), 0) + 5, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''dbid='', wt.resource_description) + 5), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''dbid='', wt.resource_description) - 5)
																					)
																				),
																				NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
																				NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
																				NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),
																			NCHAR(0),
																			N''''
																		) AS database_name,
																		CASE x.lock_type
																			WHEN N''objectlock'' THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''objid='', wt.resource_description), 0) + 6, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''objid='', wt.resource_description) + 6), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''objid='', wt.resource_description) - 6)
																			ELSE
																				NULL
																		END AS object_id,
																		CASE x.lock_type
																			WHEN N''filelock'' THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''fileid='', wt.resource_description), 0) + 7, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''fileid='', wt.resource_description) + 7), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''fileid='', wt.resource_description) - 7)
																			ELSE
																				NULL
																		END AS file_id,
																		CASE
																			WHEN x.lock_type in (N''pagelock'', N''extentlock'', N''ridlock'') THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''associatedObjectId='', wt.resource_description), 0) + 19, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''associatedObjectId='', wt.resource_description) + 19), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''associatedObjectId='', wt.resource_description) - 19)
																			WHEN x.lock_type in (N''keylock'', N''hobtlock'', N''allocunitlock'') THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''hobtid='', wt.resource_description), 0) + 7, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''hobtid='', wt.resource_description) + 7), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''hobtid='', wt.resource_description) - 7)
																			ELSE
																				NULL
																		END AS hobt_id,
																		CASE x.lock_type
																			WHEN N''applicationlock'' THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''hash='', wt.resource_description), 0) + 5, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''hash='', wt.resource_description) + 5), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''hash='', wt.resource_description) - 5)
																			ELSE
																				NULL
																		END AS applock_hash,
																		CASE x.lock_type
																			WHEN N''metadatalock'' THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''subresource='', wt.resource_description), 0) + 12, COALESCE(NULLIF(CHARINDEX(N'' '', wt.resource_description, CHARINDEX(N''subresource='', wt.resource_description) + 12), 0), LEN(wt.resource_description) + 1) - CHARINDEX(N''subresource='', wt.resource_description) - 12)
																			ELSE
																				NULL
																		END AS metadata_resource,
																		CASE x.lock_type
																			WHEN N''metadatalock'' THEN
																				SUBSTRING(wt.resource_description, NULLIF(CHARINDEX(N''classid='', wt.resource_description), 0) + 8, COALESCE(NULLIF(CHARINDEX(N'' dbid='', wt.resource_description) - CHARINDEX(N''classid='', wt.resource_description), 0), LEN(wt.resource_description) + 1) - 8)
																			ELSE
																				NULL
																		END AS metadata_class_id
																	FROM
																	(
																		SELECT TOP(1)
																			LEFT(wt.resource_description, CHARINDEX(N'' '', wt.resource_description) - 1) COLLATE Latin1_General_Bin2 AS lock_type
																	) AS x
																	FOR XML
																		PATH('''')
																)
															ELSE NULL
														END AS block_info,
														wt.wait_duration_ms,
														wt.waiting_task_address
													FROM
													(
														SELECT TOP(@i)
															wt0.wait_type COLLATE Latin1_General_Bin2 AS wait_type,
															wt0.resource_description COLLATE Latin1_General_Bin2 AS resource_description,
															wt0.wait_duration_ms,
															wt0.waiting_task_address,
															CASE
																WHEN wt0.blocking_session_id = p.blocked THEN
																	wt0.blocking_session_id
																ELSE
																	NULL
															END AS blocking_session_id
														FROM sys.dm_os_waiting_tasks AS wt0
														CROSS APPLY
														(
															SELECT TOP(1)
																s0.blocked
															FROM @sessions AS s0
															WHERE
																s0.session_id = wt0.session_id
																AND COALESCE(s0.wait_type, N'''') <> N''OLEDB''
																AND wt0.wait_type <> N''OLEDB''
														) AS p
													) AS wt
												) AS wt1
												GROUP BY
													wt1.wait_type,
													wt1.waiting_task_address
											) AS wt2 ON
												wt2.waiting_task_address = task_info.task_address
												AND wt2.wait_duration_ms > 0
												AND task_info.runnable_time IS NULL
											GROUP BY
												task_info.session_id,
												task_info.request_id,
												task_info.physical_io,
												task_info.context_switches,
												task_info.thread_CPU_snapshot,
												task_info.num_tasks,
												CASE
													WHEN task_info.runnable_time IS NOT NULL THEN
														''RUNNABLE''
													ELSE
														wt2.wait_type
												END
										) AS w1
									) AS waits
									ORDER BY
										waits.session_id,
										waits.request_id,
										waits.r
									FOR XML
										PATH(N''tasks''),
										TYPE
								) AS tasks_raw (task_xml_raw)
							) AS tasks_final
							CROSS APPLY tasks_final.task_xml.nodes(N''/tasks'') AS task_nodes (task_node)
							WHERE
								task_nodes.task_node.exist(N''session_id'') = 1
						) AS tasks ON
							tasks.session_id = y.session_id
							AND tasks.request_id = y.request_id 
						'
					ELSE
						''
				END +
				'LEFT OUTER HASH JOIN
				(
					SELECT TOP(@i)
						t_info.session_id,
						COALESCE(t_info.request_id, -1) AS request_id,
						SUM(t_info.tempdb_allocations) AS tempdb_allocations,
						SUM(t_info.tempdb_current) AS tempdb_current
					FROM
					(
						SELECT TOP(@i)
							tsu.session_id,
							tsu.request_id,
							tsu.user_objects_alloc_page_count +
								tsu.internal_objects_alloc_page_count AS tempdb_allocations,
							tsu.user_objects_alloc_page_count +
								tsu.internal_objects_alloc_page_count -
								tsu.user_objects_dealloc_page_count -
								tsu.internal_objects_dealloc_page_count AS tempdb_current
						FROM sys.dm_db_task_space_usage AS tsu
						CROSS APPLY
						(
							SELECT TOP(1)
								s0.session_id
							FROM @sessions AS s0
							WHERE
								s0.session_id = tsu.session_id
						) AS p

						UNION ALL

						SELECT TOP(@i)
							ssu.session_id,
							NULL AS request_id,
							ssu.user_objects_alloc_page_count +
								ssu.internal_objects_alloc_page_count AS tempdb_allocations,
							ssu.user_objects_alloc_page_count +
								ssu.internal_objects_alloc_page_count -
								ssu.user_objects_dealloc_page_count -
								ssu.internal_objects_dealloc_page_count AS tempdb_current
						FROM sys.dm_db_session_space_usage AS ssu
						CROSS APPLY
						(
							SELECT TOP(1)
								s0.session_id
							FROM @sessions AS s0
							WHERE
								s0.session_id = ssu.session_id
						) AS p
					) AS t_info
					GROUP BY
						t_info.session_id,
						COALESCE(t_info.request_id, -1)
				) AS tempdb_info ON
					tempdb_info.session_id = y.session_id
					AND tempdb_info.request_id =
						CASE
							WHEN y.status = N''sleeping'' THEN
								-1
							ELSE
								y.request_id
						END
				' +
				CASE 
					WHEN 
						NOT 
						(
							@get_avg_time = 1 
							AND @recursion = 1
						) THEN 
							''
					ELSE
						'LEFT OUTER HASH JOIN
						(
							SELECT TOP(@i)
								*
							FROM sys.dm_exec_query_stats
						) AS qs ON
							qs.sql_handle = y.sql_handle
							AND qs.plan_handle = y.plan_handle
							AND qs.statement_start_offset = y.statement_start_offset
							AND qs.statement_end_offset = y.statement_end_offset
						'
				END + 
			') AS x
			OPTION (KEEPFIXED PLAN, OPTIMIZE FOR (@i = 1)); ';

		SET @sql_n = CONVERT(NVARCHAR(MAX), @sql);

		SET @last_collection_start = GETDATE();

		IF @recursion = -1
		BEGIN;
			SELECT
				@first_collection_ms_ticks = ms_ticks
			FROM sys.dm_os_sys_info;
		END;

		INSERT #sessions
		(
			recursion,
			session_id,
			request_id,
			session_number,
			elapsed_time,
			avg_elapsed_time,
			physical_io,
			reads,
			physical_reads,
			writes,
			tempdb_allocations,
			tempdb_current,
			CPU,
			thread_CPU_snapshot,
			context_switches,
			used_memory,
			tasks,
			status,
			wait_info,
			transaction_id,
			open_tran_count,
			sql_handle,
			statement_start_offset,
			statement_end_offset,		
			sql_text,
			plan_handle,
			blocking_session_id,
			percent_complete,
			host_name,
			login_name,
			database_name,
			program_name,
			additional_info,
			start_time,
			login_time,
			last_request_start_time
		)
		EXEC sp_executesql 
			@sql_n,
			N'@recursion SMALLINT, @filter sysname, @not_filter sysname, @first_collection_ms_ticks BIGINT',
			@recursion, @filter, @not_filter, @first_collection_ms_ticks;

		--Collect transaction information?
		IF
			@recursion = 1
			AND
			(
				@output_column_list LIKE '%|[tran_start_time|]%' ESCAPE '|'
				OR @output_column_list LIKE '%|[tran_log_writes|]%' ESCAPE '|' 
			)
		BEGIN;	
			DECLARE @i INT;
			SET @i = 2147483647;

			UPDATE s
			SET
				tran_start_time =
					CONVERT
					(
						DATETIME,
						LEFT
						(
							x.trans_info,
							NULLIF(CHARINDEX(NCHAR(254) COLLATE Latin1_General_Bin2, x.trans_info) - 1, -1)
						),
						121
					),
				tran_log_writes =
					RIGHT
					(
						x.trans_info,
						LEN(x.trans_info) - CHARINDEX(NCHAR(254) COLLATE Latin1_General_Bin2, x.trans_info)
					)
			FROM
			(
				SELECT TOP(@i)
					trans_nodes.trans_node.value('(session_id/text())[1]', 'SMALLINT') AS session_id,
					COALESCE(trans_nodes.trans_node.value('(request_id/text())[1]', 'INT'), 0) AS request_id,
					trans_nodes.trans_node.value('(trans_info/text())[1]', 'NVARCHAR(4000)') AS trans_info				
				FROM
				(
					SELECT TOP(@i)
						CONVERT
						(
							XML,
							REPLACE
							(
								CONVERT(NVARCHAR(MAX), trans_raw.trans_xml_raw) COLLATE Latin1_General_Bin2, 
								N'</trans_info></trans><trans><trans_info>', N''
							)
						)
					FROM
					(
						SELECT TOP(@i)
							CASE u_trans.r
								WHEN 1 THEN u_trans.session_id
								ELSE NULL
							END AS [session_id],
							CASE u_trans.r
								WHEN 1 THEN u_trans.request_id
								ELSE NULL
							END AS [request_id],
							CONVERT
							(
								NVARCHAR(MAX),
								CASE
									WHEN u_trans.database_id IS NOT NULL THEN
										CASE u_trans.r
											WHEN 1 THEN COALESCE(CONVERT(NVARCHAR, u_trans.transaction_start_time, 121) + NCHAR(254), N'')
											ELSE N''
										END + 
											REPLACE
											(
												REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
												REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
												REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
													CONVERT(VARCHAR(128), COALESCE(DB_NAME(u_trans.database_id), N'(null)')),
													NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
													NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
													NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
												NCHAR(0),
												N'?'
											) +
											N': ' +
										CONVERT(NVARCHAR, u_trans.log_record_count) + N' (' + CONVERT(NVARCHAR, u_trans.log_kb_used) + N' kB)' +
										N','
									ELSE
										N'N/A,'
								END COLLATE Latin1_General_Bin2
							) AS [trans_info]
						FROM
						(
							SELECT TOP(@i)
								trans.*,
								ROW_NUMBER() OVER
								(
									PARTITION BY
										trans.session_id,
										trans.request_id
									ORDER BY
										trans.transaction_start_time DESC
								) AS r
							FROM
							(
								SELECT TOP(@i)
									session_tran_map.session_id,
									session_tran_map.request_id,
									s_tran.database_id,
									COALESCE(SUM(s_tran.database_transaction_log_record_count), 0) AS log_record_count,
									COALESCE(SUM(s_tran.database_transaction_log_bytes_used), 0) / 1024 AS log_kb_used,
									MIN(s_tran.database_transaction_begin_time) AS transaction_start_time
								FROM
								(
									SELECT TOP(@i)
										*
									FROM sys.dm_tran_active_transactions
									WHERE
										transaction_begin_time <= @last_collection_start
								) AS a_tran
								INNER HASH JOIN
								(
									SELECT TOP(@i)
										*
									FROM sys.dm_tran_database_transactions
									WHERE
										database_id < 32767
								) AS s_tran ON
									s_tran.transaction_id = a_tran.transaction_id
								LEFT OUTER HASH JOIN
								(
									SELECT TOP(@i)
										*
									FROM sys.dm_tran_session_transactions
								) AS tst ON
									s_tran.transaction_id = tst.transaction_id
								CROSS APPLY
								(
									SELECT TOP(1)
										s3.session_id,
										s3.request_id
									FROM
									(
										SELECT TOP(1)
											s1.session_id,
											s1.request_id
										FROM #sessions AS s1
										WHERE
											s1.transaction_id = s_tran.transaction_id
											AND s1.recursion = 1
											
										UNION ALL
									
										SELECT TOP(1)
											s2.session_id,
											s2.request_id
										FROM #sessions AS s2
										WHERE
											s2.session_id = tst.session_id
											AND s2.recursion = 1
									) AS s3
									ORDER BY
										s3.request_id
								) AS session_tran_map
								GROUP BY
									session_tran_map.session_id,
									session_tran_map.request_id,
									s_tran.database_id
							) AS trans
						) AS u_trans
						FOR XML
							PATH('trans'),
							TYPE
					) AS trans_raw (trans_xml_raw)
				) AS trans_final (trans_xml)
				CROSS APPLY trans_final.trans_xml.nodes('/trans') AS trans_nodes (trans_node)
			) AS x
			INNER HASH JOIN #sessions AS s ON
				s.session_id = x.session_id
				AND s.request_id = x.request_id
			OPTION (OPTIMIZE FOR (@i = 1));
		END;

		--Variables for text and plan collection
		DECLARE	
			@session_id SMALLINT,
			@request_id INT,
			@sql_handle VARBINARY(64),
			@plan_handle VARBINARY(64),
			@statement_start_offset INT,
			@statement_end_offset INT,
			@start_time DATETIME,
			@database_name sysname;

		IF 
			@recursion = 1
			AND @output_column_list LIKE '%|[sql_text|]%' ESCAPE '|'
		BEGIN;
			DECLARE sql_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR 
				SELECT 
					session_id,
					request_id,
					sql_handle,
					statement_start_offset,
					statement_end_offset
				FROM #sessions
				WHERE
					recursion = 1
					AND sql_handle IS NOT NULL
			OPTION (KEEPFIXED PLAN);

			OPEN sql_cursor;

			FETCH NEXT FROM sql_cursor
			INTO 
				@session_id,
				@request_id,
				@sql_handle,
				@statement_start_offset,
				@statement_end_offset;

			--Wait up to 5 ms for the SQL text, then give up
			SET LOCK_TIMEOUT 5;

			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					UPDATE s
					SET
						s.sql_text =
						(
							SELECT
								REPLACE
								(
									REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
										N'--' + NCHAR(13) + NCHAR(10) +
										CASE 
											WHEN @get_full_inner_text = 1 THEN est.text
											WHEN LEN(est.text) < (@statement_end_offset / 2) + 1 THEN est.text
											WHEN SUBSTRING(est.text, (@statement_start_offset/2), 2) LIKE N'[a-zA-Z0-9][a-zA-Z0-9]' THEN est.text
											ELSE
												CASE
													WHEN @statement_start_offset > 0 THEN
														SUBSTRING
														(
															est.text,
															((@statement_start_offset/2) + 1),
															(
																CASE
																	WHEN @statement_end_offset = -1 THEN 2147483647
																	ELSE ((@statement_end_offset - @statement_start_offset)/2) + 1
																END
															)
														)
													ELSE RTRIM(LTRIM(est.text))
												END
										END +
										NCHAR(13) + NCHAR(10) + N'--' COLLATE Latin1_General_Bin2,
										NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
										NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
										NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
									NCHAR(0),
									N''
								) AS [processing-instruction(query)]
							FOR XML
								PATH(''),
								TYPE
						),
						s.statement_start_offset = 
							CASE 
								WHEN LEN(est.text) < (@statement_end_offset / 2) + 1 THEN 0
								WHEN SUBSTRING(CONVERT(VARCHAR(MAX), est.text), (@statement_start_offset/2), 2) LIKE '[a-zA-Z0-9][a-zA-Z0-9]' THEN 0
								ELSE @statement_start_offset
							END,
						s.statement_end_offset = 
							CASE 
								WHEN LEN(est.text) < (@statement_end_offset / 2) + 1 THEN -1
								WHEN SUBSTRING(CONVERT(VARCHAR(MAX), est.text), (@statement_start_offset/2), 2) LIKE '[a-zA-Z0-9][a-zA-Z0-9]' THEN -1
								ELSE @statement_end_offset
							END
					FROM 
						#sessions AS s,
						(
							SELECT TOP(1)
								text
							FROM
							(
								SELECT 
									text, 
									0 AS row_num
								FROM sys.dm_exec_sql_text(@sql_handle)
								
								UNION ALL
								
								SELECT 
									NULL,
									1 AS row_num
							) AS est0
							ORDER BY
								row_num
						) AS est
					WHERE 
						s.session_id = @session_id
						AND s.request_id = @request_id
						AND s.recursion = 1
					OPTION (KEEPFIXED PLAN);
				END TRY
				BEGIN CATCH;
					UPDATE s
					SET
						s.sql_text = 
							CASE ERROR_NUMBER() 
								WHEN 1222 THEN '<timeout_exceeded />'
								ELSE '<error message="' + ERROR_MESSAGE() + '" />'
							END
					FROM #sessions AS s
					WHERE 
						s.session_id = @session_id
						AND s.request_id = @request_id
						AND s.recursion = 1
					OPTION (KEEPFIXED PLAN);
				END CATCH;

				FETCH NEXT FROM sql_cursor
				INTO
					@session_id,
					@request_id,
					@sql_handle,
					@statement_start_offset,
					@statement_end_offset;
			END;

			--Return this to the default
			SET LOCK_TIMEOUT -1;

			CLOSE sql_cursor;
			DEALLOCATE sql_cursor;
		END;

		IF 
			@get_outer_command = 1 
			AND @recursion = 1
			AND @output_column_list LIKE '%|[sql_command|]%' ESCAPE '|'
		BEGIN;
			DECLARE @buffer_results TABLE
			(
				EventType VARCHAR(30),
				Parameters INT,
				EventInfo NVARCHAR(4000),
				start_time DATETIME,
				session_number INT IDENTITY(1,1) NOT NULL PRIMARY KEY
			);

			DECLARE buffer_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR 
				SELECT 
					session_id,
					MAX(start_time) AS start_time
				FROM #sessions
				WHERE
					recursion = 1
				GROUP BY
					session_id
				ORDER BY
					session_id
				OPTION (KEEPFIXED PLAN);

			OPEN buffer_cursor;

			FETCH NEXT FROM buffer_cursor
			INTO 
				@session_id,
				@start_time;

			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					--In SQL Server 2008, DBCC INPUTBUFFER will throw 
					--an exception if the session no longer exists
					INSERT @buffer_results
					(
						EventType,
						Parameters,
						EventInfo
					)
					EXEC sp_executesql
						N'DBCC INPUTBUFFER(@session_id) WITH NO_INFOMSGS;',
						N'@session_id SMALLINT',
						@session_id;

					UPDATE br
					SET
						br.start_time = @start_time
					FROM @buffer_results AS br
					WHERE
						br.session_number = 
						(
							SELECT MAX(br2.session_number)
							FROM @buffer_results br2
						);
				END TRY
				BEGIN CATCH
				END CATCH;

				FETCH NEXT FROM buffer_cursor
				INTO 
					@session_id,
					@start_time;
			END;

			UPDATE s
			SET
				sql_command = 
				(
					SELECT 
						REPLACE
						(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								CONVERT
								(
									NVARCHAR(MAX),
									N'--' + NCHAR(13) + NCHAR(10) + br.EventInfo + NCHAR(13) + NCHAR(10) + N'--' COLLATE Latin1_General_Bin2
								),
								NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
								NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
								NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
							NCHAR(0),
							N''
						) AS [processing-instruction(query)]
					FROM @buffer_results AS br
					WHERE 
						br.session_number = s.session_number
						AND br.start_time = s.start_time
						AND 
						(
							(
								s.start_time = s.last_request_start_time
								AND EXISTS
								(
									SELECT *
									FROM sys.dm_exec_requests r2
									WHERE
										r2.session_id = s.session_id
										AND r2.request_id = s.request_id
										AND r2.start_time = s.start_time
								)
							)
							OR 
							(
								s.request_id = 0
								AND EXISTS
								(
									SELECT *
									FROM sys.dm_exec_sessions s2
									WHERE
										s2.session_id = s.session_id
										AND s2.last_request_start_time = s.last_request_start_time
								)
							)
						)
					FOR XML
						PATH(''),
						TYPE
				)
			FROM #sessions AS s
			WHERE
				recursion = 1
			OPTION (KEEPFIXED PLAN);

			CLOSE buffer_cursor;
			DEALLOCATE buffer_cursor;
		END;

		IF 
			@get_plans >= 1 
			AND @recursion = 1
			AND @output_column_list LIKE '%|[query_plan|]%' ESCAPE '|'
		BEGIN;
			DECLARE plan_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR 
				SELECT
					session_id,
					request_id,
					plan_handle,
					statement_start_offset,
					statement_end_offset
				FROM #sessions
				WHERE
					recursion = 1
					AND plan_handle IS NOT NULL
			OPTION (KEEPFIXED PLAN);

			OPEN plan_cursor;

			FETCH NEXT FROM plan_cursor
			INTO 
				@session_id,
				@request_id,
				@plan_handle,
				@statement_start_offset,
				@statement_end_offset;

			--Wait up to 5 ms for a query plan, then give up
			SET LOCK_TIMEOUT 5;

			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					UPDATE s
					SET
						s.query_plan =
						(
							SELECT
								CONVERT(xml, query_plan)
							FROM sys.dm_exec_text_query_plan
							(
								@plan_handle, 
								CASE @get_plans
									WHEN 1 THEN
										@statement_start_offset
									ELSE
										0
								END, 
								CASE @get_plans
									WHEN 1 THEN
										@statement_end_offset
									ELSE
										-1
								END
							)
						)
					FROM #sessions AS s
					WHERE 
						s.session_id = @session_id
						AND s.request_id = @request_id
						AND s.recursion = 1
					OPTION (KEEPFIXED PLAN);
				END TRY
				BEGIN CATCH;
					IF ERROR_NUMBER() = 6335
					BEGIN;
						UPDATE s
						SET
							s.query_plan =
							(
								SELECT
									N'--' + NCHAR(13) + NCHAR(10) + 
									N'-- Could not render showplan due to XML data type limitations. ' + NCHAR(13) + NCHAR(10) + 
									N'-- To see the graphical plan save the XML below as a .SQLPLAN file and re-open in SSMS.' + NCHAR(13) + NCHAR(10) +
									N'--' + NCHAR(13) + NCHAR(10) +
										REPLACE(qp.query_plan, N'<RelOp', NCHAR(13)+NCHAR(10)+N'<RelOp') + 
										NCHAR(13) + NCHAR(10) + N'--' COLLATE Latin1_General_Bin2 AS [processing-instruction(query_plan)]
								FROM sys.dm_exec_text_query_plan
								(
									@plan_handle, 
									CASE @get_plans
										WHEN 1 THEN
											@statement_start_offset
										ELSE
											0
									END, 
									CASE @get_plans
										WHEN 1 THEN
											@statement_end_offset
										ELSE
											-1
									END
								) AS qp
								FOR XML
									PATH(''),
									TYPE
							)
						FROM #sessions AS s
						WHERE 
							s.session_id = @session_id
							AND s.request_id = @request_id
							AND s.recursion = 1
						OPTION (KEEPFIXED PLAN);
					END;
					ELSE
					BEGIN;
						UPDATE s
						SET
							s.query_plan = 
								CASE ERROR_NUMBER() 
									WHEN 1222 THEN '<timeout_exceeded />'
									ELSE '<error message="' + ERROR_MESSAGE() + '" />'
								END
						FROM #sessions AS s
						WHERE 
							s.session_id = @session_id
							AND s.request_id = @request_id
							AND s.recursion = 1
						OPTION (KEEPFIXED PLAN);
					END;
				END CATCH;

				FETCH NEXT FROM plan_cursor
				INTO
					@session_id,
					@request_id,
					@plan_handle,
					@statement_start_offset,
					@statement_end_offset;
			END;

			--Return this to the default
			SET LOCK_TIMEOUT -1;

			CLOSE plan_cursor;
			DEALLOCATE plan_cursor;
		END;

		IF 
			@get_locks = 1 
			AND @recursion = 1
			AND @output_column_list LIKE '%|[locks|]%' ESCAPE '|'
		BEGIN;
			DECLARE locks_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR 
				SELECT DISTINCT
					database_name
				FROM #locks
				WHERE
					EXISTS
					(
						SELECT *
						FROM #sessions AS s
						WHERE
							s.session_id = #locks.session_id
							AND recursion = 1
					)
					AND database_name <> '(null)'
				OPTION (KEEPFIXED PLAN);

			OPEN locks_cursor;

			FETCH NEXT FROM locks_cursor
			INTO 
				@database_name;

			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					SET @sql_n = CONVERT(NVARCHAR(MAX), '') +
						'UPDATE l ' +
						'SET ' +
							'object_name = ' +
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										'o.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								'), ' +
							'index_name = ' +
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										'i.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								'), ' +
							'schema_name = ' +
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										's.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								'), ' +
							'principal_name = ' + 
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										'dp.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								') ' +
						'FROM #locks AS l ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.allocation_units AS au ON ' +
							'au.allocation_unit_id = l.allocation_unit_id ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.partitions AS p ON ' +
							'p.hobt_id = ' +
								'COALESCE ' +
								'( ' +
									'l.hobt_id, ' +
									'CASE ' +
										'WHEN au.type IN (1, 3) THEN au.container_id ' +
										'ELSE NULL ' +
									'END ' +
								') ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.partitions AS p1 ON ' +
							'l.hobt_id IS NULL ' +
							'AND au.type = 2 ' +
							'AND p1.partition_id = au.container_id ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.objects AS o ON ' +
							'o.object_id = COALESCE(l.object_id, p.object_id, p1.object_id) ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.indexes AS i ON ' +
							'i.object_id = COALESCE(l.object_id, p.object_id, p1.object_id) ' +
							'AND i.index_id = COALESCE(l.index_id, p.index_id, p1.index_id) ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.schemas AS s ON ' +
							's.schema_id = COALESCE(l.schema_id, o.schema_id) ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.database_principals AS dp ON ' +
							'dp.principal_id = l.principal_id ' +
						'WHERE ' +
							'l.database_name = @database_name ' +
						'OPTION (KEEPFIXED PLAN); ';
					
					EXEC sp_executesql
						@sql_n,
						N'@database_name sysname',
						@database_name;
				END TRY
				BEGIN CATCH;
					UPDATE #locks
					SET
						query_error = 
							REPLACE
							(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									CONVERT
									(
										NVARCHAR(MAX), 
										ERROR_MESSAGE() COLLATE Latin1_General_Bin2
									),
									NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
									NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
									NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
								NCHAR(0),
								N''
							)
					WHERE 
						database_name = @database_name
					OPTION (KEEPFIXED PLAN);
				END CATCH;

				FETCH NEXT FROM locks_cursor
				INTO
					@database_name;
			END;

			CLOSE locks_cursor;
			DEALLOCATE locks_cursor;

			CREATE CLUSTERED INDEX IX_SRD ON #locks (session_id, request_id, database_name);

			UPDATE s
			SET 
				s.locks =
				(
					SELECT 
						REPLACE
						(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
							REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								CONVERT
								(
									NVARCHAR(MAX), 
									l1.database_name COLLATE Latin1_General_Bin2
								),
								NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
								NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
								NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
							NCHAR(0),
							N''
						) AS [Database/@name],
						MIN(l1.query_error) AS [Database/@query_error],
						(
							SELECT 
								l2.request_mode AS [Lock/@request_mode],
								l2.request_status AS [Lock/@request_status],
								COUNT(*) AS [Lock/@request_count]
							FROM #locks AS l2
							WHERE 
								l1.session_id = l2.session_id
								AND l1.request_id = l2.request_id
								AND l2.database_name = l1.database_name
								AND l2.resource_type = 'DATABASE'
							GROUP BY
								l2.request_mode,
								l2.request_status
							FOR XML
								PATH(''),
								TYPE
						) AS [Database/Locks],
						(
							SELECT
								COALESCE(l3.object_name, '(null)') AS [Object/@name],
								l3.schema_name AS [Object/@schema_name],
								(
									SELECT
										l4.resource_type AS [Lock/@resource_type],
										l4.page_type AS [Lock/@page_type],
										l4.index_name AS [Lock/@index_name],
										CASE 
											WHEN l4.object_name IS NULL THEN l4.schema_name
											ELSE NULL
										END AS [Lock/@schema_name],
										l4.principal_name AS [Lock/@principal_name],
										l4.resource_description AS [Lock/@resource_description],
										l4.request_mode AS [Lock/@request_mode],
										l4.request_status AS [Lock/@request_status],
										SUM(l4.request_count) AS [Lock/@request_count]
									FROM #locks AS l4
									WHERE 
										l4.session_id = l3.session_id
										AND l4.request_id = l3.request_id
										AND l3.database_name = l4.database_name
										AND COALESCE(l3.object_name, '(null)') = COALESCE(l4.object_name, '(null)')
										AND COALESCE(l3.schema_name, '') = COALESCE(l4.schema_name, '')
										AND l4.resource_type <> 'DATABASE'
									GROUP BY
										l4.resource_type,
										l4.page_type,
										l4.index_name,
										CASE 
											WHEN l4.object_name IS NULL THEN l4.schema_name
											ELSE NULL
										END,
										l4.principal_name,
										l4.resource_description,
										l4.request_mode,
										l4.request_status
									FOR XML
										PATH(''),
										TYPE
								) AS [Object/Locks]
							FROM #locks AS l3
							WHERE 
								l3.session_id = l1.session_id
								AND l3.request_id = l1.request_id
								AND l3.database_name = l1.database_name
								AND l3.resource_type <> 'DATABASE'
							GROUP BY 
								l3.session_id,
								l3.request_id,
								l3.database_name,
								COALESCE(l3.object_name, '(null)'),
								l3.schema_name
							FOR XML
								PATH(''),
								TYPE
						) AS [Database/Objects]
					FROM #locks AS l1
					WHERE
						l1.session_id = s.session_id
						AND l1.request_id = s.request_id
						AND l1.start_time IN (s.start_time, s.last_request_start_time)
						AND s.recursion = 1
					GROUP BY 
						l1.session_id,
						l1.request_id,
						l1.database_name
					FOR XML
						PATH(''),
						TYPE
				)
			FROM #sessions s
			OPTION (KEEPFIXED PLAN);
		END;

		IF 
			@find_block_leaders = 1
			AND @recursion = 1
			AND @output_column_list LIKE '%|[blocked_session_count|]%' ESCAPE '|'
		BEGIN;
			WITH
			blockers AS
			(
				SELECT
					session_id,
					session_id AS top_level_session_id
				FROM #sessions
				WHERE
					recursion = 1

				UNION ALL

				SELECT
					s.session_id,
					b.top_level_session_id
				FROM blockers AS b
				JOIN #sessions AS s ON
					s.blocking_session_id = b.session_id
					AND s.recursion = 1
			)
			UPDATE s
			SET
				s.blocked_session_count = x.blocked_session_count
			FROM #sessions AS s
			JOIN
			(
				SELECT
					b.top_level_session_id AS session_id,
					COUNT(*) - 1 AS blocked_session_count
				FROM blockers AS b
				GROUP BY
					b.top_level_session_id
			) x ON
				s.session_id = x.session_id
			WHERE
				s.recursion = 1;
		END;

		IF
			@get_task_info = 2
			AND @output_column_list LIKE '%|[additional_info|]%' ESCAPE '|'
			AND @recursion = 1
		BEGIN;
			CREATE TABLE #blocked_requests
			(
				session_id SMALLINT NOT NULL,
				request_id INT NOT NULL,
				database_name sysname NOT NULL,
				object_id INT,
				hobt_id BIGINT,
				schema_id INT,
				schema_name sysname NULL,
				object_name sysname NULL,
				query_error NVARCHAR(2048),
				PRIMARY KEY (database_name, session_id, request_id)
			);

			CREATE STATISTICS s_database_name ON #blocked_requests (database_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_schema_name ON #blocked_requests (schema_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_object_name ON #blocked_requests (object_name)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
			CREATE STATISTICS s_query_error ON #blocked_requests (query_error)
			WITH SAMPLE 0 ROWS, NORECOMPUTE;
		
			INSERT #blocked_requests
			(
				session_id,
				request_id,
				database_name,
				object_id,
				hobt_id,
				schema_id
			)
			SELECT
				session_id,
				request_id,
				database_name,
				object_id,
				hobt_id,
				CONVERT(INT, SUBSTRING(schema_node, CHARINDEX(' = ', schema_node) + 3, LEN(schema_node))) AS schema_id
			FROM
			(
				SELECT
					session_id,
					request_id,
					agent_nodes.agent_node.value('(database_name/text())[1]', 'sysname') AS database_name,
					agent_nodes.agent_node.value('(object_id/text())[1]', 'int') AS object_id,
					agent_nodes.agent_node.value('(hobt_id/text())[1]', 'bigint') AS hobt_id,
					agent_nodes.agent_node.value('(metadata_resource/text()[.="SCHEMA"]/../../metadata_class_id/text())[1]', 'varchar(100)') AS schema_node
				FROM #sessions AS s
				CROSS APPLY s.additional_info.nodes('//block_info') AS agent_nodes (agent_node)
				WHERE
					s.recursion = 1
			) AS t
			WHERE
				t.database_name IS NOT NULL
				AND
				(
					t.object_id IS NOT NULL
					OR t.hobt_id IS NOT NULL
					OR t.schema_node IS NOT NULL
				);
			
			DECLARE blocks_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR
				SELECT DISTINCT
					database_name
				FROM #blocked_requests;
				
			OPEN blocks_cursor;
			
			FETCH NEXT FROM blocks_cursor
			INTO 
				@database_name;
			
			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					SET @sql_n = 
						CONVERT(NVARCHAR(MAX), '') +
						'UPDATE b ' +
						'SET ' +
							'b.schema_name = ' +
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										's.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								'), ' +
							'b.object_name = ' +
								'REPLACE ' +
								'( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
									'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE( ' +
										'o.name COLLATE Latin1_General_Bin2, ' +
										'NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''), ' +
										'NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''), ' +
										'NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''), ' +
									'NCHAR(0), ' +
									N''''' ' +
								') ' +
						'FROM #blocked_requests AS b ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.partitions AS p ON ' +
							'p.hobt_id = b.hobt_id ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.objects AS o ON ' +
							'o.object_id = COALESCE(p.object_id, b.object_id) ' +
						'LEFT OUTER JOIN ' + QUOTENAME(@database_name) + '.sys.schemas AS s ON ' +
							's.schema_id = COALESCE(o.schema_id, b.schema_id) ' +
						'WHERE ' +
							'b.database_name = @database_name; ';
					
					EXEC sp_executesql
						@sql_n,
						N'@database_name sysname',
						@database_name;
				END TRY
				BEGIN CATCH;
					UPDATE #blocked_requests
					SET
						query_error = 
							REPLACE
							(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									CONVERT
									(
										NVARCHAR(MAX), 
										ERROR_MESSAGE() COLLATE Latin1_General_Bin2
									),
									NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
									NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
									NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
								NCHAR(0),
								N''
							)
					WHERE
						database_name = @database_name;
				END CATCH;

				FETCH NEXT FROM blocks_cursor
				INTO
					@database_name;
			END;
			
			CLOSE blocks_cursor;
			DEALLOCATE blocks_cursor;
			
			UPDATE s
			SET
				additional_info.modify
				('
					insert <schema_name>{sql:column("b.schema_name")}</schema_name>
					as last
					into (/additional_info/block_info)[1]
				')
			FROM #sessions AS s
			INNER JOIN #blocked_requests AS b ON
				b.session_id = s.session_id
				AND b.request_id = s.request_id
				AND s.recursion = 1
			WHERE
				b.schema_name IS NOT NULL;

			UPDATE s
			SET
				additional_info.modify
				('
					insert <object_name>{sql:column("b.object_name")}</object_name>
					as last
					into (/additional_info/block_info)[1]
				')
			FROM #sessions AS s
			INNER JOIN #blocked_requests AS b ON
				b.session_id = s.session_id
				AND b.request_id = s.request_id
				AND s.recursion = 1
			WHERE
				b.object_name IS NOT NULL;

			UPDATE s
			SET
				additional_info.modify
				('
					insert <query_error>{sql:column("b.query_error")}</query_error>
					as last
					into (/additional_info/block_info)[1]
				')
			FROM #sessions AS s
			INNER JOIN #blocked_requests AS b ON
				b.session_id = s.session_id
				AND b.request_id = s.request_id
				AND s.recursion = 1
			WHERE
				b.query_error IS NOT NULL;
		END;

		IF
			@output_column_list LIKE '%|[program_name|]%' ESCAPE '|'
			AND @output_column_list LIKE '%|[additional_info|]%' ESCAPE '|'
			AND @recursion = 1
		BEGIN;
			DECLARE @job_id UNIQUEIDENTIFIER;
			DECLARE @step_id INT;

			DECLARE agent_cursor
			CURSOR LOCAL FAST_FORWARD
			FOR 
				SELECT
					s.session_id,
					agent_nodes.agent_node.value('(job_id/text())[1]', 'uniqueidentifier') AS job_id,
					agent_nodes.agent_node.value('(step_id/text())[1]', 'int') AS step_id
				FROM #sessions AS s
				CROSS APPLY s.additional_info.nodes('//agent_job_info') AS agent_nodes (agent_node)
				WHERE
					s.recursion = 1
			OPTION (KEEPFIXED PLAN);
			
			OPEN agent_cursor;

			FETCH NEXT FROM agent_cursor
			INTO 
				@session_id,
				@job_id,
				@step_id;

			WHILE @@FETCH_STATUS = 0
			BEGIN;
				BEGIN TRY;
					DECLARE @job_name sysname;
					SET @job_name = NULL;
					DECLARE @step_name sysname;
					SET @step_name = NULL;
					
					SELECT
						@job_name = 
							REPLACE
							(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									j.name,
									NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
									NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
									NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
								NCHAR(0),
								N'?'
							),
						@step_name = 
							REPLACE
							(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
								REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
									s.step_name,
									NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
									NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
									NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
								NCHAR(0),
								N'?'
							)
					FROM msdb.dbo.sysjobs AS j
					INNER JOIN msdb..sysjobsteps AS s ON
						j.job_id = s.job_id
					WHERE
						j.job_id = @job_id
						AND s.step_id = @step_id;

					IF @job_name IS NOT NULL
					BEGIN;
						UPDATE s
						SET
							additional_info.modify
							('
								insert text{sql:variable("@job_name")}
								into (/additional_info/agent_job_info/job_name)[1]
							')
						FROM #sessions AS s
						WHERE 
							s.session_id = @session_id
						OPTION (KEEPFIXED PLAN);
						
						UPDATE s
						SET
							additional_info.modify
							('
								insert text{sql:variable("@step_name")}
								into (/additional_info/agent_job_info/step_name)[1]
							')
						FROM #sessions AS s
						WHERE 
							s.session_id = @session_id
						OPTION (KEEPFIXED PLAN);
					END;
				END TRY
				BEGIN CATCH;
					DECLARE @msdb_error_message NVARCHAR(256);
					SET @msdb_error_message = ERROR_MESSAGE();
				
					UPDATE s
					SET
						additional_info.modify
						('
							insert <msdb_query_error>{sql:variable("@msdb_error_message")}</msdb_query_error>
							as last
							into (/additional_info/agent_job_info)[1]
						')
					FROM #sessions AS s
					WHERE 
						s.session_id = @session_id
						AND s.recursion = 1
					OPTION (KEEPFIXED PLAN);
				END CATCH;

				FETCH NEXT FROM agent_cursor
				INTO 
					@session_id,
					@job_id,
					@step_id;
			END;

			CLOSE agent_cursor;
			DEALLOCATE agent_cursor;
		END; 
		
		IF 
			@delta_interval > 0 
			AND @recursion <> 1
		BEGIN;
			SET @recursion = 1;

			DECLARE @delay_time CHAR(12);
			SET @delay_time = CONVERT(VARCHAR, DATEADD(second, @delta_interval, 0), 114);
			WAITFOR DELAY @delay_time;

			GOTO REDO;
		END;
	END;

	SET @sql = 
		--Outer column list
		CONVERT
		(
			VARCHAR(MAX),
			CASE
				WHEN 
					@destination_table <> '' 
					AND @return_schema = 0 
						THEN 'INSERT ' + @destination_table + ' '
				ELSE ''
			END +
			'SELECT ' +
				@output_column_list + ' ' +
			CASE @return_schema
				WHEN 1 THEN 'INTO #session_schema '
				ELSE ''
			END
		--End outer column list
		) + 
		--Inner column list
		CONVERT
		(
			VARCHAR(MAX),
			'FROM ' +
			'( ' +
				'SELECT ' +
					'session_id, ' +
					--[dd hh:mm:ss.mss]
					CASE
						WHEN @format_output IN (1, 2) THEN
							'CASE ' +
								'WHEN elapsed_time < 0 THEN ' +
									'RIGHT ' +
									'( ' +
										'REPLICATE(''0'', max_elapsed_length) + CONVERT(VARCHAR, (-1 * elapsed_time) / 86400), ' +
										'max_elapsed_length ' +
									') + ' +
										'RIGHT ' +
										'( ' +
											'CONVERT(VARCHAR, DATEADD(second, (-1 * elapsed_time), 0), 120), ' +
											'9 ' +
										') + ' +
										'''.000'' ' +
								'ELSE ' +
									'RIGHT ' +
									'( ' +
										'REPLICATE(''0'', max_elapsed_length) + CONVERT(VARCHAR, elapsed_time / 86400000), ' +
										'max_elapsed_length ' +
									') + ' +
										'RIGHT ' +
										'( ' +
											'CONVERT(VARCHAR, DATEADD(second, elapsed_time / 1000, 0), 120), ' +
											'9 ' +
										') + ' +
										'''.'' + ' + 
										'RIGHT(''000'' + CONVERT(VARCHAR, elapsed_time % 1000), 3) ' +
							'END AS [dd hh:mm:ss.mss], '
						ELSE
							''
					END +
					--[dd hh:mm:ss.mss (avg)] / avg_elapsed_time
					CASE 
						WHEN  @format_output IN (1, 2) THEN 
							'RIGHT ' +
							'( ' +
								'''00'' + CONVERT(VARCHAR, avg_elapsed_time / 86400000), ' +
								'2 ' +
							') + ' +
								'RIGHT ' +
								'( ' +
									'CONVERT(VARCHAR, DATEADD(second, avg_elapsed_time / 1000, 0), 120), ' +
									'9 ' +
								') + ' +
								'''.'' + ' +
								'RIGHT(''000'' + CONVERT(VARCHAR, avg_elapsed_time % 1000), 3) AS [dd hh:mm:ss.mss (avg)], '
						ELSE
							'avg_elapsed_time, '
					END +
					--physical_io
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, physical_io))) OVER() - LEN(CONVERT(VARCHAR, physical_io))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_io), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_io), 1), 19)) AS '
						ELSE ''
					END + 'physical_io, ' +
					--reads
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, reads))) OVER() - LEN(CONVERT(VARCHAR, reads))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, reads), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, reads), 1), 19)) AS '
						ELSE ''
					END + 'reads, ' +
					--physical_reads
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, physical_reads))) OVER() - LEN(CONVERT(VARCHAR, physical_reads))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_reads), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_reads), 1), 19)) AS '
						ELSE ''
					END + 'physical_reads, ' +
					--writes
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, writes))) OVER() - LEN(CONVERT(VARCHAR, writes))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, writes), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, writes), 1), 19)) AS '
						ELSE ''
					END + 'writes, ' +
					--tempdb_allocations
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, tempdb_allocations))) OVER() - LEN(CONVERT(VARCHAR, tempdb_allocations))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_allocations), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_allocations), 1), 19)) AS '
						ELSE ''
					END + 'tempdb_allocations, ' +
					--tempdb_current
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, tempdb_current))) OVER() - LEN(CONVERT(VARCHAR, tempdb_current))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_current), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_current), 1), 19)) AS '
						ELSE ''
					END + 'tempdb_current, ' +
					--CPU
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, CPU))) OVER() - LEN(CONVERT(VARCHAR, CPU))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, CPU), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, CPU), 1), 19)) AS '
						ELSE ''
					END + 'CPU, ' +
					--context_switches
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, context_switches))) OVER() - LEN(CONVERT(VARCHAR, context_switches))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, context_switches), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, context_switches), 1), 19)) AS '
						ELSE ''
					END + 'context_switches, ' +
					--used_memory
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, used_memory))) OVER() - LEN(CONVERT(VARCHAR, used_memory))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, used_memory), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, used_memory), 1), 19)) AS '
						ELSE ''
					END + 'used_memory, ' +
					CASE
						WHEN @output_column_list LIKE '%|_delta|]%' ESCAPE '|' THEN
							--physical_io_delta			
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND physical_io_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, physical_io_delta))) OVER() - LEN(CONVERT(VARCHAR, physical_io_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_io_delta), 1), 19)) ' 
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_io_delta), 1), 19)) '
											ELSE 'physical_io_delta '
										END +
								'ELSE NULL ' +
							'END AS physical_io_delta, ' +
							--reads_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND reads_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, reads_delta))) OVER() - LEN(CONVERT(VARCHAR, reads_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, reads_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, reads_delta), 1), 19)) '
											ELSE 'reads_delta '
										END +
								'ELSE NULL ' +
							'END AS reads_delta, ' +
							--physical_reads_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND physical_reads_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, physical_reads_delta))) OVER() - LEN(CONVERT(VARCHAR, physical_reads_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_reads_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, physical_reads_delta), 1), 19)) '
											ELSE 'physical_reads_delta '
										END + 
								'ELSE NULL ' +
							'END AS physical_reads_delta, ' +
							--writes_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND writes_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, writes_delta))) OVER() - LEN(CONVERT(VARCHAR, writes_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, writes_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, writes_delta), 1), 19)) '
											ELSE 'writes_delta '
										END + 
								'ELSE NULL ' +
							'END AS writes_delta, ' +
							--tempdb_allocations_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND tempdb_allocations_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, tempdb_allocations_delta))) OVER() - LEN(CONVERT(VARCHAR, tempdb_allocations_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_allocations_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_allocations_delta), 1), 19)) '
											ELSE 'tempdb_allocations_delta '
										END + 
								'ELSE NULL ' +
							'END AS tempdb_allocations_delta, ' +
							--tempdb_current_delta
							--this is the only one that can (legitimately) go negative 
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, tempdb_current_delta))) OVER() - LEN(CONVERT(VARCHAR, tempdb_current_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_current_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tempdb_current_delta), 1), 19)) '
											ELSE 'tempdb_current_delta '
										END + 
								'ELSE NULL ' +
							'END AS tempdb_current_delta, ' +
							--CPU_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
										'THEN ' +
											'CASE ' +
												'WHEN ' +
													'thread_CPU_delta > CPU_delta ' +
													'AND thread_CPU_delta > 0 ' +
														'THEN ' +
															CASE @format_output
																WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, thread_CPU_delta + CPU_delta))) OVER() - LEN(CONVERT(VARCHAR, thread_CPU_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, thread_CPU_delta), 1), 19)) '
																WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, thread_CPU_delta), 1), 19)) '
																ELSE 'thread_CPU_delta '
															END + 
												'WHEN CPU_delta >= 0 THEN ' +
													CASE @format_output
														WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, thread_CPU_delta + CPU_delta))) OVER() - LEN(CONVERT(VARCHAR, CPU_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, CPU_delta), 1), 19)) '
														WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, CPU_delta), 1), 19)) '
														ELSE 'CPU_delta '
													END + 
												'ELSE NULL ' +
											'END ' +
								'ELSE ' +
									'NULL ' +
							'END AS CPU_delta, ' +
							--context_switches_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND context_switches_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, context_switches_delta))) OVER() - LEN(CONVERT(VARCHAR, context_switches_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, context_switches_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, context_switches_delta), 1), 19)) '
											ELSE 'context_switches_delta '
										END + 
								'ELSE NULL ' +
							'END AS context_switches_delta, ' +
							--used_memory_delta
							'CASE ' +
								'WHEN ' +
									'first_request_start_time = last_request_start_time ' + 
									'AND num_events = 2 ' +
									'AND used_memory_delta >= 0 ' +
										'THEN ' +
										CASE @format_output
											WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, used_memory_delta))) OVER() - LEN(CONVERT(VARCHAR, used_memory_delta))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, used_memory_delta), 1), 19)) '
											WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, used_memory_delta), 1), 19)) '
											ELSE 'used_memory_delta '
										END + 
								'ELSE NULL ' +
							'END AS used_memory_delta, '
						ELSE ''
					END +
					--tasks
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, tasks))) OVER() - LEN(CONVERT(VARCHAR, tasks))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tasks), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, tasks), 1), 19)) '
						ELSE ''
					END + 'tasks, ' +
					'status, ' +
					'wait_info, ' +
					'locks, ' +
					'tran_start_time, ' +
					'LEFT(tran_log_writes, LEN(tran_log_writes) - 1) AS tran_log_writes, ' +
					--open_tran_count
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, open_tran_count))) OVER() - LEN(CONVERT(VARCHAR, open_tran_count))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, open_tran_count), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, open_tran_count), 1), 19)) AS '
						ELSE ''
					END + 'open_tran_count, ' +
					--sql_command
					CASE @format_output 
						WHEN 0 THEN 'REPLACE(REPLACE(CONVERT(NVARCHAR(MAX), sql_command), ''<?query --''+CHAR(13)+CHAR(10), ''''), CHAR(13)+CHAR(10)+''--?>'', '''') AS '
						ELSE ''
					END + 'sql_command, ' +
					--sql_text
					CASE @format_output 
						WHEN 0 THEN 'REPLACE(REPLACE(CONVERT(NVARCHAR(MAX), sql_text), ''<?query --''+CHAR(13)+CHAR(10), ''''), CHAR(13)+CHAR(10)+''--?>'', '''') AS '
						ELSE ''
					END + 'sql_text, ' +
					'query_plan, ' +
					'blocking_session_id, ' +
					--blocked_session_count
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, blocked_session_count))) OVER() - LEN(CONVERT(VARCHAR, blocked_session_count))) + LEFT(CONVERT(CHAR(22), CONVERT(MONEY, blocked_session_count), 1), 19)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, LEFT(CONVERT(CHAR(22), CONVERT(MONEY, blocked_session_count), 1), 19)) AS '
						ELSE ''
					END + 'blocked_session_count, ' +
					--percent_complete
					CASE @format_output
						WHEN 1 THEN 'CONVERT(VARCHAR, SPACE(MAX(LEN(CONVERT(VARCHAR, CONVERT(MONEY, percent_complete), 2))) OVER() - LEN(CONVERT(VARCHAR, CONVERT(MONEY, percent_complete), 2))) + CONVERT(CHAR(22), CONVERT(MONEY, percent_complete), 2)) AS '
						WHEN 2 THEN 'CONVERT(VARCHAR, CONVERT(CHAR(22), CONVERT(MONEY, blocked_session_count), 1)) AS '
						ELSE ''
					END + 'percent_complete, ' +
					'host_name, ' +
					'login_name, ' +
					'database_name, ' +
					'program_name, ' +
					'additional_info, ' +
					'start_time, ' +
					'login_time, ' +
					'CASE ' +
						'WHEN status = N''sleeping'' THEN NULL ' +
						'ELSE request_id ' +
					'END AS request_id, ' +
					'GETDATE() AS collection_time '
		--End inner column list
		) +
		--Derived table and INSERT specification
		CONVERT
		(
			VARCHAR(MAX),
				'FROM ' +
				'( ' +
					'SELECT TOP(2147483647) ' +
						'*, ' +
						'CASE ' +
							'MAX ' +
							'( ' +
								'LEN ' +
								'( ' +
									'CONVERT ' +
									'( ' +
										'VARCHAR, ' +
										'CASE ' +
											'WHEN elapsed_time < 0 THEN ' +
												'(-1 * elapsed_time) / 86400 ' +
											'ELSE ' +
												'elapsed_time / 86400000 ' +
										'END ' +
									') ' +
								') ' +
							') OVER () ' +
								'WHEN 1 THEN 2 ' +
								'ELSE ' +
									'MAX ' +
									'( ' +
										'LEN ' +
										'( ' +
											'CONVERT ' +
											'( ' +
												'VARCHAR, ' +
												'CASE ' +
													'WHEN elapsed_time < 0 THEN ' +
														'(-1 * elapsed_time) / 86400 ' +
													'ELSE ' +
														'elapsed_time / 86400000 ' +
												'END ' +
											') ' +
										') ' +
									') OVER () ' +
						'END AS max_elapsed_length, ' +
						CASE
							WHEN @output_column_list LIKE '%|_delta|]%' ESCAPE '|' THEN
								'MAX(physical_io * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(physical_io * recursion) OVER (PARTITION BY session_id, request_id) AS physical_io_delta, ' +
								'MAX(reads * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(reads * recursion) OVER (PARTITION BY session_id, request_id) AS reads_delta, ' +
								'MAX(physical_reads * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(physical_reads * recursion) OVER (PARTITION BY session_id, request_id) AS physical_reads_delta, ' +
								'MAX(writes * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(writes * recursion) OVER (PARTITION BY session_id, request_id) AS writes_delta, ' +
								'MAX(tempdb_allocations * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(tempdb_allocations * recursion) OVER (PARTITION BY session_id, request_id) AS tempdb_allocations_delta, ' +
								'MAX(tempdb_current * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(tempdb_current * recursion) OVER (PARTITION BY session_id, request_id) AS tempdb_current_delta, ' +
								'MAX(CPU * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(CPU * recursion) OVER (PARTITION BY session_id, request_id) AS CPU_delta, ' +
								'MAX(thread_CPU_snapshot * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(thread_CPU_snapshot * recursion) OVER (PARTITION BY session_id, request_id) AS thread_CPU_delta, ' +
								'MAX(context_switches * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(context_switches * recursion) OVER (PARTITION BY session_id, request_id) AS context_switches_delta, ' +
								'MAX(used_memory * recursion) OVER (PARTITION BY session_id, request_id) + ' +
									'MIN(used_memory * recursion) OVER (PARTITION BY session_id, request_id) AS used_memory_delta, ' +
								'MIN(last_request_start_time) OVER (PARTITION BY session_id, request_id) AS first_request_start_time, '
							ELSE ''
						END +
						'COUNT(*) OVER (PARTITION BY session_id, request_id) AS num_events ' +
					'FROM #sessions AS s1 ' +
					CASE 
						WHEN @sort_order = '' THEN ''
						ELSE
							'ORDER BY ' +
								@sort_order
					END +
				') AS s ' +
				'WHERE ' +
					's.recursion = 1 ' +
			') x ' +
			'OPTION (KEEPFIXED PLAN); ' +
			'' +
			CASE @return_schema
				WHEN 1 THEN
					'SET @schema = ' +
						'''CREATE TABLE <table_name> ( '' + ' +
							'STUFF ' +
							'( ' +
								'( ' +
									'SELECT ' +
										''','' + ' +
										'QUOTENAME(COLUMN_NAME) + '' '' + ' +
										'DATA_TYPE + ' + 
										'CASE ' +
											'WHEN DATA_TYPE LIKE ''%char'' THEN ''('' + COALESCE(NULLIF(CONVERT(VARCHAR, CHARACTER_MAXIMUM_LENGTH), ''-1''), ''max'') + '') '' ' +
											'ELSE '' '' ' +
										'END + ' +
										'CASE IS_NULLABLE ' +
											'WHEN ''NO'' THEN ''NOT '' ' +
											'ELSE '''' ' +
										'END + ''NULL'' AS [text()] ' +
									'FROM tempdb.INFORMATION_SCHEMA.COLUMNS ' +
									'WHERE ' +
										'TABLE_NAME = (SELECT name FROM tempdb.sys.objects WHERE object_id = OBJECT_ID(''tempdb..#session_schema'')) ' +
										'ORDER BY ' +
											'ORDINAL_POSITION ' +
									'FOR XML ' +
										'PATH('''') ' +
								'), + ' +
								'1, ' +
								'1, ' +
								''''' ' +
							') + ' +
						''')''; ' 
				ELSE ''
			END
		--End derived table and INSERT specification
		);

	SET @sql_n = CONVERT(NVARCHAR(MAX), @sql);

	EXEC sp_executesql
		@sql_n,
		N'@schema VARCHAR(MAX) OUTPUT',
		@schema OUTPUT;
END;



GO
