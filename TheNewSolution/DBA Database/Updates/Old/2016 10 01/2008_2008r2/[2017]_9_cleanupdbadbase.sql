/** 
	Final cleanup of DBA Database

**/

USE DBA

IF OBJECT_ID('DBA.dbo.uspDBDefrag') IS NOT NULL
BEGIN
	DROP PROCEDURE uspDBDefrag
END

IF OBJECT_ID('DBA.dbo.uspfixusers') IS NOT NULL
BEGIN
	DROP PROCEDURE uspfixusers
END

IF OBJECT_ID('DBA.dbo.sp_GetSQLConfigChanges') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetSQLConfigChanges
END

IF OBJECT_ID('DBA.dbo.Data_SQLConfigChanges') IS NOT NULL
BEGIN
	DROP TABLE Data_SQLConfigChanges
END


