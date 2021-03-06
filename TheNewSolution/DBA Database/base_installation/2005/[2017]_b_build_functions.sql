USE [DBA]
GO
/****** Object:  UserDefinedFunction [dbo].[fn_GetSQLTrcFiles]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_GetSQLTrcFiles]()
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
/****** Object:  UserDefinedFunction [dbo].[fn_CreateBckupStatemnt]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCreateBackupStatement]
	(
	@DbName VARCHAR(200)
	, @BackupType CHAR(1)
	, @DestinationPath VARCHAR(1000)
	, @FileCount INT = NULL
	)
RETURNS NVARCHAR(4000)
AS
BEGIN

/*****************
Name: fnCreateBackupStatement
Author: Dustin Marzolf
Created: 2/26/2016

Purpose: To programmatically generate the backup statements.

Update: 5/8/2016 - Dustin Marzolf
	Corrected logic that let the setting in DBA.dbo.Option truly control whether compression
	is enabled or not.  Logic is:
		* If the option in DBA.dbo.Option allows it AND the server edition allows it then enable compression.
		* If either DBA.dbo.Option or the server edition do not allow compression, then do not use compression.

Inputs:
	@DbName VARCHAR(200) - The name of the database to be backed up.
	@BackupType CHAR(1) - The type of the backup.
	@DestinationPath VARCHAR(1000) - The destination path
	@FileCount INT (NULL) - The number of files to put the backup in.  
		If NULL is specified then the system will attempt to determine it based
		on the size of the last backup.
		@FileCount will always be 1 if doing a LOG backup.
	
Outputs:
	NVARCHAR(4000) - The statement to generate that creates the backups.
	
NOTES:
* Database name must exist or this will exit.
* BackupTypes must be supported (D - FULL, L - LOG)
* Uses compression if it's supported.

********************/

--Return Value.
DECLARE @RetVal NVARCHAR(4000)

-- Validation
IF NOT(@DbName IN (SELECT name FROM sys.databases))
BEGIN
	RETURN N'-- Specified database does not exist.'
END

SET @BackupType = UPPER(@BackupType)
IF NOT(@BackupType IN ('D', 'L'))
BEGIN
	RETURN N'-- Specified backup type not supported.'
END

/** Additional declarations needed for work. **/
DECLARE @IsCompression BIT
DECLARE @IsServerCompression BIT
DECLARE @TimeStamp VARCHAR(200) 
SET @TimeStamp = CAST(REPLACE(REPLACE(CONVERT(VARCHAR(20), GETDATE(), 120), ':', '_'), '-', '_') AS NVARCHAR(100))
DECLARE @BackupFileName VARCHAR(200)
DECLARE @BackupSetName VARCHAR(200)
DECLARE @Options NVARCHAR(4000)
DECLARE @BckupSizeGB DECIMAL(10,2)
DECLARE @CurrentFileCount INT
DECLARE @BackupFileList VARCHAR(MAX)
DECLARE @BackupCheckSUM BIT

--Compression Enabled if Enterprise 2008 or Standard 2008 R2 or later.
IF (SERVERPROPERTY('EngineEdition') = 3
	AND LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) >= '10'
	)
	OR (SERVERPROPERTY('EngineEdition') = 2
		AND LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) >= '10'
		AND RIGHT(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 5), 2) >= '50'
		)
BEGIN
	SET @IsCompression = 1
END

--But compression should only be done if the flag is enabled in DBA.dbo.Option.
SET @IsServerCompression = CASE WHEN ISNULL((SELECT DBA.dbo.fn_GetOptVal('Server', 'BackupCompression')), 0) = 1 THEN 1 ELSE 0 END

IF @IsCompression = 1 AND @IsServerCompression = 0
BEGIN
	SET @IsCompression = 0
END

--Determine if checksum should be used.
SET @BackupCheckSUM = CASE WHEN ISNULL((SELECT DBA.dbo.fn_GetOptVal('Server', 'BackupCheckSUM')), 0) = 1 THEN 1 ELSE 0 END

/** How many backup files to use **/

--If log then always use 1 backup file, regardless of what is input.
IF @BackupType = 'L' AND ISNULL(@FileCount, 0) <> 1
BEGIN
	SET @FileCount = 1
