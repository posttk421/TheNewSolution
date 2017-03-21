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
	
#######################################################################

$RootFolder = [string](Invoke-SqlCmd2 -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\SSAS\')" -ServerInstance $Instance -Database "DBA")[0]

#Build The Folder If Needed.
If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadwithpartialName("Microsoft.AnalysisServices") | Out-Null 
$AMO = New-Object ('Microsoft.AnalysisServices.Server')

#Need a try/catch block here because not all servers will have SSAS installed.
try
{
	$AMO.Connect($Instance)
}
catch {
	"Server Not Present or Not Online."
	Exit
}

ForEach ($SSASDB in $AMO.Databases)
{

	#Create the database folder...
	$DBFolder = $RootFolder + $SSASDB.name + "\"
	
	If ((Test-Path -Path $DBFolder -PathType Container) -eq $false)
	{
		New-Item -Path $DBFolder -ItemType directory
	}
	
	#Decide on backup file name.
	$Rightnow = [string](Get-Date).ToString("yyyy_MM_dd hh_mm_ss_tt")
	$BackupFile = $DBFolder + $SSASDB.Name + " " + $Rightnow + ".abf"
	
	If ((Test-Path -Path $BackupFile -PathType Container) -eq $true)
	{
		Remove-Item -Path $BackupFile -ErrorAction SilentlyContinue 
	}
	
	#Backup the database
	#File, AllowOverwrite (no), BackupRemote (yes), BackupLocations (null), UseCompression (yes), Password (null)
	$SSASDB.backup($BackupFile, $false, $true, $null, $true, $null)
	
	#Log it.
	$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
	$Query = $Query + " VALUES"
	$Query = $Query + " (GETDATE(), 'SSAS Backup', '" + $SSASDB.name + "', '" + $BackupFile + "')"
	
	Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"

}