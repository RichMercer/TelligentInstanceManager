function Write-ProgressFromVerbose {
    param (
        [parameter(Mandatory=$true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,
        [parameter(Mandatory=$true, Position = 1)]
        [string]$Status,
        [parameter(Mandatory=$true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$Script
    )

    #HACK: executing script inside an inner function so we can pipe verbose output
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