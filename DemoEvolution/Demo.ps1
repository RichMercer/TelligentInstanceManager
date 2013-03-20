$pathData = @{
    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = 'd:\Telligent\MassInstall\Licences'

    # The directory where web folders are created for each website
	WebBase = 'c:\sites\'

    #Solr Url for solr cores.
    #{0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = 'http://localhost:8080/shared_3-6/'

    # Solr core Directories.
	SolrCoreBase = 'C:\telligentsearch\shared_3-6\'
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
    $webDir = Join-Path (Join-Path $pathData.WebBase $name) (Get-Date -f yyyyMMdd)

    $domain = "${name}.telligentdemo.com"

    Install-Evolution -name $name `
        -package $basePackage `
        -hotfixPackage $hotfixPackage `
        -webDir $webDir `
        -webDomain $domain `
        -licenceFile (join-path $pathData.LicencesPath "${product}$($version.Major).xml") `
        -solrUrl $pathData.SolrUrl.TrimEnd("/") `
        -solrCoreDir $pathData.SolrCoreBase  

    #Install JS

    #Install Addons

    #Filestorage

    pushd $webdir 
    try {
    #      
    }
    finally {
    	popd
    }

    #Add site to hosts files
    Add-Content -value "127.0.0.1 $domain" -path (join-path $env:SystemRoot system32\drivers\etc\hosts)
	Write-Host "Created website at http://$domain/"
    Start-Process "http://$domain/"
}