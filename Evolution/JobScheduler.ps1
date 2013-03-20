function Update-JobSchedulerFromWeb {
	[cmdletBinding(SupportsShouldProcess=$True)]
    param(
    	[parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$webBase,
    	[parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$jsBase
    )
    pushd $webBase
    $sharedParams = @(
        # 1 second Wait between retries, max 5 retries
        '/W:1', '/R:5',
        #No Progrtess, no header, no directory list, no summary, no extra file listing
        '/NP', '/NJH', '/NDL', '/NJS', '/XX'
    )

    if ($pscmdlet.ShouldProcess($jsBase)) {
        $sharedParams += '/L'

        #Copy web /bin/ to JS root
        &robocopy "bin\" "$jsBase" /e @sharedParams

        #Copy .config files except web.config & tasks.config
        &robocopy "." "$jsBase\" *.config /s /XF web.config tasks.config /XD ControlPanel @sharedParams 

        #Mirror modules & languagesdirectories
        #TODO: is themes required if we copy *.config?
        @('modules', 'languages') |% {
            Write-Host "Syncing $_"
            &robocopy "$_\" "$jsBase\$_\" /e /Mir @sharedParams 
        }
        &cd

    }
    popd
}


Update-JobSchedulerFromWeb c:\sites\test-demo\20130318 c:\telligentservices\test-demo.jobscheduler -WhatIf


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
        [string]$webBase,
	    [parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [string]$username,
	    [parameter(Mandatory=$false,Position=4)]
        [string]$password
    )
    $servicePath = join-path $jsBase Telligent.JobScheduler.Service.exe

    #extract base JS

    #Copy all config files recursively from web except web.config, tasks.config

    #Copy dlls from web bin to JS root

    #Mirror languages, Modules


    $serviceName = "JS-$name"
    New-Service $serviceName `
        -BinaryPathName $servicePath `
        -DisplayName "Job Scheduler - $name" `
        -Description "Job Scheduler service for $domainName" `
        -StartupType Automatic `
        | out-null
        
    $wmiService = Get-Wmiobject win32_service -filter "name='$serviceName'" 
    $params = $wmiService.psbase.getMethodParameters("Change") 
    $params["StartName"] = $username
    $params["StartPassword"] = $null
    $wmiService.invokeMethod("Change",$params,$null) | out-null
    start-service $serviceName
}