$base = $env:EvolutionPackageLocation
if (!$base) {
    $base = $PSScriptRoot
}

$pathData = @{
    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = Join-Path $env:EvolutionPackageLocation Licences | Resolve-Path

    # The directory where web folders are created for each website
	WebBase = Join-Path $base Web

    #Solr Url for solr cores.
    #{0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = 'http://localhost:8080/{0}'

    # Solr core Directories.
    # {0} gets replaced in the same way as for SolrUrl
	SolrCoreBase = Join-Path $base 'Solr\{0}\Cores\'
}
function Install-DevEvolution {
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
		[ValidateScript({Test-Path $_ })]
        [string] $basePackage,
        [parameter(ValueFromPipelineByPropertyName=$true)]
		[ValidateScript({Test-Path $_ })]
        [string] $hotfixPackage,
        [switch] $noSearch
    )
    $ErrorActionPreference = "Stop"

    $solrVersion = if(@(2,3,5,6) -contains $version.Major){ "1-4" } else {"3-6" }
    $webDir = (Join-Path $pathData.WebBase $name)
    $domain = "$name.local"

    Install-Evolution -name $name `
        -package $basePackage `
        -hotfixPackage $hotfixPackage `
        -webDir $webDir `
        -netVersion $(if (@(2,5) -contains $version.Major) { 2.0 } else { 4.0 }) `
        -webDomain $domain `
        -licenceFile (join-path $pathData.LicencesPath "${product}$($version.Major).xml") `
        -solrCore:(!$noSearch) `
        -solrUrl ($pathData.SolrUrl -f $solrVersion).TrimEnd("/") `
        -solrCoreDir ($pathData.SolrCoreBase -f $solrVersion) 

    pushd $webdir 
    try {
		Disable-CustomErrors

		if(($product -eq 'community' -and $version -gt 5.6) -or ($product -eq 'enterprise' -and $version -gt 2.6)) {
            Register-TasksInWebProcess $basePackage
        }

        if ($product -eq "enterprise") {
            Enable-WindowsAuth
        }        
    }
    finally {
    	popd
    }

    #Add site to hosts files
    Add-Content -value "127.0.0.1 $domain" -path (join-path $env:SystemRoot system32\drivers\etc\hosts)
	Write-Host "Created website at http://$domain/"
    Start-Process "http://$domain/"
}