
USE DBA
GO

IF OBJECT_ID('DBA.dbo.sp_TstlinkedSrvr') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_TstlinkedSrvr
END
GO	

CREATE PROCEDURE sp_TstlinkedSrvr
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