USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[spGetBackupFolderList]    Script Date: 02/08/2017 13:59:02 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[spGetBackupFolderList]
AS

DECLARE @Folders TABLE
	(
	FolderPath VARCHAR(1000) NOT NULL
	)

--Get the folder for each of the databases...	
INSERT INTO @Folders
(FolderPath)
SELECT DBA.dbo.fn_GetBckupFolder(D.name)
FROM sys.databases D
WHERE NOT(D.name = 'tempdb')

--Additional Folders.
INSERT INTO @Folders
(FolderPath)
SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Logins\'
UNION ALL
SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Agent Jobs\'
UNION ALL
SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\SSIS Packages\'
UNION ALL
SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Schemas\'

SELECT FolderPath
FROM @Folders

GO


