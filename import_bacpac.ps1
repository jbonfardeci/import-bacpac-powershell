<#
    Imports a .bacpac file to an EXISTING database. 
    NOTE: The database schema must already be in place before running this script!

    Author: John Bonfardeci
    Created: 2019-12-04
    Modified: 2019-12-09

    Required Dependencies: BCP and SQLCMD utilities (normally included with SQL Server and SSMS installations)

    References:
    BCP: https://docs.microsoft.com/en-us/sql/tools/bcp-utility?view=sql-server-ver15
    SQLCMD: https://docs.microsoft.com/en-us/sql/tools/sqlcmd-utility?view=sql-server-ver15

    -f : The full path of the .bacpac file
    -s : The full database server address
    -c : database name
    -u : SQL auth database username
    -p : SQL auth database password
    -t : if using trusted database connection. Default = TRUE.
    -b : batch size, default=1000
    -a : network packet size, default = 4096
    -e : Exclude tables with Regex expression;
#>

# Load .NET Zip classes.
Add-Type -AssemblyName System.IO.Compression.FileSystem;

function create_folder($path){
    if(-not (Test-Path -Path $path)){
        New-Item -Path $path -ItemType Directory -Force;
    }
}

function delete_folder($path){
    if((Test-Path -Path $path)){
        Remove-Item -Path $path -Recurse -Force;
    }
}

function delete_file($path){
    Remove-Item -Path $path -Force;
}

function table_exists($tablename){
    $sqlcmd_parms[1] = "SELECT TOP 1 0 FROM $tablename";

    $res = & "sqlcmd" $sqlcmd_parms;
 
    if($res[1].ToString().Contains("Invalid")){
        return $false;
    }
    return $true;
}

function execute_sql($query){
    $sqlcmd_parms[1] = $query;

    $res = (& "sqlcmd" $sqlcmd_parms);

    foreach($m in $res){
        if($m.ToString() -match "Error"){
            return $m.ToString();
        }
    }

    return "Success";
}

function truncate_table($tablename){
    # TRUNCATE TABLE will not work when there are FK constraints.
    # Must DELETE FROM TABLE, then reset ID seed.
    # Then disable the Identity column if it has one.
    $query = "DELETE FROM $tablename;
    
    IF (OBJECTPROPERTY(OBJECT_ID('$tablename'), 'TableHasIdentity') = 1) 
    BEGIN
		DBCC CHECKIDENT('$tablename', reseed, 1);
    END";
    
    $res = execute_sql $query;

    if($res -match "^DBCC execution completed"){
        return "Success";
    }
    return $res;
}

function set_identity_on($tablename){
    $query = "IF (OBJECTPROPERTY(OBJECT_ID('$tablename'), 'TableHasIdentity') = 1) 
    BEGIN
        SET IDENTITY_INSERT $tablename ON;
    END";
    return execute_sql $query;
}

function set_identity_off($tablename){
    $query = "IF (OBJECTPROPERTY(OBJECT_ID('$tablename'), 'TableHasIdentity') = 1) 
    BEGIN
        SET IDENTITY_INSERT $tablename OFF;
    END";
    return execute_sql $query;
}

function disable_db_constraints(){
    write-host "Disabling database PK/FK constraints...";
    # https://gist.github.com/metaskills/893599
    return execute_sql "EXEC $schema.usp_MSforeachtable 'ALTER TABLE ? NOCHECK CONSTRAINT all'";
}

function enable_db_constraints(){
    write-host "Re-enabling database PK/FK constraints...";
    # https://gist.github.com/metaskills/893599
    return execute_sql "EXEC $schema.usp_MSforeachtable 'ALTER TABLE ? WITH CHECK CHECK CONSTRAINT all'";
}

function get_bcp_error($messages){
    foreach($m in $messages){
        if($m.ToString().Contains("Error")){
            return $m.ToString();
        }
    }
    return $null;
}

function get_bcp_rows_copied($messages){
    $rx = "^\d+ rows copied.";

    foreach($m in $messages){
        if($m -match $rx){
            $num = $m -replace "[^0-9]", "";
            return $num/1;
        }
    }
    return 0;
}

