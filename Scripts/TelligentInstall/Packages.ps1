Set-StrictMode -Version 2

$versionRegex = [regex]'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'

function Get-TelligentVersion {
    <#
    .SYNOPSIS
	    Gets a list of Teligent Evolution builds in the Mass Install directory.
    .PARAMETER Version
	    Filters to the most recent build whose version matches the given pattern
    .EXAMPLE
        Get-TelligentVersion
        
        Gets a list of all available builds of Telligent Community.
    .EXAMPLE
        Get-TelligentVersion 7.6
        
        Gets the most recent build with major version 7 and minor version 6.
    #>
    [CmdletBinding(DefaultParameterSetName='All')]
    param(
        [parameter(Position=0)]
        [string]$Version
    )
	
	$base = $env:TelligentInstanceManager
	if (!$base) {
		throw 'TelligentInstanceManager environmental variable not defined' 
	}
	$basePackageDir = Join-Path $base TelligentPackages
	
    $basePackages = Get-VersionedEvolutionPackage $basePackageDir
    $fullBuilds = $basePackages |
        % { 
            new-object psobject -Property ([ordered]@{
                Version = $_.Version
                BasePackage = $_.Path
            })
        }
    # Commenting out hotfixes for now as theses mostly affect v7. Will circle back and fix later.
    #$hotfixBuilds = Get-VersionedEvolutionPackage $hotfixDir|
    #    % {
    #        $hotfix = $_
    #        $base = $basePackages |
    #            ? { $_.Version.Major -eq $hotfix.Version.Major -and $_.Version.Minor -eq $hotfix.Version.Minor -and $hotfix.Version.Revision -gt $_.Version.Revision }|
    #            sort Version -Descending |
    #            select -First 1
    #        if ($base) 
    #        {
    #            new-object PSObject -Property ([ordered]@{
    #                Version = $_.Version
    #                BasePackage = $base.Path
    #                HotfixPackage = $_.Path
    #            })
    #        }
    #    }  
	
	$results = @($fullBuilds) # + @($hotfixBuilds)

    $results = $results | sort Version
		
	if($Version){
        $versionPattern = "$($Version.TrimEnd('*'))*"
		$results = $results |
            ? {$_.Version.ToString() -like $versionPattern } |
            select -Last 1
	}
    $results

}

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
            $match = $versionRegex.Match($_.Name)

            if ($match.Value) {                
                New-Object PSObject -Property (@{
                    Version = [version]$match.Value
                    Path = $_.FullName
                })
            }
        }

}

