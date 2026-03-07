---
name: mssql-cli
description: Query SQL Server databases from the command line using mssql-cli (or sqlcmd). Use when the user provides a SQL Server connection string and needs to execute queries, explore schema, or run batch SQL scripts against the database. Handles connection string parsing (ADO.NET, ODBC, Azure SQL formats) into CLI flags, query execution, and result capture.
allowed-tools: Bash(mssql-cli:*), Bash(python3:*), Bash(sqlcmd:*)
---

# SQL Server CLI Querying

## Toolchain Note

**mssql-cli** (Python-based) is deprecated but widely installed. **sqlcmd** (Go-based, [go-sqlcmd](https://github.com/microsoft/go-sqlcmd)) is the maintained successor with near-identical flags. Both are covered here — use whichever is available:

```bash
which mssql-cli || which sqlcmd
```

---

## Connection String → CLI Flags

mssql-cli and sqlcmd do **not** accept a full connection string directly. Parse it first using the bundled helper:

```bash
python3 scripts/parse_connection_string.py "Server=myserver;Database=mydb;User Id=sa;Password=Pass123;"
# Outputs: -S myserver -d mydb -U sa -P 'Pass123'
```

Then compose the full command:

```bash
CONN=$(python3 /path/to/skill/scripts/parse_connection_string.py "$CONNECTION_STRING")
mssql-cli $CONN -Q "SELECT @@VERSION"
```

### Common connection string formats

| Format | Example |
|--------|---------|
| ADO.NET | `Server=host;Database=db;User Id=u;Password=p;` |
| ADO.NET (Encrypt) | `Server=host;Database=db;User Id=u;Password=p;Encrypt=yes;TrustServerCertificate=yes;` |
| Azure SQL | `Server=tcp:srv.database.windows.net,1433;Initial Catalog=db;User ID=u;Password=p;Encrypt=True;` |
| ODBC | `Driver={ODBC Driver 18 for SQL Server};Server=host;Database=db;UID=u;PWD=p;` |
| Windows Auth | `Server=host;Database=db;Integrated Security=true;` |

---

## Key Connection Flags

```
-S   Server host[,port]           e.g. localhost  or  srv.database.windows.net,1433
-d   Database name
-U   Username (SQL Auth)
-P   Password (or set MSSQL_CLI_PASSWORD env var)
-E   Windows Integrated Authentication (skip -U/-P)
-N   Force SSL/TLS encryption
-C   Trust server certificate (required for self-signed certs)
-l   Connect timeout in seconds   e.g. -l 30
```

---

## Executing Queries

### Single inline query
```bash
mssql-cli -S localhost -d mydb -U sa -P 'Pass123' -Q "SELECT TOP 10 * FROM Orders"
```

### From a SQL file
```bash
mssql-cli -S localhost -d mydb -U sa -P 'Pass123' -i migration.sql
```

### Capture output to file
```bash
mssql-cli -S localhost -d mydb -U sa -P 'Pass123' -Q "SELECT * FROM sys.tables" -o tables.txt
```

### Suppress welcome/goodbye banner
```bash
mssql-cli ... --less-chatty -Q "SELECT 1"
```

### Check exit code (for scripting)
```bash
mssql-cli ... -Q "SELECT 1" && echo "OK" || echo "FAILED"
```

---

## Schema Exploration

### Via system views (scriptable — preferred)
```bash
# List all tables
mssql-cli $CONN -Q "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME"

# Describe a table's columns
mssql-cli $CONN -Q "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='Orders' ORDER BY ORDINAL_POSITION"

# List stored procedures
mssql-cli $CONN -Q "SELECT ROUTINE_SCHEMA, ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE='PROCEDURE'"

# Row counts for all tables
mssql-cli $CONN -Q "SELECT t.name, p.rows FROM sys.tables t JOIN sys.partitions p ON t.object_id=p.object_id WHERE p.index_id IN (0,1) ORDER BY p.rows DESC"
```

### Interactive meta-commands (mssql-cli only)
```
\dt [pattern]    List tables matching pattern
\dv [pattern]    List views
\di [pattern]    List indexes
\df [pattern]    List functions
\dn              List schemas
\d TableName     Describe table (calls sp_help)
```

---

## Azure SQL Specifics

Azure SQL requires encryption and often certificate trust:

```bash
mssql-cli -S "tcp:myserver.database.windows.net,1433" -d mydb -U "user@myserver" -P 'pass' -N -C -Q "SELECT @@VERSION"
```

Or parsed from an Azure connection string:
```bash
CONN=$(python3 /path/to/skill/scripts/parse_connection_string.py "$AZURE_CONN_STR")
mssql-cli $CONN -Q "SELECT @@VERSION"
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| SSL / certificate error | Add `-C` (trust server cert) |
| Connection refused | Verify port: `-S "host,1433"` |
| Timeout | Add `-l 60` |
| Password with special chars | Wrap in single quotes or use `MSSQL_CLI_PASSWORD` env var |
| Azure "Login failed" | Use FQDN (`server.database.windows.net`), add `-N -C` |
| `mssql-cli not found` | Fall back to `sqlcmd`; same flags apply |

---

## sqlcmd (Go) — Drop-in Alternative

The Go-based `sqlcmd` uses the same core flags (`-S`, `-d`, `-U`, `-P`, `-Q`, `-i`, `-o`). Use it when mssql-cli is unavailable or for production pipelines:

```bash
sqlcmd -S localhost -d mydb -U sa -P 'Pass123' -Q "SELECT @@VERSION"
```

Additional sqlcmd-specific flags:
```
-b   Abort batch on error (like sqlcmd classic)
-r   Redirect error messages to stderr
```

---

## Bundled Script

See [scripts/parse_connection_string.py](scripts/parse_connection_string.py) — call with a connection string, outputs ready-to-use mssql-cli flags. Handles ADO.NET, ODBC, and Azure SQL string formats.
