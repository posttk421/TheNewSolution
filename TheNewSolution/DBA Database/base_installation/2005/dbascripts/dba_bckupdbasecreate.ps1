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

$RootFolder = [string](Invoke-SqlCmd2 -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Database Build\')" -ServerInstance $Instance -Database "DBA")[0]

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
			#Not sure if it's really slower or not, actually.
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
	$Query = $Query + " (GETDATE(), 'Database Creation', '" + $Database.name + "', '" + $File + "')"
	
	Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"
	
}