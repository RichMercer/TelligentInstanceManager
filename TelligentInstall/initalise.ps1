Set-StrictMode -Version 2

#Undo SQLPs's forcing the SqlServer drive
if((get-location).Provider.Name -eq 'SqlServer') {
    get-location -PSProvider FileSystem | Set-Location
}

