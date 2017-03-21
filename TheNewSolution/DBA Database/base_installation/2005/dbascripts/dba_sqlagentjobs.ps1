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

$RootFolder = [string](Invoke-SqlCmd2 -Query "SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Agent Jobs\'" -ServerInstance $Instance -Database "DBA")[0]
$MasterList = @()

If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

If ($SMO.JobServer.Jobs.Count -ge 1)
{

	# Instantiate the Scripter object and set the base properties
	$Scripter = new-object ('Microsoft.SqlServer.Management.Smo.Scripter') ($SMO)
	$Scripter.Options.ScriptDrops = $False
	$Scripter.Options.WithDependencies = $False
	$Scripter.Options.IncludeHeaders = $True
	$Scripter.Options.AppendToFile = $False
	$Scripter.Options.ToFileOnly = $True
	$Scripter.Options.ClusteredIndexes = $True
	$Scripter.Options.DriAll = $True
	$Scripter.Options.Indexes = $True
	$Scripter.Options.Triggers = $True

	ForEach ($Job In $SMO.JobServer.Jobs | Where-Object {$Job.name -ne ""})
	{
	
		Try
		{
		
			$JobName = $Job.name
			$File = $RootFolder + $JobName + ".sql"
			$Scripter.Options.FileName = $File
			$Scripter.Script($Job)
			
			$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
			$Query = $Query + " VALUES"
			$Query = $Query + " (GETDATE(), 'Agent Job', '" + $Job.name + "', '" + $File + "')"
			
			Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
			
			$Output = New-Object System.Object
	        $Output | Add-Member -type NoteProperty -name Date -value (Get-Date -format MM/dd/yyyy)
	        $Output | Add-Member -type NoteProperty -name ServerName -value $Server
	        $Output | Add-Member -type NoteProperty -Name JobName -Value $JobName
			$Output | Add-Member -type NoteProperty -Name Enabled -Value $Job.IsEnabled 
			$Output | Add-Member -type NoteProperty -Name LastRunDate -Value $Job.LastRunDate 
			$Output | Add-Member -type NoteProperty -Name LastOutcome -Value $Job.LastRunOutcome 
			$Output | Add-Member -type NoteProperty -Name NextRun -Value $Job.NextRunDate 
			$Output | Add-Member -type NoteProperty -Name Description -Value $Job.Description 
			$Output | Add-Member -type NoteProperty -Name DateCreated -Value $Job.DateCreated 
			$Output | Add-Member -type NoteProperty -Name DateLastModified -Value $Job.DateLastModified 
			$Output | Add-Member -type NoteProperty -Name VersionNumber -Value $Job.VersionNumber 
			
			$MasterList += $Output	
		
		}
		catch 
		{
		
			"Error Creating File - Agent Job"
			$Error[0]
		
		}
	
	} #End ForEach ($Job In $SMO.JobServer.Jobs | Where-Object {$Job.name -ne ""})

} #End If ($SMO.JobServer.Jobs.Count -ge 1)

If ((Test-Path -Path ($RootFolder + "!Agent Job List.csv") -PathType leaf) -eq $true)
{
	Remove-Item -Path ($RootFolder + "!Agent Job List.csv") -ErrorAction SilentlyContinue 
}

#Writeout the master list.
$MasterList | Export-Csv ($RootFolder + "!Agent Job List.csv") -NoTypeInformation -NoClobber -Encoding ASCII