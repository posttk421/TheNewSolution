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
$RootFolder = [string](Invoke-SqlCmd2 -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Roles\')" -ServerInstance $Instance -Database "DBA")[0]
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

	ForEach ($Role IN $Database.roles)
	{
	
		#Only Backup non-standard roles.
		if ($Role.IsFixedRole -eq $false)
		{
		
			$Folder = $RootFolder + $Database.Name + "\Database Roles"
		
			If ((Test-Path -Path $Folder -PathType Container) -eq $false)
			{
				New-Item -Path $Folder -ItemType directory
			}
	
			try
			{
		
				$File = $Folder + "\" + $Role.Name + '.sql'
				$Scripter.Options.FileName = $File
				$Scripter.Script($Role)
				
				$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
				$Query = $Query + " VALUES"
				$Query = $Query + " (GETDATE(), 'Database Roles', '" + $Role.name + "', '" + $File + "')"
				
				Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
				
				$Output = New-Object System.Object
		        $Output | Add-Member -type NoteProperty -name DatabaseName -Value $Database.Name
				$Output | Add-Member -type NoteProperty -name RoleName -Value $Role.Name 
				$Output | Add-Member -type NoteProperty -name RoleType -Value "Database Role" 
				$Output | Add-Member -type NoteProperty -Name Path -Value $File 
		        		
				$MasterList += $Output	
			
			}
			catch 
			{
			
				"Error Creating File - Database Roles"
				$Error[0]
			
			}	
			
		}
		
	} #End ForEach ($Schema IN $Database.schemas)
	
	ForEach ($AppRole In $Database.ApplicationRoles)
	{
		
		#Only Backup non-standard roles.
		if ($AppRole.IsFixedRole -eq $false)
		{
		
			$Folder = $RootFolder + $Database.Name + "\Application Roles"
		
			If ((Test-Path -Path $Folder -PathType Container) -eq $false)
			{
				New-Item -Path $Folder -ItemType directory
			}
	
			try
			{
		
				$File = $Folder + "\" + $AppRole.Name 
				$Scripter.Options.FileName = $File
				$Scripter.Script($AppRole)
				
				$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
				$Query = $Query + " VALUES"
				$Query = $Query + " (GETDATE(), 'Application Roles', '" + $AppRole.Name + "', '" + $File + "')"
				
				Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
				
				$Output = New-Object System.Object
		        $Output | Add-Member -type NoteProperty -name DatabaseName -Value $Database.Name
				$Output | Add-Member -type NoteProperty -name RoleName -Value $AppRole.Name 
				$Output | Add-Member -type NoteProperty -name RoleType -Value "Application Role" 
				$Output | Add-Member -type NoteProperty -Name Path -Value $File 
		        		
				$MasterList += $Output	
			
			}
			catch 
			{
			
				"Error Creating File - Application Roles"
				$Error[0]
			
			}	
			
		}
		
	}
	
	

} #End ForEach ($Database In $SMO.databases)

If ((Test-Path -Path ($RootFolder + "!Role List.csv") -PathType leaf) -eq $true)
{
	Remove-Item -Path ($RootFolder + "!Role List.csv") -ErrorAction SilentlyContinue 
}

#Writeout the master list.
$MasterList | Export-Csv ($RootFolder + "!Role List.csv") -NoTypeInformation -NoClobber -Encoding ASCII