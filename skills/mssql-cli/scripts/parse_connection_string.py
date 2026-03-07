#!/usr/bin/env python3
"""
Parse a SQL Server connection string into mssql-cli / sqlcmd CLI flags.

Usage:
    python3 parse_connection_string.py "Server=myserver;Database=mydb;User Id=sa;Password=Pass123;"

Output (stdout):
    -S myserver -d mydb -U sa -P 'Pass123'

Supported formats:
    - ADO.NET / SqlClient  (Server=, Database=, User Id=, Password=)
    - ODBC DSN-less        (Driver=...; Server=, UID=, PWD=)
    - Azure SQL            (tcp: prefix, Initial Catalog=, Encrypt=, TrustServerCertificate=)
    - Windows Auth         (Integrated Security=true/sspi → outputs -E instead of -U/-P)
"""

import re
import sys


def _normalize(key: str) -> str:
    return key.strip().lower().replace(" ", "").replace("_", "")


def parse_connection_string(cs: str) -> dict:
    """Return a dict of normalised key → value pairs."""
    pairs = {}
    for segment in cs.rstrip(";").split(";"):
        if "=" not in segment:
            continue
        k, _, v = segment.partition("=")
        pairs[_normalize(k)] = v.strip()
    return pairs


def extract_params(pairs: dict) -> dict:
    """Map normalised keys to canonical param names."""
    alias = {
        "server":                    "server",
        "datasource":                "server",
        "addr":                      "server",
        "address":                   "server",
        "networklibrary":            None,   # ignore
        "database":                  "database",
        "initialcatalog":            "database",
        "userid":                    "user",
        "uid":                       "user",
        "username":                  "user",
        "password":                  "password",
        "pwd":                       "password",
        "integratedsecurity":        "integrated",
        "trustedconnection":         "integrated",
        "encrypt":                   "encrypt",
        "trustservercertificate":    "trust_cert",
        "connectiontimeout":         "timeout",
        "connecttimeout":            "timeout",
    }
    out = {}
    for k, v in pairs.items():
        canonical = alias.get(k)
        if canonical and canonical not in out:
            out[canonical] = v
    return out


def build_flags(params: dict) -> str:
    """Build CLI flag string from extracted params."""
    flags = []

    # Server — strip tcp: prefix added by Azure SQL strings
    server = params.get("server", "")
    server = re.sub(r"^tcp:", "", server, flags=re.IGNORECASE)
    if server:
        flags.append(f"-S {server}")

    # Database
    db = params.get("database", "")
    if db:
        flags.append(f"-d {db}")

    # Authentication
    integrated = params.get("integrated", "").lower()
    if integrated in ("true", "yes", "sspi", "1"):
        flags.append("-E")
    else:
        user = params.get("user", "")
        password = params.get("password", "")
        if user:
            flags.append(f"-U {user}")
        if password:
            # Single-quote to protect special characters in shells
            safe_pwd = password.replace("'", "'\\''")
            flags.append(f"-P '{safe_pwd}'")

    # Encryption
    encrypt = params.get("encrypt", "").lower()
    if encrypt in ("true", "yes", "1"):
        flags.append("-N")

    # Trust server certificate
    trust = params.get("trust_cert", "").lower()
    if trust in ("true", "yes", "1"):
        flags.append("-C")

    # Connection timeout
    timeout = params.get("timeout", "")
    if timeout:
        flags.append(f"-l {timeout}")

    return " ".join(flags)


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_connection_string.py \"<connection string>\"", file=sys.stderr)
        sys.exit(1)

    cs = sys.argv[1]
    pairs = parse_connection_string(cs)
    params = extract_params(pairs)
    print(build_flags(params))


if __name__ == "__main__":
    main()
