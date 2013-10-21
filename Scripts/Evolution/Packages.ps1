$base = $env:EvolutionMassInstall
if (!$base) {
    Write-Error 'EvolutionMassInstall environmental variable not defined'
}

# The Directory where full installation packages can be found
$basePackageDir = Join-Path $base FullPackages

# The Directory where differential hotfix packages can be found
$hotfixDir = Join-Path $base Hotfixes

$versionRegex = [regex]'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'

function Get-EvolutionBuild {
    <#
    .SYNOPSIS
	    Gets a list of Teligent Evolution builds in the Mass Install directory.
    .PARAMETER Version
	    Filters to the most recent build whose version matches the given pattern
    .PARAMETER Community
	    If specified, filters the build list to just those of Telligent Community
    .PARAMETER Enterprise
	    If specified, filters the build list to just those of Telligent Enterprise
    .EXAMPLE
        Get-EvolutionBuild
        
        Gets a list of all available builds
    .EXAMPLE
        Get-EvolutionBuild 7.6
        
        Gets the most recent build with major version 7 and minor version 6.
    .EXAMPLE
        Get-EvolutionBuild -Community
        
        List all builds of Telligent Community.
    .EXAMPLE
        Get-EvolutionBuild -Enterprise
        
        List all builds of Telligent Enterprise.
    .EXAMPLE
        Get-EvolutionBuild 4 -Enterprise
        
        List the most recent build of Telligent Enterprise version 4.
    #>
    [CmdletBinding(DefaultParameterSetName='All')]
    param(
        [parameter(Position=0)]
        [string]$Version,
        [parameter(ParameterSetName='Community', Mandatory=$true)]
        [switch]$Community,
        [parameter(ParameterSetName='Enterprise', Mandatory=$true)]
        [switch]$Enterprise
    )
    $basePackages = Get-VersionedEvolutionPackage $basePackageDir
    $fullBuilds = $basePackages |
        % { 
            new-object PSObject -Property ([ordered]@{
                Product = $_.Product
                Version = $_.Version
                BasePackage = $_.Path
            })
        }

    $hotfixBuilds = Get-VersionedEvolutionPackage $hotfixDir|
        % {
            $hotfix = $_
            $base = $basePackages |
                ? { $_.Version.Major -eq $hotfix.Version.Major -and $_.Version.Minor -eq $hotfix.Version.Minor -and $hotfix.Version.Revision -gt $_.Version.Revision }|
                sort Version -Descending |
                select -First 1

            if ($base) 
            {
                new-object PSObject -Property ([ordered]@{
                    Product = $_.Product
                    Version = $_.Version
                    BasePackage = $base.Path
                    HotfixPackage = $_.Path
                })
            }
        }  
	
	$results = @($fullBuilds) + @($hotfixBuilds)

    if($Community) {
        $results = $results |? Product -eq 'Community'
    }	
    elseif($Enterprise) {
        $results = $results |? Product -eq 'Enterprise'
    }

    $results = $results | sort Version
		
	if($Version){
        $versionPattern = "$($Version.TrimEnd('*'))*"
		$results = $results |
            ? {$_.Version.ToString() -like $versionPattern } |
            select -Last 1
	}
    $results

}
Set-Alias geb Get-EvolutionBuild

function Get-VersionedEvolutionPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$Path
    )

    Get-ChildItem $Path  *.zip|
        %{
            #$product doesn't get reset on each iteration, so reset it manually to avoid issues
            $product = $null
            if ($_.Name -match 'community') {
                $product = 'Community'
            }elseif ($_.Name -match 'enterprise') {
                $product = 'Enterprise'
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