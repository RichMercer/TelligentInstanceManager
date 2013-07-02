function Install-EvolutionAddon {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Test-Zip $_})]
        [string]$AddonPackage,
        [parameter(Mandatory=$true)]
		[ValidateScript({Resolve-Path $_})]
        [string]$WebPath,
		[ValidateScript({(!$_) -or (Resolve-Path $_) })]
        [string]$JSDir,
        [string[]]$SqlScripts,
        [string[]]$PluginsToEnable,
        [ValidateNotNullOrEmpty()]
        [string]$Name = "Addon",
        [string]$SiteUrlsOverrides,
        [string]$CommunityServerOverrides,
        [string]$ControlPanelResources,
        [string]$TasksToMerge
    )
    Write-Progress "Installing $Name"
    
    #Executing SQL Scripts
    if($SqlScripts) {
        $connectionStrings = [xml](get-content (Join-Path $WebPath connectionstrings.config))
        $siteSqlConnectionString = $connectionStrings.connectionStrings.add |
            ? name -eq SiteSqlServer |
            select -ExpandProperty connectionString

        $connectionString = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $siteSqlConnectionString

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
                Invoke-Sqlcmd -serverinstance $connectionString.DataSource `
                    -Database $connectionString.InitialCatalog `
                    -InputFile $sqlScript `
                    -QueryTimeout 6000  4>&1 |
                    ? { $_ -is 'System.Management.Automation.VerboseRecord'}  |
                    % { Write-Progress "Installing $Name" $progressTitle -CurrentOperation $_.Message }
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

    if($JSDir) {
        
        Write-Progress "Installing $Name" "Copying Tasks directory"
        Expand-Zip $AddonPackage $WebPath -zipDir Tasks

        Write-Progress "Installing $Name" "Updating tasks.config"
        #TODO: Update tasks.config

        Write-Progress "Installing $Name" "Syncing JS from Web"
        Update-JobSchedulerFromWeb $WebPath $JSDir
    }
    

    Write-Progress "Installing $Name" "Enabling Plugin"
    #Enable Plugin
}


function Add-XmlToFile {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Resolve-Path $_})]
        [string]$SourcePath,
        [parameter(Mandatory=$true)]
		[ValidateScript({Resolve-Path $_})]
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
   Install-EvolutionAddon `
        'C:\Users\Alex.OLYMPUS\Downloads\TelligentEvolutionExtensionsIdeation-1.0.102.33348.zip'`
        C:\sites\addonplayground\20130702 `
        -SqlScripts 'TelligentEvolutionExtensionsIdeation-1.0.102.33348.sql' `
        -SiteUrlsOverrides SiteUrls_override.config.Ideas `
        -ControlPanelResources ControlPanelResources.xml.Ideas `
        -Name Ideation

    #TODO: Enable Plugin
}

function Install-EvolutionChat {

    Install-EvolutionAddon `
        'C:\Users\Alex.OLYMPUS\Downloads\TelligentEvolutionChat-1.0.67.32476.zip' `
        C:\sites\addonplayground\20130702 `
        -Name Chat

    #TODO: Enable Plugin
    #TODO: Add Widgets
}


function Install-EvolutionVideoTranscoding
{
    Install-EvolutionAddon `
        'C:\Users\Alex.OLYMPUS\Downloads\TelligentVideoTranscoder-1.1.9.28904.zip' `
        C:\sites\addonplayground\20130702 `
        -Name Transcoding

    #TODO: ???Can't currently install due to SQL permissions???
    #TODO: Add task
    #<job schedule="0 */2 * * * ? *"
    #     type="Telligent.Evolution.FlexPaperDocumentViewer.DocumentConversionJob, Telligent.Evolution.FlexPaperDocumentViewer"
    #     />
}

function Install-EvolutionDocumentPreview
{
    Install-EvolutionAddon `
        'C:\Users\Alex.OLYMPUS\Downloads\TelligentDocumentViewer-1.1.50.29573.zip' `
        C:\sites\addonplayground\20130702 `
        -SqlScripts TelligentDocumentViewer-1.1.50.29573.sql `
        -Name DocPreview

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}

function Install-EvolutionCalendar {
    param(
        [parameter(Mandatory=$true)]
		[ValidateScript({Resolve-Path $_})]
        [string]$Package,
        [parameter(Mandatory=$true)]
		[ValidateScript({Resolve-Path $_})]
        [string]$WebPath,
		[ValidateScript({Resolve-Path $_})]
        [string]$JobSchedulerPath
    )

    Install-EvolutionAddon `
        'C:\Users\Alex.OLYMPUS\Downloads\TelligentEventCalendar-3.0.72.32639.zip' `
        -WebPath $WebPath `
        -JobSchedulerPath $JobSchedulerPath
        -SQLScripts TelligentEventCalendar-3.0.72.32639.sql `
        -SiteUrlsOverrides SiteUrls_override.config.sample `
        -ControlPanelResources ControlPanelResources.xml.sample `
        -Name Calendar

    #TODO: Add task
    # <job schedule="0 */2 * * * ? *" type="Telligent.Evolution.VideoTranscoding.TranscodingJob, Telligent.Evolution.VideoTranscoding"/>
}

Set-Content C:\sites\addonplayground\20130702\siteurls_override.config "<Overrides />"

Install-EvolutionCalendar
Install-EvolutionDocumentPreview
Install-EvolutionVideoTranscoding
Install-EvolutionChat
Install-EvolutionIdeation