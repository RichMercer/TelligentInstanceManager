Set-StrictMode -Version 2

function Test-TelligentPath {
    <#
    .SYNOPSIS
        Tests if a SQL Server exists and can be connected to. Optonally checks for a specific database or table.
    .PARAMETER Path
        The path to test for a Teligent Community
    .PARAMETER AllowEmpty
        Specifies that an empty path should be considered as valid
    .PARAMETER IsValid
        Only test if the path is syntaticly valid, not that it actually contains a valid Telligent Community instance
    .PARAMETER Web
        Only pass if the path contains a Telligent Community website, not a Job Server 
    .PARAMETER JobScheduler
        Only pass if the path contains a Telligent Community Job Server, not a website 
    #>    [CmdletBinding(DefaultParameterSetName='Either')]
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
        [AllowEmptyString()]
        [string]$Path,
        [switch]$AllowEmpty,
        [parameter(ParameterSetName='Valid', Mandatory=$true)]
        [switch]$IsValid,
        [parameter(ParameterSetName='Web', Mandatory=$true)]
        [switch]$Web,
        [parameter(ParameterSetName='JobScheduler', Mandatory=$true)]
        [switch]$JobScheduler
    )
    if(!($Path)) {
        if(!$AllowEmpty) {
            throw 'Argument must not be null'
        }
    }
    elseif ($IsValid) {
        if (!(Test-Path $Path -PathType Container -IsValid -ErrorAction SilentlyContinue)) {
            throw "'$Path' is not a valid path"
        }
    }
    else {
        if (!(Test-Path $Path -PathType Container -ErrorAction SilentlyContinue)) {
            throw "'$Path' does not exist"
        }
        if (!(Join-Path $Path communityserver.config | Test-Path  -ErrorAction SilentlyContinue)) {
            throw "'$Path' does not contain a valid Telligent Community community"
        }
        if ($Web -and !(Join-Path $Path web.config | Test-Path  -ErrorAction SilentlyContinue)) {
            throw "'$Path' does not contain a valid Telligent Community website"
        }
        elseif ($JobScheduler -and !((Join-Path $Path Telligent.JobScheduler.Service.exe | Test-Path) -or (Join-Path $Path Telligent.Jobs.Server.exe | Test-Path))) {
            throw "'$Path' does not contain a valid Telligent Community Job Server"
        }
    }
    return $true
    
}

function Set-ConnectionString {
    <#
    .SYNOPSIS
        Sets the Connection Strings in the .net configurationf ile
    .PARAMETER WebsitePath
        The path to the application you want to set connection strings for
    .PARAMETER Server
        The SQL Server the connection string will point to
    .PARAMETER Database
        The database to use
    .PARAMETER SqlCredentials
        If using SQL Authenticaiton, specifies the username nad password to use in the connection string. If not specified, the connection string uses Integrated Security.
    .PARAMETER ConfigurationFile
        The configuration file to set the connection strings in.
    .PARAMETER ConnectionStringName
        The name of the connection string to set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [string]$ConfigurationFile = 'connectionstrings.config'
    )
    
    $path = Join-Path $WebsitePath $ConfigurationFile | Resolve-Path | select -ExpandProperty ProviderPath
    $connectionStrings = [xml](gc $path)  
    $connectionStrings.connectionStrings.add |
        ? { $_.name -eq $Name} |
        % { $_.connectionString = $Value}
    $connectionStrings.Save($path)     
}

function Set-DatabaseConnectionString {
    <#
    .SYNOPSIS
        Sets the Connection Strings in the .net configurationf ile
    .PARAMETER WebsitePath
        The path to the application you want to set connection strings for
    .PARAMETER Server
        The SQL Server the connection string will point to
    .PARAMETER Database
        The database to use
    .PARAMETER SqlCredentials
        If using SQL Authenticaiton, specifies the username nad password to use in the connection string. If not specified, the connection string uses Integrated Security.
    .PARAMETER ConfigurationFile
        The configuration file to set the connection strings in.
    .PARAMETER ConnectionStringName
        The name of the connection string to set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('ServerInstance')]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,
        [PSCredential]$SqlCredentials
    )

    if ($SqlCredentials){
        $connectionString = "Server=$Server;Database=$Database;uid=$($SqlCredentials.UserName);pwd=$($SqlCredentials.Password);"
    }
    else {
        $connectionString = "Server=$Server;Database=$Database;Trusted_Connection=yes;"
    }
    
    Set-ConnectionString $WebsitePath -Name 'SiteSqlServer' -Value $connectionString
}


