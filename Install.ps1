#Requires -Version 3
#Requires -Modules sqlps,webadministration
###Requires -RunAsAdministrator #Requires Powershell Version 4
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false, HelpMessage="The path where Tomcat is installed.  Used to add Tomcat contexts used for Solr multi core setup.")]
    [ValidateScript({(Test-TomcatPath $_) })]
    [string]$TomcatDirectory,
    [switch]$Force
)

$installDirectory = $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot Scripts


function Test-Prerequisites
{
    #Check Admin
    $currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
           Write-Error "Installation requires Administrative credentials"
    }

    #.net 4.5 required for unzipping support
    try{ Add-Type -AssemblyName System.IO.Compression }
    catch { Write-Error '.Net 4.5 not installed' }

    #Check Modules

    if (Get-Module Evolution) {
        $modulePath = (Get-Module evolution -ListAvailable).Path
        Write-Warning "Evolution module already installed at $modulePath"
    }
    if (Get-Module DevEvolution) {
        $modulePath = (Get-Module evolution -ListAvailable).Path
        Write-Warning  "DevEvolution module already installed at $modulePath"
    }
}

function Get-TomcatLocation {
    $knownTomcatLocations = @(
        "${env:ProgramFiles}\Apache Software Foundation\Tomcat 7.0"
        "${env:ProgramFiles(x86)}\Apache Software Foundation\Tomcat 7.0"
        "${env:ProgramFiles}\Apache Software Foundation\Tomcat 6.0"
        "${env:ProgramFiles(x86)}\Apache Software Foundation\Tomcat 6.0"
    ) |? { Test-TomcatPath $_ }

    
    if($knownTomcatLocations.Count -eq 1) {
        return $knownTomcatLocations
    }
}

function Test-TomcatPath {
    param(
    	[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true)]
        [string]$TomcatPath
    )
    process {
        (Test-Path $TomcatPath -PathType Container) `
            -and (Join-Path $TomcatPath conf\server.xml | Test-Path -PathType Leaf)
    }
}

function Install-SolrMultiCore {
    param(
        [Parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-TomcatPath $_ })]
        [string]$TomcatDir
    )

    $tomcatContext = @"
<Context docBase="{0}" debug="0" crossContext="true" >
   <Environment name="solr/home" type="java.lang.String" value="{1}" override="true" />
</Context>
"@
    $solrXml = @"
<?xml version='1.0' encoding='UTF-8'?>
<solr sharedLib="lib" persistent="true">
    <cores adminPath="/admin/cores" />
</solr>
"@
    
    $solrBase = Join-Path $InstallDirectory Solr
    $tomcatContextDirectory = Join-Path $TomcatDirectory conf\Catalina\localhost

    @('1-4', '3-6', '4-0') |% {
        $solrHome = Join-Path $solrBase $_
        $contextPath = Join-Path $tomcatContextDirectory "${_}.xml" 

        if (Test-Path $solrHome) {
            Write-Warning "Not seting up Multi Core Solr $_ Instance - manually ensure this is set up. SolrHome already exists at '$solrHome'"
        }        
        elseif (Test-Path $contextPath) {
            Write-Warning "Not seting up Multi Core Solr $_ Instance - manually ensure this is set up. Context already exists at '$contextPath'"
        }
        else {
            Write-Host "Installing Solr $_"
            #Create Core Directory
            New-Item $solrHome -ItemType Directory | Out-Null

            #Create Solr.xml to enable multicore
            $solrXmlPath = Join-Path $solrHome solr.xml 
            $solrXml | out-file $solrXmlPath -Encoding utf8

            #Create context file
            $war = Join-Path $solrBase "solr_${_}.war"
            $tomcatContext -f $war, $solrHome | out-file $contextPath
        }
    }
    "Restarting Tomcat"
    Restart-Service tomcat* -ErrorAction Continue
}


function Initalize-Environment
{
    param(
        [Parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory
    )
    #Set Package Location
    [Environment]::SetEnvironmentVariable('EvolutionMassInstall', $InstallDirectory)
    [Environment]::SetEnvironmentVariable('EvolutionMassInstall', $InstallDirectory, 'Machine')

    #Add script folder to PSModule Paths
    $scriptPath = Join-Path $InstallDirectory Scripts
    $psModulePaths = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';'
    if ($psModulePaths -notcontains $scriptPath) {
        $psModulePaths += $scriptPath
        #Set for both machine & current process
        [Environment]::SetEnvironmentVariable('PSModulePath', ($psModulePaths -join ';'))
        [Environment]::SetEnvironmentVariable('PSModulePath', ($psModulePaths -join ';'), 'Machine')
        Write-Host "Added $scriptPath to %PSModulePath%"
    }
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

#Banner
Write-Telligent
Write-Host "Telligent Evolution Mass Installer"
Write-Host

#Test Prerequisites
$initialErrorCount = $Error.Count
Write-Progress "Telligent Mass Install Setup" "Checking Prerequisites" -CurrentOperation "This may take a few moments"
Test-Prerequisites
if ($Error.Count -ne $initialErrorCount) {
    throw 'Prerequisites not met (see previous errors for more details)'
}

#Make Required Folders
@('Licences', 'FullPackages', 'Hotfixes', 'Web') |
    % { Join-Path $installDirectory $_} |
    ? {!(Test-Path $_)} |
    % {new-item $_ -ItemType Directory | Out-Null}

Write-Progress 'Telligent Mass Install Setup' 'Installing Solr Multi Cores'-PercentComplete 10
$solrParams = @{}
if ($TomcatDirectory) {
    $solrParams.TomcatDirectory = $TomcatDirectory
}
Install-SolrMultiCore -InstallDirectory $installDirectory @solrParams

Write-Progress 'Telligent Mass Install Setup' 'Setting Environmental Variables' -PercentComplete 70
Initalize-Environment $installDirectory

Write-Progress 'Telligent Mass Install Setup' "Ensuring files are unblocked" -PercentComplete 80
Get-ChildItem $installDirectory -Recurse | Unblock-File

Write-Progress 'Telligent Mass Install Setup' -Completed

#Provide hints for finishing installation
$licencePath = Join-Path $installDirectory Licences 
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Licenses available for installation'
    Write-Host "Add licences to '$licencePath' with filenames of the format 'Community7.xml', 'Enterprise4.xml' etc."
}

$fullPackagePath = Join-Path $installDirectory FullPackages
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Base Packages are available for Installation'
    Write-Host "Add full installation packages to '$fullPackagePath'."
}

$hotfixPackagePath = Join-Path $installDirectory FullPackages
if (!(Get-ChildItem $hotfixPackagePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Hotfixes are available for Installation'
    Write-Host "Add hotfix installation packages to '$hotfixPackagePath'."
    Write-Host 'N.B. to install a hotfix, you must have a full packages with the same Major and Minor build number'
}

Write-Host
Write-Host 'Telligent Mass Installer installation  complete' -ForegroundColor Green
Write-Host @"
For more details on how to use the Mass Installer, use the Get-Help cmdlet to learn more about the following comamnds
* Get-CommunityBuild (gcb)
* Install-DevCommunity (isdc)
* Remove-DevCommunity (rdc)

"@