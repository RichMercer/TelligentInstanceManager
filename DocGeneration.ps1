Add-Type -AssemblyName System.Web

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
        [CommunityCredential]$Credential
    )
    process {
        $existingPages = Get-CommunityWikitoc -Wikiid $wikiId -Credential $Credential

        $Module |% {
            $currentModule= $_

            $modulePage = $existingPages |? Title -eq $module
            if (!$modulePage) {
                $modulePage = New-CommunityWikipage `
                    -Wikiid $wikiId `
                    -Title $currentModule `
                    -Credential $Credential
            }
            Get-Command -Module $currentModule -CommandType Function, Workflow |
                Group Noun |
                %{
                    $noun = $_.Name
                    $noun
                    $nounPage = $existingPages |? Title -eq $noun
                    if (!$nounPage) {
                        $nounPage = New-CommunityWikipage `
                            -Wikiid $wikiId `
                            -Title $noun `
                            -ParentPageId $modulePage.Id `
                            -Credential $Credential
                    }

                    $_.Group |% {
                        $command = $_.Name
                        $tags = @($noun,$_.Verb);
                        [string]$body = (Get-CommandHelpHtml $command)
                        $existingPage = $parent.Children |? Title -eq $command
                        if($existingPage) {
                            Set-CommunityWikipage `
                                -id $existingPage.Id `
                                -Body $body `
                                -Tag $tags `
                                -Credential $Credential | Out-Null
                        }
                        else {
                            New-CommunityWikipage `
                                -Wikiid $wikiId `
                                -Title $command `
                                -Body $body `
                                -Tag $tags `
                                -ParentPageId $nounPage.Id `
                                -Credential $Credential | Out-Null
                        }
                    }
            }
        }
    }
}

$cred = ncc http://pstest3.local admin abc123
$wikiId = (New-communityWiki -GroupId 3 -Name ("DocTest$(Get-Date -f 'yyMMdd_HHmmss')") -Credential $cred).Id
Export-DocsToWiki -Module @('CommunityBuilder', 'DevCommunity') -WikiId $wikiId -Credential $cred
