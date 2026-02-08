---
name: publishToolsets
description: Publish specified toolsets to VS Code user toolsets directories.
argument-hint: Comma-delimited list of toolset names (e.g., toolset1,toolset2)
model: Grok Code Fast 1 (copilot)
metadata:
  version: 1.0.0
---
Publish the toolsets named `{arguments}` to VS Code user toolsets directories.

Use the workspace publish script to copy the toolset files from the project's toolsets/ folder to VS Code's and VS Code Insiders' user toolsets directories.

Run the following command in the terminal:
```
powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-toolsets.ps1 -Toolsets ($arguments -split ',')
```

Note: The toolsets are specified as a comma-delimited string in {arguments}, which is split into an array for the script.

If the toolsets already exist and you want to overwrite them, run the specific script directly with -Force:
```
powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-toolsets.ps1 -Toolsets ($arguments -split ',') -Force
```

This ensures the toolsets are available globally in VS Code for use in Copilot chat.