function get_table_name($bcp_path){
    $tmp = $bcp_path.Split("/");
    return $tmp[1];
}

function get_next_table($files, $i){
    $next = $i+1;
    if($files.Length -eq $i+1){
       $next = $i;
    }

    return get_table_name $files[$next].FullName;
}

function unzip_file($file, $path){
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($file, $path, $true);
}

$max_packet_size = 65535;
$max_batch_size = 100000;
$schema = "dbo";

$conf = @{

    packet_size = $max_packet_size; # Max packet size is 65535. Default will be used if not posible.
    batch_size = $max_batch_size; # Batch size - how many rows to import at a time. Default is 1000.

    exclude_regex = "";

    exclude_tables = @();

    # Full path to the .bacpac file.
    bacpac_file = "";

    server = "";
    dbname = "";

    # Set if not using trusted connection.
    username = ""; 
    pwd = "";

    # True ($true) if using current AD account as DB credentials, False ($false) if logging in with username and password.
    is_trusted_conn = $true; 
}


# Parse command line arguments.
for($i=0; $i -lt $args.Length; $i++){
    $arg = $args[$i];
    $next_arg = $args[$i+1];

    switch($arg){
        "-f" { 
            $conf.bacpac_file = $next_arg; 
        }
        "-s" { 
            $conf.server = $next_arg; 
        }
        "-c" { 
            $conf.dbname = $next_arg; 
        }
        "-u" { 
            $conf.username = $next_arg;
            $conf.is_trusted_conn = $false;
        }
        "-p" { 
            $conf.pwd = $next_arg;
            $conf.is_trusted_conn = $false;
        }
        "-t" { 
            $conf.is_trusted_conn = $true;
            if($conf.username.Length -gt 0 -or $conf.pwd.Length -gt 0){
                write-error "Warning: setting trusted connection will override SQL authentication with username and password.";
            }
        }
        "-b" { 
            $conf.batch_size = $next_arg/1;
            if($conf.batch_size -gt $max_batch_size){
                write-error "Warning: it is not recommended to import batch sizes greater than $max_batch_size rows at a time.";
            } 
        }
        "-a" { 
            $conf.packet_size = $next_arg/1; 
            if($conf.packet_size -gt $max_packet_size){
                $conf.packet_size = $max_packet_size;
                write-error "Warning: the maximum packet size is $max_packet_size. This will be used.";
            }
        }
        "-e" {
            $conf.exclude_regex = $next_arg.ToString();
        }
    }
}

if($conf.bacpac_file.Length -eq 0){
    throw 'Error: The full path to the .bacpac file (-f) is required.';
}
elseif($conf.server.Length -eq 0){
    throw 'Error: The server name (-s) is required.';
}
elseif($conf.dbname.Length -eq 0){
    throw 'Error: The database name (-c) is required.';
}
elseif(-not $conf.is_trusted_conn -and ($conf.username.Length -eq 0 -or $conf.pwd.Length -eq 0) ){
	throw 'Error: SQL auth username (-u) and password (-p) are required if not using trusted connection (-t).';
}


$exclude_tables = @();
$paths = $null;
$bacpac_file = Get-ChildItem -Path $conf.bacpac_file;
$dir = $bacpac_file.Directory.FullName;
$bcp_import_log = Join-Path -Path $dir -ChildPath 'bcp_import_log.csv';
$bcp_csv_content = "";

# Location of the unzipped bacpac folder.
$root = Join-Path -Path $dir -ChildPath 'bacpac_temp';
create_folder $root;

# Setup import CSV log.
# Exclude tables that we already imported.
if((Test-Path $bcp_import_log)){
    $csv = Import-Csv $bcp_import_log;

    for($i = 0; $i -lt $csv.Length; $i++){
        $row = $csv[$i];
        if($row.Success -eq 1){
            $exclude_tables += @($row.TableName);
        }
    }
}
else{
    Set-Content -Path $bcp_import_log -Value "TableName,Success,RowsCopied,Error";
}

