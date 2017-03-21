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
	
#Get the Disk drive information and load it into the proper table.

#######################################################################

$RightNow = [string](Get-Date -Format "MM/dd/yyyy hh:mm:ss tt")

$Disks = Get-WMIObject Win32_logicaldisk -Filter "DriveType=3" | Select @{n='ServerName';e={$Instance}} , @{n='DateGathered';e={$RightNow}} , @{n='DriveLetter';e={[string]$_.Caption}} , @{n='VolumeName';e={[string]$_.VolumeName}}, @{n='Capacity_GB';e={[decimal]$_.Size/1Gb}}, @{n='Used_GB';e={[decimal]($_.Size - $_.FreeSpace)/1GB}}, @{n='FreeSpace_GB';e={[decimal]$_.FreeSpace/1GB}}

Write-DataTable -ServerInstance $Instance -Database "DBA" -TableName "Data_SystemDisk" -Data ($Disks | Out-DataTable)



