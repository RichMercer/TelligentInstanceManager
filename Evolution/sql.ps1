function Install-EvolutionDatabase {
	<#
	.Synopsis
		Grants a user access to an evolution database.  If the user or login doesn't exist, in the SQL server, they
		are created before being granted the 
	.Parameter zipFile
	    The path to the file to test
	#>
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [alias('DataSource')]
		[alias('dbServer')]
        [string]$server,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [alias('InitialCatalog')]
        [string]$database,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDomain,
        [string]$username,
        [string]$password
    )

    #TODO: Check if DB exists first
    Write-Progress "Database: $database" "Checking if database exists"
    if($true) {
        Write-Progress "Database: $database" "Creating database"
        New-Database -name $database -server $server
    }
    
    Write-Progress "Database: $database" "Creating Schema"
    $tempDir = join-path $env:temp ([guid]::NewGuid())
    Expand-Zip -zipPath $package -destination $tempDir -zipDir "SqlScripts" -zipFile "cs_CreateFullDatabase.sql"
    $sqlScript = join-path $tempDir cs_CreateFullDatabase.sql | resolve-path

    $VerbosePreference = 'continue'
    Invoke-Sqlcmd -serverinstance $server -Database $database -InputFile $sqlScript -QueryTimeout 6000  4>&1 |
       ? { $_ -is 'System.Management.Automation.VerboseRecord'}  |
       % { Write-Progress "Database: $database" "Creating Schema" -CurrentOperation $_.Message }
    Remove-Item $tempDir -Recurse -force | out-null

    Write-Progress "Database: $database" "Creating Community"
    Invoke-Sqlcmd -serverInstance $server -database $database -query @"
         EXECUTE [dbo].[cs_system_CreateCommunity]
                @SiteUrl = N'http://${webDomain}/'
                , @ApplicationName = N'$name'
                , @AdminEmail = N'notset@localhost.com'
                , @AdminUserName = N'admin'
                , @AdminPassword = N'password'
                , @PasswordFormat = 0
                , @CreateSamples = 1
"@ 4>&1 |
       ? { $_ -is 'System.Management.Automation.VerboseRecord'}  |
       % { Write-Progress "Database: $database" "Creating Community" -CurrentOperation $_.Message }

}

function Invoke-SqlcmdWithProgress
{
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$serverInstance,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$database,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$webDomain,
        [string]$username,
        [string]$password
    )
	throw "TODO"
}

function Grant-EvolutionDatabaseAccess {
	<#
	.Synopsis
		Grants a user access to an Evolution database.  If the user or login doesn't exist, in the SQL server, they
		are created before being granted access to the database.
	.Parameter server
		The SQL server the database is contained on
	.Parameter dbName
		The name of the database
	.Parameter username
		The name of the user to grant access to.  If no password is specified, the user is assumed to be a Windows
		login.
	.Parameter password
		The password for the SQL user
	.Example
		Grant-EvolutionDatabaseAccess (local)\SqlExpress SampleCommunity "NT AUTHORITY\NETWORK SERVICE"

		Description
		-----------
		This command grant access to the SampleCommunity database on the SqlExpress instance of the local SQL server
		for the Network Service Windows account
	.Example
		Grant-EvolutionDatabaseAccess ServerName SampleCommunity CommunityUser -password SqlPa$$w0rd
		
		Description
		-----------
		This command grant access to the SampleCommunity database on the default instance of the ServerName SQL server
		for the CommunityUser SQL account. If this login does not exist, it gets created using the password SqlPa$$w0rd

	#>
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position = 0)]
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$server,
        [parameter(Mandatory=$true, Position = 1)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$database,
        [parameter(Mandatory=$true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$username,
        [ValidateNotNullOrEmpty()]
        [string]$password
    )
    #TODO: Sanatise inputs
    Write-Progress "Database: $database" "Granting access to $username"
    Invoke-Sqlcmd -serverInstance $server -database $database -query @"
        IF NOT EXISTS (SELECT 1 FROM master.sys.server_principals WHERE name = N'$username')
        BEGIN
        	if('$password' = N'') BEGIN
        		CREATE LOGIN [$username] FROM WINDOWS WITH DEFAULT_DATABASE=[$database];
            END
        	ELSE BEGIN           
        		CREATE LOGIN [$username] WITH PASSWORD=N'$password', DEFAULT_DATABASE=[$database];
            END
        END
        
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$username') BEGIN
            CREATE USER [$username] FOR LOGIN [$username];
        END
        EXEC sp_addrolemember N'aspnet_Membership_FullAccess', N'$username'
        EXEC sp_addrolemember N'aspnet_Profile_FullAccess', N'$username'
        EXEC sp_addrolemember N'db_datareader', N'$username'
        EXEC sp_addrolemember N'db_datawriter', N'$username'
        EXEC sp_addrolemember N'db_ddladmin', N'$username'
        EXEC sp_addrolemember N'db_securityadmin', N'$username'
"@ 
}

function New-Database {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$name,
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$server = "."
    )
    # need to encode the . used for the local server
    if ($server.StartsWith('.')) {
        $server = "%2e" + $server.SubString(1)
    }
    $db = New-Object Microsoft.SqlServer.Management.SMO.Database
    $db.Parent = get-item (Convert-UrnToPath "Server[@Name='$server']")
    $db.Name = $name
    #TODO: Size correctly
    $db.Create()
}