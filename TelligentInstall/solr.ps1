Set-StrictMode -Version 2

function Add-LegacySolrCore {
    <#
    .SYNOPSIS
        Creates a new Solr Core for a Telligent Community
    .PARAMETER Name
        The name of the Solr Core to create
    .PARAMETER Package
        The Telligent Community installation package to use to create the core
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
        [Uri]$CoreAdmin
    )   
    $instanceDir = "${name}\$(get-date -f yyy-MM-dd)\"
    $coreDir = join-path $coreBaseDir $instanceDir
    new-item $coreDir -type directory | out-null
        
    Write-Progress "Solr Core" "Creating Core"
    
    Expand-Zip $package $coreDir -ZipDirectory "search\solr\content\"
    
    Join-Path $coreDir core.properties | Remove-Item

    Write-Progress "Solr Core" "Registering Core"
	$url = "${coreAdmin}?action=CREATE&name=${name}&instanceDir=${instanceDir}"

    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
}

function Add-SolrCore {
    <#
    .SYNOPSIS
        Creates a new Solr Core for a Telligent Community
    .PARAMETER Name
        The name of the Solr Core to create
    .PARAMETER Package
        The Telligent Community installation package to use to create the core
    .PARAMETER CoreBaseDir
        The path to the root of the Solr instance hosting the core
    .PARAMETER CoreAdmin
        The url to the solr instance's Core Admin API.
    .PARAMETER LegacyCore
        Creates a core for Telligent Community 7.6 and below
    #>
    [CmdletBinding(DefaultParameterSetName='Legacy')]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		##[ValidateScript({Test-Zip $_ })]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$CoreBaseDir,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$CoreAdmin
    )   
        
    Write-Progress "Solr Core" "Registering Content Core"
    # TODO: Test for telligent-content-cb15392 or the correct config set for the current version
	$url = "${coreAdmin}?action=CREATE&configSet=telligent-content-cb15392&name=${Name}-content"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null

    $url = "${coreAdmin}?action=CREATE&configSet=telligent-conversations-de63a3d&name=${Name}-conversations"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
}


function Remove-LegacySolrCore {
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
        [Uri]$CoreAdmin
    )

    $url = "${CoreAdmin}?action=UNLOAD&core=${Name}-content&deleteindex=true"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null

    $url = "${CoreAdmin}?action=UNLOAD&core=${Name}-conversations&deleteindex=true"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
    
}


