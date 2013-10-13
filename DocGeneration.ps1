Add-Type -AssemblyName System.Web
. D:\Telligent\SVN\PowershellRest\RestApiExtractor\test.ps1

function ConvertTo-HtmlEncodedString {
    param(
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
                $param = "-$($_.name) <$($_.parameterValue)>"
                if($_.required -eq 'false') { $param = "[$param]"}
                $syntax += " $param"
             }
            "<pre class=`"brush: ps`">" + (ConvertTo-HtmlEncodedString $syntax) + "</pre>"         
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
        [string]$PlainText
    )

    $PlainText -split '[\r\n]{2}' |
        % {"<p>$(ConvertTo-HtmlEncodedString $_)</p>"}
}


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
            $currentModule= $_
            $existingPages = Get-Wikitoc -Wikiid $wikiId -Credential $Credential
            $parent = $existingPages |? Title -eq $module
            if (!$parent) {
                $parent = New-Wikipage -Wikiid $wikiId -Title $currentModule -Credential $Credential
            }
            $parentId = $parent.Id

            ipmo $currentModule
            get-module $currentModule |
                select -ExpandProperty ExportedCommands |
                select -ExpandProperty Keys |
                ? { (get-help $_).Name -eq $_ } |
                % {
                    $command = $_
                    Write-Progress "Exporting Documentation" $currentModule -CurrentOperation $command
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

$cred = New-EvolutionCredential http://psdocs.local admin abc123
$wikiId = (New-Wiki -GroupId 3 -Name ("DocTest$(Get-Date -f 'yyMMdd_HHmmss')") -Credential $cred).Id
Export-DocsToWiki -Module @('Evolution', 'DevEvolution', 'EvolutionAddons') -WikiId $wikiId -Credential $cred
