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

$FilesToWrite = Invoke-SqlCmd2 -Query "EXEC DBA.dbo.spGetBackupSSIS" -ServerInstance $Instance -Database "DBA"
$TrackingFolder = [string](Invoke-SqlCmd2 -Query "SELECT DBA.dbo.fn_GetBckupFolder(NULL) + '-=Miscellaneous=-\SSIS Packages\'" -ServerInstance $Instance -Database "DBA")[0]
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
	$Query = $Query + " (GETDATE(), 'SSIS Package', '" + $SSISPackageFileName + "', '" + ($FolderPath + "\" + $SSISPackageFileName) + "')"
	
	Invoke-SqlCmd2 -Query $Query -ServerInstance $Instance -Database "DBA"

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