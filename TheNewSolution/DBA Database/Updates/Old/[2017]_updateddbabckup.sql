USE [msdb]
GO

/****** Object:  Job [_DBA_Backup]    Script Date: 02/08/2017 9:39:39 AM ******/
EXEC msdb.dbo.sp_delete_job @job_name=N'_DBA_Backup', @delete_unused_schedule=1
GO

/****** Object:  Job [_DBA_Backup]    Script Date: 02/08/2017 9:39:39 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Database Maintenance]    Script Date: 02/08/2017 9:39:39 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'_DBA_Backup', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job backs up all of the databases on the server.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cleanup Phase 1 - Gather Data]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup Phase 1 - Gather Data', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC DBA.dbo.spBackupUpdateMediaInfo', 
		@database_name=N'DBA', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cleanup Phase 2 - Delete Old Database Backup Files]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup Phase 2 - Delete Old Database Backup Files', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Get The List of Files
$FilesToDelete = @(Invoke-SqlCmd -Query "EXEC DBA.dbo.sp_Getbckfilestodel NULL" -Database "DBA" -ServerInstance $Instance -MaxCharLength ([int32][system.int32]::maxvalue))

#Loop through...
ForEach ($Row in ($FilesToDelete))
{

	$File = [string]$Row.Item("BackupFile")
	
	#Determine if File Exists...
	If ((Test-Path -Path $File -PathType Leaf) -eq $true)
	{
	
		$FileInfo = Get-Item -Path $File
		
		#Remove the File...
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
		
	}
	
	$Query = "UPDATE DBA.dbo.Data_BackupMediaFiles SET DateFileDeleted = GETDATE() WHERE DateFileDeleted IS NULL AND FilePathName = ''" + $File + "''"
	Invoke-SqlCmd -Query $Query -Database "DBA" -ServerInstance $Instance

}', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cleanup Phase 3 - Remove old database Object script files]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup Phase 3 - Remove old database Object script files', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

$BackupObjectsToDelete = @(Invoke-SqlCmd -Query "SELECT FilePath FROM Data_objectBackupHistory WHERE DateRemoved IS NULL" -Database "DBA" -ServerInstance $Instance -MaxCharLength ([int32][system.int32]::maxvalue))

#Looping through.
ForEach ($Row in ($BackupObjectsToDelete))
{

	$File = [string]$Row.Item("FilePath")
	
	#Determine if File Exists...
	If ((Test-Path -Path $File -PathType Leaf) -eq $true )
	{
	
		#Remove the File...
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
		
	
	}

}

Invoke-SqlCmd -Query "UPDATE Data_ObjectBackupHistory SET DateRemoved = GETDATE() WHERE DateRemoved IS NULL" -Database "DBA" -ServerInstance $Instance', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 1 - Create Folder Structure]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 1 - Create Folder Structure', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Get The List of Files
$Folders = @(Invoke-SqlCmd -Query "EXEC DBA.dbo.spGetBackupFolderList" -Database "DBA" -ServerInstance $Instance -MaxCharLength ([int32][system.int32]::maxvalue))

#Loop through...
ForEach ($Row in ($Folders))
{

	$Folder = [string]$Row.Item("FolderPath")
	$Folder = "Microsoft.PowerShell.Core\FileSystem::" + $Folder	
	
	#Determine if Folder Exists...
	If ((Test-Path -Path $Folder -PathType Container) -eq $false)
	{
	
		#Add The Folder.
		New-Item -Path $Folder -ItemType "Directory"		
	
	}

}', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 2 - Database]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 2 - Database', 
		@step_id=5, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
--This step backs up the database.

--Setting up parameters.
DECLARE @DbName VARCHAR(200)
DECLARE @BackupType CHAR(1) 
DECLARE @IsDebug BIT

--NULL value means all.
SET @DbName = NULL

--NULL value means to do look at the Option_Database table.
SET @BackupType = NULL

--0 means to actually execute.
SET @IsDebug = 0

--Execute the command
EXEC DBA.dbo.spBackupDatabase @DbName, @BackupType, @IsDebug', 
		@database_name=N'DBA', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3a - SQL Agent Jobs]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3a - SQL Agent Jobs', 
		@step_id=6, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Agent Jobs\'')" -ServerInstance $Instance -Database "DBA")[0]
$MasterList = @()

If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadWithPartialName(''Microsoft.SqlServer.SMO'') | out-null 
#Connect.
$SMO = new-object (''Microsoft.SqlServer.Management.Smo.Server'') $Instance 

If ($SMO.JobServer.Jobs.Count -ge 1)
{

	# Instantiate the Scripter object and set the base properties
	$Scripter = new-object (''Microsoft.SqlServer.Management.Smo.Scripter'') ($SMO)
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
			$Query = $Query + " (GETDATE(), ''Agent Job'', ''" + $Job.name + "'', ''" + $File + "'')"
			
			Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
			
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
$MasterList | Export-Csv ($RootFolder + "!Agent Job List.csv") -NoTypeInformation -NoClobber -Encoding ASCII', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3b - Backup Logins]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3b - Backup Logins', 
		@step_id=7, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$FilesToWrite = Invoke-SqlCmd -Query "EXEC DBA.dbo.sp_GetbckupLogins" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)
$TrackingFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Logins\'')" -ServerInstance $Instance -Database "DBA")[0]

ForEach ($Login In $FilesToWrite)
{

	$FolderPath = [string]$Login[0]
	$LoginFileName = [string]$Login[1]
	$LoginScript = [string]$Login[2]
	
	#Create the folder?
	If ((Test-Path -Path $FolderPath -PathType container) -eq $false)
	{
		New-Item -Path $FolderPath -ItemType container
	}
	
	#Delete the file if it already exists, we are overwriting.
	If ((Test-Path -Path ($FolderPath + "\" + $LoginFileName) -PathType leaf) -eq $true)
	{
		Remove-Item -Path ($FolderPath + "\" + $LoginFileName) -ErrorAction SilentlyContinue 
	}
	
	#Write the file contents.
	$LoginScript | Out-File ($FolderPath + "\" + $LoginFileName) -Encoding ASCII -NoClobber -ErrorAction SilentlyContinue  
	
	$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
	$Query = $Query + " VALUES"
	$Query = $Query + " (GETDATE(), ''Login'', ''" + ($LoginFileName -ireplace(".sql", "")) + "'', ''" + ($FolderPath + "\" + $LoginFileName) + "'')"
	
	Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"

} #End ForEach ($Login In $FilesToWrite)

#Now we are going to write a csv for tracking.
#Create the folder?
If ((Test-Path -Path $TrackingFolder -PathType container) -eq $false)
{
	New-Item -Path $TrackingFolder -ItemType container
}

$TrackingFolder = $TrackingFolder + "!Login Script.csv"

#Delete the file if it already exists, we are overwriting.
If ((Test-Path -Path ($TrackingFolder) -PathType leaf) -eq $true)
{
	Remove-Item -Path ($TrackingFolder) -ErrorAction SilentlyContinue 
}

$FilesToWrite | Export-Csv -Path $TrackingFolder -NoClobber -NoTypeInformation -Encoding "ASCII"
', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3c - Roles]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3c - Roles', 
		@step_id=8, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Roles\'')" -ServerInstance $Instance -Database "DBA")[0]
$MasterList = @()

If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadWithPartialName(''Microsoft.SqlServer.SMO'') | out-null 
#Connect.
$SMO = new-object (''Microsoft.SqlServer.Management.Smo.Server'') $Instance 

# Instantiate the Scripter object and set the base properties
$Scripter = new-object (''Microsoft.SqlServer.Management.Smo.Scripter'') ($SMO)
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
		
				$File = $Folder + "\" + $Role.Name 
				$Scripter.Options.FileName = $File
				$Scripter.Script($Role)
				
				$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
				$Query = $Query + " VALUES"
				$Query = $Query + " (GETDATE(), ''Database Roles'', ''" + $Role.name + "'', ''" + $File + "'')"
				
				Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
				
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
				$Query = $Query + " (GETDATE(), ''Application Roles'', ''" + $AppRole.Name + "'', ''" + $File + "'')"
				
				Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
				
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
$MasterList | Export-Csv ($RootFolder + "!Role List.csv") -NoTypeInformation -NoClobber -Encoding ASCII', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3d - Schemas]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3d - Schemas', 
		@step_id=9, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Schemas\'')" -ServerInstance $Instance -Database "DBA")[0]
$MasterList = @()

If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadWithPartialName(''Microsoft.SqlServer.SMO'') | out-null 
#Connect.
$SMO = new-object (''Microsoft.SqlServer.Management.Smo.Server'') $Instance 

# Instantiate the Scripter object and set the base properties
$Scripter = new-object (''Microsoft.SqlServer.Management.Smo.Scripter'') ($SMO)
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
		
				$File = $Folder + "\" + $Schema.Name 
				$Scripter.Options.FileName = $File
				$Scripter.Script($Schema)
				
				$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
				$Query = $Query + " VALUES"
				$Query = $Query + " (GETDATE(), ''Schemas'', ''" + $Schema.Name + "'', ''" + $File + "'')"
				
				Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
				
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
$MasterList | Export-Csv ($RootFolder + "!Schema List.csv") -NoTypeInformation -NoClobber -Encoding ASCII', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3e - SSIS Packages]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3e - SSIS Packages', 
		@step_id=10, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$FilesToWrite = Invoke-SqlCmd -Query "EXEC DBA.dbo.spGetBackupSSIS" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)
$TrackingFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\SSIS Packages\'')" -ServerInstance $Instance -Database "DBA")[0]
$List = @()

ForEach ($SSISPackage In $FilesToWrite)
{

	$FolderPath = [string]$SSISPackage[1]
	$SSISPackageFileName = [string]$SSISPackage[2]
	$SSISPackageScript = [string]$SSISPackage[3]
	
	#Create the folder?
	If ((Test-Path -Path $FolderPath -PathType container) -eq $false)
	{
		New-Item -Path $FolderPath -ItemType container
	}
	
	#Delete the file if it already exists, we are overwriting.
	If ((Test-Path -Path ($FolderPath + "\" + $SSISPackageFileName) -PathType leaf) -eq $true)
	{
		Remove-Item -Path ($FolderPath + "\" + $SSISPackageFileName) -ErrorAction SilentlyContinue 
	}
	
	#Write the file contents.
	$SSISPackageScript | Out-File ($FolderPath + "\" + $SSISPackageFileName) -Encoding ASCII -NoClobber -ErrorAction SilentlyContinue 
	
	$Item = New-Object System.Object
	$Item | Add-Member -type NoteProperty -Name PackageName -Value $SSISPackageFileName
	$Item | Add-Member -type NoteProperty -Name PackageFolder -Value $FolderPath
	
	$List += $Item
	
	
	$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
	$Query = $Query + " VALUES"
	$Query = $Query + " (GETDATE(), ''SSIS Package'', ''" + $SSISPackageFileName + "'', ''" + ($FolderPath + "\" + $SSISPackageFileName) + "'')"
	
	Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"

} #End ForEach ($SSISPackage In $FilesToWrite)

#Now we are going to write a csv for tracking.
#Create the folder?
If ((Test-Path -Path $TrackingFolder -PathType container) -eq $false)
{
	New-Item -Path $TrackingFolder -ItemType container
}

$TrackingFolder = $TrackingFolder + "!SSIS Packages.csv"

#Delete the file if it already exists, we are overwriting.
If ((Test-Path -Path ($TrackingFolder) -PathType leaf) -eq $true)
{
	Remove-Item -Path ($TrackingFolder) -ErrorAction SilentlyContinue 
}

$List | Export-Csv -Path $TrackingFolder -NoClobber -NoTypeInformation -Encoding "ASCII"
', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3f - Database Build Scripts]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3f - Database Build Scripts', 
		@step_id=11, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Database Build\'')" -ServerInstance $Instance -Database "DBA")[0]

#Build The Folder If Needed.
If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadWithPartialName(''Microsoft.SqlServer.SMO'') | out-null 
#Connect.
$SMO = new-object (''Microsoft.SqlServer.Management.Smo.Server'') $Instance 

$Scripter = new-object (''Microsoft.SqlServer.Management.Smo.Scripter'') ($SMO)
$ScriptOptions = New-Object (''Microsoft.SqlServer.Management.Smo.ScriptingOptions'')

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

#Script out each user database in the system.
ForEach ($Database In ($SMO.databases | Where-Object {$_.IsSystemObject -eq $false}))
{

	$File = $RootFolder + $Database.name + ".sql"
	$ScriptOptions.FileName = $File 
	
	if ((Test-Path -Path $File -PathType Leaf) -eq $true)
	{
		Remove-Item -Path $File -ErrorAction SilentlyContinue 
	}

	$Scripter.Script($Database)
	
	<#
	$urns = new-object Microsoft.SqlServer.Management.Smo.UrnCollection
	$ItemsAdded = $false 
	
	ForEach ($Obj In ($Database.EnumObjects() | Where-Object {$_.Schema -ne "information_schema" -and $_.DatabaseObjectTypes -ne "ServiceBroker" -and $_.Schema -ne "sys"}))
	{
		$urns.add($Obj.Urn)
		$ItemsAdded = $true 
	}
	
	$Scripter.Script($Database)
	
	If ($ItemsAdded = $true)
	{
		try
		{		
			$Scripter.Script($urns)
		}
		catch 
		{
		
			#An encrypted object was encountered, trying it the harder way.
			#Not sure if it''s really slower or not, actually.
			ForEach ($U In $urns)
			{
			
				$U2 = new-object Microsoft.SqlServer.Management.Smo.UrnCollection
				$U2.Add($U)
				try
				{
					$Scripter.Script($U2)
				}
				catch {}
				
			}		
		
		}
	}
	
	#>
		
	#Log it.
	$Query = "INSERT INTO Data_ObjectBackupHistory (DateAdded, ObjectType, ObjectName, FilePath)"
	$Query = $Query + " VALUES"
	$Query = $Query + " (GETDATE(), ''Database Creation'', ''" + $Database.name + "'', ''" + $File + "'')"
	
	Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
	
}', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3g - Linked Servers]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3g - Linked Servers', 
		@step_id=12, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\Linked Servers\'')" -ServerInstance $Instance -Database "DBA")[0]

#Build The Folder If Needed.
If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadWithPartialName(''Microsoft.SqlServer.SMO'') | out-null 
#Connect.
$SMO = new-object (''Microsoft.SqlServer.Management.Smo.Server'') $Instance 

$Scripter = new-object (''Microsoft.SqlServer.Management.Smo.Scripter'') ($SMO)
$ScriptOptions = New-Object (''Microsoft.SqlServer.Management.Smo.ScriptingOptions'')

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
	$Query = $Query + " (GETDATE(), ''Database Creation'', ''" + $LinkedServer.name + "'', ''" + $File + "'')"
	
	Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"
	
}', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 3h - SSAS]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 3h - SSAS', 
		@step_id=13, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#Get The Instance.
$Instance="$(ESCAPE_DQUOTE(SRVR))"

#Load the Modules.
$Modules = Invoke-SqlCmd -Query "SELECT ModuleName, ModuleText FROM PowershellModule" -ServerInstance $Instance -Database "DBA" -MaxCharLength ([int32][system.int32]::maxvalue)

ForEach ($Row In $Modules)
{

	#Module Code...	
	$ModuleText = [string]$Row[1]

	#Add the module to the current PS Session...
	Invoke-Expression -command $ModuleText
	
}

#Get the Disk drive information and load it into the proper table.

#######################################################################

$RootFolder = [string](Invoke-SqlCmd -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + ''-=Miscellaneous=-\SSAS\'')" -ServerInstance $Instance -Database "DBA")[0]

#Build The Folder If Needed.
If ((Test-Path -Path $RootFolder -PathType Container) -eq $false)
{
	New-Item -Path $RootFolder -ItemType directory
}

[System.Reflection.Assembly]::LoadwithpartialName("Microsoft.AnalysisServices") | Out-Null 
$AMO = New-Object (''Microsoft.AnalysisServices.Server'')

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
	$Query = $Query + " (GETDATE(), ''SSAS Backup'', ''" + $SSASDB.name + "'', ''" + $BackupFile + "'')"
	
	Invoke-SqlCmd -Query $Query -ServerInstance $Instance -Database "DBA"

}
', 
		@database_name=N'master', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Phase 4 - Update Agent Job History]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Phase 4 - Update Agent Job History', 
		@step_id=14, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'--Get Agent Job
EXEC DBA.dbo.sp_GetAgtJoblist

--Get Job History
EXEC DBA.dbo.sp_agntJobHist', 
		@database_name=N'DBA', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Logging Cleanup]    Script Date: 02/08/2017 9:39:40 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Logging Cleanup', 
		@step_id=15, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/** Cleaning up backup history **/

--Set to keep 30 Days.

--Cleanup Our Own Messaging.

DELETE FROM DBA.dbo.Info_Message
WHERE MessageType = ''Backup''
	AND MessageSeverity = 0
	AND DateMessage <= DATEADD(dd, -30, GETDATE())

--Cleanup MSDB''s history

DECLARE @OldestToKeep DATETIME
SET @OldestToKeep = DATEADD(dd, -30, GETDATE())
EXEC msdb.dbo.sp_delete_backuphistory @OldestToKeep

/** Cleanup Object Scripting (Phase 3) **/
DELETE FROM DBA.dbo.Data_ObjectBackupHistory
WHERE DateAdded <= DATEADD(dd, -30, GETDATE())
', 
		@database_name=N'DBA', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'_DBA Daily @ 6:00PM', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20160227, 
		@active_end_date=99991231, 
		@active_start_time=180000, 
		@active_end_time=235959, 
		 '
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


