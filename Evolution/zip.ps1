add-type -AssemblyName System.IO.Compression
add-type -AssemblyName System.IO.Compression.FileSystem

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
        [string]$zipFileName
    )   

    $prefix = ""
    if($zipDir){
        $prefix = $zipDir.Replace('\','/').Trim('/') + '/'
    }
    if (!(test-path $destination)) {
        New-item $destination -Type Directory | out-null
    }
    $absoluteDestination = Convert-Path $destination

    $zipPackage = [IO.Compression.ZipFile]::OpenRead((Convert-Path $zipPath))
    try {

        if ($zipFileName){
            $zipPackage.Entries |
                ? {$_.FullName -eq "${prefix}${zipFileName}"} |
                select -first 1 |
                %{ Expand-ZipArchiveEntry $_ (join-path $absoluteDestination $zipFileName) }
        }
        else {
            #Filter out directories
            $entries = $zipPackage.Entries |? Name
            if ($zipDir) {
                #Filter out itmes not in filtered directory
                $entries = $entries |? { $_.FullName.StartsWith($prefix, "OrdinalIgnoreCase")}
            }

            $totalFileSize = ($entries |% length |measure-object -sum).Sum
            $processedFileSize = 0
            $entries |% {
                $destination = join-path $absoluteDestination $_.FullName.Substring($prefix.Length)
                #Write-Progress "Extracting Zip" -CurrentOperation $_.FullName -PercentComplete ($processedFileSize / $totalFileSize * 100) 

                Expand-ZipArchiveEntry $_ $destination 

                $processedFileSize += $_.Length
            }
            Write-Progress "Extracting Zip" -completed
        }
    }
    finally {
        $zipPackage.Dispose()
    }
}

function Expand-ZipArchiveEntry {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [IO.Compression.ZipArchiveEntry]$entry,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$destination            
    )

    if (!$entry.Name){
        return
        }

    $itemDir = split-path $destination -Parent
    if (!(test-path $itemDir)) {
        New-item $itemDir -Type Directory | out-null
    }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
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
	if(!(Test-Path $zipFile) -or (Get-Item $zipFile ).Extension -ne ".zip"){
		throw "$zipFile is not a valid zip file"
	}
	return $true
}
