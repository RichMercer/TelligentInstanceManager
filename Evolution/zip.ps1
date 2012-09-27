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
	.Example 
		Expand-Zip c:\sample.zip c:\files\
		
		Description
		-----------
		This command extracts the entire contents of c:\sample.zip to c:\files\	
	.Example
		Expand-Zip c:\sample.zip c:\sample\web\ -zipDir web
		
		Description
		-----------
		This command extracts the contents of the web directory	of c:\sample.zip to c:\sample\web
	.Example
		Expand-Zip c:\sample.zip c:\test\ -zipDir documentation -zipFileName sample.txt
		
		Description
		-----------
		This command extracts the sample.txt file from the web directory of c:\sample.zip to c:\sample\sample.txt
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
	<#
	.Synopsis
		Tests whether a file exists and is a valid zip file.
	.Parameter zipFile
	    The path to the file to test
	.Example
		Test-Zip c:\sample.zip
		
		Description
		-----------
		This command checks if the file c:\sample.zip exists		
	#>
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
