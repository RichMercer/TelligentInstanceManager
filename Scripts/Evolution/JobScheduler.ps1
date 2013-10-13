function Install-JobScheduler {
    <#
    .SYNOPSIS
        Installs the Telligent Job Scheduler        
    .PARAMETER package
        The installation package containing the Job Scheduler installation files.        
    .PARAMETER webPath
        The path containing the Telligent Evolution website. Any configuration, addons and hotfixed are copied from here into the Job Scheduler.
    .PARAMETER jsPath
        The path to install the Job Scheduler at
    .PARAMETER InstallService
        Specify this flag to install the Job Scheduler as a service.  You will have to manually run the Job Scheduler as required.        
    .PARAMETER ServiceName
        The name to use when installing the Service
    .PARAMETER Credential
        The credentials for the service to run under
    #>
	[CmdletBinding(DefaultParameterSetName='NoService')]
    param(
    	[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -IsValid})]
        [string]$JobSchedulerPath,
    	[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package,
    	[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
    	[Parameter(ParameterSetName='InstallService')]
        [switch]$InstallService,
    	[Parameter(ParameterSetName='InstallService', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName,
	    [Parameter(ParameterSetName='InstallService',Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$ServiceCredential
    )

    Write-Progress 'Installing Job Scheduler' 'Creating Directory'

    if(!(Test-Path $JobSchedulerPath)) {
        New-Item $JobSchedulerPath -ItemType Directory | out-null
    }

    Write-Progress 'Job Scheduler' 'Extracting Base Job Scheduler'
    Expand-Zip $Package $JobSchedulerPath -ZipDirectory tasks

    Write-Progress 'Job Scheduler' 'Updating Job Scheduler from Website'
    Update-JobSchedulerFromWeb $WebsitePath $JobSchedulerPath

    if($InstallService){
        Install-JobSchedulerService $ServiceName $JobSchedulerPath $Credential
    }
}

function Install-JobSchedulerService {
    <#
    .SYNOPSIS
        Installs the Telligent Job Scheduler as a windows service allation files.        
    .PARAMETER Name
        The name to use when installing the Service
    .PARAMETER Path
        The path the Job Scheduler has been installed to.
    .PARAMETER Credential
        The credentials for the service to run under
    .PARAMETER StartupType
        The startup type to use for the service.
    #>
    [CmdletBinding()]
    param(
    	[Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
    	[Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath,
	    [Parameter(Mandatory=$true,Position=4)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential,
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType = 'Automatic'
    )

    Write-Progress 'Job Scheduler' 'Setting up Service'
    $servicePath = join-path $JobSchedulerPath Telligent.JobScheduler.Service.exe | Resolve-Path
    $serviceName = "Telligent.JobScheduler-$Name"
    $service = New-Service $serviceName `
        -BinaryPathName $servicePath `
        -DisplayName "Telligent Job Scheduler - $Name" `
        -StartupType $StartupType `
        -Credential $Credential `
    
    if($StartupType -eq 'Automatic') {
        Start-Service $service

        Write-Progress 'Job Scheduler' 'Setting automatic service recovery'
        # - first restart after 30 secs, subsequent every 2 mins.
        # - reset failure count after 20 mins
        &sc.exe failure "$serviceName" actions= restart/30000/restart/120000 reset= 1200 | Out-Null

        #If SQL is on the current server, set startup to Automatic (Delayed Startup)
        $info = Get-Community $JobSchedulerPath
        if (('.','(local)','localhost') -contains $info.ServerInstance) {
            Write-Progress 'Job Scheduler' 'Changing startup mode to Automatic (Delayed Start) to prevent race conditions with SQL Server'
            &sc.exe config "$serviceName" start= delayed-auto | Out-Null
        }
    }
}

function Update-JobSchedulerFromWeb {
    <#
    .SYNOPSIS
        Installs the Telligent Job Scheduler as a windows service allation files.        
    .PARAMETER Name
        The name to use when installing the Service
    .PARAMETER jsPath
        The path the Job Scheduler has been installed to.
    .PARAMETER Credential
        The credentials for the service to run under
    .PARAMETER StartupType
        The startup type to use for the service.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
    	[Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -Web})]
        [string]$WebsitePath,
    	[Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler})]
        [string]$JobSchedulerPath
    )
    $roboCopyParams = @(
        # 1 second Wait between retries, max 5 retries
        '/W:1', '/R:5',
        #No Progress, no header, no directory list, no summary, no extra file listing
        '/NP', '/NJH', '/NDL', '/NJS', '/XX'
    )

    if ($pscmdlet.ShouldProcess($jsPath)) {
        #$sharedParams += '/L'

        #Copy web /bin/ to JS root
        Write-Progress 'Job Scheduler' 'Updating binaries from web'
        &robocopy "$WebsitePath\bin\" "$JobSchedulerPath" /e @roboCopyParams | Out-Null

        Write-Progress 'Job Scheduler' 'Updating config files from web'
        &robocopy "$WebsitePath" "$JobSchedulerPath\" *.config /s /XF web.config tasks.config /XD ControlPanel @roboCopyParams | Out-Null

        #TODO: is themes explicitly required if we copy *.config?
        Write-Progress 'Job Scheduler' 'Updating modules and languages from web'
        @('modules', 'languages') |% {
            Write-Verbose "JS Install: Syncing $_"
            &robocopy "$WebsitePath\$_\" "$JobSchedulerPath\$_\" /e /Mir @roboCopyParams | Out-Null
        }

        #TODO: Sync sections of web.config into tellgient.js.service.exe.config
        #      OR use web.config then merge back in JS specifics?
    }
    popd
}