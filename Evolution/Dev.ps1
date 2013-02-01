$base = "w:\"

$pathData = @{
    # The Directory where full installation packages can be found
	PackagesPath = Join-Path $base Packages

    # The Directory where differential hotfix packages can be found
	HotfixesPath = Join-Path $base Hotfixes

    # The directory where licences can be found.
    # Licences in this directory should be named in the format "{Product}{MajorVersion}.xml"
    # i.e. Community7.xml for a Community 7.x licence
	LicencesPath = Join-Path $base Licences

    # The directory where web folders are created for each website
	WebBase = Join-Path $base Web

    #Solr Url for solr cores.
    #{0} gets replaced with 1-4 or 3-6 depending on the solr version needed
	SolrUrl = 'http://localhost:8080/{0}'

    # Solr core Directories.
    # {0} gets replaced in the same way as for SolrUrl
	SolrCoreBase = Join-Path $base 'Solr\{0}\Cores\'
}
$versionRegex = [regex]"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"

function Install-DevEvolution {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $name,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
 		[ValidateSet('Community','Enterprise')]
 		[string] $product,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
		[ValidateNotNullOrEmpty()]
        [version] $version      
    )

    #$ErrorActionPreference = "Stop"
	$buildInfo = Get-EvolutionBuild | ? {$_.Product -ieq $product -and $_.Version -eq $version }
	
	if (!$buildInfo){
		throw "Invalid Build specified"
	}
    
	$solrVersion = if(@(2,3,5,6) -contains $version.Major){ "1-4" } else {"3-6" }

	$coreName = $name.ToLower()
	$solrUrl = ($pathData.SolrUrl -f $solrVersion).TrimEnd("/")
    Add-SolrCore $coreName `
		-package $buildInfo.BasePackage `
		-coreBaseDir ($pathData.SolrCoreBase -f $solrVersion) `
		-coreAdmin "$solrUrl/admin/cores"
	$solrUrl += "/$coreName/"

	$licenceFile = join-path $pathData.LicencesPath "${product}$($version.Major).xml"
    $licenceData = @{}
    if (test-path $licenceFile) {
        $licenceData.LicenceFile = $licenceFile;
    }

    $webDir = Join-Path $pathData.WebBase $name

	Install-Evolution -name $name `
		-package $buildInfo.BasePackage `
		-hotfixPackage $buildInfo.HotfixPackage `
		-webDir $webDir `
		-searchUrl $solrUrl  `
		-appPool $name `
        -netVersion (if (@(2,5) -contains $version.Major) { 2.0 } else { 4.0 }) `
        @licenceData

    pushd $webdir 
    try {
		Disable-CustomErrors

		if(($product -eq 'community' -and $version -gt 5.6) -or ($product -eq 'enterprise' -and $version -gt 2.6)) {
            Register-TasksInWebProcess $buildInfo.BasePackage
        }

        if ($product -eq "enterprise") {
            Enable-WindowsAuth
        }        
    }
    finally {
    	popd
    }
	Write-Host "Created website at http://${webDomain}/"
}

function Get-EvolutionBuild {
    param(
        [string]$versionPattern
    )

    function Get-VersionedEvolutionPackages {
    param(
        [string]$path
    )

    Get-ChildItem $path  *.zip|
        %{
            if ($_.Name -match "community") {
                $product = "Community"
            }elseif ($_.Name -match "enterprise") {
                $product ="Enterprise"
            } else {
                #$product doesn't get reset on each iteration, so reset it to null for an invalid package
                $product = $null
            }
            $match = $versionRegex.Match($_.Name)

            if ($product -and $match.Value) {                
                New-Object PSObject -Property (@{
                    Product = $product
                    Version = [version]$match.Value
                    Path = $_.FullName
                })
            }
        }

    }

    $basePackages = Get-VersionedEvolutionPackages $pathData.PackagesPath
    $fullBuilds = $basePackages |
        select Product,Version,@{Expression={$_.Path};Label="BasePackage"},@{Expression={$null};Label="HotfixPackage"}

    $hotfixBuilds = Get-VersionedEvolutionPackages $pathData.HotfixesPath|
        % {
            $hotfix = $_
            $base = $basePackages |
                ? { $_.Version.Major -eq $hotfix.Version.Major -and $_.Version.Minor -eq $hotfix.Version.Minor }|
                sort Version -Descending |
                select -First 1

            if ($base) 
            {
                $_ |select Product,Version,@{Expression={$base.Path};Label="BasePackage"},@{Expression={$_.Path};Label="HotfixPackage"}
            }
        }  
		
	$results = $fullBuilds + $hotfixBuilds |
        sort version
		
	if($versionPattern){
		$results = $results |
            ? version -match "^$versionPattern"

        if($true) {
            $results = $results | select -Last 1
        }
	}
    $results

}