function Install-EvolutionAddon {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$AddonPackage,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container) })]
        [string]$JobSchedulerPath,
        [string[]]$SqlScripts,
        [string[]]$Plugins,
        [ValidateNotNullOrEmpty()]
        [string]$Name = "Addon",
        [string]$SiteUrlsOverrides,
        [string]$CommunityServerOverrides,
        [string]$ControlPanelResources,
        [string]$TasksToMerge
    )

    Write-Progress "Installing $Name"

    #Load connection string info
    $connectionStrings = [xml](get-content (Join-Path $WebPath connectionstrings.config))
    $siteSqlConnectionString = $connectionStrings.connectionStrings.add |
        ? name -eq SiteSqlServer |
        select -ExpandProperty connectionString

    $connectionString = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $siteSqlConnectionString
    
    #Executing SQL Scripts
    if($SqlScripts) {
        $VerbosePreference = 'continue'
        $tempDir = join-path $env:temp ([guid]::NewGuid())
        New-item $tempDir -ItemType Directory | Out-Null

        $sqlScripts |% {
            $progressTitle = "Executing SQL Script '{0}' against database '{1}' on {2}" -f `
                $_, $connectionString.InitialCatalog, $connectionString.DataSource

            Write-Progress "Installing $Name" "Executing SQL Script: $progressTitle"

            Expand-Zip -zipPath $AddonPackage -destination $tempDir -zipDir SqlScripts -zipFile $_
            Expand-Zip -zipPath $AddonPackage -destination $tempDir -zipDir Sql -zipFile $_

            $sqlScript = join-path $tempDir $_ | resolve-path

            if(Test-Path $sqlScript) {
                Write-ProgressFromVerbose "Installing $Name" $progressTitle {
                    Invoke-Sqlcmd -serverinstance $connectionString.DataSource `
                        -Database $connectionString.InitialCatalog `
                        -InputFile $sqlScript `
                        -QueryTimeout 6000
                }
            }
            else {
                Write-Warning "Could not find script $_"
            }
        }

        Remove-Item $tempDir -Recurse -force | out-null
    }

    Write-Progress "Installing $Name" "Copying web directory"
    Expand-Zip $AddonPackage $WebPath -zipDir Web

    # Update Override Files
    @{
        'siteurls_override.config' = $SiteUrlsOverrides
        'communityserver_override.config' = $CommunityServerOverrides
    }.GetEnumerator() |% {
        $sourceFileName = $_.Value

        if($sourceFileName) {
            $destinationFileName = $_.Key
            Write-Progress "Installing $Name" "Updating $destinationFileName"

            $source= Join-Path $WebPath $sourceFileName | Resolve-Path
            $destination = Join-Path $WebPath $destinationFileName

            if (!(Test-Path $destination)) {
                "<Overrides/>" | out-file $destination
            }

            Add-XmlToFile $source $destination
            Remove-Item $source
        }
    }

    #Update resources
    if($ControlPanelResources) {
        $source= Join-Path (Join-Path $WebPath Languages\en-US) $ControlPanelResources | Resolve-Path
        $destination= Join-Path $WebPath Languages\en-US\ControlPanelResources.xml | Resolve-Path

        Add-XmlToFile $source $destination
        Remove-Item $source
    }

    if($JobSchedulerPath) {
        
        Write-Progress "Installing $Name" "Copying Tasks directory"
        Expand-Zip $AddonPackage $JobSchedulerPath -zipDir Tasks

        Write-Progress "Installing $Name" "Updating tasks.config"
        #TODO: Update tasks.config

        Write-Progress "Installing $Name" "Syncing JS from Web"
        Update-JobSchedulerFromWeb $WebPath $JobSchedulerPath
    }
    

    Write-Progress "Installing $Name" "Enabling Plugins"

    $plugins | % {
        Write-Progress "Installing $Name" "Enabling Plugins" -CurrentOperation $_ 
        Invoke-Sqlcmd -serverinstance $connectionString.DataSource `
            -Database $connectionString.InitialCatalog `
            -query @"
            DELETE FROM [dbo].[te_Plugins] WHERE [Type] = '$_';
            INSERT INTO [dbo].[te_Plugins] VALUES ('$_');
"@
    }
    #Enable Plugin
}


