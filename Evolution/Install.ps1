function Install-DevEvolution {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $webDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [ValidateNotNullOrEmpty()]
        [int]$port
    )

    $solrUrl = "http://localhost:8090/solr"
    $solrCoreBase = "C:\temp\Tomcat\solr\"

    New-EvolutionWebsite -name $name -path $webDir -package $package -domain "localhost" -port $port
    Install-EvolutionDatabase -server "." -package $package -database $name -webDomain "localhost"

    $identity = Get-IISAppPoolIdentity $name
    
    Grant-EvolutionDatabaseAccess -server "." -database $name -username $identity
    Add-SolrCore $name -package $package -coreBaseDir $solrCoreBase -coreAdmin "$solrUrl/admin/cores"

    pushd $webdir 
    try {
        Update-ConnectionStrings -database $name -server "."
        Update-EvolutionSolrUrl "$solrUrl/$name/"
        Register-TasksInWebProcess $package
        Disable-CustomErrors
    }
    finally {
    	popd
    }


}

function Install-Evolution {
	<#
	.Synopsis
		Sets up a new Evolution Community
	.Description
		Extensive description of the function
	.Parameter name
	    The name of the community to create
	.Parameter package
	    The path to the zip package containing the Telligent Evolution installation files from Telligent Support
	.Parameter hotfixPackage
	    If specified applys the hotfix from the referenced zip file.
	.Parameter webDir
	    The directory to place the Evolution website in
	.Parameter webDomain
	    The domain name to use in the community's IIS binding
	.Parameter webPort
	    The port number to use int the community's IIS binding.  Defaults to 80
	.Parameter appPool
	    The name of the Applicaiton Pool to use the community with.  If not specified creates a new apppool using ApplicationPoolIdentity identity
	.Parameter dbServer
	    The DNS name of your SQL server.  Must be able to connect using Windows Auhtenticaiton from the current machine.  Only supports Default instances.
	.Parameter dbName
	    The name of the database to locate your community in
	.Parameter searchDomain
	    The DNS name of the tomcat instance Solr will be installed to
	.Parameter searchPort
	    The port tomcat runs on - defaults to 8080
	.Parameter licenceFile
	    The path to the licence XML file to install in the community
	.Example Basic Install
		Install-Evolution -name "Powershell Test" -package "c:\temp\TelligentCommunitySuite-6.0.119.19092.zip" -webDir "c:\temp\PowershellTest\Web\" -webDomain "mydomain.com" -searchDir "c:\temp\PowershellTest\Search\" -tomcatContextDir "C:\Program Files\Apache Software Foundation\Tomcat 7.0\conf\Catalina\localhost" -licenceFile "c:\temp\licence.xml"
	#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$hotfixPackage,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDomain,
        [uint16]$webPort = 80,
        [string]$appPool,

        [ValidateNotNullOrEmpty()]
        [string]$dbServer = "localhost",
        [ValidateNotNullOrEmpty()]
        [string]$dbName = $name,
        [string]$sqlUsername,
        [string]$sqlPassword,

        [uri]$searchUrl,
        [string]$licenceFile
    )   
    $ErrorActionPreference = "Stop"
    
    Write-Progress "Website" "Creating IIS Website $name"
    New-IISWebsite -name $name -path $webDir -domain $webDomain -port $webPort -appPool $appPool
    if (!$appPool) {
        $appPool = $name
    }

    Write-Progress "Website" "Extracting Web Files: $webDir"
    Expand-Zip -zipPath $package -destination $webDir -zipDir "Web"


    $appPoolIdentity = Get-IISAppPoolIdentity $appPool
    Write-Progress "Website" "Granting Permissions to $appPoolIdentity"
    $filestorage = join-path $webDir filestorage
    #TODO: outputs a status message.  switch to Set-Acl instead
    icacls "$webDir" /grant "${appPoolIdentity}:(OI)(CI)RX" /Q
    icacls "$filestorage" /grant "${appPoolIdentity}:(OI)(CI)M" /Q


    #If Create DB
    Install-EvolutionDatabase -server $dbServer -package $package -name $dbName -username $dbUsername -password $dbPassword

    if ($hotfixPackage) {
        Install-EvolutionHotfix -communityDir $webDir -package $hotfixPackage -dbServer $dbServer -dbName $dbName
    }

	
    if ($sqlUsername) {
        Write-Progress "Database" "Granting Permissions to SQL Auth: $dbUsername"
        Grant-EvolutionDatabaseAccess -server $dbServer -database $dbName -username $sqlUsername -password $sqlPassword
    }
    else {
        Write-Progress "Database" "Granting Permissions to Windows Auth: $appPoolIdentity"
        Grant-EvolutionDatabaseAccess -server $dbServer -database $dbName -username $appPoolIdentity
    }

    Write-Progress "Search" "Configuring Search url in community" 
    AddChangeAttributeOverride -webDir $webDir -xpath /CommunityServer/Search/Solr -name host -value "http://${searchdomain}:$searchPort/$searchWebPath/"

    if ($licenceFile) {
        Write-Progress "Configuration" "Installing Licence"
        Install-EvolutionLicence $licenceFile $dbServer $dbName
    }
    else {
        Write-Warning "No licence specified. Not installing a licence will affect your ability to use the community. You may install a licence at a later date through the Control Panel, or Install-EvolutionLicence cmdlet"
    }

    Write-Progress "Configuration" "Updating Solr Url"
    if ($searchUrl) {
        Update-EvolutionSolrUrl $webDir $searchUrl
    }
    else {
        Write-Warning "No solr url specifies. Without search, a number of features will be unavailable in your community"
    }

	
    Write-Progress "Configuration" "Updating connectionstrings.config"
    Update-ConnectionStrings -path (join-path $webDir connectionstrings.config) -dbServer $dbServer -dbName $dbName	
}