END

--If full backup and NULL (Auto) specified, then determine the count.
IF @BackupType = 'D' AND @FileCount IS NULL
BEGIN
	SET @BckupSizeGB = (	SELECT TOP 1 ISNULL(CompressedSizeGB, BckupSizeGB) 
							FROM DBA.dbo.Data_BackupHistory 
							WHERE DatabaseName = @DbName 
								AND BackupType = 'D'
							ORDER BY DateGathered DESC
							)
	
	SET @FileCount = CASE	WHEN @BckupSizeGB IS NULL THEN 1
							WHEN @BckupSizeGB BETWEEN 0.0 AND 2500 THEN 1
							WHEN @BckupSizeGB BETWEEN 2500 AND 5000 THEN 5
							WHEN @BckupSizeGB BETWEEN 5000 AND 10000 THEN 10
							WHEN @BckupSizeGB BETWEEN 10000 AND 50000 THEN 20
							WHEN @BckupSizeGB BETWEEN 50000 AND 100000 THEN 30
							WHEN @BckupSizeGB >= 100000 THEN 30
							ELSE 1
							END
END

/** Assemble Backup Command **/
--What are we doing?
IF @BackupType = 'D'
BEGIN
	SET @RetVal = 'BACKUP DATABASE ' + QUOTENAME(@DbName)
	SET @BackupFileName = @DbName + ' FULL BACKUP ' + @TimeStamp + '.BAK'
	SET @BackupSetName = @DbName + ' FULL BACKUP'
END

IF @BackupType = 'L'
BEGIN
	SET @RetVal = 'BACKUP LOG ' + QUOTENAME(@DbName)
	SET @BackupFileName = @DbName + ' LOG BACKUP ' + @TimeStamp + '.TRN'
	SET @BackupSetName = @DbName + ' LOG BACKUP'
END

--Where are we putting it?
IF RIGHT(@DestinationPath, 1) <> '\'
BEGIN
	SET @DestinationPath = @DestinationPath + '\'
END

--Assemble the backup path.
SET @CurrentFileCount = 1
SET @BackupFileList = ''
WHILE @CurrentFileCount <= @FileCount AND LEN(@BackupFileList) <= 3000
BEGIN
	IF @CurrentFileCount >= 2
	BEGIN
		SET @BackupFileList = @BackupFileList + ', '
	END
	
	SET @BackupFileList = @BackupFileList + 'DISK = N' + '''' + @DestinationPath + REPLACE(@BackupFileName, '.BAK', '_' + RIGHT('000' + CAST(@CurrentFileCount AS VARCHAR(3)), 3) + '.BAK') + ''''
	
	SET @CurrentFileCount = @CurrentFileCount + 1
	
END


SET @DestinationPath = @DestinationPath + @BackupFileName

--What options?
SET @Options = 'RETAINDAYS = 14, NOFORMAT, NOINIT, SKIP, NOREWIND, NOUNLOAD, STATS = 10'

IF @IsCompression = 1
BEGIN
	SET @Options = @Options + ', COMPRESSION'
END

IF @BackupCheckSUM = 1
BEGIN
	SET @Options = @Options + ', CHECKSUM'
END

--Put it all together.
SET @RetVal = @RetVal + ' TO ' + @BackupFileList
					+ ' WITH ' + @Options 
					+ ', NAME = N' + '''' + @BackupSetName + ''''
					
RETURN @RetVal

END





GO
/****** Object:  UserDefinedFunction [dbo].[fn_FrmtDate]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_FrmtDate]
	(
	@InputDate DATETIME
	, @LongFormat BIT = 0
	)
RETURNS VARCHAR(20)
BEGIN

/*****
Name: fn_FrmtDate

Author: Dustin Marzolf

Created: 2/4/2016

Purpose: To return a string representation of the date.

Inputs:
	@InputDate DATETIME - the input date/time
	@LongFormat BIT (default 0) - If 0 then returns in short form (MM/dd/yyyy), else long form (MMMM dd, yyyy).
	
Outputs:
	Returns a VARCHAR(20) containing the string representation of the input datetime.
	
Notes:
	* If input value is NULL, then return value will be NULL
	* LongFormat is assumed to be 0/false by default.
	* If LongFormat is 0/false then returns short form (MM/dd/yyyy, ex: 2/14/2016)
	* If LongFormat is 1/true then returns long form (MMMM dd, yyyy, ex: February 14, 2016)

******/