function Add-XmlToFile {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SourcePath,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$DestinationPath
    )

    $source = [xml](gc $SourcePath)
    $destination = [xml](gc $DestinationPath)

    if($source.DocumentElement.Name -ne $destination.DocumentElement.Name) {
        throw "Source and Destination documents have different root elements"
    }
    
    $source.DocumentElement.ChildNodes |% {
        $destination.DocumentElement.AppendChild($destination.ImportNode($_, $true)) | out-null
    }

    $destination.Save($($DestinationPath | Resolve-Path))
}


function Install-EvolutionIdeation
{
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container)})]
        [string]$JobSchedulerPath
    )

   Install-EvolutionAddon `
        -AddonPackage $Package `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath `
        -SqlScripts 'TelligentEvolutionExtensionsIdeation-1.0.102.33348.sql' `
        -SiteUrlsOverrides SiteUrls_override.config.Ideas `
        -ControlPanelResources ControlPanelResources.xml.Ideas `
        -Plugins 'Telligent.Evolution.Extensions.Ideation.Plugins.IdeasApplication, Telligent.Evolution.Extensions.Ideation' `
            ,'Telligent.Evolution.Extensions.Ideation.Plugins.IdeaActivityStoryType, Telligent.Evolution.Extensions.Ideation' `
            ,'Telligent.Evolution.Extensions.Ideation.Plugins.IdeasApplicationActivityStoryType, Telligent.Evolution.Extensions.Ideation' `
        -Name Ideation
}

function Install-EvolutionChat {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container)})]
        [string]$JobSchedulerPath
    )

    Install-EvolutionAddon `
        -AddonPackage $Package `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath `
        -Plugins 'Telligent.Evolution.Chat.Plugins.ChatHost, Telligent.Evolution.Chat' `
        -Name Chat

    #TODO: Add Widgets
}


function Install-EvolutionVideoTranscoding
{
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container)})]
        [string]$JobSchedulerPath
    )

    Install-EvolutionAddon `
        -AddonPackage $Package `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath `
        -Plugins 'Telligent.Evolution.VideoTranscoding.VideoTranscoderPlugin, Telligent.Evolution.VideoTranscoding' `
        -Name Transcoding

    #TODO: ???Can't currently install due to SQL permissions???
    #TODO: Add task
    #<job schedule="0 */2 * * * ? *"
    #     type="Telligent.Evolution.FlexPaperDocumentViewer.DocumentConversionJob, Telligent.Evolution.FlexPaperDocumentViewer"
    #     />
}

function Install-EvolutionDocumentPreview
{
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container)})]
        [string]$JobSchedulerPath
    )

    Install-EvolutionAddon `
        -AddonPackage $Package `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath `
        -SqlScripts TelligentDocumentViewer-1.1.50.29573.sql `
        -Plugins 'Telligent.Evolution.FlexPaperDocumentViewer.DocumentViewerConfiguration, Telligent.Evolution.FlexPaperDocumentViewer' `
        -Name DocPreview

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}

function Install-EvolutionCalendar {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Container})]
        [string]$WebPath,
        [parameter(Mandatory=$true)]
		[ValidateScript({(!$_) -or (Test-Path $_ -PathType Container)})]
        [string]$JobSchedulerPath
    )

    Install-EvolutionAddon `
        -AddonPackage $Package `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath `
        -SQLScripts TelligentEventCalendar-3.0.72.32639.sql `
        -SiteUrlsOverrides SiteUrls_override.config.sample `
        -ControlPanelResources ControlPanelResources.xml.sample `
        -Plugins 'Telligent.Evolution.Extensions.Calendar.ScriptedWidgets.Plugin, Telligent.Evolution.Extensions.Calendar' `
        -Name Calendar

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}