---
name: publishPrompt
description: Publish specified prompts to VS Code user prompts directories.
argument-hint: One or more prompt names to publish, separated by spaces (e.g., prompt1 prompt2)
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.1
  author: arisng
---
Publish the prompts named `{arguments}` to VS Code user prompts directories.

Use the workspace publish script to copy the prompt files from the project's prompts/ folder to VS Code's and VS Code Insiders' user prompts directories.

Run the following command in the terminal:
```
powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-artifact.ps1 -Type prompt -Name {arguments}
```

Note: If publishing multiple prompts, separate the names with spaces in the -Name parameter, as the script accepts an array.

If the prompts already exist and you want to overwrite them, run the specific script directly with -Force:
```
powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-prompts.ps1 -Prompts {arguments} -Force
```

This ensures the prompts are available globally in VS Code for use in Copilot chat.
