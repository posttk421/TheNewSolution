USE DBA;
GO

IF OBJECT_ID('spFindAppRoleUsers') IS NOT NULL
BEGIN
	DROP PROCEDURE spFindAppRoleUsers
END

GO

CREATE PROCEDURE spFindAppRoleUsers
	(
	@DbName VARCHAR(100) = NULL
	)
AS

/************
Name: spFindAppRoleUsers
Author: Dustin Marzolf
Created: 6/19/2016
 Output:
A table containing the databasename and username of all application role users.

*************/

--Fix Inputs.
IF ISNULL(@DbName, '') = ''
BEGIN
	SET @DbName = NULL
END

--Test for temp table, drop if already exists.
IF OBJECT_ID('tempdb..#OrphanUsers') IS NOT NULL
BEGIN
	DROP TABLE #OrphanUsers
END

--Create temp table.
CREATE TABLE #OrphanUsers
	(
	DatabaseName SYSNAME NULL
	, UserName SYSNAME NULL
	)

--To hold the database name in the cursor.
DECLARE @DBName SYSNAME

--For every database...
DECLARE curDBLoop CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT D.name
	FROM sys.databases D
	WHERE D.state_desc = 'ONLINE'
		AND (
			D.name = @DbName
			OR @DbName IS NULL
			)

OPEN curDBLoop

FETCH NEXT FROM curDBLoop
INTO @DBName

WHILE @@FETCH_STATUS = 0
BEGIN

	DECLARE @SQL NVARCHAR(4000)

	SET @SQL = 'USE ' + QUOTENAME(@DBName) + ';'
		+ ' INSERT INTO #OrphanUsers (DatabaseName, UserName)'
		+ ' SELECT DB_NAME(), D.name'
		+ ' FROM sys.database_principals D'
		+ ' WHERE NOT(D.[sid] IN (SELECT P.[sid] FROM sys.server_principals P))'
		+ ' AND D.[type] IN (' + QUOTENAME('S', '''') + ', ' + QUOTENAME('U', '''') + ', ' + QUOTENAME('G', '''') + ')'
		+ ' AND NOT(D.name IN (' + QUOTENAME('dbo', '''') + ', ' + QUOTENAME('guest', '''') + '))'

	EXEC sp_executesql @SQL	

	FETCH NEXT FROM curDBLoop
	INTO @DBName

END

--Cleanup Cursor.
CLOSE curDBLoop
DEALLOCATE curDBLoop

SELECT DatabaseName
	, UserName 
FROM #OrphanUsers
ORDER BY DatabaseName
	, UserName

--Cleanup Temp Table.
IF OBJECT_ID('tempdb..#OrphanUsers') IS NOT NULL
BEGIN
	DROP TABLE #OrphanUsers
END


