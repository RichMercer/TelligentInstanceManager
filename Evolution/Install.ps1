function Install-Evolution {
	<#
	.Synopsis
		Sets up a new Evolution Community.
	.Description
		The Install-Evolution cmdlet automates the process of creating a new Telligent Evolution community.
		
		It takes the installation package, and from it deploys the website to IIS and a creates a new database using
		the scripts from the package.  It also sets permissions automatically.
		
		Optionally, you can specify a path to a licence file and this will be installed into your community.
		
		By default, authentication between the web and databases uses the Applicaiton Pool Identity, but SQL authentiation
		is used if an explicity username & password are provided.
	.Parameter package
	    The path to the zip package containing the Telligent Evolution installation files from Telligent Support
	.Parameter hotfixPackage
	    If specified applys the hotfix from the referenced zip file.
	.Parameter name
	    The name of the community to create
	.Parameter webDir
	    The directory to place the Telligent Evolution website in
	.Parameter webDomain
	    The domain name the community will be accessible at
	.Parameter appPool
	    The name of the Applicaiton Pool to use the community with.  If not specified creates a new apppool.
	.Parameter dbServer
	    The DNS name of your SQL server.  Must be able to connect using Windows Authenticaiton from the current machine.  Only supports Default instances.
	.Parameter dbName
	    The name of the database to locate your community in.  Defaults to the value provided for name.
	.Parameter sqlAuth
	    Specify if you want your community to connect using SQL Auth
	.Parameter dbUsername
	    If using SQL Authentication for your community to connect to the database, the username to use.  If this use doesn't exist, it will be created.
	.Parameter dbPassword
	    If using SQL Authentication for your community to connect to the database, the password to use.	
	.Parameter searchUrl
	    The url your community's solr instance can be found at
	.Parameter licenceFile
	    The path to the licence XML file to install in the community
	.Example Standard install using Windows Auth to connect to DB
		Install-Evolution -name "Telligent Evolution" -package "d:\temp\TelligentCommunity-7.0.1824.27400.zip" -webDir "d:\inetpub\TelligentEvolution\" -webdomain "mydomain.com" -searchUrl "http://localhost:8080/solr/"
	.Example Standard install using SQL Auth to connect to DB, as well as specifying a licence file
		Install-Evolution -name "Telligent Evolution" -package "d:\temp\TelligentCommunity-7.0.1824.27400.zip" -webDir "d:\inetpub\TelligentEvolution\" -webdomain "mydomain.com" -searchUrl "http://localhost:8080/solr/" -dbUsername "TellgientEvolutionSql" -dbPassword "Mega$ecretP@$$w0rd" -licenceFile "c:\licence.xml"
	#>
    [CmdletBinding(DefaultParameterSetName='WindowsAuth')]
    param (
		#Packages
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [string]$hotfixPackage,

		#Web Settings
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDir, #TODO: Validate Dir is Empty
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDomain,
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path IIS:\AppPools\$_})]
		[string]$appPool, #TODO: Validate AppPool Exists

		#Database Connection
        [ValidateNotNullOrEmpty()]
        [string]$dbServer = "(local)", #TODO: Validate SQL Server can be found
        [ValidateNotNullOrEmpty()]
        [string]$dbName = $name,
		
		#Database Auth
		[parameter(ParameterSetName='SqlAuth')]
        [switch]$sqlAuth,
        [parameter(ParameterSetName='SqlAuth', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbUsername,
        [parameter(ParameterSetName='SqlAuth', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbPassword,

		#Misc
        [ValidateNotNullOrEmpty()]
		#[ValidateScript({(New-Object System.Net.WebClient).DownloadString("$_/admin/")})]
        [uri]$searchUrl, #TODO: Validate Search Url
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$licenceFile
    )   
    $ErrorActionPreference = "Stop"

	if(!$appPool){
		#TODO: Test if app pool exists before creating new one
		$appPool = $name
		New-IISAppPool $appPool -netVersion 4.0
	}
	$sqlConnectionSettings = @{
		dbServer = $dbServer
		dbName = $dbName
	}
	$sqlAuthSettings = @{}
	if($sqlAuth) {
		$sqlAuthSettings.username = $dbUsername
		$sqlAuthSettings.password = $dbPassword
	}
	else {
		$sqlAuthSettings.username = Get-IISAppPoolIdentity $name
	}
	
    New-EvolutionWebsite -name $name `
		-path $webDir `
		-package $package `
		-domain $webDomain `
		-appPool $appPool

    Install-EvolutionDatabase -package $package -webDomain $webDomain @sqlConnectionSettings 
    Grant-EvolutionDatabaseAccess @sqlConnectionSettings @sqlAuthSettings

	if($hotfixPackage) {
        Install-EvolutionHotfix -communityDir $webDir -package $hotfixPackage @sqlConnectionSettings
	}	

	pushd $webdir 
    try {
        Set-ConnectionStrings @sqlConnectionSettings @sqlAuthSettings
		if($searchUrl) {
	        Set-EvolutionSolrUrl $searchUrl
		}
		else {
			Write-Warning "No search url specified.  Many features will not work until search is configured."
		}

		if ($licenceFile) {
        	Install-EvolutionLicence $licenceFile @sqlConnectionSettings 
		}
		else {
			Write-Warning "No Licence installed."
		}
    }
    finally {
    	popd
    }
}

function Install-EvolutionHotfix {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$communityDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [ValidateNotNullOrEmpty()]
        [string]$dbServer = "(local)",
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbName
    )
    
    Write-Progress "Applying Hotfix" "Updating Web"
    Expand-Zip -zipPath $package -destination $communityDir -zipDir "Web"
   
    Write-Progress "Applying Hotfix" "Updating Database"
    $tempDir = join-path $env:temp ([guid]::NewGuid())
    @("update.sql", "updates.sql") |% {
        Expand-Zip -zipPath $package -destination $tempDir -zipFile $_
        $sqlPath = join-path $tempDir $_
        if (test-path $sqlPath) {
            Invoke-Sqlcmd -serverinstance $dbServer -Database $dbName -InputFile $sqlPath |out-null
        }
    }
   
}

