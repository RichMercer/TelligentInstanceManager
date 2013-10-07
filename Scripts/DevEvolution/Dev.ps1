$base = $env:EvolutionMassInstall
if (!$base) {
    Write-Error 'EvolutionMassInstall environmental variable not defined'
}

$pathData = @{
    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = Join-Path $base Licences | Resolve-Path

    # The directory where web folders are created for each website
	WebBase = Join-Path $base Web

    #Solr Url for solr cores.
    #{0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = 'http://localhost:8080/{0}'

    # Solr core Directories.
    # {0} gets replaced in the same way as for SolrUrl
	SolrCoreBase = Join-Path $base 'Solr\{0}\'
}

<#
.Synopsis
	Sets up a new Telligent Evolution community for development purposes.
.Description
	The Install-Evolution cmdlet automates the process of creating a new Telligent Evolution community.
		
	It takes the installation package, and from it deploys the website to IIS and a creates a new database using
	the scripts from the package.  It also sets permissions automatically.
		
	This scripts install the new community as follows (where NAME is the value of the name paramater)

		
    If a Telligent Enterprise instance is being installed, Windows Authentication will be enabled automatically
.Parameter name
	The name of the community to create. This is used when creating the locations used by the community.
		* Web Files - %EvolutionMassInstall%\Web\NAME\
		* Database Server - (local)
		* Database name NAME
		* Solr Url - http://localhost:8080/3-6/NAME/ (or 1-4 for versions using solr 1.4)
		* Solr Core - %EvolutionMassInstall%\Solr\3-6\NAME\ (or 1-4 for versions using solr 1.4)
		* Url - http://NAME.local/ (entry automatically added to hosts file)
		* Jobs run in web process
		* Custom Errors disabled

.Parameter Product
	The product being installed.  This along with the version is used to determine what version to determine
		* The version of .net to use
		* The version of Solr to use
		* The licence file to install
		* Whether Windows Authenticaiton should be enabled
		* Whether Jobs should be enabled in the web process
	
.Parameter Version
	The version being installed.  See documentation for Product parameter for more details on how this is used.

.Parameter BasePackage
	The path to the zip package containing the Telligent Evolution installation files, provided by Telligent Support.

.Parameter HotfixPackage
	If specified applys the hotfix from the referenced zip file to the community.

.Parameter Version
	The version being installed.  This is used to determine what version of .net to use for the app pool, and which version of Solr to use.

.Parameter NoSearch
	Specify this switch to not set up a new search instance

.Example
    Get-EvolutionBuild 7.6 | Install-DevEvolution TestSite
        
    Output can be piped from Get-EvolutionBuild to automatically fill in the product, version, basePackage and hotfixPackage paramaters
    
				
#>
function Install-DevEvolution {
    param(
        [parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
 		[ValidateSet('Community','Enterprise')]
 		[string] $product,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
        [version] $Version,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string] $BasePackage,
        [parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [string] $HotfixPackage,
        [switch] $WindowsAuth
    )
    $ErrorActionPreference = "Stop"

    $name = $name.ToLower()

    $solrVersion = if(@(2,3,5,6) -contains $Version.Major){ "1-4" } else {"3-6" }
    $webDir = (Join-Path $pathData.WebBase $Name)
    $domain = "$Name.local"

    Install-Evolution -name $Name `
        -package $BasePackage `
        -hotfixPackage $HotfixPackage `
        -webDir $webDir `
        -netVersion $(if (@(2,5) -contains $version.Major) { 2.0 } else { 4.0 }) `
        -webDomain $domain `
        -licenceFile (join-path $pathData.LicencesPath "${Product}$($Version.Major).xml") `
        -solrUrl ($pathData.SolrUrl -f $solrVersion).TrimEnd("/") `
        -solrCoreDir ($pathData.SolrCoreBase -f $solrVersion) `
        -adminPassword 'p' `
        -dbServer $env:DBServerName

    pushd $webdir 
    try {
		Disable-CustomErrors

		if(($Product -eq 'community' -and $Version -gt 5.6) -or ($Product -eq 'enterprise' -and $Version -gt 2.6)) {
            Register-TasksInWebProcess $basePackage
        }

        if ($WindowsAuth) {
            Enable-WindowsAuth -emailDomain '@tempuri.org' -profileRefreshInterval 0
        }        
    }
    finally {
    	popd
    }

    #Add site to hosts files
    Add-Content -value "127.0.0.1 $domain" -path (join-path $env:SystemRoot system32\drivers\etc\hosts)
	Write-Host "Created website at http://$domain/"
    Start-Process "http://$domain/"
}

Set-Alias isde Install-DevEvolution

function Remove-DevEvolution {
    param(
        [parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )
    $ErrorActionPreference = "Stop"

    $webDir = (Join-Path $pathData.WebBase $Name)
    
    if(!(Test-Path $webDir)) {
        return
    }

    $Version = (Get-Command $webDir\bin\Telligent.Evolution.Components.dll).FileVersionInfo.ProductVersion
    $solrVersion = if(@(2,3,5,6) -contains $Version.Major){ "1-4" } else {"3-6" }
    $domain = "$Name.local"

    #Delete the site in IIS
    if(Get-Website -Name $Name -ErrorAction SilentlyContinue) {
        Remove-Website -Name $Name
    }
    if((Join-Path IIS:\AppPools\ $Name| Test-Path)){
        Remove-WebAppPool -Name $Name
    }

    #Delete the DB
    Remove-Database -name $Name -dbServer $env:DBServerName

    #Delete the files
    if(Test-Path $webDir) {
        Remove-Item -Path $webDir -Recurse -Force
    }
    
    #Remove site from hosts files
    $hostsPath = join-path $env:SystemRoot system32\drivers\etc\hosts
    (Get-Content $hostsPath) | Foreach-Object {$_ -replace "127.0.0.1 $domain", ""} | Set-Content $hostsPath
    
    #Remove the solr core
    $solrUrl = ($pathData.SolrUrl -f $solrVersion).TrimEnd("/") + '/admin/cores'
    Remove-SolrCore -name $Name -coreBaseDir ($pathData.SolrCoreBase -f $solrVersion) -coreAdmin $solrUrl

	Write-Host "Deleted website at http://$domain/"
}