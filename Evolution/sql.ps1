
function Install-EvolutionDatabase {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$server,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
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
    Invoke-Sqlcmd -serverinstance $server -Database $database -InputFile $sqlScript -QueryTimeout 6000 |out-null
    #TODO: Cleanup temp

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
"@       |out-null
}

function Grant-EvolutionDatabaseAccess {
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$server,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$database,
        [parameter(Mandatory=$true)]
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
        [string]$name,
        [ValidateNotNullOrEmpty()]
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