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
	SolrUrl = 'http://localhost:8080/{0}'

    # Solr core Directories.
    # {0} gets replaced in the same way as for SolrUrl
	SolrCoreBase = Join-Path $base 'Solr\{0}\'
}

function Get-DevEvolution {
    <#
        .SYNOPSIS
            Gets DevEvolution instances
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Get-DevEvolution
               
            Gets all DevEvolution instances
        .EXAMPLE
            Get-DevEvolution test123

            Gets the DevEvolution instance named 'test123'
        .EXAMPLE
            Get-DevEvolution ps*
               
            Gets all DevEvolution instances whose names match the pattern 'ps*'
    #>
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Name
    )
    $results = get-childitem $data.WebBase |
            select -ExpandProperty FullName |
            Get-Community

    if ($Name) {
        $results = $results |? Name -like $Name
    }
    $results
}

function Install-DevEvolution {
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateScript({if(Get-DevEvolution $_){ throw "DevEvolution Instance '$_' already exists" } else { $true }})]
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

    $solrVersion = if(@(2,3,5,6) -contains $Version.Major){ '1-4' } else { '3-6'  }
    $webDir = Join-Path $data.WebBase $Name
    $jsDir = Join-Path $data.JobSchedulerBase $Name
    $filestorageDir = Join-Path $webDir filestorage
    $domain = if($Name.Contains('.')) { $Name } else { "$Name.local"}

    $info = Install-Evolution -name $Name `
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

function Remove-DevEvolution {
    <#
        .SYNOPSIS
            Removes a DevEvolution Instance
        .PARAMETER Name
            The name of the instance to remove
        .PARAMETER Force
            Forces removal of the named instance, even if the named instance cannot be found.
        .EXAMPLE
            Remove-DevEvolution test1, test2
               
            Removes the 'test1' and 'test2' DevEvolution Instances
        .EXAMPLE
            Get-DevEvolution | Remove-DevEvolution
               
            Removes all DevEvolution instances
        .EXAMPLE
            Remove-DevEvolution FailedInstall -Force
               
            Removes the 'FailedInstall' DevEvolution instance if it's corrupted to the point it's not dete
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
            $solrVersion = if(@(2,3,5,6) -contains $info.PlatformVersion.Major){ '1-4' } else { '3-6' }
            $domain = $Name

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
            $solrUrl = ($data.SolrUrl -f $solrVersion).TrimEnd('/') + '/admin/cores'
            Remove-SolrCore -Name $Name -CoreBaseDir ($data.SolrCoreBase -f $solrVersion) -CoreAdmin $solrUrl

	        Write-Host "Deleted website at http://$domain/"
        }
    }
}

Set-Alias isde Install-DevEvolution
Set-Alias rde Remove-DevEvolution
Set-Alias gde Get-DevEvolution