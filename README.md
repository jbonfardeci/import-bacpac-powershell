# Import a SQL Server BACPAC Export File to an EXISTING Database Schema
Normally, it's only possible to import a `.bacpac` into a new empty database.

## How it Works
A .bacpac file is really a .zip archive. The PowerShell script can read the ZIP file directory without unzipping the archive. Each data table folder in the ZIP is temporarily extracted, one at a time, and its data inserted into the target table via the BCP utility included with SSMS and SQL Server installations. 

## Prerequisite Stored Procedures
Azure SQL Database lacks two key stored procedures normally found in the master table. There is no master table in an Azure SQL database.<br />
Be sure to change the schemas in the procedure SQL scripts and the import-bacpac.ps1 PowerShell script (`$schema = "dbo"`). As they are, the default schema will be 'dbo'.<br />
Run the two SQL scripts in ./procedures to create `usp_MSforeach_worker` and `usp_MSforeachtable`. These procedures are used to temporarily turn off table constraints and set ` IDENTITY_INSERT ON/OFF`, which allows the insertion of primary keys into the target tables.

Thanks to https://gist.github.com/metaskills/893599 for these missing procedures in Azure SQL Server.

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

### Example with SQL Authentication:
`.\import-bacpac.ps1 -f c:\import\my-export.bacpac -s my-database.database.windows.net -c MyDatabase -u MyUserName -p MyPassword`

### Example with Trusted Connection:
`.\import-bacpac.ps1 -f c:\import\my-export.bacpac -s my-database.database.windows.net -c MyDatabase -t true`

### Change Transaction Batch Size:
`.\import-bacpac.ps1 -f c:\import\my-export.bacpac -s my-database.database.windows.net -c MyDatabase -t true -b 10000`

### Skip Tables with Regex
`.\import-bacpac.ps1 -f c:\import\my-export.bacpac -s my-database.database.windows.net -c MyDatabase -t true -e "^test_"`
