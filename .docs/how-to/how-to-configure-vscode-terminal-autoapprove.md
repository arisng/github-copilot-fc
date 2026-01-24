# How to Configure VS Code to Auto-Approve Terminal Commands with Dynamic Arguments

This guide shows you how to configure VS Code's `chat.tools.terminal.autoApprove` setting to auto-approve terminal commands with dynamic arguments, such as Python scripts in the skills/ directory.

## When to use this guide

Use this guide if you need to automatically approve terminal commands executed by Copilot Chat that include dynamic arguments, reducing manual confirmations for trusted operations like running Python scripts with varying parameters.

## Before you start

- VS Code installed with GitHub Copilot Chat extension enabled.
- Access to VS Code settings (via Command Palette or settings.json).

## Steps

### Enable terminal auto-approve

1. Open VS Code.
2. Open the Command Palette (Ctrl+Shift+P or Cmd+Shift+P on Mac).
3. Type "Preferences: Open Settings (JSON)" and select it to edit settings.json directly, or use the Settings UI.
4. Add or modify the following setting to enable auto-approval:

```json
"chat.tools.terminal.enableAutoApprove": true
```

### Configure auto-approve rules for commands

1. In the same settings file, add or modify the `chat.tools.terminal.autoApprove` setting as an object.
2. To auto-approve Python commands (including those with dynamic arguments), set:

```json
"chat.tools.terminal.autoApprove": {
  "python": true
}
```

This allows Copilot Chat to run commands like `python skills/example.py --input data.txt` without manual approval.

## Troubleshooting

**Problem: Commands are not auto-approving despite the setting.**

Solution: Ensure the command name matches exactly (e.g., "python" for Python interpreter). Check the VS Code output panel for any errors in settings parsing. Restart VS Code after changing settings.

**Problem: Only specific scripts should be approved, not all Python commands.**

Solution: Use regex patterns instead of simple strings. For example, to approve only Python scripts in the skills/ directory:

```json
"chat.tools.terminal.autoApprove": {
  "/^python\\s+skills\\//": true
}
```

Note: Regex support may vary; test with your specific commands.

## Variations

If you need to auto-approve other commands with dynamic arguments (e.g., Node.js scripts), add them to the object:

```json
"chat.tools.terminal.autoApprove": {
  "python": true,
  "node": true
}
```

For more restrictive approval, set specific commands to `false` to override defaults.

## Related guides

- [How to Set Up GitHub Copilot Chat in VS Code](https://code.visualstudio.com/docs/copilot/chat/getting-started) (external link)

## See also

- [VS Code Copilot Chat Settings Reference](https://code.visualstudio.com/docs/copilot/chat/chat-tools) for complete configuration options.