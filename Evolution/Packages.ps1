$base = $env:EvolutionPackageLocation
if (!$base) {
    Write-Warning "EvolutionPackageLocation environmental variable not specified. Defaulting to $PSScriptRoot"
    $base = $PSScriptRoot
}

# The Directory where full installation packages can be found
$basePackageDir = Join-Path $base Full

# The Directory where differential hotfix packages can be found
$hotfixDir = Join-Path $base Diff

$versionRegex = [regex]"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
function Get-EvolutionBuild {
    param(
        [string]$versionPattern
    )
    $basePackages = Get-VersionedEvolutionPackages $basePackageDir
    $fullBuilds = $basePackages |
        select Product,Version, `
            @{Expression={$_.Path};Label="BasePackage"},`
            @{Expression={$null};Label="HotfixPackage"}

    $hotfixBuilds = Get-VersionedEvolutionPackages $hotfixDir|
        % {
            $hotfix = $_
            $base = $basePackages |
                ? { $_.Version.Major -eq $hotfix.Version.Major -and $_.Version.Minor -eq $hotfix.Version.Minor }|
                sort Version -Descending |
                select -First 1

            if ($base) 
            {
                $_ |select Product,Version,`
                @{Expression={$base.Path};Label="BasePackage"},`
                @{Expression={$_.Path};Label="HotfixPackage"}
            }
        }  
		
	$results = @($fullBuilds) + $hotfixBuilds |
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

function Get-VersionedEvolutionPackages {
param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$path
)

Get-ChildItem $path  *.zip|
    %{
        #$product doesn't get reset on each iteration, so reset it manually to avoid issues
        $product = $null
        if ($_.Name -match "community") {
            $product = "Community"
        }elseif ($_.Name -match "enterprise") {
            $product ="Enterprise"
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