function Get-ConnectionString {
    <#
    .SYNOPSIS
        Sets the Connection Strings in the .net configurationf ile
    .PARAMETER Database
        The database 
    .PARAMETER Server
        The SQL Server the connection string will point to
    .PARAMETER SqlCredentials
        If using SQL Authenticaiton, specifies the username nad password to use in the connection string. If not specified, the connection string uses Integrated Security.
    .PARAMETER ConfigurationFile
        The configuration file containing the connection string to read.
    .PARAMETER ConnectionStringName
        The name of the connection string to set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$Directory,
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$ConfigurationFile = 'connectionStrings.Config',
        [string]$ConnectionStringName = 'SiteSqlServer'

    )
    #Load connection string info
    $connectionStrings = [xml](get-content (Join-Path $Directory $ConfigurationFile) -ErrorAction SilentlyContinue)
    $siteSqlConnectionString = $connectionStrings.connectionStrings.add |
        ? name -eq $ConnectionStringName |
        select -ExpandProperty connectionString

    if(!$siteSqlConnectionString) {
        Write-Error "'$ConnectionStringName' connection string not found in $ConfigFile"
    }
	try {
		$connectionString = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $siteSqlConnectionString -EA SilentlyContinue
	}
	catch{}
    $connectionInfo = @{
        ServerInstance = $connectionString.DataSource
        Database = $connectionString.InitialCatalog
    }
    if(!$connectionString.IntegratedSecurity) {
        $connectionInfo.Username = $connectionString.UserID
        $connectionInfo.Password = $connectionString.Password
    }

    $connectionInfo
}

function New-CommunityApiKey {
    <#
    .SYNOPSIS
        Creates a new REST API Key 
    .PARAMETER ApiKey
        The API Key to Create
    .PARAMETER Name
        The name for the API Key.
    .PARAMETER UserId
        The User to create the API Key for
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z0-9]+$')]
        [string]$ApiKey,
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'Auto Generated',
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [int]$UserId= 2100
    )

    $createApiKey = "INSERT INTO [dbo].[cs_ApiKeys] ([UserID],[Value],[Name],[DateCreated],[Enabled]) VALUES ($UserId,'$ApiKey','$Name',GETDATE(), 1)"
    Invoke-TelligentSqlCmd $WebsitePath -Query $createApiKey
}

function Add-TelligentOverrideChangeAttribute {
    <#
    .SYNOPSIS
        Adds a Change entry to the communityserver_override.config
    .PARAMETER XPath
        The XPath for the element containing the attribute to manipulate
    .PARAMETER Name
        The Name of the node to modify
    .PARAMETER Value
        The new value of the node
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$XPath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )
    #TODO: Look at original config file to ensure XPath & Node exist
    
    $overridePath = join-path $WebsitePath communityserver_override.config
    if (!(test-path $overridePath)) {
        '<?xml version="1.0" ?><Overrides />' |out-file $overridePath    
    }

    $overrides = [xml](gc $overridePath)
    $override = $overrides.CreateElement('Override')
    $override.SetAttribute('xpath', $XPath)
    $override.SetAttribute('mode', 'change')
    $override.SetAttribute('name', $Name)
    $override.SetAttribute('value', $Value)
    $overrides.DocumentElement.AppendChild($override) |out-null
    $overrides.Save(($overridePath | Resolve-Path).ProviderPath)
}

