function Test-SqlServer {
    <#
    .SYNOPSIS
        Tests if a SQL Server exists and can be connected to
    .PARAMETER Server
        The SQL Server to test
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Server
    )
    $parts = $Server.Split('\');
    $hostName = Encode-SqlName $parts[0];
    $instance = if ($parts.Count -eq 1) {'DEFAULT'} else { Encode-SqlName $parts[1] }

    #Test-Path will only fail after a timeout.  Reduce the timeout for the local scope to 
    try {
        Set-Variable -Scope Local -Name SqlServerConnectionTimeout 5
        $srv = Test-Path SQLSERVER:\Sql\$hostName\$instance
    }
    catch {}

    if ($srv) {
        $true
    }
    else {
        throw "Unable to connect to SQL Instance '$Server'"
    }    
}

function Install-EvolutionDatabase {
	<#
	.SYNOPSIS
		Grants a user access to an Evolution database.  If the user or login doesn't exist, in SQL server, they
		are created before being granted access to the database.
	.PARAMETER Server
		The SQL server to install the community to 
	.PARAMETER  Database
		The name of the database to install the community to
	.PARAMETER  Package
		The installation package to create the community database from
	.PARAMETER  WebDomain
		The domain the community is being hosted at
	.PARAMETER  AdminPassword
		The password to create the admin user with.
	#>
	[CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-SqlServer $_ })]
        [alias('ServerInstance')]
        [alias('DataSource')]
		[alias('dbServer')]
        [string]$Server,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [alias('InitialCatalog')]
        [string]$Database,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[ValidateScript({Test-Zip $_ })]
        [string]$Package,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$WebDomain,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
		[string]$AdminPassword
    )

    #TODO: Check if DB exists first
    Write-Progress "Database: $Database" 'Checking if database exists'
    if($true) {
        Write-Progress "Database: $Database" 'Creating database'
        New-Database -Name $Database -Server $Server
    }
    
    Write-Progress "Database: $database" 'Creating Schema'
    $tempDir = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ([guid]::NewGuid())
    Expand-Zip -Path $package -Destination $tempDir -ZipDirectory SqlScripts -ZipFile cs_CreateFullDatabase.sql
    $sqlScript = Join-Path $tempDir cs_CreateFullDatabase.sql | Resolve-Path

    $connectionInfo = @{
        ServerInstance = $Server
        Database = $database
    }
    Write-ProgressFromVerbose "Database: $database" 'Creating Schema' {
        Invoke-Sqlcmd @connectionInfo -InputFile $sqlScript -QueryTimeout 6000
    }
    Remove-Item $tempDir -Recurse -Force | out-null

    $createCommunityQuery = @"
         EXECUTE [dbo].[cs_system_CreateCommunity]
                @SiteUrl = N'http://${WebDomain}/'
                , @ApplicationName = N'$Name'
                , @AdminEmail = N'notset@${WebDomain}'
                , @AdminUserName = N'admin'
                , @AdminPassword = N'$adminPassword'
                , @PasswordFormat = 0
                , @CreateSamples = 1
"@

    Write-ProgressFromVerbose "Database: $database" 'Creating Community' {
        Invoke-Sqlcmd @connectionInfo -query $createCommunityQuery
    }
}

