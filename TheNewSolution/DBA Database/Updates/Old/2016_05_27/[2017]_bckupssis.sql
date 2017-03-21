USE DBA
GO

IF OBJECT_ID('DBA.dbo.spGetBackupSSIS') IS NOT NULL
BEGIN
	DROP PROCEDURE spGetBackupSSIS
END

GO
CREATE PROCEDURE spGetBackupSSIS
AS

DECLARE @List TABLE
	(
	PackageName VARCHAR(200) NULL
	, FolderPath VARCHAR(1000) NULL
	, PackageFileName VARCHAR(1000) NULL
	, PackageText VARCHAR(MAX)
	)
	
DECLARE @FolderRoot VARCHAR(500)

SET @FolderRoot = (SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\SSIS Packages\');

--Define CTE.
;WITH SSISCTE AS 
	(
	SELECT CAST(F.foldername AS VARCHAR(MAX)) AS folderpath
		, F.folderid
	FROM msdb.dbo.sysssispackagefolders F
	UNION ALL
	SELECT CAST(E.folderpath + '\' + F.foldername AS VARCHAR(MAX))
		, F.folderid
	FROM msdb.dbo.sysssispackagefolders F
		INNER JOIN SSISCTE E ON E.folderid = F.parentfolderid
	)
        
-- Put the data into the result table.
INSERT INTO @List
(PackageName, FolderPath, PackageFileName, PackageText)
SELECT P.name
	, @FolderRoot + ISNULL(S.folderpath, '')
	, P.name + '.dtsx'
	, CAST(CAST(P.packagedata AS VARBINARY(MAX)) AS VARCHAR(MAX))
FROM SSISCTE S
	INNER JOIN msdb.dbo.sysssispackages P ON P.folderid = S.folderid
	
SELECT PackageName, FolderPath, PackageFileName, PackageText FROM @List ORDER BY FolderPath, PackageName