--Check inputs.
IF @InputDate IS NULL
BEGIN
	RETURN NULL
END

IF @LongFormat IS NULL
BEGIN
	SET @LongFormat = 0
END

/** Begin work **/
DECLARE @RetVal VARCHAR(20)

IF @LongFormat = 0
BEGIN

	--Short Format MM/dd/yyyy
	SET @RetVal = CONVERT(VARCHAR(20), @InputDate, 101)
	
END

IF @LongFormat = 1
BEGIN

	--Long Format MMMM dd, yyyy
	SET @RetVal = DATENAME(month, @InputDate) + ' ' + DATENAME(day, @InputDate) + ', ' + CAST(YEAR(@InputDate) AS CHAR(4))

END

--Return the String value.
RETURN @RetVal

END


GO
/****** Object:  UserDefinedFunction [dbo].[fn_FrmtTime]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_FrmtTime]
	(
	@InputTime DATETIME 
	, @24HrClck BIT = 0
	)
RETURNS VARCHAR(20)
BEGIN

/***********
Name: fn_FrmtTime

Author: Dustin Marzolf

Created: 2/4/2016

Purpose: To convert the indicated time into a string representation of it.

Inputs:
	@InputTime DATETIME - The indicated date/time
	@24HrClck BIT (default 0) - Indicates whether to report the time in 12 hour format (with AM/PM) or in 24 hour format (with leading 0).
	
Outputs:
	VARCHAR(20) - indicating the time in the specified format.
	
Notes:
	* An input value of NULL will return NULL.
	* @24HrClck defaults to 0/false
	* If @24HrClck = 0/false then returned format will be (hh:mm tt ex: 12:58 PM, 3:23 PM)
	* If @24HrClck = 1/true then returned format will be (HH:mm ex: 12:58, 15:23)
	
************/

--Fix Inputs.
IF @InputTime IS NULL
BEGIN
	RETURN NULL
END

IF @24HrClck IS NULL
BEGIN
	SET @24HrClck = 0
END

/** Begin Work. **/
DECLARE @RetVal VARCHAR(20)
SET @RetVal = ''

--Volitale Variables.
DECLARE @Hour INT
DECLARE @Minute INT

--Get Val in 24 hr time
SET @Hour = DATENAME(hour, @InputTime)
SET @Minute = DATENAME(minute, @InputTime)

--If 24 hour clock and time is less than 10, then we need to insert a 0.
IF @24HrClck = 1 AND @Hour < 10
BEGIN

	SET @RetVal = '0' + CAST(@Hour AS CHAR(1)) + ':'

END
ELSE
BEGIN

	-- 12 hour clock
	IF @Hour <= 12 OR @24HrClck = 1
	BEGIN
		SET @RetVal = CAST(@Hour AS VARCHAR(2)) + ':'
	END
	ELSE
	BEGIN
		SET @RetVal = CAST((@Hour - 12) AS VARCHAR(2)) + ':'
	END

END

--Minutes...
IF @24HrClck = 0 AND @Minute < 10
BEGIN

	--Add leading 0 to the minute time.
	SET @RetVal = @RetVal + '0' + CAST(@Minute AS CHAR(1))

END
ELSE
BEGIN

	--Just get the time.
	SET @RetVal = @RetVal + CAST(@Minute AS CHAR(2))

END

--AM/PM, for 12 hour clock time.
IF @24HrClck = 0
BEGIN

	SET @RetVal = @RetVal + ' ' + CASE WHEN @Hour >= 13 THEN 'PM' ELSE 'AM' END

END

RETURN @RetVal

END


