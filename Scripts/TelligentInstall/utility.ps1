Set-StrictMode -Version 2

function Write-ProgressFromVerbose {    
    <#
    .SYNOPSIS
        Executes a script, and redirects any output on the verbose stream to Write-Progress.
    .PARAMETER Activity
        The Activity to pass to Write-Progress
    .PARAMETER Status
        The Status to pass to Write-Progress
    .PARAMETER Script
        The Script to execute, and redirect verbose output as the Write-Progress as the CurrentOperation parameter
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,
        [Parameter(Mandatory=$true, Position = 1)]
        [string]$Status,
        [Parameter(Mandatory=$true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$Script
    )

    #HACK: executing script inside an inner function so we can pipe verbose output
    # Even if the VerbosePrefrence level is currently SilentlyIgnore
    function Execute-ScriptBlock {
        [CmdletBinding()]
        param()

        $Script.Invoke()
    }

    Write-Progress $Activity $Status

    Execute-ScriptBlock -Verbose 4>&1 |
        ? { $_ -is 'System.Management.Automation.VerboseRecord'}  |
        % {
            Write-Progress $Activity $Status  -CurrentOperation $_.Message
            $_ | Write-Verbose
        }
}

function Expand-UNCPath {
    param(
        [Parameter(Mandatory=$true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^\\\\[^\\]+\\[^\\]+')]
        [string]$Path
    )
    $pathToSplit = $Path.Substring(2);
    $parts = $pathToSplit -split '\\'

    $result = [ordered]@{
        Path = $Path
        ComputerName = $parts[0]
        Share = $parts[1]
        LocalPath = ''
    }

    #If the computer name given is a CName, resolve to the real host
    $hostInfo = [system.net.dns]::GetHostByName($result.ComputerName)
    if ($hostInfo) {
        $result.ComputerName = $hostInfo.HostName
    }

    $share = gwmi win32_share -ComputerName $result.ComputerName |
        ? Name -eq $result.Share

    if ($share) {
        $remaining = $parts[2..$parts.Length] -join '\'
        $result.LocalPath = "$($share.Path.TrimEnd('\'))\$remaining"
    }
    [PSCustomObject]$result
}


