Set-StrictMode -Version 2

function Install-Community {
	<#
	.Synopsis
		Sets up a new Evolution Community.
	.Description
		The Install-Community cmdlet automates the process of creating a new Telligent Evolution community.
		
		It takes the installation package, and from it deploys the website to IIS and a creates a new database using
		the scripts from the package.  It also sets permissions automatically.
		
		Optionally, you can specify a path to a License file and this will be installed into your community.
		
		By default, authentication between the web and databases uses the Applicaiton Pool Identity, but SQL authentiation
		is used if an explicit username & password are provided.
	.Parameter Name
	    The name of the community to create
	.Parameter Package
	    The path to the zip package containing the Telligent Evolution installation files from Telligent Support
	.Parameter Hotfix
	    If specified applys the hotfix from the referenced zip file.
	.Parameter WebsitePath
	    The directory to place the Telligent Evolution website in
	.Parameter WebDomain
	    The domain name the community will be accessible at
	.Parameter ApplicationPool
	    The name of the Application Pool to use the community with.  If not specified creates a new apppool.
	.Parameter DatabaseServer
	    The DNS name of your SQL server.  Must be able to connect using Windows Authentication from the current machine.  Only supports Default instances.
	.Parameter DatabaseName
	    The name of the database to locate your community in.  Defaults to the value provided for name.
	.Parameter SqlCredential
	    Specifies the SQL Authenticaiton credential the community will use to connect to the database.  If not specified, then Windows Authentication is used (prefered).  Note, the installer will always connect using Windows Authentication to create the database.  These credentials are only used post-installation.
	.Parameter SolrBaseUrl
	    The url the base Solr instance to create the new core in.
	.Parameter AdminPassword
	    The password to use for the admin user created during installation.
	.Parameter ApiKey
	    If specified, a REST Api Key is created for the admin user with the given value.  This is useful for automation scenarios where you want to go and automate creation of content after installation.
	.Parameter FilestoragePath
	    The location to install Filestorage to.  If not specified, will use the default location ~/filestorage/ in the website.
	.Parameter License
	    The path to the License XML file to install in the community
	.Example
		Install-Community -name 'Telligent Evolution' -package d:\temp\TelligentCommunity-7.0.1824.27400.zip -webDir "d:\inetpub\TelligentEvolution\" -webdomain "mydomain.com" -searchUrl "http://localhost:8080/solr/"
		
		Description
		-----------
		Local install using Windows Auth to connect to DB

	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

		#Packages
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [string]$Hotfix,

		#Web Settings
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ -IsValid })]
        [string]$WebsitePath,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$WebDomain,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [uint16]$Port= 80,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
		[string]$ApplicationPool = $name,

		#Database Connection
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-SqlServer $_ })]
        [string]$DatabaseServer = '(local)',

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$DatabaseName = $name,
		
		#Database Auth
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [PSCredential]$SqlCredential,

		#Solr Params
		[Parameter(ParameterSetName='SolrCore', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [switch]$SolrCore,

        [Parameter(ParameterSetName='SolrCore', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Invoke-WebRequest $_ -UseBasicParsing -Method HEAD })]
        [uri]$SolrBaseUrl,

        [Parameter(ParameterSetName='SolrCore', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SolrCoreDir,

        [Parameter(ParameterSetName='SolrCore', ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$SolrCoreName = $Name,


		#Misc
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$AdminPassword ,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string]$ApiKey,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Container -IsValid)})]
        [string]$FilestoragePath,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({ Test-TelligentPath $_ -IsValid -AllowEmpty })]
        [string]$JobSchedulerPath,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Path $_ -PathType Leaf)})]
        [string]$License
    )   

    if($JobSchedulerPath -and -not $FilestoragePath) {
        throw 'FilestoragePath must be specified when using JobSchedulerPath'
    }

	$sqlConnectionSettings = @{
		Server = $DatabaseServer
		Database = $DatabaseName
	}

    if(Test-SqlServer @sqlConnectionSettings -EA SilentlyContinue) {
        throw "Database '$DatabaseName' already exists on server '$DatabaseServer'"
    }


    New-TelligentWebsite `
        -Name $name `
		-Path $WebsitePath `
		-Package $package `
		-HostName $webDomain `
		-ApplicationPool $ApplicationPool `
        -Port $Port `
        -FilestoragePath $FilestoragePath


	$sqlAuthSettings = @{}
	if($SqlCredential) {
		$sqlAuthSettings.username = $SqlCredential.Username
		$sqlAuthSettings.password = $SqlCredential.Password
	}
	else {
		$sqlAuthSettings.username = Get-IISAppPoolIdentity $name
	}

    Write-Progress 'Configuration' 'Setting Connection Strings'
    Set-ConnectionString $WebsitePath @sqlConnectionSettings $SqlCredential
    
    New-TelligentDatabase -Package $Package -WebDomain $webDomain -AdminPassword $AdminPassword @sqlConnectionSettings        

    Grant-TelligentDatabaseAccess -CommunityPath $WebsitePath @sqlAuthSettings

	if($Hotfix) {
        Install-TelligentHotfix -WebsitePath $WebsitePath -Package $Hotfix
	}	


	if ($License) {
        Write-Progress 'Configuration' 'Installing License'
        Install-TelligentLicense $WebsitePath $License
	}
	else {
		Write-Warning 'No License installed.'
	}

    $info = Get-TelligentCommunity $WebsitePath 
	if(!$SolrCore) {
		Write-Warning 'No search url specified.  Many features will not work until search is configured.'
	}
	else {
        $solrUrl = $SolrBaseUrl.AbsoluteUri.TrimEnd('/')
        Write-Progress 'Search' 'Setting Up Search'
        $solrCoreParams = @{}
        if($info.PlatformVersion.Major -ge 8) {
            $solrCoreParams.ModernCore = $true
        }
        Add-SolrCore $SolrCoreName `
		    -package $Package `
		    -coreBaseDir $SolrCoreDir `
		    -coreAdmin "$solrUrl/admin/cores" `
            @solrCoreParams

	    Set-TelligentSolrUrl $WebsitePath "$solrUrl/$SolrCoreName/"
	}

    if($ApiKey) {
        New-CommunityApiKey $WebsitePath $ApiKey -UserId 2100 -Name "Well Known API Key $(Get-Date -f g)"
    }

    if($JobSchedulerPath -and $info.PlatformVersion.Major -ge 6) {
        Install-TelligentJobScheduler -JobSchedulerPath $JobSchedulerPath -Package $Package -WebsitePath $WebsitePath
    }
    else {
        $JobSchedulerPath = ''
    }

    # Ensure Community Info has the latest configuration changes
    Get-TelligentCommunity $WebsitePath |
        Add-Member JobSchedulerPath $JobSchedulerPath -PassThru |
        Add-Member AdminApiKey $ApiKey -PassThru
}

function Install-TelligentHotfix {
    <#
    .SYNOPSIS
        Installs a Telligent Evolution hotfix 
    .Details
        Applies a hotfix to a Telligent Evolution community.  It updates the web files, pulls the Database conneciton information from the website and updates the database.  If a Job Scheduler path is specified, it also updates the Job Scheduler.
    .PARAMETER WebsitePath
        The path to the Telligent Evolution website files to apply the hotfix against.
    .PARAMETER Package
        The path to the Telligent Evolution hotfix installation packgae.
    .PARAMETER WebsitePath
        The path to the community's Job Scheduler.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ -Web })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Package,
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )
   
    #TODO: Verify hotfix version is higher than current version
    #TODO: Verify major versions of hotfix & existing community are the same
    
    Write-Progress 'Applying Hotfix' 'Updating Web'
    Expand-Zip -Path $Package -destination $WebsitePath -ZipDirectory "Web"
   
    Write-Progress 'Applying Hotfix' 'Updating Database'
    $tempDir = join-path ([System.IO.Path]::GetFullPath($env:TEMP)) ([guid]::NewGuid())
    @('update.sql', 'updates.sql') |% {
        Expand-Zip -Path $package -destination $tempDir -zipFile $_
        $sqlFile = join-path $tempDir $_

        if (Test-Path $sqlFile -PathType Leaf) {
            Write-ProgressFromVerbose 'Applying Hotfix' 'Updating Database' {
                Invoke-TelligentSqlCmd -WebsitePath $WebsitePath -File $sqlFile 
            }
        }
    }

    if($JobSchedulerPath) {
        Write-Progress 'Applying Hotfix' 'Updating Job Scheduler'
        Update-TelligentJobSchedulerFromWeb $WebsitePath $JobSchedulerPath
    }

    Write-Progress 'Applying Hotfix' 'Cleanup'
    Remove-Item $tempDir -Recurse -Force | Out-Null
}

function Uninstall-Community {
	[CmdletBinding(DefaultParameterSetName='NoService')]
    param(
    	[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ -Web})]
        [string]$WebsitePath,
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ -JobScheduler })]
        [string]$JobschedulerPath
    )
    process {
        $WebsitePath
        $info = Get-TelligentCommunity $WebsitePath

        #Delete JS
        if($JobSchedulerPath) {
            Write-Progress 'Uninstalling Evolution Community' 'Removing Job Scheduler'
            Remove-Item $JobSchedulerPath -Recurse -Force
        }

        #Delete Solr
        $safeSolrUrl = $info.SolrUrl.TrimEnd('/')
        Write-Progress 'Uninstalling Evolution Community' "Removing Solr instance '$safeSolrUrl'"

        if (Invoke-WebRequest "$safeSolrUrl/admin/" -ErrorAction SilentlyContinue) {
            #Can't auto detect solr location, but we can submit a delete all query to reduce disk usage
            Invoke-WebRequest "$safeSolrUrl/update?Commit=true" `
                -Method POST `
                -Body '<delete><query>*:*</query></delete>' `
                -Headers @{'Content-Type'='application/xml'} | Out-Null

            Write-Warning "All documents deleted from Solr, but instance '$safeSolrUrl' needs to be manually deleted"
        }


        #Delete Filestorage
        Write-Progress 'Uninstalling Evolution Community' 'Removing Filestorage'
        $info.CfsPath |? {Test-Path $_} | Remove-Item -Recurse -Force

        #Delete Web
        Write-Progress 'Uninstalling Evolution Community' 'Removing Website'
        $iisSites = Get-IISWebsite $WebsitePath 
        $appPools = $iisSites | select -ExpandProperty applicationpool -Unique

        $iisSites | Remove-Website
        Get-ChildItem IIS:\AppPools |? Name -in $appPools | Remove-WebAppPool

        Remove-Item $WebsitePath -Recurse -Force

        #Delete SQL
        Write-Progress 'Uninstalling Evolution Community' 'Removing Database'
        Remove-Database -Server $info.DatabaseServer -Database $info.DatabaseName 

        #TODO: Remove from hosts file
    }
}


