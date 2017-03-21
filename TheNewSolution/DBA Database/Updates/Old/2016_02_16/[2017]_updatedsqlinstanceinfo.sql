USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_GetSqlInstInfo]    Script Date: 02/08/2017 13:34:59 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_GetSqlInstInfo]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[sp_GetSqlInstInfo]
GO

USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_GetSqlInstInfo]    Script Date: 02/08/2017 13:34:59 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[sp_GEtSQlInstInfo]
	(
	@ForceUpdateAll BIT = 0
	)
AS

/************
Name: sp_GetSqlInstInfo

Author: Dustin Marzolf

Created: 2/6/2016

Purpose: To get information about the local SQL instance.

*************/

SET NOCOUNT ON

--Fix Inputs.
IF @ForceUpdateAll IS NULL
BEGIN
	SET @ForceUpdateAll = 1
END

/** Begin Initial Setup for Work **/

--Variable Declaration.
DECLARE @LogMessage VARCHAR(MAX)
DECLARE @Name VARCHAR(100)
DECLARE @OriginalValue VARCHAR(200)
DECLARE @CurrentValue VARCHAR(200)
DECLARE @IsValueChanged BIT
DECLARE @IndexID INT
DECLARE @RightNow DATETIME = GETDATE()

IF @ForceUpdateAll = 1
BEGIN
	TRUNCATE TABLE Info_SQLInstance
	
	--Log.
	SET @LogMessage = 'The procedure sp_GetSqlInstInfo is being run with a "ForceUpdateAll" flag set to 1, clearing exisiting data.'
	EXEC sp_logMsg 0, 'SQLInstance', 'Clearing Data', @LogMessage, NULL
END

IF @ForceUpdateAll = 0
	AND ISNULL((SELECT COUNT(Name) FROM Info_SQLInstance), 0) = 0
BEGIN
	SET @ForceUpdateAll = 1
END

/** Get the pieces of information we are interested in. **/

--Instance Name
SET @Name = 'Instance Name'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('InstanceName')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Product Version
SET @Name = 'Product Version'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('ProductVersion')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Product Level
SET @Name = 'Product Level'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('ProductLevel')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Product Edition
SET @Name = 'Product Edition'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('Edition')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Collation
SET @Name = 'Server Collation'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('Collation')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Max Memory
SET @Name = 'Memory Physical Max'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT value FROM sys.configurations WHERE name = 'max server memory (MB)') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Min Memory
SET @Name = 'Memory Physical Min'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT value FROM sys.configurations WHERE name = 'min server memory (MB)') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--AWE Memory
SET @Name = 'Memory AWE enabled'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CASE CAST(value AS BIT) WHEN 1 THEN 'yes' ELSE 'no' END FROM sys.configurations WHERE name = 'awe enabled') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Is Clustered
SET @Name = 'Is Clustered'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST(ISNULL((SELECT SERVERPROPERTY('IsClustered')), 0) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Active Node Name
SET @Name = 'Cluster Active Node Name'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--XP Command Shell
SET @Name = 'XP_CmdShell'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS Config_Value FROM sys.configurations WHERE [name] = 'xp_cmdshell') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Max Degree of Paralellism
SET @Name = 'Max DOP'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS Config_Value FROM sys.configurations WHERE [name] = 'max degree of parallelism') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--CLR enabled
SET @Name = 'CLR Enabled'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS Config_Value FROM sys.configurations WHERE [name] = 'clr enabled') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Default Trace Enabled
SET @Name = 'Default Trace'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS Config_Value FROM sys.configurations WHERE [name] = 'default trace enabled') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Remote Admin Connections
SET @Name = 'Remote Admin'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

SET @IsValueChanged = 0
SET @CurrentValue = CAST((SELECT CONVERT(INT, ISNULL(value, value_in_use)) AS Config_Value FROM sys.configurations WHERE [name] = 'remote admin connections') AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END

--Agent Token Replace
SET @Name = 'Agent Token Replace'

SELECT @OriginalValue = OriginalValue
	, @IndexID = IndexID
FROM Info_SQLInstance
WHERE Name = @Name

DECLARE @TokenStatus INT
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'AlertReplaceRuntimeTokens', @TokenStatus OUT

SET @IsValueChanged = 0
SET @CurrentValue = CAST((ISNULL(@TokenStatus, 0)) AS VARCHAR(200))

IF @IndexID IS NULL
BEGIN

	--New Entry...
	INSERT INTO Info_SQLInstance
	(Name, OriginalValue, OriginalValue_DateTime)
	VALUES
	(@Name, @CurrentValue, @RightNow)

END
ELSE
BEGIN

	--Updating existing entry...
	UPDATE Info_SQLInstance
	SET LastValue = @CurrentValue
		, LastValue_DateTime = @RightNow
		, @IsValueChanged = CASE WHEN @CurrentValue <> OriginalValue THEN 1 ELSE 0 END
	WHERE Name = @Name
	
	IF @IsValueChanged = 1
	BEGIN
		SET @LogMessage = 'While processing sp_GetSqlInstInfo it was detected that a value has changed.  Check table Info_SQLInstance, Name: ' + @Name
		EXEC sp_logMsg 4, 'SQLInstance', 'Data Changed', @LogMessage, NULL
	END
	
END



GO


EXEC sp_GEtSQlInstInfo @ForceUpdateAll = 1