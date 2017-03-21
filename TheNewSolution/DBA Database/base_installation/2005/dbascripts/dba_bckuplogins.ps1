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


$FilesToWrite = Invoke-SqlCmd2 -Query "EXEC DBA.dbo.sp_GetbckupLogins" -ServerInstance $Instance -Database "DBA"
$TrackingFolder = [string](Invoke-SqlCmd2 -Query "(SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\Logins\')" -ServerInstance $Instance -Database "DBA")[0]

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
	$Query = $Query + " (GETDATE(), 'Login', '" + ($LoginFileName -ireplace(".sql", "")) + "', '" + ($FolderPath + "\" + $LoginFileName) + "')"
	
	Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"

} #End ForEach ($Login In $FilesToWrite)

#Now we are going to write a csv for tracking.
#Create the folder?
If ((Test-Path -Path $TrackingFolder -PathType container) -eq $false)
{
	New-Item -Path $TrackingFolder -ItemType container
}

$TrackingFolder = $TrackingFolder + "!Login Script.csv"

#Delete the file if it already exists, we are overwriting.
If ((Test-Path -Path ($TrackingFolder) -PathType Container) -eq $true)
{
	Remove-Item -Path ($TrackingFolder) -ErrorAction SilentlyContinue 
}

$FilesToWrite | Export-Csv -Path $TrackingFolder -NoClobber -NoTypeInformation -Encoding "ASCII"

