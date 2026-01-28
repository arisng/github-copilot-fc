# Playwright CLI Environment Variables

Playwright CLI supports various environment variables for configuration. These can be used instead of or in conjunction with configuration files.

## Environment Variables

| Variable                                        | Description                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PLAYWRIGHT_MCP_ALLOWED_HOSTS`                  | Comma-separated list of hosts this server is allowed to serve from. Defaults to the host the server is bound to. Pass '*' to disable the host check.                                                                                                                                         |
| `PLAYWRIGHT_MCP_ALLOWED_ORIGINS`                | Semicolon-separated list of TRUSTED origins to allow the browser to request. Default is to allow all. Important: *does not* serve as a security boundary and *does not* affect redirects.                                                                                                    |
| `PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS` | Allow access to files outside of the workspace roots. Also allows unrestricted access to file:// URLs. By default access to file system is restricted to workspace root directories (or cwd if no roots are configured) only, and navigation to file:// URLs is blocked.                     |
| `PLAYWRIGHT_MCP_BLOCKED_ORIGINS`                | Semicolon-separated list of origins to block the browser from requesting. Blocklist is evaluated before allowlist. If used without the allowlist, requests not matching the blocklist are still allowed. Important: *does not* serve as a security boundary and *does not* affect redirects. |
| `PLAYWRIGHT_MCP_BROWSER`                        | Browser or chrome channel to use, possible values: chrome, firefox, webkit, msedge.                                                                                                                                                                                                          |
| `PLAYWRIGHT_MCP_CAPS`                           | Comma-separated list of additional capabilities to enable, possible values: vision, pdf.                                                                                                                                                                                                     |
| `PLAYWRIGHT_MCP_CDP_ENDPOINT`                   | CDP endpoint to connect to.                                                                                                                                                                                                                                                                  |
| `PLAYWRIGHT_MCP_CDP_HEADER`                     | CDP headers to send with the connect request, multiple can be specified.                                                                                                                                                                                                                     |
| `PLAYWRIGHT_MCP_CODEGEN`                        | Specify the language to use for code generation, possible values: "typescript", "none". Default is "typescript".                                                                                                                                                                             |
| `PLAYWRIGHT_MCP_CONFIG`                         | Path to the configuration file.                                                                                                                                                                                                                                                              |
| `PLAYWRIGHT_MCP_CONSOLE_LEVEL`                  | Level of console messages to return: "error", "warning", "info", "debug". Each level includes the messages of more severe levels.                                                                                                                                                            |
| `PLAYWRIGHT_MCP_DEVICE`                         | Device to emulate, for example: "iPhone 15"                                                                                                                                                                                                                                                  |
| `PLAYWRIGHT_MCP_EXECUTABLE_PATH`                | Path to the browser executable.                                                                                                                                                                                                                                                              |
| `PLAYWRIGHT_MCP_EXTENSION`                      | Connect to a running browser instance (Edge/Chrome only). Requires the "Playwright MCP Bridge" browser extension to be installed.                                                                                                                                                            |
| `PLAYWRIGHT_MCP_GRANT_PERMISSIONS`              | List of permissions to grant to the browser context, for example "geolocation", "clipboard-read", "clipboard-write".                                                                                                                                                                         |
| `PLAYWRIGHT_MCP_HEADLESS`                       | Run browser in headless mode, headed by default                                                                                                                                                                                                                                              |
| `PLAYWRIGHT_MCP_HOST`                           | Host to bind server to. Default is localhost. Use 0.0.0.0 to bind to all interfaces.                                                                                                                                                                                                         |
| `PLAYWRIGHT_MCP_IGNORE_HTTPS_ERRORS`            | Ignore https errors                                                                                                                                                                                                                                                                          |
| `PLAYWRIGHT_MCP_INIT_PAGE`                      | Path to TypeScript file to evaluate on Playwright page object                                                                                                                                                                                                                                |
| `PLAYWRIGHT_MCP_INIT_SCRIPT`                    | Path to JavaScript file to add as an initialization script. The script will be evaluated in every page before any of the page's scripts. Can be specified multiple times.                                                                                                                    |
| `PLAYWRIGHT_MCP_ISOLATED`                       | Keep the browser profile in memory, do not save it to disk.                                                                                                                                                                                                                                  |
| `PLAYWRIGHT_MCP_IMAGE_RESPONSES`                | Whether to send image responses to the client. Can be "allow" or "omit", Defaults to "allow".                                                                                                                                                                                                |
| `PLAYWRIGHT_MCP_NO_SANDBOX`                     | Disable the sandbox for all process types that are normally sandboxed.                                                                                                                                                                                                                       |
| `PLAYWRIGHT_MCP_OUTPUT_DIR`                     | Path to the directory for output files.                                                                                                                                                                                                                                                      |
| `PLAYWRIGHT_MCP_OUTPUT_MODE`                    | Whether to save snapshots, console messages, network logs to a file or to the standard output. Can be "file" or "stdout". Default is "stdout".                                                                                                                                               |
| `PLAYWRIGHT_MCP_PORT`                           | Port to listen on for SSE transport.                                                                                                                                                                                                                                                         |
| `PLAYWRIGHT_MCP_PROXY_BYPASS`                   | Comma-separated domains to bypass proxy, for example ".com,chromium.org,.domain.com"                                                                                                                                                                                                         |
| `PLAYWRIGHT_MCP_PROXY_SERVER`                   | Specify proxy server, for example "<http://myproxy:3128>" or "socks5://myproxy:8080"                                                                                                                                                                                                           |
| `PLAYWRIGHT_MCP_SAVE_SESSION`                   | Whether to save the Playwright MCP session into the output directory.                                                                                                                                                                                                                        |
| `PLAYWRIGHT_MCP_SAVE_TRACE`                     | Whether to save the Playwright Trace of the session into the output directory.                                                                                                                                                                                                               |
| `PLAYWRIGHT_MCP_SAVE_VIDEO`                     | Whether to save the video of the session into the output directory. For example "--save-video=800x600"                                                                                                                                                                                       |
| `PLAYWRIGHT_MCP_SECRETS`                        | Path to a file containing secrets in the dotenv format                                                                                                                                                                                                                                       |
| `PLAYWRIGHT_MCP_SHARED_BROWSER_CONTEXT`         | Reuse the same browser context between all connected HTTP clients.                                                                                                                                                                                                                           |
| `PLAYWRIGHT_MCP_SNAPSHOT_MODE`                  | When taking snapshots for responses, specifies the mode to use. Can be "incremental", "full", or "none". Default is incremental.                                                                                                                                                             |
| `PLAYWRIGHT_MCP_STORAGE_STATE`                  | Path to the storage state file for isolated sessions.                                                                                                                                                                                                                                        |
| `PLAYWRIGHT_MCP_TEST_ID_ATTRIBUTE`              | Specify the attribute to use for test ids, defaults to "data-testid"                                                                                                                                                                                                                         |
| `PLAYWRIGHT_MCP_TIMEOUT_ACTION`                 | Specify action timeout in milliseconds, defaults to 5000ms                                                                                                                                                                                                                                   |
| `PLAYWRIGHT_MCP_TIMEOUT_NAVIGATION`             | Specify navigation timeout in milliseconds, defaults to 60000ms                                                                                                                                                                                                                              |
| `PLAYWRIGHT_MCP_USER_AGENT`                     | Specify user agent string                                                                                                                                                                                                                                                                    |
| `PLAYWRIGHT_MCP_USER_DATA_DIR`                  | Path to the user data directory. If not specified, a temporary directory will be created.                                                                                                                                                                                                    |
| `PLAYWRIGHT_MCP_USER_DATA_DIR`                  | Path to the user data directory. If not specified, a temporary directory will be created.                                                                                                                                                                                                    |
| `PLAYWRIGHT_MCP_VIEWPORT_SIZE`                  | Specify browser viewport size in pixels, for example "1280x720"                                                                                                                                                                                                                              |

## Usage Examples

### Setting Browser and Headless Mode

```bash
export PLAYWRIGHT_MCP_BROWSER=firefox
export PLAYWRIGHT_MCP_HEADLESS=true
playwright-cli open https://example.com
```

### Configuring Timeouts

```bash
export PLAYWRIGHT_MCP_TIMEOUT_ACTION=10000
export PLAYWRIGHT_MCP_TIMEOUT_NAVIGATION=45000
playwright-cli open https://example.com
```

### Setting Output Directory

```bash
export PLAYWRIGHT_MCP_OUTPUT_DIR=./my-output
export PLAYWRIGHT_MCP_OUTPUT_MODE=file
playwright-cli screenshot
```

### Using a Specific Device

```bash
export PLAYWRIGHT_MCP_DEVICE="iPhone 15"
playwright-cli open https://example.com
```

### Allowing File Access

```bash
export PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS=true
playwright-cli upload /path/to/file.pdf
```