function Set-TelligentFilestorage {
    <#
    .SYNOPSIS
        Sets the Filestorage location for a Telligent Community
    .PARAMETER WebsitePath
        The path of the Telligent Community website.
    .PARAMETER FilestoragePath
        The Filestorage Location to use. The Filestorage should already have been moved to this location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$FilestoragePath
    )

    $version = Get-TelligentCommunity $WebsitePath | select -ExpandProperty PlatformVersion

    if ($Version.Major -ge 10) {
        Set-ConnectionString $WebsitePath -Name FileStorage -Value $FilestoragePath
    }
    elseif ($version.Major -ge 7) {
        Add-TelligentOverrideChangeAttribute $WebsitePath `
            -XPath "/CommunityServer/CentralizedFileStorage/fileStoreGroup[@name='default']" `
            -Name basePath `
            -Value $FilestoragePath
    }
    else {
        $csConfig = Merge-CommunityConfigurationFile $WebsitePath communityserver
        $csConfig.CommunityServer.CentralizedFileStorage.fileStore.name |% {
            Add-TelligentOverrideChangeAttribute $WebsitePath `
                -XPath "/CommunityServer/CentralizedFileStorage/fileStore[@name='$_']" `
                -Name basePath `
                -Value $FilestoragePath
        }
    }

}

function Set-TelligentSolrUrl {
	<#
	.SYNOPSIS
		Updates the Search Url used by the Telligent Community in the current directory
	.PARAMETER Url
	    The url of the Solr instance to use
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        ##No longer works for solr 4.0
        #[ValidateScript({Invoke-WebRequest ($_.AbsoluteUri.TrimEnd('/') + "/admin/") -Method HEAD -UseBasicParsing})]
        [ValidateNotNullOrEmpty()]
        [uri]$Url
    )

	$version = Get-TelligentCommunity $WebsitePath | select -ExpandProperty PlatformVersion

	Write-Progress "Configuration" "Updating Solr Url"
    if ($Version.Major -ge 10) {
        Set-ConnectionString $WebsitePath -Name SearchContentUrl -Value $Url
		Set-ConnectionString $WebsitePath -Name SearchConversationsUrl -Value $Url
    }
	else{
		Add-TelligentOverrideChangeAttribute `
        -XPath /CommunityServer/Search/Solr `
        -Name host `
        -Value $Url `
        -WebsitePath $WebsitePath
	}
}

function Install-TelligentLicense {
	<#
	.SYNOPSIS
		Installs a License file into a Telligent Community
	.PARAMETER LicenseFile
	    The XML License file
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$LicenseFile
    )

    $LicenseContent = (gc $LicenseFile) -join [Environment]::NewLine
    $LicenseId = ([xml]$LicenseContent).document.licenseId
    
    $sql = @"
delete from cs_Licenses
GO
insert into cs_Licenses (LicenseID, LicenseValue, InstallDate)
values ('$LicenseId', N'$LicenseContent', getdate())
"@
	Invoke-TelligentSqlCmd -WebsitePath $WebsitePath -Query $sql
}

function Register-TelligentTasksInWebProcess {
	<#
	.SYNOPSIS
		Registers the Job Scheduler tasks in the web process of the Telligent Community instance in the current directory for a development environment
    .DESCRIPTION
        Do NOT use this in a production environment
        
        In production environments, the Job Scheduler must be used to offload tasks from the Web Server and to ensure tasks continue to run through Application Pool recycles, as well as to avoid conflicts in a multi server environment
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
	.PARAMETER Package
	    The path to the zip package containing the Telligent Community installation files from Telligent Support
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package
    )
    $info = Get-TelligentCommunity $WebsitePath
	if($info.PlatformVersion -lt 5.6){
        Write-Error 'Job Scheduler not supported on 5.5 or below'
    }
    elseif($info.PlatformVersion.Major -ge 8) { 
        Write-Error 'Jobs can no longer be run in the web process in 8.0 or higher'
    }
    else {
        Write-Warning "Registering Tasks in the web process is not supported for production environments. Only do this in non production environments"

        $tempDir = Join-Path $env:temp ([guid]::NewGuid())
        Expand-Zip -Path $Package -destination $tempDir -ZipDirectory Tasks -zipFile tasks.config
        $webTasksPath = Join-Path $WebsitePath tasks.config | Resolve-Path
        if ($webTasksPath) {
            $webTasks = [xml](gc $webTasksPath)
	        if($webTasks.jobs.cron){
		        #6.0+
		        $jsTasks = [xml](Join-Path $tempDir tasks.config | Resolve-Path | Get-Content)
		        $jsTasks.jobs.cron.jobs.job |% {
    	            $webTasks.jobs.cron.jobs.AppendChild($webTasks.ImportNode($_, $true)) | Out-Null
	            }
		        $webTasks.jobs.dynamic.mode = 'Server'
	        }
	        else {
		        #5.6
		        $tasks = [xml]$tasks5x
		        $tasks.jobs.job |% {
    	            $webTasks.scheduler.jobs.AppendChild($webTasks.ImportNode($_, $true)) | out-null
	            }
		        $version = (Get-TelligentCommunity $WebsitePath).PlatformVersion
		        if($version.Revision -ge 17537) {
			        $reindexNode = [xml]'<job schedule="30 * * * * ? *" type="CommunityServer.Search.SiteReindexJob, CommunityServer.Search" />'
    	            $webTasks.scheduler.jobs.AppendChild($webTasks.ImportNode($reindexNode.job, $true)) | out-null
		        }
	        }

	        $webTasks.Save($webTasksPath)
        }
	}
}

