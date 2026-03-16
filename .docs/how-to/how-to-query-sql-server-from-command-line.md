---
category: how-to
---

# How to Query SQL Server from the Command Line

This guide shows how to choose between `sqlcmd` and `mssql-cli`, verify the binary you need, and run a simple SQL Server query from the command line.

## When to Use This Guide

Use this when you need to:

- connect to SQL Server from a terminal
- decide whether `sqlcmd` or `mssql-cli` is the better fit
- verify local installation before automating queries

## Choose the Right Tool

- Use `sqlcmd` for normal query execution and automation.
- Use `mssql-cli` only when you specifically need its interactive meta-commands.

## Steps

### 1. Check which binary is available

Windows PowerShell:

```powershell
Get-Command sqlcmd -ErrorAction SilentlyContinue
Get-Command mssql-cli -ErrorAction SilentlyContinue
```

WSL or Linux:

```bash
command -v sqlcmd || command -v mssql-cli
```

### 2. Install `sqlcmd` if neither binary exists

Windows:

```powershell
winget install sqlcmd
```

WSL or Linux with Homebrew:

```bash
brew install sqlcmd
```

If you need the Microsoft ODBC-based tooling instead, follow the current Microsoft Learn instructions for `mssql-tools18`.

### 3. Run a query

Using `sqlcmd`:

```bash
sqlcmd -S <server> -d <database> -U <user> -P <password> -Q "SELECT @@VERSION"
```

Using `mssql-cli`:

```bash
mssql-cli -S <server> -d <database> -U <user> -P <password> -Q "SELECT @@VERSION"
```

### 4. Prefer environment variables for sensitive values

If your workflow allows it, prefer environment variables or secure credential storage over inlining passwords directly in shell history.

## Troubleshooting

**Problem: `mssql-cli` is missing**

Prefer `sqlcmd`. Install `mssql-cli` only if you specifically depend on its interactive commands.

**Problem: Azure SQL login fails**

Use the fully qualified server name and the TLS flags required by your environment.

## See Also

- [skills/mssql-cli/SKILL.md](../../skills/mssql-cli/SKILL.md)
- [Microsoft Learn SQL Server tooling docs](https://learn.microsoft.com/sql/tools/)

