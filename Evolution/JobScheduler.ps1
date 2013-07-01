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
		[ValidateScript({Resolve-Path $_ })]
        [string]$webPath,
    	[parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [string]$jsPath,
	    [parameter(Mandatory=$true,Position=4)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$credential
    )

    Write-Progress "Job Scheduler" "Creating Directory"

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
        -Credential $credential
        | out-null
        
    $wmiService = Get-Wmiobject win32_service -filter "name='$serviceName'" 
    $params = $wmiService.psbase.getMethodParameters("Change") 
    $params["StartName"] = $username
    $params["StartPassword"] = $null
    $wmiService.invokeMethod("Change",$params,$null) | out-null

    return Get-Service $serviceName
}

function Update-JobSchedulerFromWeb {
	[cmdletBinding(SupportsShouldProcess=$True)]
    param(
    	[parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$webPath,
    	[parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
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
        &robocopy "$webPath\bin\" "$jsPath" /e @sharedParams

        #Copy .config files except web.config & tasks.config
        &robocopy "$webPath" "$jsPath\" *.config /s /XF web.config tasks.config /XD ControlPanel @sharedParams 

        #Mirror modules & languagesdirectories
        #TODO: is themes required if we copy *.config?
        @('modules', 'languages') |% {
            Write-Host "Syncing $_"
            &robocopy "$webPath\$_\" "$jsPath\$_\" /e /Mir @sharedParams 
        }
        &cd

    }
    popd
}

