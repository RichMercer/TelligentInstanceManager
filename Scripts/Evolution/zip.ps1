function Expand-Zip {
	<#
	.Synopsis
		Extracts files from a zip folder
	.Parameter ZipPath
	    The path to the Zip folder to extract
	.Parameter Destination
	    The location to extract the files to
    .Parameter ZipDir
        The directory within the zip folder to extract.  If not specified, extracts the whole zip file
    .Parameter ZipFileName
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
        [string]$ZipPath,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        [string]$ZipDir,
        [string]$ZipFileName
    )   

    $prefix = ""
    if($ZipDir){
        $prefix = $ZipDir.Replace('\','/').Trim('/') + '/'
    }
    if (!(test-path $Destination -PathType Container)) {
        New-item $Destination -Type Directory | out-null
    }

    #Convert path requried to ensure 
    $absoluteDestination = (Resolve-Path $Destination).ProviderPath
    $zipAbsolutePath = (Resolve-Path $ZipPath).ProviderPath

    $zipPackage = [IO.Compression.ZipFile]::OpenRead($zipAbsolutePath)
    try {

        if ($ZipFileName){
            $zipPackage.Entries |
                ? {$_.FullName -eq "${prefix}${ZipFileName}"} |
                select -first 1 |
                %{ Expand-ZipArchiveEntry $_ (Join-Path $absoluteDestination $ZipFileName) }
        }
        else {
            #Filter out directories
            $entries = $zipPackage.Entries |? Name
            if ($ZipDir) {
                #Filter out items not under requested directory
                $entries = $entries |? { $_.FullName.StartsWith($prefix, "OrdinalIgnoreCase")}
            }

            $totalFileSize = ($entries |% length |measure-object -sum).Sum
            $processedFileSize = 0
            $entries |% {
                $destination = join-path $absoluteDestination $_.FullName.Substring($prefix.Length)
                <#
                Write-Progress "Extracting Zip" `
                    -CurrentOperation $_.FullName `
                    -PercentComplete ($processedFileSize / $totalFileSize * 100)
                #>
                      
                Expand-ZipArchiveEntry $_ $destination 

                $processedFileSize += $_.Length
            }
            #Write-Progress "Extracting-Zip" -Completed
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
        [IO.Compression.ZipArchiveEntry]$Entry,
        [parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination            
    )

    if (!$Entry.Name){
        return
     }

    $itemDir = split-path $Destination -Parent
    if (!(test-path $itemDir -PathType Container)) {
        New-item $itemDir -Type Directory | out-null
    }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $true)
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
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $ErrorActionPreference = "Stop"

    Test-Path $Path -PathType Leaf
    if((Get-Item $Path).Extension -ne ".zip") {
		throw "$Path is not a zip file"
    }
}
