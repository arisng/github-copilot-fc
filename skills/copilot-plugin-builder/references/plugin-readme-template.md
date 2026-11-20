# Plugin README Template

Consumer-facing README skeleton for a shipped plugin. Copy the template below into the
plugin's `README.md`, replace every `<placeholder>` slot, and keep all six sections —
the submission review grades against it (see
[submission-review.md](submission-review.md) → README quality). Delete component tables
the plugin does not ship.

````markdown
# <plugin-name>

<One-paragraph pitch: what the plugin does, who it is for, and the outcome it produces — two or three sentences, not a feature list.>

## Installation

Marketplace flow (recommended):

```bash
/plugin marketplace add arisng/github-copilot-fc
/plugin install <plugin-name>@<marketplace-name>
```

Equivalent from a shell: `copilot plugin install <plugin-name>@<marketplace-name>`.

Local bundle alternative (no marketplace registration):

```bash
copilot plugin install <path>
```

For example: `copilot plugin install dist/plugins/<runtime>/<plugin-name>`.

## Quick start

1. <Install the plugin and open a new Copilot session.>
2. <One command or prompt that demonstrates the core value.>
3. <The result the user should see.>

## How it works

<Short paragraph: which components load, what they call, and any prerequisites (runtime, credentials, files). Bullets welcome for multi-step flows.>

## Components

One table per component type shipped; delete the rest.

| Skill | Description |
| ----- | ----------- |
| `<skill-name>` | <what it does and when to use it> |

| Command | Description |
| ------- | ----------- |
| `/<command-name>` | <what it runs> |

| Agent | Description |
| ----- | ----------- |
| `<agent-name>` | <scope and tool access> |

| Hook | Event | Description |
| ---- | ----- | ----------- |
| `<script>` | `<event>` | <why it fires> |

| MCP server | Description |
| ---------- | ----------- |
| `<server-name>` | <tools it provides> |

## License

MIT — see [LICENSE](../../LICENSE) in the repository.

<!-- Release bundles: dist/plugins/<runtime>/<plugin-name>/ has no ../../LICENSE two
     levels up. Ship a LICENSE file inside the bundle or keep the plain "MIT" statement. -->
````

Slots used above: `<plugin-name>`, `<marketplace-name>`, `<runtime>`, `<path>`,
`<skill-name>`, `<command-name>`, `<agent-name>`, `<script>`, `<event>`,
`<server-name>` — replace every one; the submission review fails on leftover `<...>`.
