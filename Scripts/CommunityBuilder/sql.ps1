Set-StrictMode -Version 2

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
		[ValidateNotNullOrEmpty()]
        [string]$Server,
        [parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
        [string]$Database,
        [parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
        [string]$Table
    )

    if ($Database) {
        $Database = Encode-SqlName $Database
    }

    $parts = $Server.Split('\');
    $hostName = Encode-SqlName $parts[0];
    $instance = if ($parts.Count -eq 1) {'DEFAULT'} else { Encode-SqlName $parts[1] }

    #Test-Path will only fail after a timeout.  Reduce the timeout for the local scope to 
    Set-Variable -Scope Local -Name SqlServerConnectionTimeout 5
    $path = "SQLSERVER:\Sql\$hostName\$instance"

    if (!(Test-Path $path -EA SilentlyContinue)) {
        throw "Unable to connect to SQL Instance '$Server'"
        return
    }
    elseif ($Database) {
        $path = Join-Path $path "Databases\$Database"

        if (!(Test-Path $path -EA SilentlyContinue)) {
            throw "Database '$Database' does not exist on server '$Server'"
            return
        }
        elseif($Table)
        {
            $parts = $Table.Split('.');
            if ($parts.Count -eq 1) {
                $Table = "dbo.$Table"
            }
            $path = Join-Path $path "Tables\$Table"

            if (!(Test-Path $path -EA SilentlyContinue)) {
                throw "Table '$Table' does not exist in database '$Database' does not exist on server '$Server'"
                return
            }
        }
    }
    $true
}

function New-CommunityDatabase {
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

    $connectionInfo = @{
        ServerInstance = $Server
        Database = $database
    }

    #TODO: Check if DB exists first
    Write-Progress "Database: $Database" 'Checking if database exists'
    if(!(Test-SqlServer -Server $Server -Database $Database -EA SilentlyContinue)) {
        Write-Progress "Database: $Database" 'Creating database'
        New-Database @connectionInfo
    }
    
    Write-Progress "Database: $database" 'Creating Schema'
    $tempDir = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ([guid]::NewGuid())
    Expand-Zip -Path $package -Destination $tempDir -ZipDirectory SqlScripts -ZipFile cs_CreateFullDatabase.sql
    $sqlScript = Join-Path $tempDir cs_CreateFullDatabase.sql | Resolve-Path

    Write-ProgressFromVerbose "Database: $database" 'Creating Schema' {
        Invoke-Sqlcmd @connectionInfo -InputFile $sqlScript -QueryTimeout 6000 -DisableVariables
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
                , @CreateSamples = 0
"@

    Write-ProgressFromVerbose "Database: $database" 'Creating Community' {
        Invoke-Sqlcmd @connectionInfo -query $createCommunityQuery -DisableVariables
    }
}

function Update-CommunityDatabase {
	<#
	.SYNOPSIS
        Updates an existing Telligent Evolution database to upgrade it to the version in the package
	.PARAMETER Server
		The SQL server to install the community to 
	.PARAMETER  Database
		The name of the database to install the community to
	.PARAMETER  Package
		The installation package to create the community database from
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
        [string]$Package
    )

	$connectionInfo = @{
		Server = $Server
		Database = $Database
	}

    Write-Progress "Database: $Database" 'Checking if database can be upgraded'
    if(!(Test-SqlServer @connectionInfo -Table dbo.cs_schemaversion -EA SilentlyContinue)) {
        throw "Database '$Database' on Server '$Server' is not a valid Telligent Evolution database to be upgraded"
    }
    
    Write-Progress "Database: $database" 'Creating Schema'
    $tempDir = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) ([guid]::NewGuid())
    Expand-Zip -Path $package -Destination $tempDir -ZipDirectory SqlScripts -ZipFile cs_UpdateSchemaAndProcedures.sql
    $sqlScript = Join-Path $tempDir cs_UpdateSchemaAndProcedures.sql | Resolve-Path

    Write-ProgressFromVerbose "Database: $Database" 'Upgrading Schema' {
        Invoke-Sqlcmd @connectionInfo -InputFile $sqlScript -QueryTimeout 6000 -DisableVariables
    }
    Remove-Item $tempDir -Recurse -Force | out-null
}

function Grant-CommunityDatabaseAccess {
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
		Grant-CommunityDatabaseAccess (local)\SqlExpress SampleCommunity 'NT AUTHORITY\NETWORK SERVICE'

		Description
		-----------
		This command grant access to the SampleCommunity database on the SqlExpress instance of the local SQL server
		for the Network Service Windows account
	.EXAMPLE
		Grant-CommunityDatabaseAccess ServerName SampleCommunity CommunityUser -password SqlPa$$w0rd
		
		Description
		-----------
		This command grant access to the SampleCommunity database on the default instance of the ServerName SQL server
		for the CommunityUser SQL account. If this login does not exist, it gets created using the password SqlPa$$w0rd

	#>
	[CmdletBinding()]
    param(
    	[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-CommunityPath $_ })]
        [string]$CommunityPath,
        [parameter(Mandatory=$true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,
        [string]$Password
    )
    $info = Get-Community $CommunityPath

    #TODO: Sanatise inputs
    Write-Verbose "Granting database access to $Username"

    if ($Password) {
        $CreateLogin = "CREATE LOGIN [$Username] WITH PASSWORD=N'$Password', DEFAULT_DATABASE=[$($info.DatabaseName)];"
    }
    else {
        $CreateLogin = "CREATE LOGIN [$Username] FROM WINDOWS WITH DEFAULT_DATABASE=[$($info.DatabaseName)];"
    }

    $query = @"
        IF NOT EXISTS (SELECT 1 FROM master.sys.server_principals WHERE name = N'$Username')
        BEGIN
            $CreateLogin
        END;
        
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$Username') BEGIN
            CREATE USER [$Username] FOR LOGIN [$Username];
        END;
        EXEC sp_addrolemember N'aspnet_Membership_FullAccess', N'$Username';
        EXEC sp_addrolemember N'aspnet_Profile_FullAccess', N'$Username';
        EXEC sp_addrolemember N'db_datareader', N'$Username';
        EXEC sp_addrolemember N'db_datawriter', N'$Username';
        EXEC sp_addrolemember N'db_ddladmin', N'$Username';
"@ 

    Invoke-SqlcmdAgainstCommunity -WebsitePath $CommunityPath -Query $query
}

function Invoke-SqlCmdAgainstCommunity {
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

    Invoke-Sqlcmd @sqlParams -DisableVariables
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
		[alias('Database')]
        [string]$Name,
        [ValidateNotNullOrEmpty()]
		[alias('ServerInstance')]
        [string]$Server = "."
    )
    $safeDbName = Encode-SqlName $Name
    $query = "Create Database [$(Encode-SqlName $NAME)]";
    Invoke-Sqlcmd -ServerInstance $Server -Query $query
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