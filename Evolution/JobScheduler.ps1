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
        [string]$jsBase,
	    [parameter(Mandatory=$true,Position=4)]
        [ValidateNotNullOrEmpty()]
        [string]$username,
	    [parameter(Mandatory=$false,Position=5)]
        [string]$password
    )

    Write-Progress "Job Scheduler" "Creating Directory"

    if(!(Test-Path $jsBase)) {
        New-Item $jsBase -ItemType Directory | out-null
    }

    Write-Progress "Job Scheduler" "Extracting Base Job Scheduler"
    Expand-Zip $package $jsBase -zipDir "tasks"


    Write-Progress "Job Scheduler" "Extracting Base Job Scheduler"
    Update-JobSchedulerFromWeb $webBase $jsBase | Write-Host

    Write-Progress "Job Scheduler" "Setting up Service"
    $servicePath = join-path $jsBase Telligent.JobScheduler.Service.exe
    $serviceName = "Telligent.JobScheduler-$name"
    New-Service $serviceName `
        -BinaryPathName $servicePath `
        -DisplayName "Telligent Job Scheduler - $name" `
        -Description "Telligent Job Scheduler service for $domainName" `
        -StartupType Automatic `
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
        [string]$webBase,
    	[parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$jsBase
    )
    $sharedParams = @(
        # 1 second Wait between retries, max 5 retries
        '/W:1', '/R:5',
        #No Progrtess, no header, no directory list, no summary, no extra file listing
        '/NP', '/NJH', '/NDL', '/NJS', '/XX'
    )

    if ($pscmdlet.ShouldProcess($jsBase)) {
        #$sharedParams += '/L'

        #Copy web /bin/ to JS root
        &robocopy "$webBase\bin\" "$jsBase" /e @sharedParams

        #Copy .config files except web.config & tasks.config
        &robocopy "$webBase" "$jsBase\" *.config /s /XF web.config tasks.config /XD ControlPanel @sharedParams 

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

