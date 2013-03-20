ipmo webadministration
$sitesBaseDir = 'c:\sites'

function Invoke-ChangeControl {
	[cmdletBinding(SupportsShouldProcess=$True, ConfirmImpact='High')]
    param(
    	[parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Join-Path $sitesBaseDir $_ | Resolve-Path})]
        [string]$siteName,
        [switch]$force
    )
    $siteDir = Join-Path $sitesBaseDir $siteName

    $iisSite = dir iis:\sites\ |? {$_.PhysicalPath.StartsWith($siteDir, 'OrdinalIgnoreCase') }

    #For some reason the above query could find multiple matching sites, or nothing.  Report if so
    if(@($iisSite).Count -ne 1)
    {
        Write-Error "Unable to detect current web driectory - incorrectly detected iis site"
        Write-Error "Detected IIS Sites:"
        Write-Error $iisSite
        return;
    }

    $currentWebdir = $iisSite.PhysicalPath

    #Check nothing funny's happened and the path reported by IIS actually exists
    if (!(Test-Path $currentWebdir))
    {
        Write-Error "Can't find IIS Physical Path: $currentWebDir"
        return
    }

    # Work out the directory name of the new
    # this will be in the form:
    #    yyyyMMdd
    # OR yyyMMdd-XXX - if the previous directory exists, where XXX is an incremented number
    $newWebPrefix = Get-Date -f yyyyMMdd
    $newWebDir = $newWebPrefix
    $i = 1
    while(Test-Path $newWebDir)
    {
        $newWebDir = "$newWebPrefix-$i"
        $i++
    }

    #Get full path of new web dir to show in confimration prompt
    $newWebDir = Join-Path $siteDir $newWebDir

    #Set up initial arguments to use for robocpy
    $robocopyArgs = @(
        '/E', # Copy all subdirs, including empty
        '/SEC' # Copy security 7 ACLs
        '/ZB' # Copy in restartable backup mode
        '/NP' # Don't log percent progress copy for file
        '/R:5' #Retry up to 5 times
        '/W:1' #Wait 1 sec between retries
    )

    ##Support for -whatIf
    #-WhatIf support

    #Only continue if the -WhatIf or -Force are specified, or the user has accepted a manual confirmation prompt
    if($WhatIfPreference.IsPresent -or $force -or $pscmdlet.ShouldProcess($newWebDir, "Change Control for $siteName")) {

        if($WhatIfPreference.IsPresent) {
            #When the WhatIf switch is present, use the /L paramater on robocopy to list changes
            $robocopyArgs += '/L' #Only list changes, don't actually make them
        }
        else {
            #If -WhatIf not specified, log changes to a file and use a MultiThreaded copy
            $robocopyArgs += @(
                ('/LOG:"' + $newWebDir.TrimEnd("\") + '.log"'),
                '/MT'
            )
        }

        #Now call robocopy with the requried arguments
        #Note, robocopy *must* have trailing slashes on the source and destination directories
        &robocopy "$currentWebDir\" "$newWebDir\" @robocopyArgs
    }
}