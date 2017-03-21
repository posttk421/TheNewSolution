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

$RootFolder = [string](Invoke-SqlCmd2 -Query "SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Linked Servers\'" -ServerInstance $Instance -Database "DBA")[0]

#Build The Folder If Needed.
If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

$Scripter = new-object ('Microsoft.SqlServer.Management.Smo.Scripter') ($SMO)
$ScriptOptions = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')

$ScriptOptions.AllowSystemObjects = $false
$ScriptOptions.ExtendedProperties = $true 
$ScriptOptions.AnsiPadding = $true 
$ScriptOptions.WithDependencies = $false
$ScriptOptions.IncludeHeaders = $true 
$ScriptOptions.ClusteredIndexes = $true 
$ScriptOptions.AppendToFile = $true 
$ScriptOptions.IncludeIfNotExists = $true
$ScriptOptions.ScriptBatchTerminator = $true
$ScriptOptions.DriAll = $true 
$ScriptOptions.Indexes = $true 
$ScriptOptions.Triggers = $true 
$ScriptOptions.ToFileOnly = $true 

$Scripter.PrefetchObjects = $true 

$Scripter.Options = $ScriptOptions

ForEach ($LinkedServer IN $SMO.LinkedServers)
{

	$File = $RootFolder + ($LinkedServer.name.replace("\", "-=-")) + ".sql"
	$ScriptOptions.FileName = $File 
	
	if ((Test-Path -Path $File -PathType Leaf) -eq $true)
	{
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
	}

	$Scripter.Script($LinkedServer)
				
	#Log it.
	$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
	$Query = $Query + " VALUES"
	$Query = $Query + " (GETDATE(), 'Database Creation', '" + $LinkedServer.name + "', '" + $File + "')"
	
	Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
	
}