USE [DBA]
GO

IF OBJECT_ID('DBA.dbo.sp_GetbckupLogins') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetbckupLogins
END

/****** Object:  StoredProcedure [dbo].[sp_GetbckupLogins]    Script Date: 02/08/2017 15:13:33 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[sp_GetbckupLogins]
AS

/*********************************
Name: sp_GetbckupLogins

Author: Dustin Marzolf
Created: 3/22/2016

Purpose: To aid in the scripting of the logins.

It uses the previously scripted logins and simply prepares the system
to write to disk.  It provides the file name, the folder path and the contents
of the file.  

***********************************/

DECLARE @List TABLE
	(
	LoginName VARCHAR(200) NULL
	, FolderName VARCHAR(100) NULL
	, LoginSafeName VARCHAR(300) NULL
	, LoginFileName VARCHAR(100) NULL
	, LoginScript VARCHAR(MAX) NULL
	)
	
/** Get the names for the server level logins **/
INSERT INTO @List
(LoginName, FolderName, LoginFileName, LoginScript)
SELECT I.LoginName
	, '!Server - ' + REPLACE(@@SERVERNAME, '\', '_')
	, NULL
	, ISNULL(I.LastScript, I.OriginalScript)
FROM Info_LoginServer I


/** Get the names for the database level logins **/
INSERT INTO @List
(LoginName, FolderName, LoginFileName, LoginScript)
SELECT D.LoginName
	, D.DatabaseName
	, ' - Database'
	, ISNULL(D.LastScript, D.OriginalScript)
FROM Info_LoginDatabase D

/** Get the names for the database/object level logins **/
INSERT INTO @List
(LoginName, FolderName, LoginFileName, LoginScript)
SELECT DO.LoginName
	, DO.DatabaseName
	, ' - DatabaseObjects'
	, ISNULL(DO.LastScript, DO.OriginalScript)
FROM Info_LoginDatabaseObject DO


/** Make the login name safe for files **/
UPDATE @List
SET LoginSafeName = REPLACE(LoginName, '\', '_')

/** Return the data, preparing it for processing by the powershell script. **/
DECLARE @FolderRoot VARCHAR(1000) = (SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Logins\')

SELECT @FolderRoot + FolderName AS FolderPath
	, LoginSafeName + ISNULL(LoginFileName, '') + '.sql' AS LoginFileName
	, LoginScript AS Contents
FROM @List
ORDER BY FolderName, LoginName



 



GO

