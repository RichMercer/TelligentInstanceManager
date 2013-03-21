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
		[ValidateScript({Resolve-Path $_ })]
        [string]$coreBaseDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		#[ValidateScript({ Invoke-WebRequest $_ -UseBasicParsing -Method HEAD })]
        [Uri]$coreAdmin
    )
    $instanceDir = "${name}\$(get-date -f yyy-MM-dd)\"
    $coreDir = join-path $coreBaseDir $instanceDir
    new-item $coreDir -type directory | out-null
        
    Write-Progress "Solr Core" "Creating Core"
    Expand-Zip $package $coreDir -zipDir "search\solr"
        
    Write-Progress "Solr Core" "Registering Core"
	$url = "${coreAdmin}?action=CREATE&name=${name}&instanceDir=${instanceDir}"
    Invoke-WebRequest $url -UseBasicParsing -Method Post | out-null
}