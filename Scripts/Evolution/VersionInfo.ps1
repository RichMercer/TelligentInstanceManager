$versionDllNames = [ordered]@{
    Platform = 'Telligent.Evolution.Components.dll', 'CommunityServer.Components.dll'
    Calendar = 'Telligent.Evolution.Extensions.Calendar.dll'
    Chat = 'Telligent.Evolution.Chat.dll'
    DocPreview = 'Telligent.Evolution.FlexPaperDocumentViewer.dll'
    Ideation = 'Telligent.Evolution.Extensions.Ideation.dll'
    Transcoding = 'Telligent.Evolution.VideoTranscoding.dll'
}

function Get-Community {
    <#
    .SYNOPSIS
        Gets an summary of a Telligent Evolution community
    .Descriptions
        Gets information about a Telligent Evolution community including Filestorage, Solr and database locations as well as platform and addon version numbers.
    .PARAMETER path
        The path to the community's Website or Job Scheduler.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({ Test-CommunityPath $_ })]
        [alias('physicalPath')]
        [string]$path
    )
    process {
        $csConfig = Merge-EvolutionConfigurationFile $path communityserver -ErrorAction SilentlyContinue

        $product = @($versionDllNames.platform) |
            % { $_, (join-path bin $_) } |
            % { join-path $path $_ } |
            Get-Item -ErrorAction SilentlyContinue |
            Select -ExpandProperty VersionInfo -First 1 |
            Select -ExpandProperty ProductName -ErrorAction SilentlyContinue

        $product = if($product -match 'community') { 'Community' } elseif ($product -match 'enterprise') { 'Enterprise' } else { 'Unknown' }

        $dbInfo = Get-ConnectionString $path -ErrorAction SilentlyContinue

        $info = [ordered]@{
            Name = split-path $path -Leaf
            Path = $path
            CfsPath = @($csConfig.CommunityServer.CentralizedFileStorage.fileStore) + @($csConfig.CommunityServer.CentralizedFileStorage.fileStoreGroup) | select -ExpandProperty basePath -unique
            SolrUrl = $csConfig.CommunityServer.Search.Solr.host
            DatabaseServer = $dbInfo.ServerInstance
            DatabaseName = $dbInfo.Database
            Product = $product
        }
        $versionDllNames.GetEnumerator() |% {
            $info["$($_.Key)Version"] = Get-EvolutionVersionFromDlls $path $_.Value
        }

        new-object psobject -Property $info
    }
}

function Get-EvolutionVersionFromDlls {
    <#
    .SYNOPSIS
        Gets version information from Telligent Evolution dlls
    .DESCRIPTION
        Helper function for getting the version of a Telligent extension.  It looks for the version number of the speciifed dll in both the root directoy and the /bin/ directory (to support both Web and Job Schedulers)        .
    .PARAMETER path
        The path to the community's Website or Job Scheduler.
    .PARAMETER dlls
        The dll names to look for version information in
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ })]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [ValidateScript({Test-Path $_ -PathType Leaf -IsValid})]
        [ValidateNotNullOrEmpty()]
        [parameter(Mandatory=$true)]
        [string[]]$Dlls
    )
    $version = @($Dlls) |
        % { $_, (Join-Path bin $_) } |
        % { Join-Path $Path $_ } |
        Get-Item -ErrorAction SilentlyContinue |
        Select -ExpandProperty VersionInfo -First 1 |
        Select -ExpandProperty ProductVersion -ErrorAction SilentlyContinue

        return [Version]$version
}

function Merge-EvolutionConfigurationFile {
    <#
    .SYNOPSIS
        Gets the resultant configuration XML after merging a Telligent override configuration file with the original config file
    .PARAMETER Ppath
        The path to the community's Website or Job Scheduler.
    .PARAMETER FileName
        The name of the config file to merge
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('communityserver', 'siteurls')]
        [string]$FileName
    )
    $config = [xml](Get-Content (Join-Path $Path "${Filename}.config"))

    $overridePath = Join-Path $Path "${Filename}_override.config"
    if (Test-Path $overridePath  -PathType Leaf){
        $overrides = [xml](Get-Content $overridePath)

        $overrides.Overrides.Override |% {
            $node = $config.SelectSingleNode($_.xPath)
            if (!$node) {
                Write-Error ("Cannot select node " + $_.xPath)
            }
            else {
                $override = $_
                switch($override.mode) {
                    remove {
                        $attName = $node.Attributes.GetNamedItem($override.name)
                        if ($attrName) {
                            if(!$node.Attributes.GetNamedItem($attName)) {                                
                                Write-Error ("Attribute {0} does not exist at {1}" -f $attName, $override.xpath)
                            }
                            else {
                                $node.Attributes.Remove($override.name)
                            }
                        }
                        else {
                            $node.CreateNavigator().DeleteSelf();
                        }
                    }
                    update {
                        $node.InnerXml = $override.InnerXml
                    }
                    add {
                        $where = $override.where
                        if (!$where) {
                            $where = "start"
                        }
                        switch($override.where){
                            after {
                                $node.CreateNavigator().InsertAfter($override.InnerXml)
                            }
                            before {
                                $node.CreateNavigator().InsertBefore($override.InnerXml)
                            }
                            start {
                                $node.CreateNavigator().PrependChild($override.InnerXml)
                            }
                            default {
                                $node.CreateNavigator().AppendChild($override.InnerXml)
                            }
                        }
                    }
                    change {
                        $attribute = $node.Attributes.GetNamedItem($override.name)
                        if(!$attribute){
                            Write-Error ("Attribute '{0}' not defined at {1}" -f $override.name, $override.xPath )
                        }
                        else {
                            $attribute.Value = $override.value
                        }
                    }
                    new {
                        if(!$override.name) {
                            Write-Error ("New attribute name not defined for " + $override.xpath)
                        }
                        else {
                            $node.CreateNavigator().CreateAttribute($null, $override.name, $null, $override.value)
                        }
                    }
                    default {
                        Write-Error ("Invalid mode attribute" -f $_)
                    }
            
                }
            }
        }
    }
    return $config
}