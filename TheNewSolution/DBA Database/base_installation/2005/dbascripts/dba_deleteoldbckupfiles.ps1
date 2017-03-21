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

$FilesToDelete = $DBADB.ExecuteWithResults("EXEC DBA.dbo.sp_Getbckfilestodel NULL")

#Loop Through.
ForEach ($Row In $FilesToDelete.Tables.Item(0).Rows)
	{
	
	$File = [string]$Row.Item("BackupFile")
	
	#Determine if File Exists.
	If ((Test-Path -Path $File -PathType Leaf) -eq $true)
		{
		
		#Remove the file.
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
		
		}
		
	$Query = "UPDATE DBA.dbo.Data_BackupMediaFiles SET DateFileDeleted = GETDATE() WHERE DateFileDeleted IS NULL AND FilePathName = '" + $File + "'"
	$DBADB.ExecuteNonQuery($Query)
	
	}