function Install-EvolutionHotfix {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$communityDir,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$package,
        [ValidateNotNullOrEmpty()]
        [string]$dbServer = ".",
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$dbName
    )
    
    Write-Progress "Applying Hotfix" "Updating Web"
    Expand-Zip -zipPath $package -destination $communityDir -zipDir "Web"
   
    Write-Progress "Applying Hotfix" "Updating Database"
    $tempDir = join-path $env:temp ([guid]::NewGuid())
    @("update.sql", "updates.sql") |% {
        Expand-Zip -zipPath $package -destination $tempDir -zipFile $_
        $sqlPath = join-path $tempDir $_
        if (test-path $sqlPath) {
            Invoke-Sqlcmd -serverinstance $dbServer -Database $dbName -InputFile $sqlPath |out-null
        }
    }
   
}

function Install-EvolutionMobile {
}
function Install-EvolutionCalendar {
}


function CCTest {
    [CmdletBinding()]
    param(
        $port = (Get-Random -min 1000 -max 9999)
    )
    $ErrorActionPreference = "Stop"
    
    "Creating website http://${port}.alex.support.telligent.com/"
    $name = "PS-$port"
    $package = "C:\OOTB\Packages\TelligentCommunitySuite-6.0.119.19092.zip"
    
    $passwordPlain = [guid]::NewGuid()
    $password = ConvertTo-SecureString $passwordPlain -AsPlainText -force
  
    #TODO: Currently adds the user to the Domain Users group.  Don't want this
    Write-Progress "Active Directory" "Creating User $name"
    New-ADUser $name `
          -AccountPassword $password  `
          -Path "OU=ServiceAccounts,DC=support,DC=telligent,DC=com" `
          -CannotChangePassword $true `
          -ChangePasswordAtLogon $false `
          -PasswordNeverExpires $true `
          -Enabled $true `
	        | Add-ADPrincipalGroupMembership -MemberOf "Service Users" -PassThru `
			| Remove-ADPrincipalGroupMembership -MemberOf "Domain Users" -PassThru
  
    Create-IISDomainAppPool -name $name -username "SUPPORT\$name" -password $passwordPlain    
    
    Add-SolrCore $name `
        -package $package `
        -coreBaseDir "\\tomcat.support.telligent.com\c$\SolrMultiCore" `
        -coreAdmin "http://tomcat.support.telligent.com/solr/1-4/admin/cores"

    $webDir = "c:\Alex\$name\"
    Install-Evolution -name "$name" `
       -package $package `
       -webDir $webDir `
       -webDomain "${port}.alex.support.telligent.com" `
       -searchUrl "http://tomcat.support.telligent.com/solr/1-4/$name/" `
       -licenceFile C:\OOTB\Licences\Community6.xml `
       -dbServer "sql.support.telligent.com\SQL2008R2" `
       -appPool $name
       
    Register-TasksInWebProcess $webDir $package
    Disable-CustomErrors $webDir
}


