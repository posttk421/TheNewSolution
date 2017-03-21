USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[spLoginObject]    Script Date: 02/08/2017 08:49:17 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[spLoginObject]
	(
	@LoginName VARCHAR(100)
	, @DbName VARCHAR(100)
	, @Script VARCHAR(MAX) OUTPUT
	)
AS

/******************************************

Name: spLoginObject
Author: Dustin Marzolf
	, based upon scripts by Claire Hsu (http://www.databasejournal.com/article.php/3921871/Claire-Hsu.htm)
	, also based upon scripts by Schott SQL (http://schottsql.blogspot.com/2011/02/quickly-script-permissions-in-sql-2005.html)

Created: 1/30/2016

Purpose: To script out the permissions that a given login has on objects within a specific database (or all database)

Inputs:
	@LoginName VARCHAR(100) - The name of the login to script.
	@DbName VARCHAR(100) - The name of the database to get permissions for.
		(If NULL, or empty string or * then will do for all databases)

Output:
	@Script VARCHAR(MAX) - The output script.
	
***********************************************/

SET NOCOUNT ON

/** Fix Inputs and check for validity **/
SET @Script = ''

--@LoginName
IF LTRIM(RTRIM(ISNULL(@LoginName, ''))) = ''
BEGIN
	SET @LoginName = NULL
END

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

--@DbName
IF LTRIM(RTRIM(ISNULL(@DbName, ''))) IN ('', '*')
BEGIN
	SET @DbName = NULL
END

IF NOT EXISTS (	SELECT *
				FROM sys.databases D
				WHERE D.name = @DbName
					OR @DbName IS NULL
					)
BEGIN

	SET @Script = '-- Specified Database: ' + ISNULL(@DbName, '<no database specified>') + ' does not exist.'
	RETURN

END

--Check for sa, public or sysadmin roles.
IF LOWER(@LoginName) IN ('sa', 'public')
	OR @LoginName IN (SELECT P.name FROM sys.syslogins P WHERE P.sysadmin = 1)
BEGIN

	SET @Script = '-- Specified User: ' + @LoginName + ' is sa, public or sysadmin.  Exiting Object level scripting of logins.'
	RETURN

END

/**************************************************
Begin Actual Work

This section gets the login and their SID if a SQL Login.
***************************************************/

--Get some login information.
DECLARE @LoginSID VARBINARY(85)

SET @LoginSID = (	SELECT P.[sid] 
					FROM sys.server_principals P 
					WHERE P.name = @LoginName
					)
					
/** Preparing tables to hold data... **/
IF OBJECT_ID('tempdb..#ObjectPermissions') IS NOT NULL
BEGIN
	DROP TABLE #ObjectPermissions
END

CREATE TABLE #ObjectPermissions
	(
	dbname VARCHAR(100) NULL
	, permType VARCHAR(100) NULL
	, state_desc SYSNAME NULL
	, permission_name NVARCHAR(128) NULL
	, [object_schema_name] SYSNAME NULL
	, [object_name] SYSNAME NULL
	, LoginName SYSNAME NULL
	, LoginSID VARBINARY(85) NULL
	)
	
DECLARE @Databases TABLE
	(
	dbname VARCHAR(100) NULL
	)
	
DECLARE @DBName VARCHAR(100)

DECLARE curDatabase CURSOR STATIC LOCAL FORWARD_ONLY

FOR SELECT D.[name]
	FROM sys.databases D
	WHERE D.[name] = @DbName
		OR @DbName IS NULL
		
OPEN curDatabase

FETCH NEXT FROM curDatabase
INTO @DBName