GO
/****** Object:  UserDefinedFunction [dbo].[fn_GetBckupFolder]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_GetBckupFolder] 
	(
	@DBName VARCHAR(500)
	) 
RETURNS VARCHAR(MAX)
BEGIN

/*************
Name: fn_GetBckupFolder
Author: Dustin Marzolf
Created: 2/25/2016

Purpose: Get the backup folder destination by assembling variuos parameters.

Inputs:
	@DBName VARCHAR(500) = NULL - The name of the database to append in there
	
Outputs:
	VARCHAR(MAX) - The path of where to place the backups.
	
NOTES:
 * If @DBName is NULL then you will get the destination path without the database
	as part of the name.
 * If the Option table is not built to contain some options then it will return 
	defaults (see below where it is getting values.)
	
Example Output:
	\\DMDBAPRDBAK02\D$\SQLBCKUPS\DEV\DMDBA-TST-TST01-=-DMDBATESTING\AdventureWorks2012\

***************/

--Return Value.
DECLARE @RetVal VARCHAR(MAX)

-- Validation
SET @DBName = REPLACE(@DBName, '\', '')

IF @DBName IS NOT NULL 
	AND NOT(@DBName IN (SELECT name FROM sys.databases))
BEGIN
	SET @DBName = NULL
END

-- Required for processing
DECLARE @BckupRootFldr VARCHAR(MAX)
DECLARE @SrvrType VARCHAR(MAX)
DECLARE @SrvrName VARCHAR(500)
DECLARE @NetPath BIT 
SET @NetPath = 0

--Get Vals, input default vals in none
SELECT @BckupRootFldr = ISNULL(DBA.dbo.fn_GetOptVal('Server', 'BackupFolderRoot'), '\\DMDBAPRDBAK02\D$\SQLBCKUPS')
	, @SrvrType = ISNULL(DBA.dbo.fn_GetOptVal('Server', 'ServerType'), 'DEV')
	, @SrvrName = REPLACE(@@SERVERNAME, '\', '-=-')

IF ISNULL(@SrvrName, '') = ''
BEGIN
	SET @SrvrName = CAST(SERVERPROPERTY('servername') AS VARCHAR(100))
END
	
--Chk 4 net path dest
IF LEFT(@BckupRootFldr, 2) = '\\'
BEGIN
	SET @NetPath = 1
END

/** Assemblying Ret Val. ** /

--1st the root bckup folder.
SET @RetVal = @BckupRootFldr

IF RIGHT(@RetVal, 1) <> '\'
	AND @BckupRootFldr IS NOT NULL
BEGIN
	SET @RetVal = @RetVal + '\'
END

--2nd, Srvr Type
SET @RetVal = @RetVal + @SrvrType

IF RIGHT(@RetVal, 1) <> '\'
	AND @SrvrType IS NOT NULL
BEGIN
	SET @RetVal = @RetVal + '\'
END

--3rd, srvrname
SET @RetVal = @RetVal + @SrvrName

IF RIGHT(@RetVal, 1) <> '\'
	AND @SrvrName IS NOT NULL
BEGIN
	SET @RetVal = @RetVal + '\'
END

--4th, the dbname 
IF @DBName IS NOT NULL
BEGIN

	SET @RetVal = @RetVal + @DBName
		
	IF RIGHT(@RetVal, 1) <> '\'
		AND @DBName IS NOT NULL
	BEGIN
		SET @RetVal = @RetVal + '\'
	END

END

--Paranoia check for double slashes in pathname...
SET @RetVal = CASE WHEN @NetPath = 1 THEN '\\' ELSE '' END + REPLACE(@RetVal, '\\', '')

RETURN @RetVal

END



GO
/****** Object:  UserDefinedFunction [dbo].[fn_GetDbbckuptype]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_GetDbbckuptype]
	(
	@DbName VARCHAR(200)
	, @DayOfWeek INT
	)
RETURNS CHAR(1)
AS
BEGIN

/******************
Name: fn_GetDbbckuptype
Author: Dustin Marzolf
Created: 2/26/2016

Purpose: To get the backup type from the Option_Database table.

Inputs:
	@DbName VARCHAR(200) - The name of the database.
	@DayOfWeek INT - The numeric value for the day of the week.
	
Output:
	CHAR(1) - The backup type.  D-FULL or L-LOG.
	
NOTES:
* If no database is specified or if the specified database has no entry
	in Option_Database then 'D' is returned.
* If the day of the week is not between 1 and 7 then 'D' is returned.
* If no entry can be found then 'D' is returned.

********************/

--Return Value.
DECLARE @RetVal CHAR(1)

-- Validation
IF NOT(@DbName IN (	SELECT DatabaseName 
							FROM Option_Database)
							)
BEGIN
	RETURN 'D'
END

IF NOT(@DayOfWeek BETWEEN 1 AND 7)
BEGIN
	RETURN 'D'
END

--Get the value.
SELECT @RetVal = CASE @DayOfWeek	WHEN 1 THEN O.BckupTypeSunday
										WHEN 2 THEN O.BckupTypeMonday
										WHEN 3 THEN O.BckupTypeTuesday
										WHEN 4 THEN O.BckupTypeWednesday
										WHEN 5 THEN O.BckupTypeThursday
										WHEN 6 THEN O.BckupTypeFriday
										WHEN 7 THEN O.BckupTypeSaturday
										ELSE 'D'
										END
FROM Option_Database O
WHERE O.DatabaseName = @DbName 

RETURN ISNULL(@RetVal, 'D')

END


GO
/****** Object:  UserDefinedFunction [dbo].[fn_GetOptVal]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_GetOptVal]
	(
	@OptionLevel VARCHAR(20) = NULL
	, @OptionName VARCHAR(200) = NULL
	)
RETURNS VARCHAR(MAX)
AS
BEGIN

/*****************
Name: fn_GetOptVal
Author: Dustin Marzolf
Created: 2/25/2016

Purpose: To streamline the process of getting the values from the Option table.

Inputs:
	@OptionLevel VARCHAR(20) = NULL - The name of the option level (Server, Database, etc.)
	@OptionName VARCHAR(200) = NULL - The name of the option name (BackupFolderRoot, ServerType, etc.)
	
Returns:
	VARCHAR(MAX) - The value of the requested option.
	
NOTES:
* If the either of the inputs are NULL then it returns NULL.
* If the [Option] table doesn't exist, then returns NULL.

*******************/

--The return value.
DECLARE @RetVal VARCHAR(MAX)

-- Validation..
IF @OptionLevel IS NULL 
	OR @OptionName IS NULL
	OR OBJECT_ID('DBA.dbo.[Option]') IS NULL
BEGIN
	RETURN NULL
END

--Begin work.
SET @RetVal = (	SELECT OptionValue 
						FROM DBA.dbo.[Option] 
						WHERE OptionLevel = @OptionLevel 
						AND OptionName = @OptionName
						)

--Return the return value.
RETURN @RetVal

END


GO
/****** Object:  UserDefinedFunction [dbo].[fn_JOBDurToSec]    Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fn_JOBDurToSec]
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
DECLARE @Time DATETIME 

IF ISNULL(@run_duration, 0) = 0
BEGIN
	RETURN 0
END

IF ABS(@run_duration) > 90000
BEGIN
	RETURN NULL
END

--Get the value as a time variable.
SET @Time = DBA.dbo.fn_FrmtDate(GETDATE(), 0) + ' ' + STUFF(STUFF(REPLACE(STR(@run_duration, 6), ' ', '0'), 3, 0, ':'), 6, 0, ':')

--Convert to seconds (hours, minutes, etc.)
SET @RetVal = (DATEPART(HOUR, @Time) * 60 * 60) + (DATEPART(MINUTE, @Time) * 60) + (DATEPART(SECOND, @Time))

RETURN @RetVal

END



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
DECLARE @RunDate DATETIME
DECLARE @RunTime VARCHAR(20)

--Exit Conditions.
IF ISNULL(@run_date, 0) = 0 OR ISNULL(@run_time, 0) = 0
BEGIN
	RETURN NULL
END

--Date Portion
SET @RunDate = CAST(CAST(@run_date AS VARCHAR(10)) AS DATETIME)

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
/****** Object:  UserDefinedFunction [dbo].[fn_TrimTime]     Script Date: 02/08/2017 12:00:00 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_TrimTime] 
	(
	@InputDate DATETIME
	)
RETURNS DATETIME
BEGIN

DECLARE @RetVal DATETIME

IF @InputDate IS NULL
BEGIN
	SET @RetVal = NULL
	RETURN @RetVal
END

SET @RetVal = CONVERT(VARCHAR(10), @InputDate, 101)

RETURN @RetVal

END

GO
