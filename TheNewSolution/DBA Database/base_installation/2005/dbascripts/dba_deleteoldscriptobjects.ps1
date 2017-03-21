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

$FilesToDelete = $DBADB.ExecuteWithResults("SELECT FilePath FROM Data_objectBackupHistory WHERE DateRemoved IS NULL")

#Loop Through.
ForEach ($Row In $FilesToDelete.Tables.Item(0).Rows)
	{
	
	$File = [string]$Row.Item("FilePath")
	
	#Determine if File Exists.
	If ((Test-Path -Path $File -PathType Leaf) -eq $true)
		{
		
		#Remove the file.
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
		
		}
		
	}
	
#Update the list of objects.
$DBADB.ExecuteNonQuery("UPDATE Data_ObjectBackupHistory SET DateRemoved = GETDATE() WHERE DateRemoved IS NULL")