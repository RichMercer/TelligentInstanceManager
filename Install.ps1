[cmdletbinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true)]
	[ValidateScript({Test-Path $_ -PathType Container -IsValid})]
    [string]$InstallDirectory,
    [parameter(Mandatory=$true)]
    [ValidateScript({(Test-Path $_ -PathType Container) -and (Join-Path $_ conf\server.xml | Test-Path -PathType Leaf) })]
    [string]$TomcatDirectory,
    [switch]$Force
)

$scriptPath = Join-Path $PSScriptRoot Scripts
$scriptsDirectory = Join-Path $InstallDirectory Scripts


function Test-Prerequisites
{
    #Check Admin
    $currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
           Write-Error "Installation requires Administrative credentials"
    }

    #Powershell 3.0
    if($PSVersionTable.PSVersion -lt 3.0.0.0){
        Write-Error "Powershell Version 3 required"
    }

    #.net 4.5
    try{ Add-Type -AssemblyName System.IO.Compression }
    catch { Write-Error '.Net 4.5 not installed' }

    #Check Modules
    $availableModules = Get-Module -ListAvailable | select -ExpandProperty Name

    if($availableModules -notcontains 'WebAdministration') {
        Write-Error 'WebAdministration powershell module not available'
    }
    if($availableModules -notcontains 'sqlps') {
        Write-Error 'SQL Powershell not installed'
    }

    if ($availableModules -contains 'Evolution') {
        $modulePath = (Get-Module evolution -ListAvailable).Path
        Write-Warning "Evolution module already installed at $modulePath"
    }
    if ($availableModules -contains 'DevEvolution') {
        $modulePath = (Get-Module evolution -ListAvailable).Path
        Write-Warning  "DevEvolution module already installed at $modulePath"
    }
}

function Install-EvolutionInstallation
{
    param(
        [parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory,
        [parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$SourceDirectory
    )

    #Remove Scripts directory if it exists
    if(Test-Path $scriptsDirectory){
        if(!($Force -or $PSCmdlet.ShouldContinue("Scripts already exist at '$scriptsDirectory'.  Continuing will delete the contents of this directory", 'Overwrite?')))
        {
            return
        }
        Write-Warning "Replacing Script directory '$scriptsDirectory'"
        $scriptsDirectory| remove-item -Recurse
    }
    #Make Required Folders
    @('Licences', 'FullPackages', 'Hotfixes', 'Web', 'Scripts', 'Solr') |
        % { Join-Path $InstallDirectory $_} |
        ? {!(Test-Path $_)} |
        % {new-item $_ -ItemType Directory | Out-Null}

    #Copy Scripts
    $scriptsDestination = Join-Path $InstallDirectory Scripts
    Join-Path $SourceDirectory Scripts |
        get-childitem -Directory |
        %{ copy-item $_.FullName $scriptsDestination -Recurse }
}


function Install-SolrMultiCore {
    param(
        [parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$InstallDirectory,
        [parameter(Mandatory=$true)]
	    [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$SourceDirectory,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container })]
        [string]$ContextDir
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

    Join-Path $SourceDirectory Solr |
        Get-ChildItem -Filter *.war |
        % { Copy-Item $_.FullName $solrBase }

    @('1-4', '3-6') |% {
        $solrHome = Join-Path $solrBase $_
        $contextPath = Join-Path $contextDir "${_}.xml" 

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
        [parameter(Mandatory=$true)]
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
			[parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part1,
			[parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part2,
			[parameter(Mandatory=$true)]
			[ValidateNotNullOrEmpty()]
			[string]$part3,
			[parameter(Mandatory=$true)]
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


Write-Progress "Telligent Mass Install Setup" "Installing files to $InstallDirectory" -PercentComplete 40
Install-EvolutionInstallation -InstallDirectory $InstallDirectory -SourceDirectory $PSScriptRoot


Write-Progress 'Telligent Mass Install Setup' 'Installing Solr Multi Cores'-PercentComplete 60
$tomcatContextDirectory = Join-Path $TomcatDirectory conf\Catalina\localhost
Install-SolrMultiCore -ContextDir $TomcatContextDirectory -InstallDirectory $InstallDirectory -SourceDirectory $PSScriptRoot

Write-Progress 'Telligent Mass Install Setup' 'Setting Environmental Variables' -PercentComplete 70
Initalize-Environment $InstallDirectory

Write-Progress 'Telligent Mass Install Setup' "Unblocking files under $InstallDirectory" -PercentComplete 80
Get-ChildItem $InstallDirectory -Recurse | Unblock-File

Write-Progress 'Telligent Mass Install Setup' -Completed

#Provide hints for finishing installation
$licencePath = Join-Path $InstallDirectory Licences 
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Licenses available for installation'
    Write-Host "Add licences to '$licencePath' with filenames of the format 'Community7.xml', 'Enterprise4.xml' etc."
}

$fullPackagePath = Join-Path $InstallDirectory FullPackages
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Base Packages are available for Installation'
    Write-Host "Add full installation packages to '$fullPackagePath'."
}

$hotfixPackagePath = Join-Path $InstallDirectory FullPackages
if (!(Get-ChildItem $hotfixPackagePath -ErrorAction SilentlyContinue)){
    Write-Warning 'No Hotfixes are available for Installation'
    Write-Host "Add hotfix installation packages to '$hotfixPackagePath'."
    Write-Host 'N.B. to install a hotfix, you must have a full packages with the same Major and Minor build number'
}

Write-Host
Write-Host 'Telligent Mass Installer installation  complete' -ForegroundColor Green
Write-Host @"
For more details on how to use the Mass Installer, use the Get-Help cmdlet to learn more about the following comamnds
* Get-EvolutionBuild (geb)
* Install-DevEvolution (isde)

"@