function Grant-EvolutionDatabaseAccess {
	<#
	.SYNOPSIS
		Grants a user access to an Evolution database.  If the user or login doesn't exist, in SQL server, they
		are created before being granted access to the database.
	.PARAMETER  Server
		The SQL server the database is contained on
	.PARAMETER  Database
		The name of the database
	.PARAMETER  Username
		The name of the user to grant access to.  If no password is specified, the user is assumed to be a Windows
		login.
	.PARAMETER  Password
		The password for the SQL user
	.EXAMPLE
		Grant-EvolutionDatabaseAccess (local)\SqlExpress SampleCommunity 'NT AUTHORITY\NETWORK SERVICE'

		Description
		-----------
		This command grant access to the SampleCommunity database on the SqlExpress instance of the local SQL server
		for the Network Service Windows account
	.EXAMPLE
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
        [alias('ServerInstance')]
        [alias('DataSource')]
        [alias('dbServer')]
        [string]$Server,
        [parameter(Mandatory=$true, Position = 1)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [alias('InitialCatalog')]
        [string]$Database,
        [parameter(Mandatory=$true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )
    #TODO: Sanatise inputs
    Write-Progress "Database: $Database" "Granting access to $Username"
    Invoke-Sqlcmd -serverInstance $Server -database $Database -query @"
        IF NOT EXISTS (SELECT 1 FROM master.sys.server_principals WHERE name = N'$Username')
        BEGIN
        	if('$Password' = N'') BEGIN
        		CREATE LOGIN [$Username] FROM WINDOWS WITH DEFAULT_DATABASE=[$Database];
            END
        	ELSE BEGIN           
        		CREATE LOGIN [$Username] WITH PASSWORD=N'$Password', DEFAULT_DATABASE=[$Database];
            END
        END
        
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$Username') BEGIN
            CREATE USER [$Username] FOR LOGIN [$Username];
        END
        EXEC sp_addrolemember N'aspnet_Membership_FullAccess', N'$Username'
        EXEC sp_addrolemember N'aspnet_Profile_FullAccess', N'$Username'
        EXEC sp_addrolemember N'db_datareader', N'$Username'
        EXEC sp_addrolemember N'db_datawriter', N'$Username'
        EXEC sp_addrolemember N'db_ddladmin', N'$Username'
"@ 
}

function Invoke-SqlCommandAgainstCommunity {
	<#
	.SYNOPSIS
		Executes a SQL Script agains the specified community's database.
    .PARAMETER WebsitePath
        The path of the Telligent Evolution Community website.  If not specified, defaults to the current directory.
    .PARAMETER Query
        A bespoke query to run agains the community's database.
    .PARAMETER File
        A script in an external file run agains the community's database.
    .PARAMETER QueryTimeout
        The maximum length of time the query can run for 
	#>
    param (
		[Parameter(Mandatory=$true, Position=0)]
        [ValidateScript({ Test-CommunityPath $_ -Web })]
        [string]$WebsitePath,

		[Parameter(ParameterSetName='Query', Mandatory=$true)]
        [string]$Query,

		[Parameter(ParameterSetName='File', Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$File,
        [int]$QueryTimeout
    )    
    $info = Get-Community $WebsitePath

    $sqlParams = @{
        ServerInstance = $info.DatabaseServer
        Database = $info.DatabaseName
    }
    if ($Query) {
        $sqlParams.Query = $Query
    }
    else {
        $sqlParams.InputFile = $File
    }
    if ($QueryTimeout) {
        $sqlParams.QueryTimeout = $QueryTimeout
    }

    Invoke-Sqlcmd @sqlParams
}

function New-Database {
    <#
    .SYNOPSIS
        Creates a new SQL Database
    .PARAMETER Database
        The name of the database to create
    .PARAMETER Server
        The server to create the database on
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$Name,
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$Server = "."
    )
    # need to encode the . used for the local server
    if ($Server.StartsWith('.')) {
        $Server = "%2e" + $server.SubString(1)
    }
    $db = New-Object Microsoft.SqlServer.Management.SMO.Database
    $db.Parent = get-item (Convert-UrnToPath "Server[@Name='$Server']")
    $db.Name = $Name
    #TODO: Size correctly
    $db.Create()
}

function Remove-Database {
    <#
    .SYNOPSIS
        Drops a SQL Database
    .PARAMETER Database
        The name of the database to drop
    .PARAMETER Server
        The server to drop the database from
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
		[alias('dbName')]
        [string]$Database,
        [ValidateNotNullOrEmpty()]
		[alias('dbServer')]
        [string]$Server = "."
    )
    $srv = New-Object Microsoft.SqlServer.Management.SMO.Server($Server)

    if($srv.Databases[$Database]){
        $srv.KillDatabase($Database)
    }
}