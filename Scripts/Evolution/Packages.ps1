$base = $env:EvolutionMassInstall
if (!$base) {
    Write-Error 'EvolutionMassInstall environmental variable not defined'
}

# The Directory where full installation packages can be found
$basePackageDir = Join-Path $base FullPackages

# The Directory where differential hotfix packages can be found
$hotfixDir = Join-Path $base Hotfixes

$versionRegex = [regex]"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"

<#
.Synopsis
	Gets a list of Teligent Evolution builds in the Mass Install directory.
.Description
	The Install-Evolution cmdlet automates the process of creating a new Telligent Evolution community.
		
	It takes the installation package, and from it deploys the website to IIS and a creates a new database using
	the scripts from the package.  It also sets permissions automatically.
		
	This scripts install the new community as follows (where NAME is the value of the name paramater)

		
    If a Telligent Enterprise instance is being installed, Windows Authentication will be enabled automatically
.Parameter Version
	Filters to the most recent build whose version matches the given pattern
.Example
    Get-EvolutionBuild
        
    Gets a list of all available builds
.Example
    Get-EvolutionBuild 7.6
        
    Gets the most recent build with major version 7 and minor version 6.
#>
function Get-EvolutionBuild {
    param(
        [string]$Version
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
		
	if($Version){
        #escape dots for regex match
        $regexMatch = '^' + $Version.Replace('.', '\.')
		$results = $results |? version -match $regexMatch

        if($true) {
            $results = $results | select -Last 1
        }
	}
    $results

}
Set-Alias geb Get-EvolutionBuild

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