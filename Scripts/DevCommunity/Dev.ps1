Set-StrictMode -Version 2

$base = $env:EvolutionMassInstall
if (!$base) {
    Write-Error 'EvolutionMassInstall environmental variable not defined'
}

$data = @{
    #SQL Server to use.
    SqlServer = if($env:DBServerName) { $env:DBServerName } else { '(local)' }

    #Default password to use for new communities
    AdminPassword = 'password'

    #A default API key to create for the administrator account
    ApiKey = 'abc123'

    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = Join-Path $base Licences | Resolve-Path

    # The directory where web folders are created for each website
	WebBase = Join-Path $base Web

    # The directory where web folders are created for each website
	JobSchedulerBase = Join-Path $base JobScheduler

    #Solr Url for solr cores.
    #{0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = "http://${env:COMPUTERNAME}:8080/{0}"

    # Solr core Directories.
    # {0} gets replaced in the same way as for SolrUrl
	SolrCoreBase = Join-Path $base 'Solr\{0}\'
}

function Get-DevCommunity {
    <#
        .SYNOPSIS
            Gets DevCommunity instances
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Get-DevCommunity
               
            Gets all DevCommunity instances
        .EXAMPLE
            Get-DevCommunity test123

            Gets the DevCommunity instance named 'test123'
        .EXAMPLE
            Get-DevCommunity ps*
               
            Gets all DevCommunity instances whose names match the pattern 'ps*'
    #>
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Name,
        [string]$Version
    )

    $results = Get-ChildItem $data.WebBase |
            select -ExpandProperty FullName |
            Get-Community -EA SilentlyContinue

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