# BCP params.
$parms = @("<tablename>", "in", "<filename.bcp>", "-S", $conf.server, "-d", $conf.dbname, "-N", "-a", $conf.packet_size, "-b", $conf.batch_size, "-E");


# SQLCMD params.
$sqlcmd_parms = @("-Q", "<query>", "-S", $conf.server, "-d", $conf.dbname, "-b");

# Set BCP and SQLCMD logins.
$login = @("-T");
$sqlcmd_login = @("-E");

if($conf.is_trusted_conn -eq $false){
    $login = $sqlcmd_login = @("-U", $conf.username, "-P", $conf.pwd);
}

$parms = $parms + $login;
$sqlcmd_parms = $sqlcmd_parms + $sqlcmd_login;
$has_error = $false;
$ct = 0;
$tables = @();
if($conf.exclude_regex.Length -gt 0){
    $rx = $conf.exclude_regex -replace "\^", "";
    if(-not $rx.StartsWith("^Data/")){
        $rx = "^Data/" + $rx;
    }
}
$tmp = "";

disable_db_constraints;

$files = [System.IO.Compression.ZipFile]::OpenRead($bacpac_file).Entries | Where-Object { `
    ($_.FullName -match "^Data/") `
     -and ($_.Name -match ".bcp$") `
     -and -not ($rx.Length -gt 0 -and $_.FullName -match $rx) `
     -and ($exclude_tables.IndexOf($_.Name) -lt 0) `
     -and ($tables.indexOf($tablename) -lt 0) `
} | Sort-Object $_.FullName;
 
for($i=0; $i -lt $files.Length; $i++) {

    $file = $files[$i];

    # Read all table folders.
    $filename = $file.Name;
    $bcp_path = $file.FullName;
    $tablename = get_table_name $bcp_path;

    if($tmp -ne $tablename){
        $rows_copied = 0;

        $exists = table_exists $tablename;

        if(-not $exists){
            continue;
        }

        write-host "Importing $tablename...";

        # Exexute truncate table with sqlcmd.
        $sql_res = truncate_table $tablename;
        if($sql_res -ne "Success"){
            $bcp_csv_content += "`r`n$tablename,0,$rows_copied,""$sql_res""";
            continue;
        }

        $sql_res = set_identity_on $tablename;
        if($sql_res -ne "Success"){
            $bcp_csv_content += "`r`n$tablename,0,$rows_copied,""$sql_res""";
            continue;
        }
    }

    # Extract bcp to temp file for BCP import.
    $temp_path = Join-Path -Path $root -ChildPath $filename;
    unzip_file $file $temp_path;

    # Execute Bulk Copy Program utility (bcp).
    $parms[0] = $tablename;
    $parms[2] = $temp_path;
    $res = & "bcp" $parms;

    write-host $res;

    $rows_copied += get_bcp_rows_copied $res;

    $err = get_bcp_error $res;
    if($err -ne $null){
        $bcp_csv_content += "`r`n$tablename,0,$rows_copied,""$err""";
        $has_error = $true;
        Write-Error "Error importing $tablename.$filename. $err";
    }

    # Delete tmp file.
    delete_file $temp_path;

    # Wrap up table results and actions.
    $next_table = get_next_table $files $i;

    if($next_table -ne $tablename -or $files.Length -eq $i+1){           
        $sql_res = set_identity_off $tablename;
        if($sql_res -ne "Success"){
            $bcp_csv_content += "`r`n$tablename,0,$rows_copied,""$sql_res""";
            continue;
        }
        else{
            $bcp_csv_content += "`r`n$tablename,1,$rows_copied,";
        }
    }

    $tmp = $tablename;
}

enable_db_constraints

delete_folder $root;

# Append CSV import log.
$csv_content = Get-Content -Path $bcp_import_log;
$csv_content += $bcp_csv_content;
Set-Content -Path $bcp_import_log -Value ($csv_content -replace "(^\r\n|\r\n$)", "");
