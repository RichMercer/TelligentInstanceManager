
function New-SolrInstance {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$solrDir,
        [string]$solrLocalDir = $solrDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$tomcatContextDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$solrWebPath
    )
    "Extracting Solr: $solrDir"
    Expand-Zip -zipPath $package -destination $solrDir -zipDir "Search"

    "Configuring Tomcat"
    $solrWar = join-path $solrLocalDir solr.war
    $solrHome = join-path $solrLocalDir "solr"
    $contextName = $solrWebPath.Replace('\', '#') + ".xml"
    @"
        <Context docBase="$solrWar" debug="0" crossContext="true" >
           <Environment name="solr/home" type="java.lang.String" value="$solrHome" override="true" />
        </Context>
"@     | out-file (join-path $tomcatContextDir $contextName)
}

function Install-Solr {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$solrDir,
        [string]$solrLocalDir = $solrDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$tomcatContextDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$solrWebPath,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$communityDir,
        [string]$domain = "localhost",
        [int]$port = 8080
    )
    
    New-SolrInstance -package $package -solrDir $solrDir -solrLocalDir $solrLocalDir -tomcatContextDir $tomcatContextDir -solrWebPath $solrWebPath
    
    AddChangeAttributeOverride -webDir $communityDir -xpath /CommunityServer/Search/Solr -name host -value "http://${domain}:$port/$webPath/"

}

function Add-SolrCore {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$coreBaseDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Uri]$coreAdmin
    )
    begin{
        $webClient = new-object System.Net.WebClient
    }
    process {
        $date = get-date -f yyy-MM-dd
        $instanceDir = "${name}\$date\"
        $coreDir = join-path $coreBaseDir $instanceDir
        new-item $coreDir -type directory | out-null
        
        Write-Progress "Solr Core" "Creating Core"
        Expand-Zip $package $coreDir -zipDir "search\solr"
        
        Write-Progress "Solr Core" "Registering Core"
		$url = "${coreAdmin}?action=CREATE&name=${name}&instanceDir=${instanceDir}"
        $webClient.DownloadString($url) | out-null
    }    
}