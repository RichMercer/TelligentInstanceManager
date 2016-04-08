#Requires -Version 3

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
    @('webadministration','sqlps') |
        ? { !(Get-Module $_ -ListAvailable) } |
        % { Write-Error "Required Module '$_' is not available" }
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

    # TODO: Download files here

	if(!(Test-Path $tomcatContextDirectory)) {
		Write-Host "Creating $tomcatContextDirectory"
		New-Item $tomcatContextDirectory -ItemType Directory | Out-Null
	}
	
    @('3-6', '4-5-1', '4-10-3') |% {
        $solrHome = Join-Path $solrBase $_
        $contextPath = Join-Path $tomcatContextDirectory "${_}.xml" 

        if(!(Test-Path $solrHome)) {
            new-item $solrHome -ItemType Directory | Out-Null
        }

        $war = Join-Path $solrBase "solr_${_}.war"
        if(!(Test-Path $war)) {
            Write-Host "Downloading $war"
            $warUri = "https://github.com/afscrome/TelligentInstanceManager/blob/master/Solr/solr_${_}.war?raw=true"
            Invoke-WebRequest -Uri $warUri -OutFile $war 
        }        

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
            $tomcatContext -f $war, $solrHome | out-file $contextPath
        }
    }

    Write-Progress 'Telligent Instance Manager Setup' 'Restarting Tocmat' -PercentComplete 50
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
    [Environment]::SetEnvironmentVariable('TelligentInstanceManager', $InstallDirectory)
    [Environment]::SetEnvironmentVariable('TelligentInstanceManager', $InstallDirectory, 'Machine')
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

function Initialize-TelligentInstanceManager {
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true, HelpMessage="The path where Telligent Instances Manager will store instances and builds.")]
    [string]$InstallDirectory,
    [Parameter(Mandatory=$false, HelpMessage="The path where Tomcat is installed.  Used to add Tomcat contexts used for Solr multi core setup.")]
    [ValidateScript({$_ -and (Test-TomcatPath $_) })]
    [string]$TomcatDirectory,
    [switch]$Force
)

#Banner
Write-Telligent
Write-Host "Telligent Instance Manager"
Write-Host

#Test Prerequisites
$initialErrorCount = $Error.Count
Write-Progress "Telligent Instance Manager Setup" "Checking Prerequisites" -CurrentOperation "This may take a few moments"
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

Test-Prerequisites $installDirectory
if ($Error.Count -ne $initialErrorCount) {
    throw 'Prerequisites not met (see previous errors for more details)'
}

#Make Required Folders
@('Licences', 'TelligentPackages', 'Web', 'Solr') |
    % { Join-Path $InstallDirectory $_} |
    ? {!(Test-Path $_)} |
    % {new-item $_ -ItemType Directory | Out-Null}

Write-Progress 'Telligent Instance Manager Setup' 'Installing Solr Dependencies to Tomcat Lib'-PercentComplete 10
$tomcatLib= Join-Path "$TomcatDirectory" 'lib'
#TODO: Download required files from git here
#$libSource = Join-Path $PSScriptRoot 'Solr\_tomcatlib\*'
#Copy-Item $libSource  $tomcatLib

Write-Progress 'Telligent Instance Manager Setup' 'Installing Solr Multi Cores'-PercentComplete 20
$solrParams = @{}
if ($TomcatDirectory) {
    $solrParams.TomcatDirectory = $TomcatDirectory
}
Install-SolrMultiCore -InstallDirectory $InstallDirectory @solrParams

Write-Progress 'Telligent Instance Manager Setup' 'Setting Environmental Variables' -PercentComplete 70
Initalize-Environment $InstallDirectory

Write-Progress 'Telligent Instance Manager Setup' "Ensuring files are unblocked" -PercentComplete 80
Get-ChildItem $InstallDirectory -Recurse | Unblock-File

Write-Progress 'Telligent Instance Manager Setup' -Completed

#Provide hints for finishing installation
$licencePath = Join-Path $InstallDirectory Licences 
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning "No Licenses available for installation at '$licencePath' "
    Write-Warning "Add files to this directory with filenames of the format 'Community8.xml', 'Community9.xml' etc."
}

$packagesPath = Join-Path $InstallDirectory TelligentPackages
if (!(Get-ChildItem $licencePath -ErrorAction SilentlyContinue)){
    Write-Warning "No packages are available for Installation at '$fullPackagePath'."
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