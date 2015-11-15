Set-StrictMode -Version 2

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

    $info = Get-Community $WebsitePath
    if ($info.PlatformVersion.Major -ge 8 ) {
        Expand-Zip $Package $JobSchedulerPath -ZipDirectory JobService

        Write-Progress 'Job Scheduler' 'Executing Job Scheduler SQL'
        $tempDir = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ([guid]::NewGuid())
        Expand-Zip -Path $package -Destination $tempDir -ZipDirectory SqlScripts -ZipFile Jobs_InstallUpdate.sql
        $sqlScript = Join-Path $tempDir Jobs_InstallUpdate.sql | Resolve-Path

    	Invoke-SqlCmdAgainstCommunity -WebsitePath $WebsitePath -File $sqlScript
    }
    else {
        Write-Progress 'Job Scheduler' 'Extracting Base Job Scheduler'
        Expand-Zip $Package $JobSchedulerPath -ZipDirectory tasks
    }
    
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
    	[Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
    	[Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath,
	    [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential,
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType = 'Automatic'
    )

    $localJsPath = $JobSchedulerPath | Convert-Path

    $splat = @{}
    if ($localJsPath.StartsWith('\\')) {
        $path = Expand-UNCPath $localJsPath
        if (!$path.LocalPath ) {
            Write-Error "Unable to determine local path for '$localJsPath'"
            return;
        }
        $splat.ComputerName = $path.ComputerName
        $localJsPath = $path.LocalPath
    }
    if (Join-Path $JobSchedulerPath Telligent.Jobs.Server.exe | Test-Path) {
        $servicePath = "$($localJsPath.TrimEnd('\'))\Telligent.Jobs.Server.exe"
        $serviceName = "Telligent.Jobs.Server-$Name"
    }
    else {
        $servicePath = "$($localJsPath.TrimEnd('\'))\Telligent.JobScheduler.Service.exe"
        $serviceName = "Telligent.JobScheduler-$Name"
    }
    

    if ($splat.ContainsKey('ComputerName')) {
        Write-Verbose "Setting up service on '$($splat.ComputerName)'"
    } 
    else {
        Write-Verbose 'Setting up service'
    }

    $displayName = "Telligent Job Scheduler - $Name"
    $localSqlServer = ('.','(local)','localhost') -contains (Get-Community $JobSchedulerPath).DatabaseServer

    Invoke-Command @splat -ArgumentList @($serviceName, $servicePath, $displayName, $StartupType, $Credential, $localSqlServer) {
        param (
        	[Parameter(Mandatory=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$serviceName,
        	[Parameter(Mandatory=$true,Position=2)]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({ Test-Path $_ -PathType Leaf})]
            [string]$servicePath,
        	[Parameter(Mandatory=$true,Position=3)]
            [string]$displayName,
            [ValidateNotNullOrEmpty()]
        	[Parameter(Mandatory=$true,Position=4)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet('Automatic', 'Manual', 'Disabled')]
            [string]$startupType,
        	[Parameter(Mandatory=$true,Position=5)]
            [ValidateNotNullOrEmpty()]
            [PSCredential]$credential,
        	[Parameter(Mandatory=$true,Position=6)]
            [ValidateNotNullOrEmpty()]
            [bool]$localSqlServer
        )
        #New-Service doesn't support Managed Service accounts on it's Credential object
        $service = if ($credential.Password.Length -eq 0)
        {
            &sc.exe create "$serviceName" binPath= "$servicePath" DisplayName= "$displayName" start= auto obj= "$($credential.UserName)"
        }
        else {
            New-Service $serviceName `
                -BinaryPathName $servicePath `
                -DisplayName $displayName `
                -StartupType $startupType `
                -Credential $credential
        }
    
        if($service -and $startupType -eq 'Automatic') {

            Write-Verbose 'Setting automatic service recovery'
            # - first restart after 30 secs, subsequent every 2 mins.
            # - reset failure count after 20 mins
            &sc.exe failure "$serviceName" actions= restart/30000/restart/120000 reset= 1200 | Out-Null

            #If SQL is on the current server, set startup to Automatic (Delayed Startup)
            if ($localSqlServer) {
                Write-Verbose 'Changing startup mode to Automatic (Delayed Start) to prevent race conditions with SQL Server'
                &sc.exe config "$serviceName" start= delayed-auto | Out-Null
            }

            Start-Service $serviceName
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
        #No Progress, no file list, no header, no directory list, no summary, no extra file listing
        '/NP', '/NFL', '/NJH', '/NDL', '/NJS', '/XX'
    )
    if ($pscmdlet.ShouldProcess($JobSchedulerPath)) {
        #$sharedParams += '/L'
        $WebsitePath = $WebsitePath.TrimEnd('\')
        $JobSchedulerPath = $JobSchedulerPath.TrimEnd('\')

        #Copy web /bin/ to JS root
        Write-Progress 'Job Scheduler' 'Updating binaries from web'
        &robocopy "$WebsitePath\bin" "$JobSchedulerPath" /e @roboCopyParams | Write-Host

        Write-Progress 'Job Scheduler' 'Updating config files from web'
        &robocopy "$WebsitePath" "$JobSchedulerPath" *.config /s /XF web.config tasks.config jobs.config /XD ControlPanel @roboCopyParams  | Write-Host


        #TODO: is themes explicitly required if we copy *.config?
        Write-Progress 'Job Scheduler' 'Updating modules and languages from web'
        @('modules', 'languages') |% {
            $dir = Join-Path $WebsitePath $_
            if(Test-Path $dir) {
                &robocopy "$dir" "$JobSchedulerPath\$_" /e /Mir @roboCopyParams  | Write-Host
            }
        }

        #TODO: Sync sections of web.config into tellgient.js.service.exe.config
        #      OR use web.config then merge back in JS specifics?
    }
    popd
}

function Remove-Service {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
    	[Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Leaf})]        
        [string]$Executable,
        [switch]$Force
    )

    $localPath = $Executable | Convert-Path

    $splat = @{}
    if ($localPath.StartsWith('\\')) {
        $path = Expand-UNCPath $localPath
        if (!$path.LocalPath ) {
            Write-Error "Unable to determine local path for '$localJsPath'"
            return;
        }
        $splat.ComputerName = $path.ComputerName
        $localPath = $path.LocalPath
    }

    gwmi win32_service @splat |
        ? PathName -like "${localPath}*" |
        ? { $Force -or $PSCmdlet.ShouldProcess($_.Name) } |
        % {
            Write-Verbose "Removing Service '$($_.Name)'"
            $_.StopService() |Out-Null
            $_.Delete() | Out-Null
        }
}