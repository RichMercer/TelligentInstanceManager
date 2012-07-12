function Expand-Zip {
	<#
	.Synopsis
		Extracts files from a zip folder
	.Parameter zipPath
	    The path to the Zip folder to extract
	.Parameter destination
	    The location to extract the files to
    .Parameter zipDir
        The directory within the zip folder to extract.  If not specified, extracts the whole zip file
    .Parameter zipFileName
        The name of a specific file within zipDir to extract
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$zipPath,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$destination,
        [string]$zipDir,
        [ValidateNotNullOrEmpty()]
        [string]$zipFileName
    )
    begin{
        $shell_app=new-object -com shell.application 
    }
    process {
        if (!($zipPath -and (test-path $zipPath))){
            throw "$zipPath does not exist"
        }
        
        if (!(test-path $destination)) {
          new-item $destination -type directory |out-null
        }   
        
        $shellNamesapce= Join-Path $zipPath $zipDir
        $zip_file = $shell_app.namespace($shellNamesapce) 
        $destinationFolder = $shell_app.namespace($destination)
        if ($zipFileName) {
            $zip_file.items() |
                ? { (Split-Path $_.Path -leaf) -eq $zipFileName } |
                % { $destinationFolder.Copyhere($_, 3604) }
        }
        else {
            $destinationFolder.Copyhere($zip_file.items(), 3604)
        }
        #For more info on CopyHere - http://msdn.microsoft.com/en-us/library/windows/desktop/bb787866(v=vs.85).aspx
    }
}

function Test-Zip {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$zipFile
    )
	if(!(Test-Path $_) -or (Get-Item $_ ).Extension -ne ".zip"){
		throw "$_ is not a valid zip file"
	}
	return $true
}
