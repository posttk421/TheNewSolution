param ([string]$Instance)

#Get the Additional Modules needed for doing the work.
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
#Connect.
$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $Instance 
$DBADB = New-Object Microsoft.SqlServer.Management.Smo.Database
$DBADB = $SMO.Databases.Item("DBA")

$DS = $DBADB.ExecuteWithResults("SELECT ModuleText FROM PowershellModule")

ForEach ($Module in $DS.Tables.Item(0).Rows)
	{
	
		$ModuleText = [string]$Module.ModuleText
		Invoke-Expression $ModuleText
	
	}
	
#####################################################################

$FilesToDelete = $DBADB.ExecuteWithResults("EXEC DBA.dbo.spGetBackupFolderList")

#Loop Through.
ForEach ($Row In $FilesToDelete.Tables.Item(0).Rows)
	{
	
	$Folder = [string]$Row.Item("FolderPath")
	$Folder = "Microsoft.PowerShell.Core\FileSystem::" + $Folder
	
	#Determine if File Exists.
	If ((Test-Path -Path $Folder -PathType container) -eq $false)
		{
		
		#Add the Item
		New-Item -Path $Folder -ItemType "Directory"
		
		}
		
	}