function Install-DevCommunity {
    <#
    .Synopsis
	    Sets up a new Telligent Evolution community for development purposes.
    .Description
	    The Install-Community cmdlet automates the process of creating a new Telligent Evolution community.
		
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
        Get-CommunityBuild 7.6 | Install-DevCommunity TestSite
        
        Output can be piped from Get-CommunityBuild to automatically fill in the product, version, basePackage and hotfixPackage paramaters
    
				
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateScript({if(Get-DevCommunity $_){ throw "DevCommunity Instance '$_' already exists" } else { $true }})]
        [string] $Name,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
 		[ValidateSet('Community','Enterprise')]
 		[string] $Product,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
        [version] $Version,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string] $BasePackage,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [string] $HotfixPackage,
        [switch] $WindowsAuth
    )
    $name = $name.ToLower()

    $solrVersion = Get-CommunitySolrVersion $Version
    $webDir = Join-Path $data.WebBase $Name
    $jsDir = Join-Path $data.JobSchedulerBase $Name
    $filestorageDir = Join-Path $webDir filestorage
    $domain = if($Name.Contains('.')) { $Name } else { "$Name.local"}

    $info = Install-Community -name $Name `
        -Package $BasePackage `
        -Hotfix $HotfixPackage `
        -WebsitePath $webDir `
        -JobSchedulerPath $jsDir `
        -FilestoragePath $filestorageDir `
        -WebDomain $domain `
        -Licence (join-path $data.LicencesPath "${Product}$($Version.Major).xml") `
        -SolrCore `
        -SolrBaseUrl ($data.SolrUrl -f $solrVersion).TrimEnd('/') `
        -SolrCoreDir ($data.SolrCoreBase -f $solrVersion) `
        -AdminPassword $data.AdminPassword `
        -DatabaseServer $data.SqlServer `
        -ApiKey $data.ApiKey

    if ($info) {
	    Disable-CustomErrors $webDir

        $dbUsername = Get-IISAppPoolIdentity $Name
        Invoke-SqlCmdAgainstCommunity -WebsitePath $webDir -Query "EXEC sp_addrolemember N'db_owner', N'$dbUsername'"

    	if($info.PlatformVersion -ge 5.6 -and $info.PlatformVersion.Major -lt 8){
            Register-TasksInWebProcess $webDir $basePackage
        }

        if ($WindowsAuth) {
            Enable-WindowsAuth $webDir -EmailDomain '@tempuri.org' -ProfileRefreshInterval 0
        }        

        #Add site to hosts files
        Add-Content -value "`r`n127.0.0.1 $domain" -Path (join-path $env:SystemRoot system32\drivers\etc\hosts)

        $info | Add-Member Url "http://$domain/" -PassThru

        if([Environment]::UserInteractive) {
            Start-Process $info.Url
        }
    }
}

function Get-CommunitySolrVersion {
    <#
        .SYNOPSIS
            Gets the Solr version for a given community version numeber
        .PARAMETER Version
            The community version
        .EXAMPLE
            Get-CommunitySolrVersion 9.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Version]$Version
    )
	if($Version.Major -ge 9) {
		'4-10-3'
	}
	elseif($Version.Major -ge 8) {
		'4-5-1'
	}
	elseif(@(2,3,5,6) -contains $Version.Major) {
		'1-4'
	}
	else {
		'3-6'
	}
}

function Remove-DevCommunity {
    <#
        .SYNOPSIS
            Removes a DevCommunity Instance
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Remove-DevCommunity test1, test2
               
            Removes the 'test1' and 'test2' DevCommunity Instances
        .EXAMPLE
            Get-DevCommunity | Remove-DevCommunity
               
            Removes all DevCommunity instances
        .EXAMPLE
            Remove-DevCommunity FailedInstall -Force
               
            Removes the 'FailedInstall' DevCommunity instance if it's corrupted to the point it's not dete
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Force
    )
    process {
        $webDir = Join-Path $data.WebBase $Name
    
        $info = Get-Community $webDir -ErrorAction SilentlyContinue
        if(!($info -or $Force)) {
            return
        }

        if($Force -or $PSCmdlet.ShouldProcess($Name)) {
            $domain = if($Name.Contains('.')) { $Name } else { "$Name.local"}

            #Delete the JS
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Job Scheduler'
            $jsDir = Join-Path $data.JobschedulerBase $Name
            if (Test-Path $jsDir -PathType Container) {
                Get-Process |? Path -like "$jsDir*" | Stop-Process
                Remove-Item $jsDir -Recurse -Force
            }

            #Delete the site in IIS
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Website from IIS'
            if(Get-Website -Name $Name -ErrorAction SilentlyContinue) {
                Remove-Website -Name $Name
            }
            if((Join-Path IIS:\AppPools\ $Name| Test-Path)){
                Remove-WebAppPool -Name $Name
            }

            #Delete the DB
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Database'
            Remove-Database -Database $Name -Server $data.SqlServer

            #Delete the files
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Website Files'
            if(Test-Path $webDir) {
                Remove-Item -Path $webDir -Recurse -Force
            }
    
            #Remove site from hosts files
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Hosts entry'
            $hostsPath = join-path $env:SystemRoot system32\drivers\etc\hosts
            (Get-Content $hostsPath) | Foreach-Object {$_ -replace "127.0.0.1 $domain", ''} | Set-Content $hostsPath
    
            #Remove the solr core
            Write-Progress 'Uninstalling Evolution Community' $Name -CurrentOperation 'Removing Solr Core'
            $solrVersion = Get-CommunitySolrVersion $info.PlatformVersion
            $solrUrl = ($data.SolrUrl -f $solrVersion).TrimEnd('/') + '/admin/cores'
            Remove-SolrCore -Name $Name -CoreBaseDir ($data.SolrCoreBase -f $solrVersion) -CoreAdmin $solrUrl -EA SilentlyContinue

            Write-Host "Deleted website at http://$domain/"
        }
    }
}

Set-Alias isdc Install-DevCommunity
Set-Alias rdc Remove-DevCommunity
Set-Alias gdc Get-DevCommunity


#Backwards compatibility with previous names
Set-Alias Install-DevEvolution Install-DevCommunity
Set-Alias Remove-DevEvolution Remove-DevCommunity
Set-Alias Get-DevEvolution Get-DevCommunity
Set-Alias isde Install-DevCommunity
Set-Alias rde Remove-DevCommunity
Set-Alias gde Get-DevCommunity