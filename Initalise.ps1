$env:PSModulePath +=  ";$env:TelligentPowershell"
pushd
$modules = @('webadministration', 'sqlps', 'activedirectory', 'DistributedCacheAdministration', 'Evolution' , 'Support')
(0..($modules.length - 1)) |% -ErrorAction "Stop" {
	Write-Progress -Activity "Loading Support Evolution Installation Module" -Status "Importing Dependant Modules" -CurrentOperation $modules[$_] -Id 172 -Percent ($_ /$modules.Length * 100)
	ipmo $modules[$_] -DisableNameChecking 
}
popd