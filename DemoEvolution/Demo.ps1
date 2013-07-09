$pathData = @{
    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = 'c:\TelligentAutomation\Licences\'

    # The directory where web folders are created for each website
	WebBase = 'c:\sites\'

    # SQL Password
    WebDomainBase = "telligentdemo.com"

    # Solr Url for solr cores.
    # {0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = 'http://localhost:8080/shared_3-6/'

    # Solr core Directories.
	SolrCoreBase = 'C:\telligentsearch\shared_3-6\Cores\'
}

function Install-DemoEvolution {
    param(
        [parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z0-9\-\._]+$')]
        [ValidateNotNullOrEmpty()]
        [string] $name,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
 		[ValidateSet('Community','Enterprise')]
 		[string] $product,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
        [version] $version,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string] $basePackage,
        [parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({!$_ -or (Test-Zip $_) })]
        [string] $hotfixPackage
    )
    $ErrorActionPreference = "Stop"

    $siteBase = Join-Path $pathData.WebBase $name
    $webDir = Join-Path $siteBase (Get-Date -f yyyyMMdd)
    $filestorage = Join-Path $siteBase filestorage

    $domain = "${name}." + $pathData.WebDomainBase

    Install-Evolution -name $name `
        -package $basePackage `
        -hotfixPackage $hotfixPackage `
        -webDir $webDir `
        -webDomain $domain `
        -filestorage $filestorage `
        -licenceFile (join-path $pathData.LicencesPath "${product}$($version.Major).xml") `
        -solrCore `
        -solrUrl $pathData.SolrUrl.TrimEnd("/") `
        -solrCoreDir $pathData.SolrCoreBase  `
        -sqlAuth `
        -dbUsername $name `
        -dbPassword ([guid]::NewGuid().ToString())




    #Install JS
    $jsPath = "C:\telligentservices\${name}.jobscheduler"
    $jsPassword = New-Object Security.SecureString
    $jsCredentials = New-Object PSCredential "NT AUTHORITY\NETWORK SERVICE", $jsPassword
    $jsService = Install-JobScheduler $name $basePackage $webDir $jsPath $jsCredentials

    pushd C:\TelligentAutomation\Addons
    try
    {
        $params = @{
            WebPath = $webDir
            JobSchedulerPath = $jsPath
        }

        Install-EvolutionCalendar -Package TelligentEventCalendar-3.0.72.32639.zip @params
        Install-EvolutionDocumentPreview -Package TelligentDocumentViewer-1.1.50.29573.zip @params
        Install-EvolutionVideoTranscoding -Package TelligentVideoTranscoder-1.1.9.28904.zip @params
        Install-EvolutionChat -Package TelligentEvolutionChat-1.0.67.32476.zip @params
        Install-EvolutionIdeation -Package TelligentEvolutionExtensionsIdeation-1.0.102.33348.zip @params
    }
    finally {
        popd
    }

    Write-Progress "Job Scheduler" "Starting Service"
    Start-Service $jsService


    #Add site to hosts files
    Add-Content -value "`r`n127.0.0.1 $domain" -path (join-path $env:SystemRoot system32\drivers\etc\hosts)
	Write-Host "Created website at http://$domain/"

    #Open site in web browser
    Start-Process "http://$domain/"
}