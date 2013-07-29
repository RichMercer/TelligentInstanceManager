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
        
    Write-Progress "Job Scheduler" "Setting automatic service recovery"
    # - first restart after 30 secs, subsequent every 2 mins.
    # - reset failure count after 20 mins
    &sc.exe failure "$serviceName" actions= restart/30000/restart/120000 reset= 1200 | Out-Null

    #If SQL is on the current server, set startup to Automatic (Delayed Startup)
    if($true){
        #TODO: Safer to check connection string for (local) / Machine name
           Write-Progress "Job Scheduler" "Changing startup mode to Automatic (Delayed Start) to prevent race conditions with SQL Server"
           &sc.exe config "$serviceName" start= delayed-auto | Out-Null
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
        #No Progress, no header, no directory list, no summary, no extra file listing
        '/NP', '/NJH', '/NDL', '/NJS', '/XX'
    )

    if ($pscmdlet.ShouldProcess($jsPath)) {
        #$sharedParams += '/L'

        #Copy web /bin/ to JS root
        Write-Progress "Job Scheduler" "Updating binaries from web"
        &robocopy "$webPath\bin\" "$jsPath" /e @sharedParams | Out-Null

        Write-Progress "Job Scheduler" "Updating config files from web"
        &robocopy "$webPath" "$jsPath\" *.config /s /XF web.config tasks.config /XD ControlPanel @sharedParams | Out-Null

        #TODO: is themes explicitly required if we copy *.config?
        Write-Progress "Job Scheduler" "Updating modules and languages from web"
        @('modules', 'languages') |% {
            Write-Verbose "JS Install: Syncing $_"
            &robocopy "$webPath\$_\" "$jsPath\$_\" /e /Mir @sharedParams | Out-Null
        }

        #TODO: Sync sections of web.config into tellgient.js.service.exe.config
        #      OR use web.config then merge back in JS specifics?
    }
    popd
}