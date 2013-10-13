function New-EvolutionWebsite {
    <#
    .SYNOPSIS
        Creates a new Evolution website
    .DESCRIPTION
        Creates a new Telligent Evolution Website, including extracting the installation package, creating the IIS website and setting up filestorage.
    .PARAMETER name
        The name of the site to be created in IIS.
    .PARAMETER Path
        The physical location of the website files
    .PARAMETER Package
        The installation package to extract the website files from.
    .PARAMETER HostName
        The HostName to use in the IIS site binding.
    .PARAMETER Port
        The port to use in the IIS site binding.
    .PARAMETER ApplicationPool
        The name of the application pool to create the website with.  If the specified application pool doesn't exist, it is created.  If not specified, IIS configuration will determine the application pool to use.
    .PARAMETER ClrVersion
        The version of .net to configure the application pool for.  If not specified, defaults to 4.0
    .PARAMETER FilestoragePath
        The location the filestorage should be stored at.  If not specified, uses teh default
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -IsValid})]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package,
        [ValidateNotNullOrEmpty()]
        [string]$HostName,
        [ValidateNotNullOrEmpty()]
        [int]$Port = 80,
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationPool = $name,
        [ValidateScript({Test-Path $_ -PathType Container -IsValid})]
        [string]$FilestoragePath
    )

    Write-Progress "Website: $Name" "Extracting Web Files: $Path"
    Expand-Zip $Package $Path -ZipDirectory Web

    $info = Get-Community $Path

    [double]$clrVersion = if($info.PlatformVersion.Major -le 5) { 2.0 } else { 4.0 }

    New-IISWebsite -Name $Name -Path $Path -HostName $HostName -Port $Port -ApplicationPool $ApplicationPool -ClrVersion $clrVersion

    $initialFilestoragePath = Join-Path $Path filestorage
    #TODO: Abstract Move-Filestorage into seperate function
    if($FilestoragePath) {
        if($FilestoragePath -ne $initialFilestoragePath) {
            Write-Progress "Website: $Name" "Moving Filestorage to $FilestoragePath"
            if(!(Test-Path $FilestoragePath)) {
                New-Item $FilestoragePath -ItemType Directory | Out-Null
            }
            Move-Item (Join-Path $initialFilestoragePath *) $FilestoragePath -Force
            Remove-Item $initialFilestoragePath
        }

        Set-EvolutionFileStorage $Path $FilestoragePath
    }
    else {
        $FilestoragePath = $initialFilestoragePath       
    }

    Grant-EvolutionNtfsPermission $Path $FilestoragePath
}

function Grant-EvolutionNtfsPermission {
    <#
    .SYNOPSIS
      Grants the required NTFS permissions for a Telligent Evolution community.
    .PARAMETER WebsitePath
        The path to the Telligent Evolution Website. This location has read permissions granted to the Application Pool Identity
    .PARAMETER FilestoragePath
        The path to the Telligent Evolution Filestorage. This location has Modify permissions granted to the Application Pool Identity        
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ })]
        [string]$WebsitePath,
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Path $_ -PathType Container })]
        [string]$FilestoragePath
    )
    Get-IISWebsite $WebsitePath |% {
        $name = $_.name
        $appPoolIdentity = Get-IISAppPoolIdentity $_.applicationPool
        Write-Progress "Website: $name" "Granting read access to '$appPoolIdentity' on '$WebsitePath'"

        #TODO: outputs a status message.  switch to Set-Acl instead
        &icacls "$WebsitePath" /grant "${appPoolIdentity}:(OI)(CI)RX" /Q | out-null

        Write-Progress "Website: $name" "Granting modify access to $appPoolIdentity on $FilestoragePath"
        &icacls "$FilestoragePath" /grant "${appPoolIdentity}:(OI)(CI)M" /Q | out-null
    }
}

