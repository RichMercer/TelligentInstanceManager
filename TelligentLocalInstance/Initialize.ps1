#Requires -Version 3

function Initialize-TelligentInstanceManager {
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(HelpMessage="The path where Telligent Instances Manager will store instances and builds.")]
    [string]$InstallDirectory,
    [string]$DatabaseServerInstance,
    [switch]$SkipSearch,
    [switch]$Force
)

#Banner
Write-Telligent
Write-Host "Telligent Instance Manager"
Write-Host

#Test Prerequisites
$initialErrorCount = $Error.Count
Write-Progress "Telligent Instance Manager Setup" "Checking Prerequisites" -CurrentOperation "This may take a few moments"
if(!$InstallDirectory){
    $InstallDirectory = $env:TelligentInstanceManager
    if(!(Test-Path $InstallDirectory)) {
        Write-Error 'Could not auto-detect Install location. Please run the command with the -InstallDirectory paramater to specify this location manually'
    }
}

if(!$DatabaseServerInstance) {
    if([string]::IsNullOrEmpty($env:TelligentDatabaseServerInstance)) { $DatabaseServerInstance = "(local)" } else { $DatabaseServerInstance= $env:TelligentDatabaseServerInstance }
}

Test-Prerequisites $installDirectory
if ($Error.Count -ne $initialErrorCount) {
    throw 'Prerequisites not met (see previous errors for more details)'
}

#Make Required Folders
@('Licenses', 'TelligentPackages', 'Communities', 'Solr') |
    % { Join-Path $InstallDirectory $_} |
    ? {!(Test-Path $_)} |
    % {new-item $_ -ItemType Directory | Out-Null}

    if(!$SkipSearch) {
        Install-Solr -InstallDirectory $InstallDirectory -Force:$Force
    }

Initalize-Environment $InstallDirectory $DatabaseServerInstance

Write-Progress 'Telligent Instance Manager Setup' -Completed

#Provide hints for finishing installation
$LicensePath = Join-Path $InstallDirectory Licenses 
if (!(Get-ChildItem $LicensePath -ErrorAction SilentlyContinue)){
    Write-Warning "No Licenses available for installation at '$LicensePath' "
    Write-Warning "Add license files to this directory with filenames of the format 'Community8.xml', 'Community9.xml' etc."
}

$packagesPath = Join-Path $InstallDirectory TelligentPackages
if (!(Get-ChildItem $LicensePath -ErrorAction SilentlyContinue)){
    Write-Warning "No packages are available for Installation at '$packagesPath'."
}

Write-Host
Write-Host 'Telligent Instance Manager installation  complete' -ForegroundColor Green
Write-Host @"
For more details on how to use the Telligent Instance Manager, use the Get-Help cmdlet to learn more about the following comamnds
* Get-TelligentInstance
* Install-TelligentInstance
* Remove-TelligentInstance

"@

}

function Test-Prerequisites
{
    param(
        [Parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory
    )
    #Check Admin
    $currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
           Write-Error "Installation requires Administrative credentials"
    }

    #Check for required modules
    @('webadministration','SqlServer') |
        ? { !(Get-Module $_ -ListAvailable) } |
        % { Write-Error "Required Module '$_' is not available" }
}

