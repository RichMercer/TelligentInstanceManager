#Requires -Version 3
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false, HelpMessage="The path where Tomcat is installed.  Used to add Tomcat contexts used for Solr multi core setup.")]
    [ValidateScript({$_ -and (Test-TomcatPath $_) })]
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

    #Check for required modules
    @('webadministration','sqlps') |
        ? { !(Get-Module $_ -ListAvailable) } |
        % { Write-Error "Required Module '$_' is not available" }

    #Warn for pre-existing modules
    @( 'CommunityAddons','CommunityBuilder', 'DevCommunity') |
        % { Get-Module $_ -ListAvailable } |
        ? { $_} |
        % { Write-Warning "'$($_.Name)' module already installed at '$($_.ModuleBase)'" } 
}

function Get-TomcatLocation {
    @(
        "${env:ProgramFiles}\Apache Software Foundation\Tomcat 8.0"
        "${env:ProgramFiles(x86)}\Apache Software Foundation\Tomcat 8.0"
        "${env:ProgramFiles}\Apache Software Foundation\Tomcat 7.0"
        "${env:ProgramFiles(x86)}\Apache Software Foundation\Tomcat 7.0"
        "${env:ProgramFiles}\Apache Software Foundation\Tomcat 6.0"
        "${env:ProgramFiles(x86)}\Apache Software Foundation\Tomcat 6.0"
    ) |
		? { Test-TomcatPath $_ } |
		select -First 1
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
        [string]$TomcatDirectory
    )

    $tomcatContext = @"
<Context docBase="{0}" debug="0" crossContext="true" >
   <Environment name="solr/home" type="java.lang.String" value="{1}" override="true" />
</Context>
"@
    $legacySolrXml = @"
<?xml version='1.0' encoding='UTF-8'?>
<solr sharedLib="lib" persistent="true">
    <cores adminPath="/admin/cores" />
</solr>
"@
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
    $tomcatContextDirectory = Join-Path $TomcatDirectory conf\Catalina\localhost

	if(!(Test-Path $tomcatContextDirectory)) {
		Write-Host "Creating $tomcatContextDirectory"
		New-Item $tomcatContextDirectory -ItemType Directory | Out-Null
	}
	
    #It's not actually Solr 4-0, but changing this may break some previous users of the scripts
    @('1-4', '3-6', '4-5-1', '4-10-3') |% {
        $solrHome = Join-Path $solrBase $_
        $contextPath = Join-Path $tomcatContextDirectory "${_}.xml" 

        if (Test-Path $contextPath) {
            #Don't treat existing context file as an error - most likely means it's already set up
            Write-Verbose "Not seting up Multi Core Solr $_ Instance - manually ensure this is set up. Context already exists at '$contextPath'"
        }
        elseif (Test-Path $solrHome) {
            Write-Warning "Not seting up Multi Core Solr $_ Instance - manually ensure this is set up. SolrHome already exists at '$solrHome'"
        }        
        else {
            Write-Host "Installing Solr $_"
            New-Item $solrHome -ItemType Directory | Out-Null

            #Create Solr.xml to enable multicore
            $solrXml = if($_ -in '1-4', '3-6') { $legacySolrXml } else { $modernSolrXml}
            $solrXmlPath = Join-Path $solrHome solr.xml 
            $solrXml | out-file $solrXmlPath -Encoding utf8

            #Create context file
            $war = Join-Path $solrBase "solr_${_}.war"
            $tomcatContext -f $war, $solrHome | out-file $contextPath
        }
    }

    Write-Progress 'Telligent Mass Install Setup' 'Restarting Tocmat' -PercentComplete 50
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
if (!$TomcatDirectory) {
    $TomcatDirectory = Get-TomcatLocation
	if (!$TomcatDirectory) {
		Write-Error 'Could not auto-detect Tomcat location.  Please run the command with the -TomcatDirectory paramater to specify this location manually'
	}
}
else {
	if (!(Test-TomcatPath $TomcatDirectory)) {
		Write-Error "'$TomcatDirectory' does not contain a valid Tomcat instance"
	}
}

Test-Prerequisites
if ($Error.Count -ne $initialErrorCount) {
    throw 'Prerequisites not met (see previous errors for more details)'
}

#Make Required Folders
@('Licences', 'FullPackages', 'Hotfixes', 'Web') |
    % { Join-Path $installDirectory $_} |
    ? {!(Test-Path $_)} |
    % {new-item $_ -ItemType Directory | Out-Null}

Write-Progress 'Telligent Mass Install Setup' 'Installing Solr Dependencies to Tomcat Lib'-PercentComplete 10
$tomcatLib= Join-Path "$TomcatDirectory" 'lib'
$libSource = Join-Path $PSScriptRoot 'Solr\_tomcatlib\*'
Copy-Item $libSource  $tomcatLib

Write-Progress 'Telligent Mass Install Setup' 'Installing Solr Multi Cores'-PercentComplete 20
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
    Write-Warning "No Licenses available for installation at '$licencePath' "
    Write-Warning "Add files to this directory with filenames of the format 'Community7.xml', 'Enterprise4.xml' etc."
}

$fullPackagePath = Join-Path $installDirectory FullPackages
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning "No Base Packages are available for Installation at '$fullPackagePath'."
}

$hotfixPackagePath = Join-Path $installDirectory FullPackages
if (!(Get-ChildItem $hotfixPackagePath -ErrorAction SilentlyContinue)){
    Write-Warning "No Hotfixes are available for Installation at '$hotfixPackagePath'."
    Write-Warning 'N.B. to install a hotfix, you must have a full packages with the same Major and Minor build number'
}

Write-Host
Write-Host 'Telligent Mass Installer installation  complete' -ForegroundColor Green
Write-Host @"
For more details on how to use the Mass Installer, use the Get-Help cmdlet to learn more about the following comamnds
* Get-CommunityBuild (gcb)
* Install-DevCommunity (isdc)
* Remove-DevCommunity (rdc)

"@