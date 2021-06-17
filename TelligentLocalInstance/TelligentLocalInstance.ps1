Set-StrictMode -Version 2

function Get-Configuration {
    $base = $env:TelligentInstanceManager
    if (!$base) {
        Write-Error 'TelligentInstanceManager environmental variable not defined. Please run Initialize-TelligentInstanceManager to configure the environment.'
    }

    $data = @{
        #SQL Server to use.
        SqlServer = if($env:TelligentDatabaseServerInstance) { $env:TelligentDatabaseServerInstance } else { '(local)' }

        #Default password to use for new communities
        AdminPassword = 'password'

        # The directory where licenses can be found.
        # Licenses in this directory should be named in the format "Community{MajorVersion}.xml"
        # i.e. Community7.xml for a Community 7.x license
	    LicensesPath = Join-Path $base Licenses | Resolve-Path

        # The directory where web folders are created for each website
	    InstanceBase = Join-Path $base Communities
    }

    $data
}

function Get-TelligentInstance {
    <#
        .SYNOPSIS
            Gets TelligentInstance instances
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Get-TelligentInstance
               
            Gets all TelligentInstance instances
        .EXAMPLE
            Get-TelligentInstance test123

            Gets the TelligentInstance instance named 'test123'
        .EXAMPLE
            Get-TelligentInstance ps*
               
            Gets all TelligentInstance instances whose names match the pattern 'ps*'
    #>
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Name,
        [string]$Version
    )

    $data = Get-Configuration
    
    $results = Get-ChildItem (Join-Path $data.InstanceBase "*/Web") |
            select -ExpandProperty FullName |
            Get-TelligentCommunity -EA SilentlyContinue

    if ($Name) {
        $results = $results |? Name -like $Name
    }

    if ($Version) {
        $versionPattern = "$($Version.TrimEnd('*'))*"
        $results = $results |
            ? {$_.PlatformVersion.ToString() -like $versionPattern } |
            select
    }
    $results
}

