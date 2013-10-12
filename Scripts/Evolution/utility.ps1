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
        % { Write-Progress $Activity $Status  -CurrentOperation $_.Message}
}