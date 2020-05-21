# Import a SQL Server BACPAC Export File to an EXISTING Database Schema
Normally, it's only possible to import a `.bacpac` into a new empty database.

## Prerequisite Stored Procedures
Azure SQL Database lacks two key stored procedures normally found in the master table. There is no master table in an Azure SQL database.<br />
Be sure to change the schemas in the procedure SQL scripts and the import-bacpac.ps1 PowerShell script (`$schema = "dbo"`). As they are, the default schema will be 'dbo'.<br />
Run the two SQL scripts in ./procedures to create `usp_MSforeach_worker` and `usp_MSforeachtable`.

### Usage:

```{PowerShell}
> .\import-bacpac [options]
    -f : The full path of the .bacpac file
    -s : The full database server address
    -c : database name
    -u : SQL auth database username
    -p : SQL auth database password
    -t : if using trusted database connection. Default = TRUE.
    -b : batch size, default=1000
    -a : network packet size, default = 4096
    -e : Exclude tables with Regex expression
```

### Example:
`.\import-bacpac.ps1 -f c:\import\my-export.bacpac -s my-database.database.windows.net -c MyDatabase -u MyUserName -p MyPassword`