WHILE @@FETCH_STATUS = 0
BEGIN

	INSERT INTO @Databases (dbname) VALUES (@DBName)
	
	DECLARE @OBJPermCMD NVARCHAR(4000)
	
	--Part 1 Command.
	SET @OBJPermCMD = 'INSERT INTO #ObjectPermissions (dbname, permType, state_desc, permission_name, [object_schema_name], [object_name], LoginName, LoginSID)'
						+ ' SELECT ' + QUOTENAME(@DBName, '''') + ', ' + QUOTENAME('ObjectPerm', '''') + ', DBP.state_desc, DBP.permission_name, SS.name, SO.name, P.name, P.[sid]'
						+ ' FROM ' + QUOTENAME(@DBName) + '.sys.database_permissions DBP' 
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.objects SO ON SO.[object_id] = DBP.major_id' 
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.schemas SS ON SS.[schema_id] = SO.[schema_id]'
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.database_principals P ON P.principal_id = DBP.grantee_principal_id'
						
	EXEC sp_executesql @OBJPermCMD 

	--Part 2 Command.
	SET @OBJPermCMD = 'INSERT INTO #ObjectPermissions (dbname, permType, state_desc, permission_name, [object_schema_name], [object_name], LoginName, LoginSID)'
						+ ' SELECT ' + QUOTENAME(@DBName, '''') + ', ' + QUOTENAME('SchemaPerm', '''') + ', DBP.state_desc, DBP.permission_name, SS.name, P.name, P.name, P.[sid]'
						+ ' FROM ' + QUOTENAME(@DBName) + '.sys.database_permissions DBP'
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.schemas SS ON SS.[schema_id] = DBP.major_id AND DBP.class_desc = ' + QUOTENAME('SCHEMA', '''')
						+ ' INNER JOIN ' + QUOTENAME(@DBName) + '.sys.database_principals P ON P.principal_id = DBP.grantee_principal_id'
						
	EXEC sp_executesql @OBJPermCMD
		
	FETCH NEXT FROM curDatabase
	INTO @DBName

END

--Cleanup.
CLOSE curDatabase
DEALLOCATE curDatabase

--Remove unused logins from temp table.
DELETE FROM #ObjectPermissions
WHERE LoginSID <> @LoginSID

/** Now the real work begins, scripting out the logins for the objects. **/

SET @Script = @Script + CHAR(13) + '/*** Object Permissions **/' 

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT dbname
	FROM @Databases
	
OPEN curDB

FETCH NEXT FROM curDB
INTO @DBName

WHILE @@FETCH_STATUS = 0
BEGIN

	/** Divider in the script output **/
	SET @Script = @Script + CHAR(13) + CHAR(13) + '--------------------------------------------------------'

	IF NOT (@DBName IN (SELECT dbname FROM #ObjectPermissions))
	BEGIN
	
		--No Role Exists for specified database.
		SET @Script = @Script + CHAR(13) + CHAR(13) + '-- No explicitly defined object permissions exists for ' + QUOTENAME(@LoginName) + ' in database ' + QUOTENAME(@DBName) + '.' 
	
	END
	ELSE
	BEGIN
	
		DECLARE @permType VARCHAR(100)
		DECLARE @state_desc SYSNAME
		DECLARE @permission_name NVARCHAR(128)
		DECLARE @object_schema_name SYSNAME
		DECLARE @object_name SYSNAME
		DECLARE @DBLoginName SYSNAME
	
		DECLARE curRoles CURSOR LOCAL STATIC FORWARD_ONLY
		
		FOR SELECT permType, state_desc, permission_name, [object_schema_name], [object_name], LoginName
			FROM #ObjectPermissions
			WHERE dbname = @DBName
			ORDER BY CASE	WHEN permType = 'ObjectPerm' THEN 1
							WHEN permType = 'SchemaPerm' THEN 2
							ELSE 0
							END
				, permission_name
				, [object_schema_name]
				, [object_name]				
			
		OPEN curRoles
		
		FETCH NEXT FROM curRoles
		INTO @permType, @state_desc, @permission_name, @object_schema_name, @object_name, @DBLoginName
		
		/** Bit of the script for each Database **/
		SET @Script = @Script + CHAR(13) + '-- For user ' + QUOTENAME(@LoginName) + ' in database ' + QUOTENAME(@DBName)
						+ CHAR(13) + 'USE ' + QUOTENAME(@DBName) + CHAR(13)
			
		WHILE @@FETCH_STATUS = 0
		BEGIN
		
			/** Script specific object permissions **/
			IF @permType = 'ObjectPerm'
			BEGIN
			
				SET @Script = @Script + CHAR(13) + @state_desc + ' ' + @permission_name + ' ON ' + QUOTENAME(@object_schema_name) + '.' + QUOTENAME(@object_name) + ' TO ' + QUOTENAME(@DBLoginName)
				
			END
			
			IF @permType = 'SchemaPerm'
			BEGIN
			
				SET @Script = @Script + CHAR(13) + @state_desc + ' ' + @permission_name + ' ON SCHEMA::' + QUOTENAME(@object_schema_name) + '.' + QUOTENAME(@object_name) + ' TO ' + QUOTENAME(@DBLoginName)
				
			
			END
						
			FETCH NEXT FROM curRoles
			INTO @permType, @state_desc, @permission_name, @object_schema_name, @object_name, @DBLoginName
			
		END --WHILE @@FETCH_STATUS =0 (Looping through all roles for that user in that database/objects.)
		
		--Cleanup curRoles.
		CLOSE curRoles
		DEALLOCATE curRoles
	
	END

	--Go through the next database.
	FETCH NEXT FROM curDB
	INTO @DBName

END --WHILE @@FETCH_STATUS =0 (Looping through all databases requested.)

CLOSE curDB
DEALLOCATE curDB

--Cleanup.
IF OBJECT_ID('tempdb..#ObjectPermissions') IS NOT NULL
BEGIN
	DROP TABLE #ObjectPermissions
END

GO