function Disable-CustomErrors {
	<#
	.SYNOPSIS
		Disables Custom Errors for the ASP.Net website in the specified directory
    .PARAMETER WebsitePath
        The path of the ASP.Net Web Application. If not specified, defaults to the current directory.
	.EXAMPLE
		Disable-CustomErrors 
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath
    )
    
    Write-Warning 'Disabling Custom Errors poses a security risk. Only do this in non production environments'
    $configPath = Join-Path $WebsitePath web.config | Resolve-Path
    $webConfig = [xml] (get-content $configPath )
    
    $webConfig.configuration.{system.web}.customErrors.mode = 'Off'
    $webConfig.Save($configPath)
}

function Enable-DeveloperMode {
	<#
	.SYNOPSIS
		Enables developer mode for Telligent Community 9.x and above
    .PARAMETER WebsitePath
        The path of the ASP.Net Web Application. If not specified, defaults to the current directory.
	.EXAMPLE
		Enable-DeveloperMode 
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath
    )
    
    $configPath = Join-Path $WebsitePath web.config | Resolve-Path
    $webConfig = [xml] (Get-Content $configPath )
	
	$webConfig.configuration.appSettings.add |
        ? { $_.key -eq 'EnableDeveloperMode'} |
        % { $_.value = 'true'}		
    
    $webConfig.Save($configPath)
}

