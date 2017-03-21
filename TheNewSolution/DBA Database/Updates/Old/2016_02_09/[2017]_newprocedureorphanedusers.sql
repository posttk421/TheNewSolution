USE [DBA];

IF OBJECT_ID('sp_GetOrphUsrs') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetOrphUsrs;
END

GO

CREATE PROCEDURE sp_GetOrphUsrs
	(
	@DbName VARCHAR(200) = NULL
	)
AS

/**********************
Name: sp_GetOrphUsrs

Author: Dustin Marzolf
Created: 4/3/2016

Purpose: To get orphaned users and report on them.

Inputs:
	@DbName VARCHAR(200) = NULL - The name of the database to check for orphaned users.	
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
		AND (D.name = @DbName
			OR @DbName IS NULL
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