function Install-Solr {
    param(
        [Parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory,
        [switch]$Force
    )

    $modernSolrXml = @"
<?xml version="1.0" encoding="UTF-8" ?>
<solr>
  <solrcloud>
    <str name="host">$`{host:}</str>
    <int name="hostPort">$`{jetty.port:8983}</int>
    <str name="hostContext">$`{hostContext:solr}</str>
    <int name="zkClientTimeout">$`{zkClientTimeout:15000}</int>
    <bool name="genericCoreNodeNames">$`{genericCoreNodeNames:true}</bool>
  </solrcloud>

  <shardHandlerFactory name="shardHandlerFactory"
    class="HttpShardHandlerFactory">
    <int name="socketTimeout">$`{socketTimeout:0}</int>
    <int name="connTimeout">$`{connTimeout:0}</int>
  </shardHandlerFactory>
</solr>
"@
    
    $solrBase = Join-Path $InstallDirectory Solr

	# Install new Solr 6+ Version. Add to the array for each version required to be downloaded and installed.
    @('6-3-0', '7-6-0', '8-7-0') |% {
        $FilePath = Join-Path $solrBase "$($_).zip"
        if(!(Test-Path (Join-Path $solrBase $_))) {
            Invoke-WebRequest -Uri "https://github.com/RichMercer/TIM-Search/blob/master/$($_).zip?raw=true" -OutFile $FilePath
    
            Expand-Archive $FilePath $SolrBase
            Remove-Item $FilePath

            $PortNumber = "8$($_.Replace('-', ''))"
            $InstallScript = Join-Path $SolrBase "$($_)/bin/ServiceInstall.ps1"
            &$InstallScript -ServiceName "TIM-Search-$($_)" -DisplayName "TIM Search $($_)" -Port $PortNumber
        }
    }
}

function Initalize-Environment
{
    param(
        [Parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$true)]
        [string]$DatabaseServerInstance
    )
    #Set Package Location
    [Environment]::SetEnvironmentVariable('TelligentInstanceManager', $InstallDirectory)
    [Environment]::SetEnvironmentVariable('TelligentInstanceManager', $InstallDirectory, 'Machine')

    #Set DB Instance Name, if supplied
    [Environment]::SetEnvironmentVariable('TelligentDatabaseServerInstance', $DatabaseServerInstance)
    [Environment]::SetEnvironmentVariable('TelligentDatabaseServerInstance', $DatabaseServerInstance, 'Machine')
}

function Write-Telligent
{
	$hostColor = $host.UI.RawUI.BackgroundColor
	if($hostColor -eq [ConsoleColor]::Black -or $hostColor -match "Dark") {
		$textColour = [ConsoleColor]::White
	}
	else {
		$textColour  = [ConsoleColor]::Black
	}
	function Write-LogoPart
	{
		[CmdletBinding()]
		param(
			[Parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part1,
			[Parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part2,
			[Parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part3,
			[Parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part4
		)
		Write-Host ' ' -NoNewLine
		Write-Host $part1 -ForegroundColor Blue -NoNewline
		Write-Host $part2 -ForegroundColor DarkCyan -NoNewline
		Write-Host $part3 -ForegroundColor Cyan -NoNewline
		Write-Host $part4 
	}


	Write-LogoPart "__ " "__ " "__  " " _       _ _ _                  _   "
	Write-LogoPart "\ \" "\ \" "\ \ " "| |_ ___| | (_) ___  ___   ___ | |_ "
	Write-LogoPart " \ \" "\ \" "\ \" "| __/ _ \ | | |/ _ \/ _ \ / _ \| __| "
	Write-LogoPart " / /" "/ /" "/ /" "| |_| __/ | | | (_| |  _/| | | | |_ "
	Write-LogoPart "/_/" "/_/" "/_/ " " \__\___|_|_|_|\__, |\___|_| |_|\__|"
	Write-LogoPart "   " "   " "    " "               |___/                "
	Write-Host
}

function Expand-Zip {
	<#
	.Synopsis
		Extracts files or directories from a zip folder
	.Parameter Path
	    The path to the Zip folder to extract
	.Parameter Destination
	    The location to extract the files to
    .Parameter ZipDirectory
        The directory within the zip folder to extract. If not specified, extracts the whole zip file
    .Parameter ZipFileName
        The name of a specific file within ZipDirectory to extract
	.Example 
		Expand-Zip c:\sample.zip c:\files\
		
		Description
		-----------
		This command extracts the entire contents of c:\sample.zip to c:\files\	
	.Example
		Expand-Zip c:\sample.zip c:\sample\web\ -ZipDirectory web
		
		Description
		-----------
		This command extracts the contents of the web directory	of c:\sample.zip to c:\sample\web
	.Example
		Expand-Zip c:\sample.zip c:\test\ -ZipDirectory documentation -zipFileName sample.txt
		
		Description
		-----------
		This command extracts the sample.txt file from the web directory of c:\sample.zip to c:\sample\sample.txt
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Path,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Container -IsValid)})]
        [string]$ZipDirectory,
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Leaf -IsValid)})]
        [string]$ZipFileName
    )

    $prefix = ''
    if($ZipDirectory){
        $prefix = ($ZipDirectory).Replace('\','/').Trim('/') + '/'
    }
    if (!(test-path $Destination -PathType Container)) {
        New-item $Destination -Type Directory | out-null
    }

    #Convert path requried to ensure 
    $absoluteDestination = (Resolve-Path $Destination).ProviderPath
    $zipAbsolutePath = (Resolve-Path $Path).ProviderPath

    $zipPackage = [IO.Compression.ZipFile]::OpenRead($zipAbsolutePath)
    try {
        $entries = $zipPackage.Entries
        if ($ZipFileName){
            $entries = $entries |
                ? {$_.FullName.Replace('\','/') -eq "${prefix}${ZipFileName}"} |
                select -First 1
        }
        else {
            #Filter out directories
            $entries = $zipPackage.Entries |? Name
            if ($ZipDirectory) {
                #Filter out items not under requested directory
                $entries = $entries |? { $_.FullName.Replace('\','/').StartsWith($prefix, "OrdinalIgnoreCase")}
            }
        }

        $totalFileSize = ($entries |% length | Measure-Object -sum).Sum
        $processedFileSize = 0
        $entries |% {
            $destination = join-path $absoluteDestination $_.FullName.Substring($prefix.Length)
            <#
            Write-Progress 'Extracting Zip' `
                -CurrentOperation $_.FullName `
                -PercentComplete ($processedFileSize / $totalFileSize * 100)
            #>
                      
            $itemDir = split-path $Destination -Parent
            if (!(Test-Path $itemDir -PathType Container)) {
                New-item $itemDir -Type Directory | out-null
            }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($_, $Destination, $true)

            $processedFileSize += $_.Length
        }
        #Write-Progress 'Extracting-Zip' -Completed
        
    }
    finally {
        $zipPackage.Dispose()
    }
}