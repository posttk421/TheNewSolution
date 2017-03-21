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
$RootFolder = [string](Invoke-SqlCmd2 -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Schemas\')" -ServerInstance $Instance -Database "DBA")[0]
$MasterList = @()

If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

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

ForEach ($Database In $SMO.databases)
{

	#Make Folder If needed.
	$Folder = $RootFolder + $Database.Name	
	
	ForEach ($Schema IN $Database.schemas)
	{
	
		#Only backup non-standard schemas.
		If ($Schema.IsSystemObject -eq $false)
		{
		
			If ((Test-Path -Path $Folder -PathType Container) -eq $false)
			{
				New-Item -Path $Folder -ItemType directory
			}
	
			try
			{
		
				$File = $Folder + "\" + $Schema.Name + '.sql'
				$Scripter.Options.FileName = $File
				$Scripter.Script($Schema)
				
				$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
				$Query = $Query + " VALUES"
				$Query = $Query + " (GETDATE(), 'Schemas', '" + $Schema.Name + "', '" + $File + "')"
				
				Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
				
				$Output = New-Object System.Object
		        $Output | Add-Member -type NoteProperty -name DatabaseName -Value $Database.Name
				$Output | Add-Member -type NoteProperty -name SchemaName -Value $Schema.Name 
				$Output | Add-Member -type NoteProperty -Name Path -Value $File 
		        		
				$MasterList += $Output	
			
			}
			catch 
			{
			
				"Error Creating File - Schema"
				$Error[0]
			
			}
		
		}
	
	} #End ForEach ($Schema IN $Database.schemas)

} #End ForEach ($Database In $SMO.databases)

If ((Test-Path -Path ($RootFolder + "!Schema List.csv") -PathType leaf) -eq $true)
{
	Remove-Item -Path ($RootFolder + "!Schema List.csv") -ErrorAction SilentlyContinue 
}

#Writeout the master list.
$MasterList | Export-Csv ($RootFolder + "!Schema List.csv") -NoTypeInformation -NoClobber -Encoding ASCII