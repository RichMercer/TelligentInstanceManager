Set-StrictMode -Version 2

function Add-SolrCore {
    <#
    .SYNOPSIS
        Creates a new Solr Core for a Telligent Evolution Community
    .PARAMETER Name
        The name of the Solr Core to create
    .PARAMETER Package
        The Telligent Evolution installation package to use to create the core
    .PARAMETER CoreBaseDir
        The path to the root of the Solr instance hosting the core
    .PARAMETER CoreAdmin
        The url to the solr instance's Core Admin API.
    #>
    [CmdletBinding(DefaultParameterSetName='Legacy')]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$CoreBaseDir,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$CoreAdmin,
        [Parameter(ParameterSetName='Legacy')]
        [Switch]$LegacyCore,
        [Parameter(ParameterSetName='Modern')]
        [Switch]$ModernCore
    )   
    $instanceDir = "${name}\$(get-date -f yyy-MM-dd)\"
    $coreDir = join-path $coreBaseDir $instanceDir
    new-item $coreDir -type directory | out-null
        
    Write-Progress "Solr Core" "Creating Core"
    
    $coreZipDir = if ($PSCmdlet.ParameterSetName -eq 'Legacy') { 'search\solr\' } else { 'search\solr\content\' } 
    Expand-Zip $package $coreDir -ZipDirectory $coreZipDir
    
    if ($PSCmdlet.ParameterSetName -eq 'Modern') {
        #Remove existing core.properties to allow us to create the core
        Join-Path $coreDir core.properties | Remove-Item
    }

    Write-Progress "Solr Core" "Registering Core"
	$url = "${coreAdmin}?action=CREATE&name=${name}&instanceDir=${instanceDir}"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
}


function Remove-SolrCore {
    <#
    .SYNOPSIS
        Removes a Solr Core
    .PARAMETER Name
        The name of the Solr Core to remove
    .PARAMETER CoreBaseDir
        The path to the root of the Solr instance hosting the core
    .PARAMETER CoreAdmin
        The url to the solr instance's Core Admin API.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$CoreBaseDir,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$CoreAdmin
    )

    $url = "${CoreAdmin}?action=UNLOAD&core=$Name&deleteindex=true"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
    
    $coreDir = Join-Path $CoreBaseDir $Name
    if(Test-Path $coreDir) {
        Remove-Item $coreDir -Recurse -Force
    }
}
