# Telligent Instance Manager
Powershell Scripts to automate the installation of Telligent Community on a local machine.

## Requirements
* IIS 7.5 (or Higher)
* Powershell 5
* Java 8 (or higher)
* Tomcat 8 
* SQL Server 2016 (or higher)

## Installation

The easiest way to install from the powershell gallery.  To do this run the following 3 commands.

```powershell
Set-ExecutionPolicy RemoteSigned
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
Install-Module -Name TelligentLocalInstance
Initialize-TelligentInstanceManager -InstallDirectory [Path to install]
```
We recommend that the path you install to is high up on your file system (e.g. `c:\TelligentInstances`) - if you install to a deep directory, you may encounter issues within Telligent Community due to Window's MAX_PATH length.

If you want to run from source instead of the powershell gallery, replace the second command with cloning this repo, and adding the repo path to the `PSModulePath` environment variable.

### Packages

After installation, you will need to place a Telligent Community zip package in the `TelligentPackages` folder in the install location. You can add as many packages as versions you want to support. 

### Licenses

License files can be added to the Licenses folder to allow the installer to add the lincese during the install process. The files should be named `Community[Version].xml` with `[Version]` being the product major version number e.g. `Community10.xml` for Telligent Community 10.

### Installation Problems

`The term Install-Module is not recognized...` - You're probably running powershell v1 or v2.  Upgrade to [Powershell 5](https://www.microsoft.com/en-us/download/details.aspx?id=50395)

## Usage

#### To install an instance

```powershell
Get-TelligentVersion [Version] | Install-TelligentInstance [Name]
```

Installs a Telligent Instance on your local machine. Replace `[Version]` with the required version number of Telligent Community e.g. 9 (will use the latest build of Telligent Community available in TelligentPackages) or a specific point release or build  e.g 9.1 or 9.1.0.792 and `[Name]` with the name and URL of the site e.g. demo.local. This is the URL the site will be accessible at in IIS.

Example: `Get-TelligentVersion 9 | Install-TelligentInstance demo.local` 

#### To delete an instance
```powershell
Remove-TelligentInstance
```

Deletes an instance of Telligent Community currently installed. Accepts piped parameter from `Get-TelligentInstance -Name [Instance Name]`

Example: `Get-TelligentInstance example.local | Remove-TelligentInstance`
