$versionDllNames = data{@{
    platform = 'Telligent.Evolution.Components.dll', 'CommunityServer.Components.dll'
    calendar = 'Telligent.Evolution.Extensions.Calendar.dll'
    docPreview = 'Telligent.Evolution.FlexPaperDocumentViewer.dll'
    transcoding = 'Telligent.Evolution.VideoTranscoding.dll'
    ideation = 'Telligent.Evolution.Extensions.Ideation.dll'
    chat = 'Telligent.Evolution.Chat.dll'
}}

function Get-CommunityInfo {
    param(
        [ValidateNotNullOrEmpty()]
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [alias("physicalPath")]
        [string]$path
    )

    $csConfig = Get-MergedConfigFile $path 'communityserver.config' -ErrorAction SilentlyContinue

    $product = @($versionDllNames.platform) |
        % { $_, (join-path bin $_) } |
        % { join-path $path $_ } |
        Get-Item -ErrorAction SilentlyContinue |
        Select -ExpandProperty VersionInfo -First 1 |
        Select -ExpandProperty ProductName -ErrorAction SilentlyContinue

    $product = if($product -match 'community') { 'Community' } elseif ($product -match 'enterprise') { 'Enterprise' } else { '' }

    return new-object psobject -Property ([ordered]@{
        Name = split-path $path -Leaf
        Path = $path
        Product = $product
        PlatformVersion = Get-EvolutionVersionFromDlls $path $versionDllNames.platform
        CalendarVersion = Get-EvolutionVersionFromDlls $path $versionDllNames.calendar
        DocPreviewVersions = Get-EvolutionVersionFromDlls $path $versionDllNames.docPreview
        TranscodingVersion = Get-EvolutionVersionFromDlls $path $versionDllNames.transcoding
        IdeationVersion = Get-EvolutionVersionFromDlls $path $versionDllNames.ideation
        ChatVersion = Get-EvolutionVersionFromDlls $path $versionDllNames.chat
        CfsPaths = @($csConfig.CommunityServer.CentralizedFileStorage.fileStore) + @($csConfig.CommunityServer.CentralizedFileStorage.fileStoreGroup) | select -ExpandProperty basePath -unique
        SolrUrl = $csConfig.CommunityServer.Search.Solr.host
    })
}

function Get-EvolutionVersionFromDlls {
    param(
        [ValidateNotNullOrEmpty()]
        [parameter(Mandatory=$true)]
        [string]$path,
        [ValidateNotNullOrEmpty()]
        [parameter(Mandatory=$true)]
        [string[]]$dlls
    )
    return @($dlls) |
        % { $_, (join-path bin $_) } |
        % { join-path $path $_ } |
        Get-Item -ErrorAction SilentlyContinue |
        Select -ExpandProperty VersionInfo -First 1 |
        Select -ExpandProperty ProductVersion -ErrorAction SilentlyContinue
}

function Get-MergedConfigFile {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$path,
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$fileName
    )
    if($fileName.EndsWith(".config")){
        $fileName = $fileName.Substring(0, $fileName.length - 7)
    }
    $config = [xml](get-content (join-path $path "${filename}.config"))

    $overridePath = join-path $path "${filename}_override.config"
    if (test-path $overridePath  -PathType Leaf){
        $overrides = [xml](get-content $overridePath)

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