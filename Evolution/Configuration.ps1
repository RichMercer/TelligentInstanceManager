function Set-ConnectionStrings {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$database,
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$server = ".",
        [ValidateNotNullOrEmpty()]
        [string]$username,
        [ValidateNotNullOrEmpty()]
        [string]$password
    )
    
    if ($username -and $password){
        $connectionString = "Server=$server;Database=$database;uid=$username;pwd=$password;"
    }
    else {
        $connectionString = "Server=$server;Database=$database;Trusted_Connection=yes;"
    }
    
    $path = Resolve-Path connectionstrings.config
    $connectionStrings = [xml](gc $path)  
    $connectionStrings.connectionStrings.add |
        ? { $_.name -eq "SiteSqlServer"} |
        % { $_.connectionString = $connectionString}
    $connectionStrings.Save($path)     
}

function Add-OverrideChangeAttribute {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$xpath,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$value
    )
    
    $overridePath = join-path (get-location) communityserver_override.config
    if (!(test-path $overridePath)) {
        "<?xml version=""1.0"" ?><Overrides />" |out-file $overridePath    
    }
    $overrides = [xml](gc $overridePath)
    $override = $overrides.CreateElement("Override")
    $override.SetAttribute("xpath", $xpath)
    $override.SetAttribute("mode", "change")
    $override.SetAttribute("name", $name)
    $override.SetAttribute("value", $value)
    $overrides.DocumentElement.AppendChild($override) |out-null
    $overrides.Save($overridePath)
}


function Set-EvolutionSolrUrl {
	<#
	.Synopsis
		Updates the Search Url used by a community
	.Parameter communityDir
	    The root directory of the Telligent Evolution community
	.Parameter url
	    The path to the zip package containing the Telligent Evolution installation files from Telligent Support
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [uri]$url
    )
    Write-Progress "Configuration" "Updating Solr Url"
    
    Add-ChangeAttributeOverride `
        -xpath /CommunityServer/Search/Solr `
        -name host `
        -value $url
}

function Install-EvolutionLicence {
	<#
	.Synopsis
		Installs a licence file into your community
	.Parameter licenceFile
	    The XML Licence file provided by Telligent Support
	.Parameter dbServer
	    The server the community database is located on
	.Parameter dbName
	    The name of the community 
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$licenceFile,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbServer,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbName
    )

    $licenceContent = (gc $licenceFile) -join [Environment]::NewLine
    $licenceId = ([xml]$licenceContent).document.licenseId
    
    Invoke-Sqlcmd -serverInstance $dbServer -database $dbName -query "EXEC [cs_Licenses_Update] @LicenseID = N'$licenceId' , @LicenseValue = N'$licenceContent'"
}

function Register-TasksInWebProcess {
	<#
	.Synopsis
		Registers the Job Scheduler tasks in the web process of the current directory for a development environment
    .Details
        Do NOT use this in a production environment
        
        In production environments, the Job Scheduler should be used to offload tasks from the Web Server and to ensure tasks continue to run through Application Pool recycles
	.Parameter webDir
	    The root directory of the Telligent Evolution websites
	.Parameter package
	    The path to the zip package containing the Telligent Evolution installation files from Telligent Support
	#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package
    )
    Write-Progress "Configuration" "Registrating tasks in Web Process"
    Write-Warning "Registering Tasks in the web process is not supported for production environments. Only do this in non production environments"

    $tempDir = join-path $env:temp ([guid]::NewGuid())
    Expand-Zip -zipPath $package -destination $tempDir -zipDir "Tasks" -zipFile "tasks.config"
    $webTasksPath = resolve-path tasks.config    
    $webTasks = [xml](gc $webTasksPath)
	if($webTasks.jobs.cron){
		#6.0+
		$jsTasks = [xml](join-path $tempDir tasks.config | resolve-path | gc)
		$jsTasks.jobs.cron.jobs.job |% {
    	    $webTasks.jobs.cron.jobs.AppendChild($webTasks.ImportNode($_, $true)) | out-null
	    }
		$webTasks.jobs.dynamic.mode = "Server"
	}
	else {
		#5.6
		$tasks = [xml]@"
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
					minUserMessages (int) = the minimum number of messages a user should retain.  -->
	<!--<job schedule="0 */3 * * * ? *" type="CommunityServer.Messages.Tasks.MessageRemovalTask, CommunityServer.Messages">
			<settings>
				<add key="expirationDays" value="30" />
				<add key="minUserMessages" value="30" />
			</settings>
		</job>-->


</jobs>
"@
		$tasks.jobs.job |% {
    	    $webTasks.scheduler.jobs.AppendChild($webTasks.ImportNode($_, $true)) | out-null
	    }
		$version = [Version](Get-Command "bin\CommunityServer.Components.dll").FileVersionInfo.FileVersion
		if($version -and $version.Revision -ge 17537) {
			$reindexNode = [xml]"<job schedule=""30 * * * * ? *"" type=""CommunityServer.Search.SiteReindexJob, CommunityServer.Search""/>"
    	    $webTasks.scheduler.jobs.AppendChild($webTasks.ImportNode($reindexNode.job, $true)) | out-null
		}
	}

	$webTasks.Save($webTasksPath)
	
}

function Disable-CustomErrors {
	<#
	.Synopsis
		Disables Custom Errors for an ASP.Net website
	.Example
		Disable-CustomErrors 
	#>
    [CmdletBinding()]
    param(
    )
    
    Write-Warning "Disabling Custom Errors poses a security risk. Only do this in non production environments"
    $configPath = resolve-path "web.config"
    $webConfig = [xml] (get-content $configPath )
    
    $webConfig.configuration.{system.web}.customErrors.mode = "Off"
    $webConfig.Save($configPath)
}

function Enable-WindowsAuth {
	<#
	.Synopsis
		Configures IIS to use Windows Authentication for an ASP.Net website
	.Parameter webDir
	    The root directory of the ASP.Net website
	.Parameter iisSiteName
	    The name of the IIS Website
	.Example
		Enable-WindowsAuth c:\Websites\TestSite\ TestSite
	#>
    [CmdletBinding()]
    param(
    )
    $configPath = resolve-path web.config
    $webConfig = [xml] (get-content $configPath )
    
    $webConfig.configuration.{system.web}.authentication.mode = "Windows"
    $webConfig.Save($configPath)
    
    $values = @{
        adminWindowsGroup = "SUPPORT\Community Admins";
        emailDomain = "@support.telligent.com";
        profileRefreshInterval = 1
    }
    
    Add-ChangeAttributeOverride -xpath /CommunityServer/Core/extensionModules `
        -name enabled -value true

    $values.GetEnumerator() |%{
        Add-ChangeAttributeOverride -xpath "/CommunityServer/Core/extensionModules/add[@name='WindowsAuthentication']" `
            -name $_.Key -value $_.Value
    }

    Get-IISWebsites |% {
        &c:\Windows\System32\inetsrv\appcmd.exe set config $_.Name /section:windowsAuthentication /enabled:true /commit:apphost  | out-null
        &c:\Windows\System32\inetsrv\appcmd.exe set config $_.Name /section:anonymousAuthentication /enabled:false /commit:apphost | out-null
    }
    ##For some reason, the following tries to use .net 2.0, and fails because it can't find a configuraiton
    ## section for system.web.extensions

    #    Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled `
    #        -value false -PSPath IIS:\ -location $iisSiteName
    #    Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled `
    #        -value true -PSPath IIS:\ -location $iisSiteName

}

