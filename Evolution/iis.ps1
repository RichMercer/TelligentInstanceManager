function New-EvolutionWebsite {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$path,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [ValidateNotNullOrEmpty()]
        [string]$domain,
        [ValidateNotNullOrEmpty()]
        [int]$port = 80,
        [ValidateNotNullOrEmpty()]
        [string]$appPool = $name,
 		[ValidateSet(2.0,4.0)]
        [double]$netVersion = 4.0,
        [string]$filestorage
    )

    if(!(test-path $path)) {
        new-item $path -type directory | out-null
    }    
    New-IISWebsite -name $name -path $path -domain $domain -port $port -appPool $appPool

    Write-Progress "Website: $name" "Extracting Web Files: $path"
    Expand-Zip $package $path -zipDir "Web"

    if($filestorage) {
        $originalFilestorage = join-path $path filestorage
        Write-Progress "Website: $name" "Moving Filestorage to $filestorage"
        move-item $originalFilestorage $filestorage -Force
    }
    else {
        $filestorage = join-path $webDir filestorage        
    }

    Grant-EvolutionWebPermissions $path $filestorage
}

function Grant-EvolutionWebPermissions {
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$webDir,
        [parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Resolve-Path $_ })]
        [string]$filestorage
    )
    Get-IISWebsites $webDir |% {
        $name = $_.name
        $appPoolIdentity = Get-IISAppPoolIdentity $_.applicationPool
        Write-Progress "Website: $name" "Granting read access to $appPoolIdentity"

        #TODO: outputs a status message.  switch to Set-Acl instead
        &icacls "$webDir" /grant "${appPoolIdentity}:(OI)(CI)RX" /Q | out-null

        Write-Progress "Website: $name" "Granting modify access to $appPoolIdentity for $filestorage"
        &icacls "$filestorage" /grant "${appPoolIdentity}:(OI)(CI)M" /Q | out-null

    }
}

function New-IISWebsite {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$path,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$domain,
        [ValidateNotNullOrEmpty()]
        [uint16]$port = 80,
        [ValidateNotNullOrEmpty()]
        [string]$appPool = $name,
 		[ValidateSet(2.0,4.0)]
        [double]$netVersion = 4.0
    )
    
    if (!(test-path $path)) {
        new-item $path -type directory |out-null
    }
    if (!(test-path IIS:\AppPools\$appPool)) {
        Write-Progress "Website: $name" "Creating IIS App Pool"
        New-IISAppPool $name -netVersion $netVersion
    }
    
    pushd IIS:\Sites\
    try {
        Write-Progress "Website: $name" "Creating IIS Website"
        New-Item $name -bindings @{protocol="http";bindingInformation=":${port}:${domain}"} -physicalPath $path -force |
            Set-ItemProperty -name applicationPool -value $appPool
    }
    finally{
        popd
    }
}

function New-IISAppPool{
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
 		[ValidateSet(2.0,4.0)]
        [double]$netVersion = 4.0,
        [string]$username,
        [string]$password
    )
    $versionString = "v{0:N1}" -f $netVersion
    pushd IIS:\AppPools
    try {
        new-item $name -force | out-null
        if ($username){
            set-itemProperty $name -name processmodel -value @{identityType="SpecificUser"; username=$username; password=$password} 
        }
        else {
            set-itemProperty $name -name processmodel -value @{identityType="ApplicationPoolIdentity"} 
        }
        set-itemProperty $name -name managedRuntimeVersion -value $versionString
    }
    finally {
        popd
    }
}

function Get-IISAppPoolIdentity {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name
    )
    switch (get-itemProperty IIS:\AppPools\$name -name processmodel.identityType)
    {
        "ApplicationPoolIdentity" { return "IIS AppPool\${name}"}
        "NetworkService " { return "NETWORK SERVICE"}
        "LocalService" { return "LOCAL SERVICE"}
        "LocalSystem" { return "SYSTEM"}
        "SpecificUser" { return (get-itemProperty IIS:\AppPools\$name -name processmodel.userName.value)}
    }
    throw "Unable to determine app pool identity: $name"
}


function Get-IISWebsites {
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$path = (Get-Location).Path
    )
    return get-childitem iis:\sites |? {$_.PhysicalPath.TrimEnd('\') -eq $path.TrimEnd('\') }
}

