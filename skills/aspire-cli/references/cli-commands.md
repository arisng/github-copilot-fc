# Aspire CLI commands overview (13.x)

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/

## Core commands

| Command | Purpose | Typical usage |
| --- | --- | --- |
| `aspire new` | Create a new Aspire solution from templates | `aspire new` or `aspire new <template>` |
| `aspire init` | Add Aspire to an existing solution | `aspire init` |
| `aspire run` | Run AppHost dev orchestration and dashboard | `aspire run` |
| `aspire add` | Add official integration packages | `aspire add <package-id>` |
| `aspire update` | Update Aspire NuGet packages | `aspire update` |
| `aspire update --self` | Update the CLI binary | `aspire update --self` |
| `aspire publish` | Publish deployment assets | `aspire publish` |
| `aspire deploy` | Deploy serialized assets | `aspire deploy` |
| `aspire do` | Run pipeline steps and dependencies | `aspire do <step>` |
| `aspire exec` | Run commands inside a resource context | `aspire exec --resource <name> -- <command>` |
| `aspire config` | Get/set CLI config options | `aspire config list` / `aspire config set <key> <value>` |
| `aspire cache clear` | Clear local cache | `aspire cache clear` |

## Common flags

- `-d`, `--debug`: Enable CLI debug logging (`run`, `exec`, `do`).
- `--wait-for-debugger`: Pause before run so a debugger can attach (`run`, `exec`, `do`).
- `--project <path>`: Explicitly select an AppHost when multiple are present (`run`).

## Notes

- Run commands from the AppHost directory when possible to avoid ambiguity.
- `aspire exec` is guarded by a feature flag; enable with `aspire config set features.execCommandEnabled true` when needed.