function New-IISWebsite {
    <#
    .SYNOPSIS
        Creates a new IIS website
    .PARAMETER Name
        The name of the site to be created in IIS.
    .PARAMETER Path
        The physical location of the website files
    .PARAMETER HostName
        The HostName to use in the IIS site binding.
    .PARAMETER Port
        The port to use in the IIS site binding.
    .PARAMETER ApplicationPool
        The name of the application pool to create the website with.  If the specified application pool doesn't exist, it is created.  If not specified, IIS configuration will determine the application pool to use.
    .PARAMETER ClrVersion
        The version of .net to configure the application pool for.  If not specified, defaults to 4.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-CommunityPath $_ -IsValid })]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,
        [ValidateNotNullOrEmpty()]
        [uint16]$Port = 80,
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [string]$ApplicationPool = $Name,
 		[ValidateSet(2.0,4.0)]
        [double]$ClrVersion = 4.0
    )
    
    if (!(Test-Path $path)) {
        New-Item $Path -Type Directory | Out-Null
    }
    if (!(Test-Path IIS:\AppPools\$ApplicationPool)) {
        Write-Progress "Website: $Name" "Creating IIS Application Pool"
        New-IISAppPool $Name -ClrVersion $ClrVersion
    }
    
    Write-Progress "Website: $Name" "Creating IIS Website"
    New-Item IIS:\Sites\$Name -Bindings @{protocol="http";bindingInformation=":${Port}:${HostName}"} -PhysicalPath $Path -Force |
        Set-ItemProperty -Name applicationPool -Value $ApplicationPool
}

function New-IISAppPool{
    <#
    .SYNOPSIS
        Creates a new Application Pool
    .DESCRIPTION
        Creates a new IIS Application Pool using the specified .net version.  If credentials are specified, uses these as the Application Pool Identity, otherwise uses ApplicationPoolIdentity.
    .PARAMETER Name
        The name of the Application Pool to create.
    .PARAMETER ClrVersion
        The version of .Net CLR the Application Pool should run under.
    .PARAMETER Credential
        The credentials the Application Pool should run under.  If not specified, then the ApplicationPoolIdentity is used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [string]$Name,
 		[ValidateSet(2.0,4.0)]
        [double]$ClrVersion = 4.0,
        [PSCredential]$Credential
    )
    $versionString = 'v{0:N1}' -f $ClrVersion
    Push-Location IIS:\AppPools
    try {
        New-Item $Name -Force | Out-Null
        if ($Credential){
            Set-ItemProperty $Name -Name processmodel -Value @{
                identityType = 'SpecificUser'
                username = $Credential.UserName
                password = $Credential.Password
            } 
        }
        else {
            Set-ItemProperty $Name -Name processmodel -Value @{identityType = 'ApplicationPoolIdentity'} 
        }
        Set-ItemProperty $Name -Name managedRuntimeVersion -Value $versionString
    }
    finally {
        Pop-Location
    }
}

function Get-IISAppPoolIdentity {
    <#
    .SYNOPSIS
        Gets the identity used by the specified IIS Application Pool
    .PARAMETER Name
        The name of the IIS Application Pool to get information for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z0-9\-\._ ]+$')]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    switch (Get-ItemProperty IIS:\AppPools\$Name -Name processmodel.identityType)
    {
        'ApplicationPoolIdentity' { return "IIS AppPool\${Name}"}
        'NetworkService' { return 'NETWORK SERVICE'}
        'LocalService' { return 'LOCAL SERVICE'}
        'LocalSystem' { return 'SYSTEM'}
        'SpecificUser' { return (Get-ItemProperty IIS:\AppPools\$Name -Name processmodel.userName.value)}
    }
    throw "Unable to determine app pool identity: $Name"
}

function Get-IISWebsite {
    <#
    .SYNOPSIS
        Gets the IIS Websites rooted at the provided location
    .PARAMETER Path
        The path used as the physicalPath for an IIS Websites.  If not specified, uses the current location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = (Get-Location).Path
    )
    return Get-ChildItem iis:\sites |? {$_.PhysicalPath.TrimEnd('\') -eq $Path.TrimEnd('\') }
}

