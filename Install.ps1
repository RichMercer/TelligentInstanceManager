[cmdletbinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true)]
	[ValidateScript({Test-Path $_ -PathType Container -IsValid})]
    [string]$InstallDirectory = 'C:\temp\evoauto',
    [parameter(Mandatory=$true)]
    [ValidateScript({(Test-Path $_ -PathType Container) -and (Join-Path $_ conf\server.xml | Test-Path -PathType Leaf) })]
    [string]$TomcatContextDirectory,
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


function Install-SolrMultiCore {
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript({ Invoke-WebRequest $_ -UseBasicParsing -Method HEAD })]
        [uri]$uri,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container })]
        [string]$contextDir
    )

    $tomcatContext = @"
<Context docBase="{0}" debug="0" crossContext="true" >
   <Environment name="solr/home" type="java.lang.String" value="{1}" override="true" />
</Context>
"@
    
    $solrBase = Join-Path $baseLocation Solr
    @('1-4', '3-6') |% {
        $contextPath = Join-Path $contextDir "${_}.xml" 
        if (Test-Path $contextPath) {
            Write-Warning "Context '$contextPath' already exists"
        }
        else {
            $war = Join-Path $solrBase "solr_${_}.war"
            $solrHome = Join-Path $solrBase $_

            $tomcatContext -f $war, $solrHome | out-file $contextPath
        }
    }

    Restart-Service tomcat* -ErrorAction Continue
}


function Initalize-Environment
{
    #Set Package Location
    [Environment]::SetEnvironmentVariable('EvolutionPackageLocation', $baseLocation)
    [Environment]::SetEnvironmentVariable('EvolutionPackageLocation', $baseLocation, 'Machine')

    #Add script folder to PSModule Paths
    $psModulePaths = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';'
    if ($psModulePaths -notcontains $scriptPath) {
        $psModulePaths += $scriptPath
        #Set for both machine & current process
        [Environment]::SetEnvironmentVariable('PSModulePath', ($psModulePaths -join ';'))
        [Environment]::SetEnvironmentVariable('PSModulePath', ($psModulePaths -join ';'), 'Machine')
        Write-Host "Added $scriptPath to %PSModulePath%"
    }
}


#Test Prerequisites
$Error.Clear()
Write-Host 'Checking Prerequisites'
Test-Prerequisites
if ($Error) {
    throw 'Prerequisites not met'
}


#Create Files
if(!(Test-Path $InstallDirectory)) {
    New-Item $InstallDirectory -ItemType Directory | out-null
}
elseif(Test-Path $scriptsDirectory){
    if(!($Force -or $PSCmdlet.ShouldContinue("Scripts already exist at '$scriptsDirectory'.  Continuing will delete the contents of this directory", 'Overwrite?')))
    {
        return
    }
    Write-Warning "Removing '$scriptsDirectory'"
    Join-Path $scriptPath * | remove-item -Recurse
}
#Copy Scripts
Copy-Item


#Install Solr MultiCores
Write-Host 'Installing Solr Multi Cores'
Install-EvolutionPowershellSolrCores http://localhost:8080/ $tomcatContextDir

#Now set add scripts to PSModulePath
Initalize-Environment

Write-Host "Installed to '$baseLocation'" 
Write-Host "2. Add full installation packages to 'FullPackages' to show up in the Get-EvolutionBuild command"
Write-Host "3. Add hotfix packages to 'Hotfixes' to show up in the Get-EvolutionBuild command (note, you must have a correspondign full package with the same major and minor build number"

$licencePath = Join-Path $baseLocation Licenses 
if (!(Test-Path $licencePath )){
    Write-Warning 'No Licenses available for installation'
    Write-Host "Add licences to '$licencePath' with filenames of the format 'Community7.xml', 'Enterprise4.xml' etc."
}

$fullPackagePath = Join-Path $baseLocation FullPackages
if (!(Test-Path $licencePath )){
    Write-Warning 'No Base Packages are available for Installation'
    Write-Host "Add full installation packages to '$fullPackagePath'."
}

$hotfixPackagePath = Join-Path $baseLocation FullPackages
if (!(Test-Path $hotfixPackagePath )){
    Write-Warning 'No Hotfixes are available for Installation'
    Write-Host "Add hotfix installation packages to '$hotfixPackagePath'."
    Write-Host 'N.B., to install a hotfix, you must have a full packages with the same Major and Minor build number'
}