function Enable-TelligentWindowsAuth {
	<#
	.SYNOPSIS
		Configures IIS to use Windows Authentication for the ASP.Net website
        in the current directory
    .PARAMETER AdminWindowsGroup
        The name of the windows group who should be automatically made Administrators in the community. Defaults to the local Administrators group.
    .PARAMETER EmailDomain
        The email domain to append to a user's username to get their email address if it's not found in Active Directory (USERNAME@EmailDomain).
    .PARAMETER ProfileRefreshInterval
        The interval (in days) at which a user's profile should be updated.
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [ValidateNotNullOrEmpty()]
        [string]$AdminWindowsGroup = "$env:ComputerName\Administrators",
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain,
        [ValidateNotNullOrEmpty()]
        [byte]$ProfileRefreshInterval = 7
    )
    $configPath = Join-Path $WebsitePath web.config | resolve-path 
    $webConfig = [xml] (get-content $configPath )
    
    $webConfig.configuration.{system.web}.authentication.mode = 'Windows'
    $webConfig.Save($configPath)
    
    Add-TelligentOverrideChangeAttribute $WebsitePath `
        -XPath /CommunityServer/Core/extensionModules `
        -Name enabled `
        -Value true


    @{
        adminWindowsGroup = $AdminWindowsGroup;
        emailDomain = "@$($EmailDomain.TrimStart('@'))";
        profileRefreshInterval = $ProfileRefreshInterval
    }.GetEnumerator() |%{
        Add-TelligentOverrideChangeAttribute $WebsitePath `
            -XPath "/CommunityServer/Core/extensionModules/add[@name='WindowsAuthentication']" `
            -Name $_.Key `
            -Value $_.Value
    }

    #If the following fails, ensure default .net version in IIS is set to 4.0
    Get-IISWebsite $WebsitePath |% {
        Set-WebConfigurationProperty -Filter /system.webServer/security/authentication/* `
            -Name enabled `
            -Value false `
            -PSPath IIS:\ `
            -Location $_.Name

        Set-WebConfigurationProperty -Filter /system.webServer/security/authentication/windowsAuthentication `
            -Name enabled `
            -Value true `
            -PSPath IIS:\ `
            -Location $_.Name
    }
}

function Enable-TelligentLdap {
	<#
	.SYNOPSIS
		Enables LDAP integration in a Telligent Community
    .PARAMETER WebsitePath
        The path of the Telligent Community website. If not specified, defaults to the current directory.
    .PARAMETER Server
        The server to use for LDAP. Defaults to the Global Catalog of the AD Forest the server is in.
    .PARAMETER AuthenticationType
        The email domain to append to a user's username to get their email address if it's not found in Active Directory (USERNAME@EmailDomain).
    .PARAMETER Port
        The port to connect to ldap. Defaults to the Global Catalog port.
    .PARAMETER Username
        The username port to connect to ldap with . Defaults to the credntials of Application Pool Identiy.
    .PARAMETER Password
        The password port to connect to ldap with . Defaults to the credntials of Application Pool Identiy.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-TelligentPath $_ })]
        [string]$WebsitePath,
        [string]$Server = 'GC://',
        [string]$AuthenticationType = 'Secure',
        [int]$Port = 3268,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    #Install Package
    $packagesPath = join-Path $WebsitePath packages.config | Resolve-Path
    $packages = [xml](gc $packagesPath)
    $date = get-date -format yyyy-MM-dd
    $package = [xml]"<Package Name=""Ldap"" Version=""1.0"" DateInstalled=""$date"" Id=""4BF1091D-376C-42b2-B375-E2FE9480E845"" />"
    $packages.DocumentElement.AppendChild($packages.ImportNode($package.DocumentElement, $true)) | out-null
    $packages.Save($packagesPath)

    #Configure Web.config
    $webConfigPath = Join-Path $WebsitePath web.config | resolve-path
    $webConfig = [xml] (get-content $webConfigPath )

    $ldapSection = [xml]'<section name="LdapConnection" type="System.Configuration.NameValueSectionHandler" />'
    $webConfig.configuration.configSections.AppendChild($webConfig.ImportNode($ldapSection.DocumentElement, $true)) | out-null
    $ldapConfiguration= $webConfig.CreateElement("LdapConnection")
    @{
        Server=$Server
        Port=$Port
        UserDN=$Username
        Password = $Password
        Authentication = $AuthenticationType
    }.GetEnumerator() |% {
        $add = $ldapConfiguration.OwnerDocument.CreateElement("add")
        $add.SetAttribute('key', $_.Key)
        $add.SetAttribute('value', $_.Value)
        $ldapConfiguration.AppendChild($add) | out-null
    }
    $webConfig.configuration.AppendChild($ldapConfiguration) | out-null   

    $webConfig.Save($webConfigPath)
}

$tasks5x = data {@"
<jobs>
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.AnonymousUserJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.ReferralsJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.ViewsJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Wikis.Components.PageViewsJob, CommunityServer.Wikis" />

	<job schedule="0 */1 * * * ? *" type="CommunityServer.MailRoom.Components.EmailJob, CommunityServer.MailGateway.MailRoom">
		<settings>
			<add key="failureInterval" value="1" />
			<add key="numberOfTries" value="10" />
		</settings>
	</job>
	<job schedule="0 */1 * * * ? *" type="CommunityServer.MailRoom.Components.BulkEmailJob, CommunityServer.MailGateway.MailRoom">
		<settings>
			<add key="failureInterval" value="1" />
			<add key="numberOfTries" value="10" />
		</settings>
	</job>
	<job schedule="0 */1 * * * ? *" type="CommunityServer.Search.Tasks.SearchIndexingContentHandlerTask, CommunityServer.Search">
		<settings>
			<add key="documentsPerRun" value="100" />
			<add key="handler-1" value="CommunityServer.Search.UserContentHandler, CommunityServer.Search" />
			<add key="handler-2" value="CommunityServer.Search.GroupContentHandler, CommunityServer.Search" />
			<add key="handler-3" value="CommunityServer.Search.ForumContentHandler, CommunityServer.Search" />
			<add key="handler-4" value="CommunityServer.Search.WeblogContentHandler, CommunityServer.Search" />
			<add key="handler-5" value="CommunityServer.Search.ContentFragmentPageContentHandler, CommunityServer.Search" />
			<add key="handler-6" value="CommunityServer.Search.MediaGalleryContentHandler, CommunityServer.Search" />
			<add key="handler-7" value="CommunityServer.Search.WikiContentHandler, CommunityServer.Search" />
			<add key="handler-8" value="CommunityServer.Search.WeblogPostContentHandler, CommunityServer.Search" />
			<add key="handler-9" value="CommunityServer.Search.MediaGalleryPostContentHandler, CommunityServer.Search" />
			<add key="handler-10" value="CommunityServer.Search.WikiPageContentHandler, CommunityServer.Search" />
			<add key="handler-11" value="CommunityServer.Search.ForumPostContentHandler, CommunityServer.Search" />
		</settings>
	</job>
	<job schedule="0 0 3 ? * SUN,WED" type="CommunityServer.Search.Solr.IndexOptimizationJob, CommunityServer.Search.Providers" />
	<job schedule="0 */2 * * * ? *" type="CommunityServer.Components.TagCleanupJob, CommunityServer.Components">
		<settings>
			<add key="applications" value="forum" />
		</settings>
	</job>
	<job schedule="0 */2 * * * ? *" type="CommunityServer.Blogs.Components.RecentContentJob, CommunityServer.Blogs" />
	<job schedule="0 */2 * * * ? *" type="CommunityServer.Components.CalculateTagCountsJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.SiteStatisticsJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.EventLogJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Blogs.Components.ModeratedFeedbackNotificationJob, CommunityServer.Blogs" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Blogs.Components.GenerateWeblogYearMonthDayListJob, CommunityServer.Blogs" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.TemporaryUserTokenExpirationTask, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.TemporaryStoreExpirationTask, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.CalculateSectionTotalsJob, CommunityServer.Components" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Blogs.Components.RollerBlogUpdater, CommunityServer.Blogs" />
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.PostAttachmentCleanupJob, CommunityServer.Components">
		<settings>
			<add key="expiresAfterHours" value="2" />
		</settings>
	</job>
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.ThemeConfigurationPreviewCleanupJob, CommunityServer.Components">
		<settings>
			<add key="expiresAfterHours" value="2" />
		</settings>
	</job>
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.UserInvitationExpirationJob, CommunityServer.Components">
		<settings>
			<add key="expirationDays" value="30" />
		</settings>
	</job>
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Blogs.Components.DeleteStaleSpamCommentsJob, CommunityServer.Blogs">
		<settings>
			<add key="expirationDays" value="2" />
		</settings>
	</job>
	<job schedule="0 */3 * * * ? *" type="CommunityServer.Components.MultipleFileUploadCleanupJob, CommunityServer.Components">
		<settings>
			<add key="expiresAfterHours" value="2" />
		</settings>
	</job>
	<job schedule="0 */5 * * * ? *" type="CommunityServer.Components.LdapSyncJob, CommunityServer.Components" />
	<!-- Enable this task to enable background deletion of old activity messages.
					expirationDays (int) = messages older than this number of days can be deleted
					minUserMessages (int) = the minimum number of messages a user should retain. -->
	<!--<job schedule="0 */3 * * * ? *" type="CommunityServer.Messages.Tasks.MessageRemovalTask, CommunityServer.Messages">
			<settings>
				<add key="expirationDays" value="30" />
				<add key="minUserMessages" value="30" />
			</settings>
		</job>-->


</jobs>
"@}


