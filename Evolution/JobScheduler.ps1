function Install-JobScheduler {
	[CmdletBinding()]
    param(
    	[parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
    	[parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
    	[parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$webPath,
    	[parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [string]$jsPath,
	    [parameter(Mandatory=$true,Position=4)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$credential,
        [switch]$startService
    )

    Write-Progress "Installing Job Scheduler" "Creating Directory"

    if(!(Test-Path $jsPath)) {
        New-Item $jsPath -ItemType Directory | out-null
    }

    Write-Progress "Job Scheduler" "Extracting Base Job Scheduler"
    Expand-Zip $package $jsPath -zipDir "tasks"


    Write-Progress "Job Scheduler" "Extracting Base Job Scheduler"
    Update-JobSchedulerFromWeb $webPath $jsPath | Write-Host

    Write-Progress "Job Scheduler" "Setting up Service"
    $servicePath = join-path $jsPath Telligent.JobScheduler.Service.exe
    $serviceName = "Telligent.JobScheduler-$name"
    New-Service $serviceName `
        -BinaryPathName $servicePath `
        -DisplayName "Telligent Job Scheduler - $name" `
        -Description "Telligent Job Scheduler service for $domainName" `
        -StartupType Automatic `
        -Credential $credential `
        | out-null
        
<#    $wmiService = Get-Wmiobject win32_service -filter "name='$serviceName'" 
    $params = $wmiService.psbase.getMethodParameters("Change") 
    $params["StartName"] = $username
    $params["StartPassword"] = $null
    $wmiService.invokeMethod("Change",$params,$null) | out-null
    #>


    Write-Progress "Job Scheduler" "Setting automatic service recovery"
    # - first restart after 30 secs, subsequent every 2 mins.
    # - reset failure count after 20 mins
    &sc.exe failure "$serviceName" actions= restart/30000/restart/120000 reset= 1200

    #If SQL is on the current server, set startup to Automatic (Delayed Startup)
    if(get-service MSSQLSERVER){
        #TODO: Safer to check connection string for (local) / Machine name
           Write-Progress "Job Scheduler" "Changing startup mode to Automatic (Delayed Start) to prevent race conditions with SQL Server"
           &sc.exe config "$serviceName" start= delayed-auto
    }

    if ($startService) {
        Write-Progress "Job Scheduler" "Starting service"
        Start-Service $serviceName
    }

    return Get-Service $serviceName
}

function Update-JobSchedulerFromWeb {
	[cmdletBinding(SupportsShouldProcess=$True)]
    param(
    	[parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$webPath,
    	[parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$jsPath
    )
    $sharedParams = @(
        # 1 second Wait between retries, max 5 retries
        '/W:1', '/R:5',
        #No Progrtess, no header, no directory list, no summary, no extra file listing
        '/NP', '/NJH', '/NDL', '/NJS', '/XX'
    )

    if ($pscmdlet.ShouldProcess($jsPath)) {
        #$sharedParams += '/L'

        #Copy web /bin/ to JS root
        Write-Progress "Job Scheduler" "Updating binaries from web"
        &robocopy "$webPath\bin\" "$jsPath" /e @sharedParams | Out-Null

        Write-Progress "Job Scheduler" "Updating config files from web"
        &robocopy "$webPath" "$jsPath\" *.config /s /XF web.config tasks.config /XD ControlPanel @sharedParams | Out-Null

        #TODO: is themes required if we copy *.config?
        Write-Progress "Job Scheduler" "Updating modules and languages from web"
        @('modules', 'languages') |% {
            Write-Host "Syncing $_"
            &robocopy "$webPath\$_\" "$jsPath\$_\" /e /Mir @sharedParams | Out-Null
        }
    }
    popd
}

function Enable-Plugin {
}