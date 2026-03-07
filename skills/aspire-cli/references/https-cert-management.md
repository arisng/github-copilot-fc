# Aspire HTTPS certificate management

## Automatic behavior

`aspire run` automatically installs and verifies local hosting certificates. No manual action is typically needed.

## Manual trust commands

```bash
# Check status
dotnet dev-certs https --check

# Trust (first-time or after reset)
dotnet dev-certs https --trust

# Clean and re-trust (when expired or invalid)
dotnet dev-certs https --clean
dotnet dev-certs https --trust

# Verbose check
dotnet dev-certs https --check --verbose
```

## Platform notes

**Windows**: Certificate stored in Current User > Personal > Certificates. Admin elevation may be required on first trust.

**macOS**: Added to Keychain Access > login > Certificates. Requires password prompt for keychain access.

**Linux**: Location varies by distro. Firefox uses its own store: Settings > Privacy & Security > View Certificates > Authorities > Import.

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Your connection is not private" | Certificate not trusted | `dotnet dev-certs https --trust` |
| `NET::ERR_CERT_AUTHORITY_INVALID` | Certificate expired/invalid | `--clean` then `--trust` |
| Dashboard loads over HTTP only | Certificate generation failed | `dotnet dev-certs https --check` |
| Works in one browser but not another | Browser-specific cert store | Import certificate to problematic browser |
| Works after `aspire run` restart | Initial trust delay | Normal; refresh browser |

## CI/CD and container environments

```bash
# Via environment variables (not recommended for production)
ASPNETCORE_Kestrel__Certificates__Default__Path=/path/to/cert.pfx
ASPNETCORE_Kestrel__Certificates__Default__Password=password
```

HTTP-only for internal testing (AppHost.cs):

```csharp
var api = builder.AddProject<Projects.Api>("api")
    .WithHttpEndpoint(name: "http");  // No HTTPS
```
