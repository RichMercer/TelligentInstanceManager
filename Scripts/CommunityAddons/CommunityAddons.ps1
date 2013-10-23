function Install-CommunityAddon {
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$AddonPackage,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath,
        [string[]]$SqlScripts,
        [string[]]$Plugins,
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'Addon',
        [string]$SiteUrlsOverrides,
        [string]$CommunityServerOverrides,
        [string]$ControlPanelResources,
        [string]$TasksToMerge
    )

    Write-Progress "Installing $Name"

    $info = Get-CommunityInfo $WebsitePath
    
    #Executing SQL Scripts
    if($SqlScripts) {
        $VerbosePreference = 'continue'
        $tempDir = join-path $env:temp ([guid]::NewGuid())
        New-item $tempDir -ItemType Directory | Out-Null

        $sqlScripts |% {
            $progressTitle = "Executing SQL Script '{0}' against database '{1}' on {2}" -f `
                $_, $info.DatabaseServer, $info.DatabaseName

            Write-Progress "Installing $Name" "Executing SQL Script: $progressTitle"

            Expand-Zip -Path $AddonPackage -destination $tempDir -ZipDirectory SqlScripts -zipFile $_
            Expand-Zip -Path $AddonPackage -destination $tempDir -ZipDirectory Sql -zipFile $_

            $sqlScript = join-path $tempDir $_ | resolve-path

            if(Test-Path $sqlScript) {
                Write-ProgressFromVerbose "Installing $Name" $progressTitle {
                    Invoke-Sqlcmd -ServerInstance $info.DatabaseServer `
                        -Database $info.DatabaseName `
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

    Write-Progress "Installing $Name" 'Copying web directory'
    Expand-Zip $AddonPackage $WebsitePath -ZipDirectory Web

    # Update Override Files
    @{
        'siteurls_override.config' = $SiteUrlsOverrides
        'communityserver_override.config' = $CommunityServerOverrides
    }.GetEnumerator() |% {
        $sourceFileName = $_.Value

        if($sourceFileName) {
            $destinationFileName = $_.Key
            Write-Progress "Installing $Name" "Updating $destinationFileName"

            $source= Join-Path $WebsitePath $sourceFileName | Resolve-Path
            $destination = Join-Path $WebsitePath $destinationFileName

            if (!(Test-Path $destination)) {
                '<Overrides/>' | out-file $destination
            }

            Add-XmlToFile $source $destination
            Remove-Item $source
        }
    }

    #Update resources
    if($ControlPanelResources) {
        $source= Join-Path (Join-Path $WebsitePath Languages\en-US) $ControlPanelResources | Resolve-Path
        $destination= Join-Path $WebsitePath Languages\en-US\ControlPanelResources.xml | Resolve-Path

        Add-XmlToFile $source $destination
        Remove-Item $source
    }

    if($JobSchedulerPath) {
        
        Write-Progress "Installing $Name" 'Copying Tasks directory'
        Expand-Zip $AddonPackage $JobSchedulerPath -ZipDirectory Tasks

        Write-Progress "Installing $Name" 'Updating tasks.config'
        #TODO: Update tasks.config

        Write-Progress "Installing $Name" 'Syncing JS from Web'
        Update-JobSchedulerFromWeb $WebsitePath $JobSchedulerPath
    }
    

    Write-Progress "Installing $Name" "Enabling Plugins"

    $plugins | % {
        Write-Progress "Installing $Name" 'Enabling Plugins' -CurrentOperation $_ 
        Invoke-Sqlcmd -serverinstance $connectionString.DataSource `
            -Database $connectionString.InitialCatalog `
            -query @"
            DELETE FROM [dbo].[te_Plugins] WHERE [Type] = '$_';
            INSERT INTO [dbo].[te_Plugins] VALUES ('$_');
"@
    }
}


function Add-XmlToFile {
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$DestinationPath
    )

    $source = [xml](gc $SourcePath)
    $destination = [xml](gc $DestinationPath)

    if($source.DocumentElement.Name -ne $destination.DocumentElement.Name) {
        throw 'Source and Destination documents have different root elements'
    }
    
    $source.DocumentElement.ChildNodes |% {
        $destination.DocumentElement.AppendChild($destination.ImportNode($_, $true)) | out-null
    }

    $destination.Save($($DestinationPath | Resolve-Path))
}


function Install-CommunityIdeation
{
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )

   Install-CommunityAddon `
        -AddonPackage $Package `
        -WebsitePath $WebsitePath `
        -JobSchedulerPath $JobSchedulerPath `
        -SqlScripts 'TelligentEvolutionExtensionsIdeation-1.0.102.33348.sql' `
        -SiteUrlsOverrides SiteUrls_override.config.Ideas `
        -ControlPanelResources ControlPanelResources.xml.Ideas `
        -Plugins 'Telligent.Evolution.Extensions.Ideation.Plugins.IdeasApplication, Telligent.Evolution.Extensions.Ideation' `
            ,'Telligent.Evolution.Extensions.Ideation.Plugins.IdeaActivityStoryType, Telligent.Evolution.Extensions.Ideation' `
            ,'Telligent.Evolution.Extensions.Ideation.Plugins.IdeasApplicationActivityStoryType, Telligent.Evolution.Extensions.Ideation' `
        -Name Ideation
}

function Install-CommunityChat {
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )

    Install-CommunityAddon `
        -AddonPackage $Package `
        -WebsitePath $WebsitePath `
        -JobSchedulerPath $JobSchedulerPath `
        -Plugins 'Telligent.Evolution.Chat.Plugins.ChatHost, Telligent.Evolution.Chat' `
        -Name Chat

    #TODO: Add Widgets
}


function Install-CommunityVideoTranscoding
{
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )

    Install-CommunityAddon `
        -AddonPackage $Package `
        -WebsitePath $WebsitePath `
        -JobSchedulerPath $JobSchedulerPath `
        -Plugins 'Telligent.Evolution.VideoTranscoding.VideoTranscoderPlugin, Telligent.Evolution.VideoTranscoding' `
        -Name Transcoding

    #TODO: ???Can't currently install due to SQL permissions???
    #TODO: Add task
    #<job schedule="0 */2 * * * ? *"
    #     type="Telligent.Evolution.FlexPaperDocumentViewer.DocumentConversionJob, Telligent.Evolution.FlexPaperDocumentViewer"
    #     />
}

function Install-CommunityDocumentPreview
{
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )

    Install-CommunityAddon `
        -AddonPackage $Package `
        -WebsitePath $WebsitePath `
        -JobSchedulerPath $JobSchedulerPath `
        -SqlScripts TelligentDocumentViewer-1.1.50.29573.sql `
        -Plugins 'Telligent.Evolution.FlexPaperDocumentViewer.DocumentViewerConfiguration, Telligent.Evolution.FlexPaperDocumentViewer' `
        -Name DocPreview

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}

function Install-CommunityCalendar {
    param(
        [Parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$Package,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,
        [ValidateScript({ Test-CommunityPath $_ -JobScheduler -AllowEmpty})]
        [string]$JobSchedulerPath
    )

    Install-CommunityAddon `
        -AddonPackage $Package `
        -WebsitePath $WebsitePath `
        -JobSchedulerPath $JobSchedulerPath `
        -SQLScripts TelligentEventCalendar-3.0.72.32639.sql `
        -SiteUrlsOverrides SiteUrls_override.config.sample `
        -ControlPanelResources ControlPanelResources.xml.sample `
        -Plugins 'Telligent.Evolution.Extensions.Calendar.ScriptedWidgets.Plugin, Telligent.Evolution.Extensions.Calendar' `
        -Name Calendar

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}