Add-Type -AssemblyName System.Web
. D:\Telligent\SVN\PowershellRest\RestApiExtractor\test.ps1

function ConvertTo-HtmlEncodedString {
    param(
        [parameter(Mandatory=$True)]
        [string]$Html
    )
    [System.Web.HttpUtility]::HtmlEncode($Html)
}


function Get-CommandHelpHtml
{
    param(
        [parameter(Mandatory=$True)]
        [string]$Command
    )
    $help = get-help $Command
    $syntax = $help.syntax

    $help.Synopsis
    "<h2>Syntax</h2>"
    $syntax |% {
        $_.syntaxItem |% {
            $syntax = $_.name
            $_.parameter | %{
                $param = " -$($_.name) <$($_.parameterValue)>"
                if($_.required -eq 'false') { $param = "[$($param.Trim())]"}
                $syntax += " ```r`n    $param"
             }
            "<pre class=`"brush: ps`">" + (ConvertTo-HtmlEncodedString "$syntax ```r`n    [<CommonParameters>]") + "</pre>"         
         }
    }
    if($help.description) {
        "<h2>Detailed Description</h2>"
        ConvertTo-ParagraphedHtml $help.description.Text
    }
    "<h2>Parameters</h2>"
    $help.parameters.parameter |% {
        "<h3>-$(ConvertTo-HtmlEncodedString "$($_.name) <$($_.parameterValue)>")</h3>"
        ConvertTo-ParagraphedHtml $_.description.Text
    }

    if($help.examples) {
        "<h2>Examples</h2>"
        $help.examples.example |% {
            "<h3>$($_.title.Trim('-'))</h3>"
            "<pre>$($_.code)</pre>"
            ConvertTo-ParagraphedHtml $_.remarks.Text
        }
    }
}

function ConvertTo-ParagraphedHtml
{
    param(
        [parameter(Mandatory=$True)]
        [string]$PlainText
    )

    $PlainText -split '[\r\n]{2}' |
        % {"<p>$(ConvertTo-HtmlEncodedString $_)</p>"}
}

$cred = New-EvolutionCredential -EvolutionRoot http://newrelic2.local/ -UserName admin -ApiKey j5foa6phtiduqksekv75nj7xfbpxyv

function Export-DocsToWiki {
    param(
        [parameter(Mandatory=$True)]
        [string[]]$Module,
        [parameter(Mandatory=$True)]
        [int]$WikiId,
        [parameter(Mandatory=$True)]
        [EvolutionCredential]$Credential
    )
    process {
        $Module |% {
            $module = $_
            $existingPages = Get-Wikitoc -Wikiid $wikiId -Credential $Credential
            $parent = $existingPages |? Title -eq $module
            if (!$parent) {
                $parent = New-Wikipage -Wikiid $wikiId -Title $module -Credential $Credential
            }
            $parentId = $parent.Id
            ipmo $module
            get-module $module |
                select -ExpandProperty ExportedCommands |
                select -ExpandProperty Keys |
                ? { (get-help $_).Name -eq $_ } |
                % {
                    Write-Progress "Exporting Documentation" $module -CurrentOperation $command
                    $command = $_
                    [string]$body = (Get-CommandHelpHtml $command)
                    $existingPage = $parent.Children |? Title -eq $command
                    if($existingPage) {
                        Set-Wikipage -id $existingPage.Id -Body $body -Credential $Credential | Out-Null
                    }
                    else {
                        New-Wikipage -Wikiid $wikiId -Title $command -Body $body -ParentPageId $parentId -Credential $Credential | Out-Null
                    }

                }
        }
    }
}

$cred = New-EvolutionCredential
#$wiki = New-Wiki -GroupId 1 -Name "WikiTest$(Get-Random)" -Credential $cred
#$wikiId = $wiki.Id
$wikiId = 1
Export-DocsToWiki -Module @('Evolution', 'DevEvolution', 'EvolutionAddons') -WikiId $wikiId -Credential $cred
