# Aspire 13.1 CLI changes and notes

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/

## Channel selection

- Use `--channel` with `aspire new` or `aspire init` when selecting preview or stable builds.
- Channel selection is persisted across `aspire update --self`.

## AppHost detection

- AppHost discovery prioritizes explicit `--project`, then `.aspire/settings.json` `appHostPath`, then scans current directory and subdirectories.
- When multiple AppHosts exist, run commands from the intended AppHost folder or pass `--project` to disambiguate.

## Execution flags

- `-d`, `--debug` and `--wait-for-debugger` are available on `aspire run`, `aspire exec`, and `aspire do` for troubleshooting.

## Exec command feature gate

- `aspire exec` is disabled by default; enable via `aspire config set features.execCommandEnabled true`.