function Enable-AppFabricCache {

    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$host
    )
    #Configure Web.config
    $webConfigPath = resolve-path web.config
    $webConfig = [xml] (get-content $webConfigPath )

    $ldapSection = [xml]"<section name=""dataCacheClient"" type=""Microsoft.ApplicationServer.Caching.DataCacheClientSection, Microsoft.ApplicationServer.Caching.Core, Version=1.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"" allowLocation=""true"" allowDefinition=""Everywhere"" />"
    $webConfig.configuration.configSections.AppendChild($webConfig.ImportNode($ldapSection.DocumentElement, $true)) | out-null
	
	$cacheConfig = [xml]@"
<dataCacheClient>
   <hosts>
      <host name="" cachePort="22233"/>
   </hosts>
   <securityProperties mode="None" protectionLevel="None" />
</dataCacheClient>
"@
	$cacheConfig.dataCacheClient.hosts.host.name = $host
	   
    $webConfig.configuration.AppendChild($cacheConfig) | out-null   

    $webConfig.Save($webConfigPath)
}

function Enable-Ldap {
	<#
	.Synopsis
		Configures a Telligent Enterprise community to use LDAP
	.Parameter communityDir
	    The root directoyr of the Telligent Enterprise websites
	.Parameter server
	    The name of the ldap server
	.Parameter username
        The username to connect with
	.Parameter password
        The password to connect with
	.Parameter authenticationType
        The authenticaiton type to use.
	.Parameter port
        The port to connect to the LDAP server on        
	.Parameter 
        The baseDn to use
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$server,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$username,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$password,
        [string]$authenticationType = "Secure",
        [int]$port = 389,
        [string]$baseDn
    )

    #Install Package
    $packagesPath = resolve-path packages.config
    $packages = [xml](gc $packagesPath)
    $date = get-date -format yyyy-MM-dd
    $package = [xml]"<Package Name=""Ldap"" Version=""1.0"" DateInstalled=""$date"" Id=""4BF1091D-376C-42b2-B375-E2FE9480E845"" />"
    $packages.DocumentElement.AppendChild($packages.ImportNode($package.DocumentElement, $true)) | out-null
    $packages.Save($packagesPath)

    #Configure Web.config
    $webConfigPath = resolve-path web.config
    $webConfig = [xml] (get-content $webConfigPath )

    $ldapSection = [xml]"<section name=""LdapConnection"" type=""System.Configuration.NameValueSectionHandler"" />"
    $webConfig.configuration.configSections.AppendChild($webConfig.ImportNode($ldapSection.DocumentElement, $true)) | out-null
    $ldapConfiguration= $webConfig.CreateElement("LdapConnection")
    @{
        Server="LDAP://$server";
        Port=$port;
        BaseDN=$baseDn;
        UserDN=$username;
        Password = $password;
        Authentication = $authenticationType;
    }.GetEnumerator() |% {
        $add = $ldapConfiguration.OwnerDocument.CreateElement("add")
        $add.SetAttribute("key", $_.Key)
        $add.SetAttribute("value", $_.Value)
        $ldapConfiguration.AppendChild($add) | out-null
    }
    $webConfig.configuration.AppendChild($ldapConfiguration) | out-null   

    $webConfig.Save($webConfigPath)
}