function Install-TelligentInstance {
    <#
    .Synopsis
	    Sets up a new Telligent Community for development purposes.
    .Description
	    The Install-TelligentInstance cmdlet automates the process of creating a new Telligent Community instance.
		
	    It takes the installation package, and from it deploys the website to IIS and a creates a new database using
	    the scripts from the package. It also sets permissions automatically.
		
	    This scripts install the new community as follows (where NAME is the value of the name paramater).
    .Parameter Name
	    The name of the community to create. This is used when creating the locations used by the community.
		    * Web Files - %TelligentInstanceManager%\Web\NAME\
		    * Database Server - (local)
		    * Database name NAME
		    * Solr Url - http://localhost:8080/3-6/NAME/ (or 1-4 for versions using solr 1.4)
		    * Solr Core - %TelligentInstanceManager%\Solr\3-6\NAME\ (or 1-4 for versions using solr 1.4)
		    * Url - http://NAME.local/ (entry automatically added to hosts file)
		    * Jobs run in web process
		    * Custom Errors disabled
    .Parameter Version
	    The community version being installed.
    .Parameter BasePackage
	    The path to the zip package containing the Telligent Community installation files, provided by Telligent Support.
    .Parameter WindowsAuth
	    Specify this switch to use Windows Authentication for the community.
    .Parameter DatabaseServerInstance
        Specify the SQL DB Instance name to install the site.
    .Parameter DatabaseName
	    The name of the database to be created or used. If the database doesn't exist, it will be created.
    .Parameter ApiKey
	    If specified, a REST Api Key is created for the admin user with the given value. This is useful for automation scenarios where you want to go and automate creation of content after installation.
    .Example
        Get-TelligentVersion 7.6 | Install-TelligentInstance TestSite
        
        Output can be piped from Get-TelligentVersion to automatically fill in the version andbasePackage paramaters
    
				
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateScript({if(Get-TelligentInstance $_){ throw "Telligent Instance '$_' already exists" } else { $true }})]
        [string] $Name,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
        [version] $Version,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string] $BasePackage,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [switch] $WindowsAuth,
        [string] $DatabaseServerInstance,
        [string] $DatabaseName = $Name,
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [string] $ApiKey,
        [switch] $EnableDeveloperMode,
        [switch] $InstallInternalJobs = $true
    )

    $data = Get-Configuration
    $name = $name.ToLower()

    $solrVersion = Get-CommunitySolrVersion $Version
    $solrUrl = Get-CommunitySolrUrl $Version
    $solrDir = Get-CommunitySolrFolder $Version
    $solrContentConfigSet = Get-CommunitySolrContentConfigSet $Version
    $solrConversationsConfigSet = Get-CommunitySolrConversationsConfigSet $Version
    $instanceDir = Join-Path $data.InstanceBase $Name
    $webDir = Join-Path $instanceDir Web
    $jsDir = Join-Path $instanceDir JobServer
    $filestorageDir = Join-Path $instanceDir Filestorage
    $domain = if($Name.Contains('.')) { $Name } else { "$Name.local"}
    $DatabaseServerInstance = if($DatabaseServerInstance) { $DatabaseServerInstance } else { $data.SqlServer }
    $sqlPassword = [string][guid]::NewGuid()
    $sqlCred = New-Object PSCredential $Name, (ConvertTo-SecureString -String $sqlPassword -AsPlainText -fo)
	$licensePath = join-path $data.LicensesPath "Community$($Version.Major).xml"
	
    if(!(Test-Path $licensePath)) { $licensePath = $null }

	# To avoid ambiguity between the enviornment specificl Install-TelligentCommunity and
	# the generic base, the base function is private, so have to pull it out via a bit
	# of module hackery
	$module = Get-Module TelligentInstall
	$installCommunityFunc = $module.Invoke({Get-Command Install-TelligentCommunity})
    $info = & $installCommunityFunc `
		-Name $Name `
        -Package $BasePackage `
        -WebsitePath $webDir `
        -JobSchedulerPath $jsDir `
        -FilestoragePath $filestorageDir `
        -WebDomain $domain `
        -License $licensePath `
        -SolrCore `
        -SolrBaseUrl $solrUrl `
        -SolrCoreDir $solrDir `
        -SolrContentConfigSet $solrContentConfigSet `
        -SolrConversationsConfigSet $solrConversationsConfigSet `
        -AdminPassword $data.AdminPassword `
        -DatabaseServer $DatabaseServerInstance `
        -DatabaseName $DatabaseName `
        -SqlCredential $sqlCred `
        -ApiKey $ApiKey

    if ($info) {
	    Disable-CustomErrors $webDir

        Invoke-TelligentSqlCmd -WebsitePath $webDir -Query "EXEC sp_addrolemember N'db_owner', N'$name'"

    	# Write-Progress "Job Scheduler" "Installing Service"
        # $jsCredentials = New-Object PSCredential 'NT AUTHORITY\NETWORK SERVICE', (New-Object Security.SecureString)
        # Install-TelligentJobSchedulerService -Name $Name -JobSchedulerPath $jsDir -Credential $jsCredentials -StartupType Automatic
        
    	if ($WindowsAuth) {
            Enable-TelligentWindowsAuth $webDir -EmailDomain '@tempuri.org' -ProfileRefreshInterval 0
        }        
        
        if($info.PlatformVersion.Major -ge 9 -and $EnableDeveloperMode) {
            Enable-DeveloperMode $webDir
        }

		Write-Host "Installing local jobs?" $InstallInternalJobs
        if($info.PlatformVersion.Major -ge 9 -and $InstallInternalJobs) {
            Enable-InternalJobs $webDir
        }

        #Add site to hosts files
        Add-Content -value "`r`n127.0.0.1 $domain" -Path (join-path $env:SystemRoot system32\drivers\etc\hosts)

        $info | Add-Member Url "http://$domain/" -PassThru

        # Copy AccessCode plugin to site
		# We need a v12 version here
        # Copy-Item (Join-Path $data.InstanceBase '..\Telligent.Services.AccessCode\Web\*') $webDir -Recurse -Force

		if([Environment]::UserInteractive) {
            Start-Process $info.Url
        }
    }
}

function Get-CommunitySolrVersion {
    <#
        .SYNOPSIS
            Gets the Solr version for a given community version number
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
    if($Version.Major -ge 11) {
		'7-6-0'
	}
    elseif($Version.Major -ge 10) {
		'6-3-0'
	}
	elseif($Version.Major -ge 9) {
		'4-10-3'
	}
	elseif($Version.Major -ge 8) {
		'4-5-1'
	}
	else {
		'3-6'
	}
}

function Get-CommunitySolrUrl {
    <#
        .SYNOPSIS
            Gets the Solr instance URL for a given community version number
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
    $solrVersion = Get-CommunitySolrVersion $Version

    if($Version.Major -ge 11) {
		"http://${env:COMPUTERNAME}:8760/solr"
	}
    elseif($Version.Major -ge 10) {
		"http://${env:COMPUTERNAME}:8630/solr"
	}
	else {
		"http://${env:COMPUTERNAME}:8080/$solrVersion"
	}
}

function Get-CommunitySolrContentConfigSet {
    <#
        .SYNOPSIS
            Gets the Solr instance URL for a given community version number
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
    
    if($Version.Major -ge 11) {
		"telligent-content-ca80c34"
	}
    elseif($Version.Major -ge 10) {
		"telligent-content-cb15392"
	}
    else {
        ""
    }
}

function Get-CommunitySolrConversationsConfigSet {
    <#
        .SYNOPSIS
            Gets the Solr instance URL for a given community version number
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
    
    if($Version.Major -ge 11) {
		"telligent-conversations-ca80c34"
	}
    elseif($Version.Major -ge 10) {
		"telligent-conversations-de63a3d"
	}
    else {
        ""
    }
}

function Get-CommunitySolrFolder {
    <#
        .SYNOPSIS
            Gets the Solr version for a given community version number
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
    $solrVersion = Get-CommunitySolrVersion $Version

    Join-Path $env:TelligentInstanceManager "Solr\$solrVersion"
}

function Remove-TelligentInstance {
    <#
        .SYNOPSIS
            Removes a TelligentInstance Instance
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER KeepData
            The Database and Filestorage will not be deleted.
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Remove-TelligentInstance test1, test2
               
            Removes the 'test1' and 'test2' TelligentInstance Instances
        .EXAMPLE
            Get-TelligentInstance | Remove-TelligentInstance
               
            Removes all TelligentInstance instances
        .EXAMPLE
            Remove-TelligentInstance FailedInstall -Force
               
            Removes the 'FailedInstall' TelligentInstance instance if it's corrupted to the point it's not dete
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$KeepData,
        [switch]$Force
    )
    process {

        $data = Get-Configuration
        $instanceDir = Join-Path $data.InstanceBase $Name
        $webDir = Join-Path $instanceDir Web
        $jsDir = Join-Path $instanceDir JobServer
        $filestorageDir = Join-Path $instanceDir Filestorage
    
        $info = Get-TelligentCommunity $webDir -ErrorAction SilentlyContinue
        if(!($info -or $Force)) {
            return
        }

        if($Force -or $PSCmdlet.ShouldProcess($Name)) {
            $domain = if($Name.Contains('.')) { $Name } else { "$Name.local"}

            #Delete the site in IIS
            Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Website from IIS'
            if(Get-Website -Name $Name -ErrorAction SilentlyContinue) {
                Remove-Website -Name $Name
            }
            if((Join-Path IIS:\AppPools\ $Name| Test-Path)){
                Remove-WebAppPool -Name $Name
            }

            #Delete the DB
            if(!$KeepData) {
                Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Database'
                Remove-Database -Database $info.DatabaseName -Server $info.DatabaseServer
            }
            
            #Remove Job Server Service
			Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Job Service'
			Stop-Service "Telligent.Jobs.Server-$Name"
			sc.exe delete "Telligent.Jobs.Server-$Name"
			
			if(!$KeepData) {
				# Remove everything
				Remove-Item $instanceDir -Recurse -Force
			} else {
				#Delete the website files
				Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Website Files'
				if(Test-Path $webDir) {
					Remove-Item -Path $webDir -Recurse -Force
				}
				
				#Delete the website files
				Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Job Server Files'
				if(Test-Path $jsDir) {
					Remove-Item -Path $jsDir -Recurse -Force
				}							
			}			
			
            #Remove site from hosts files
            Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Hosts entry'
            $hostsPath = join-path $env:SystemRoot system32\drivers\etc\hosts
            (Get-Content $hostsPath) | Where-Object {$_ -ne "127.0.0.1 $domain"} | Out-File $hostsPath -Encoding UTF8
    
            #Remove the solr core
            Write-Progress 'Uninstalling Telligent Community' $Name -CurrentOperation 'Removing Solr Core'
            if($info) {
				if($info.PlatformVersion.Major -ge 10) {
					$SolrUrl = (Get-CommunitySolrUrl $info.PlatformVersion) + '/admin/cores'
					Remove-SolrCore -Name $Name -CoreAdmin $SolrUrl -EA SilentlyContinue
				}
				else {
					$solrVersion = Get-CommunitySolrVersion $info.PlatformVersion
					$SolrUrl = (Get-CommunitySolrUrl $info.PlatformVersion) + '/admin/cores'
					$SolrDir = Get-CommunitySolrFolder $info.PlatformVersion
					Remove-LegacySolrCore -Name $Name -CoreBaseDir $SolrDir -CoreAdmin $SolrUrl -EA SilentlyContinue
				}
            }
            else {
                Write-Warning "Unable to determine Solr version"
            }

            Write-Host "Deleted website at http://$domain/"
        }
    }
}

function Test-Zip {
	<#
	.Synopsis
		Tests whether a file exists and is a valid zip file.

	.Parameter Path
	    The path to the file to test

	.Example
		Test-Zip c:\sample.zip
		
		Description
		-----------
		This command checks if the file c:\sample.zip exists		
	#>
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Test-Path $Path -PathType Leaf
    if((Get-Item $Path).Extension -ne '.zip') {
		throw "$Path is not a zip file"
    }
}


