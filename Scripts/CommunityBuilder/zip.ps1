Set-StrictMode -Version 2

function Expand-Zip {
	<#
	.Synopsis
		Extracts files or directories from a zip folder
	.Parameter Path
	    The path to the Zip folder to extract
	.Parameter Destination
	    The location to extract the files to
    .Parameter ZipDirectory
        The directory within the zip folder to extract.  If not specified, extracts the whole zip file
    .Parameter ZipFileName
        The name of a specific file within ZipDirectory to extract
	.Example 
		Expand-Zip c:\sample.zip c:\files\
		
		Description
		-----------
		This command extracts the entire contents of c:\sample.zip to c:\files\	
	.Example
		Expand-Zip c:\sample.zip c:\sample\web\ -ZipDirectory web
		
		Description
		-----------
		This command extracts the contents of the web directory	of c:\sample.zip to c:\sample\web
	.Example
		Expand-Zip c:\sample.zip c:\test\ -ZipDirectory documentation -zipFileName sample.txt
		
		Description
		-----------
		This command extracts the sample.txt file from the web directory of c:\sample.zip to c:\sample\sample.txt
	#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Path,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Container -IsValid)})]
        [string]$ZipDirectory,
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Leaf -IsValid)})]
        [string]$ZipFileName
    )

    $prefix = ''
    if($ZipDirectory){
        $prefix = ($ZipDirectory).Replace('\','/').Trim('/') + '/'
    }
    if (!(test-path $Destination -PathType Container)) {
        New-item $Destination -Type Directory | out-null
    }

    #Convert path requried to ensure 
    $absoluteDestination = (Resolve-Path $Destination).ProviderPath
    $zipAbsolutePath = (Resolve-Path $Path).ProviderPath

    $zipPackage = [IO.Compression.ZipFile]::OpenRead($zipAbsolutePath)
    try {
        $entries = $zipPackage.Entries
        if ($ZipFileName){
            $entries = $entries |
                ? {$_.FullName.Replace('\','/') -eq "${prefix}${ZipFileName}"} |
                select -First 1
        }
        else {
            #Filter out directories
            $entries = $zipPackage.Entries |? Name
            if ($ZipDirectory) {
                #Filter out items not under requested directory
                $entries = $entries |? { $_.FullName.Replace('\','/').StartsWith($prefix, "OrdinalIgnoreCase")}
            }
        }

        $totalFileSize = ($entries |% length | Measure-Object -sum).Sum
        $processedFileSize = 0
        $entries |% {
            $destination = join-path $absoluteDestination $_.FullName.Substring($prefix.Length)
            <#
            Write-Progress 'Extracting Zip' `
                -CurrentOperation $_.FullName `
                -PercentComplete ($processedFileSize / $totalFileSize * 100)
            #>
                      
            $itemDir = split-path $Destination -Parent
            if (!(Test-Path $itemDir -PathType Container)) {
                New-item $itemDir -Type Directory | out-null
            }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($_, $Destination, $true)

            $processedFileSize += $_.Length
        }
        #Write-Progress 'Extracting-Zip' -Completed
        
    }
    finally {
        $zipPackage.Dispose()
    }
}


function Test-Zip {
	<#
	.Synopsis
		Tests whether a file exists and is a valid zip file.

	.Parameter Path
	    The path to the file to test

	.Example
		Test-Zip c:\sample.zip
		
		Description
		-----------
		This command checks if the file c:\sample.zip exists		
	#>
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Test-Path $Path -PathType Leaf
    if((Get-Item $Path).Extension -ne '.zip') {
		throw "$Path is not a zip file"
    }
}

