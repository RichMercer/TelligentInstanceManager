function Add-SolrCore {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$coreBaseDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$coreAdmin
    )
    $instanceDir = "${name}\$(get-date -f yyy-MM-dd)\"
    $coreDir = join-path $coreBaseDir $instanceDir
    new-item $coreDir -type directory | out-null
        
    Write-Progress "Solr Core" "Creating Core"
    Expand-Zip $package $coreDir -zipDir "search\solr"
        
    Write-Progress "Solr Core" "Registering Core"
	$url = "${coreAdmin}?action=CREATE&name=${name}&instanceDir=${instanceDir}"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
}

function Remove-SolrCore {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$coreBaseDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$coreAdmin
    )

    Write-Progress "Solr Core" "Removing Core"
    try {
        $url = "${coreAdmin}?action=UNLOAD&core=$name&deleteindex=true"
        Invoke-WebRequest $url -UseBasicParsing -Method Post | Out-Null
    } catch {}
    
    $coreDir = Join-Path $coreBaseDir $name
    if(Test-Path $coreDir) {
        Remove-Item $coreDir -Recurse -Force
    }
}
