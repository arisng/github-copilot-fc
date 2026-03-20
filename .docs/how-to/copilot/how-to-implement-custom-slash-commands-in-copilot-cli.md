# How to implement custom slash commands in Copilot CLI

## Executive Summary

GitHub Copilot CLI now has a supported path for Claude-style command files: the plugin system accepts a `commands` component in `plugin.json`, and the upstream Claude Code layout exposes `.claude/commands/` single-file commands that can be reused from the same file-backed command model[^2][^5][^6][^11][^12]. That means you can usually reuse Claude Code commands instead of rewriting them, especially if your commands are just Markdown prompts with a single responsibility[^11][^12].

The important boundary is that Copilot CLI does not expose a documented API for inventing arbitrary new built-in slash verbs at runtime. The official CLI customization surface is file-backed and centered on custom instructions, MCP servers, custom agents, hooks, skills, and prompt files in IDEs; prompt files are explicitly documented as IDE-only and are not a Copilot CLI feature[^1][^3][^4]. If you need terminal-native reuse, use `.claude/commands/` or a plugin `commands` directory. If you need richer multi-file workflows, promote the command into a skill[^2][^4][^5].

## Support matrix

| Surface                       | Copilot CLI support            | How it is used                                                          | Best fit                                                       |
| ----------------------------- | ------------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------- |
| Built-in slash commands       | Yes, but fixed                 | Session control, model choice, permissions, plugin/skill management     | Things the CLI already ships with[^1]                          |
| `.claude/commands/`           | Yes, per current CLI changelog | Single-file command definitions you can reuse from Claude Code          | Lightweight reusable command files[^11][^12]                   |
| `plugin.json.commands`        | Yes                            | Bundle command directories into a plugin and install the built bundle   | Sharing command packs across machines or teams[^2][^5][^6]     |
| `skills/`                     | Yes                            | Portable multi-file capabilities with scripts/resources                 | Bigger workflows, reusable operational context[^1][^2][^4][^5] |
| `.github/prompts/*.prompt.md` | Not in CLI; yes in IDEs        | Slash-command style prompt files in VS Code / Visual Studio / JetBrains | IDE-only reusable prompts[^3][^4][^7][^9]                      |

## Recommended implementation path

If you already have Claude Code slash commands, the easiest port is to keep them as Markdown command files and let Copilot CLI consume the same layout. The upstream Claude Code repository includes a `.claude/commands/` directory, and the public command-file examples in this repository show the same file-backed pattern for reusable commands[^11][^12].

If you need to distribute the commands to a team, package them in a Copilot CLI plugin. The official plugin reference says `plugin.json` can declare a `commands` component that points at command directories, and the workspace build script treats `commands` as one of the official component fields it resolves and copies into the runtime bundle[^2][^5][^6]. The supported local install flow is bundle-first: build the plugin, then install the bundle with `copilot plugin install <local bundle path>`[^5][^6].

If the workflow is mostly a single prompt and you also want IDE parity, use a prompt file instead. GitHub Docs describe prompt files as reusable prompt examples for common tasks, but they also state that prompt files are only available in VS Code, Visual Studio, and JetBrains IDEs[^3]. VS Code's docs explicitly call prompt files "slash commands" and show invoking them with `/name` in chat[^4]. In this repository, prompt files are published to VS Code user prompt directories, not to Copilot CLI[^7][^8][^9].

If the workflow becomes multi-file or needs scripts and resources, convert it to a skill. The VS Code docs recommend prompt files for lightweight single-task prompts and skills for portable multi-file capabilities[^4]. This repository's own packaging and docs follow the same separation: prompt publishing goes to IDE prompt directories, instruction publishing intentionally avoids CLI concatenation, and plugin bundles treat skills as a first-class component alongside commands[^5][^6][^7][^8].

## Practical file layout

```text
my-workflow-plugin/
  plugin.json
  commands/
    explain-change.md
    generate-release-notes.md
  skills/
    release-engineering/
```

```json
{
  "name": "my-workflow-plugin",
  "commands": "commands/",
  "skills": "skills/"
}
```

That layout matches the plugin model documented by GitHub and the workspace build script: component paths are relative to the plugin directory, and the bundle builder copies them into the runtime bundle before installation[^2][^5][^6]. If a command name collides with a skill name, skills win; the plugin reference says skills override commands[^2].

## What to avoid

Do not try to use instruction files as a CLI slash-command mechanism. This repository's instruction publisher explicitly excludes CLI instruction publishing because concatenating `.instructions.md` files into a single CLI instruction blob would overload the context window[^8]. Use instructions for always-on behavioral guidance, not for command registration.

Do not assume prompt files will show up in Copilot CLI. GitHub Docs are explicit that prompt files are IDE-only, even though the VS Code docs call them slash commands[^3][^4]. If you want a terminal shortcut, use a command file, a plugin, or a shell wrapper that calls `copilot -p` with the prompt text[^1].

## One practical fallback for pure terminal workflows

If you only need a quick terminal alias and do not need discovery inside the slash-command menu, use Copilot CLI's programmatic prompt mode (`-p` / `--prompt`) and wrap it in a shell function or script[^1]. That approach is not a native slash-command registry, but it is the simplest way to get a custom terminal command when file-backed discovery is overkill.

## Confidence assessment

High confidence: Copilot CLI now supports `.claude/commands/` as a file-backed command surface, plugin manifests can declare `commands`, prompt files are IDE-only, and prompt publishing in this repository targets VS Code prompt directories rather than CLI[^2][^3][^4][^5][^6][^7][^8][^11][^12].

Medium confidence: the public sources I reviewed do not fully spell out every detail of the `.claude/commands/` file format or the exact interactive invocation flow beyond the changelog and plugin/reference docs. The safe assumption is that command files are Markdown single-file definitions, because upstream tooling in [github/awesome-copilot](https://github.com/github/awesome-copilot) migrates `./commands/foo.md` entries to skills and the upstream Claude Code repo exposes a `.claude/commands/` directory[^11][^12].

## Footnotes

[^1]: GitHub Docs, "About GitHub Copilot CLI" — https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-copilot-cli. This page lists the official CLI customization surfaces (custom instructions, MCP servers, custom agents, hooks, skills, memory) and documents `-p` / `--prompt` for programmatic prompts.

[^2]: GitHub Docs, "GitHub Copilot CLI plugin reference" — https://docs.github.com/en/copilot/reference/cli-plugin-reference. This page documents `plugin.json` and its `commands` component path, plus the plugin install flow and precedence rules where skills override commands.

[^3]: GitHub Docs, "Prompt files" — https://docs.github.com/en/copilot/tutorials/customization-library/prompt-files. This page says prompt files are reusable prompt examples and are only available in VS Code, Visual Studio, and JetBrains IDEs.

[^4]: Visual Studio Code docs, "Prompt files" — https://code.visualstudio.com/docs/copilot/customization/prompt-files. This page says prompt files are also known as slash commands, explains `/name` invocation in chat, and recommends prompt files for lightweight prompts and skills for multi-file capabilities.

[^5]: `C:\Workplace\Agents\github-copilot-fc\plugins\README.md:3-4,36-68,71-83,113-131,161-171`. The repository's plugin docs describe plugins as bundles of agents, skills, commands, hooks, MCP servers, and LSP servers; they also document the supported CLI install flow and note that instructions are not a plugin field.

[^6]: `C:\Workplace\Agents\github-copilot-fc\scripts\publish\build-plugins.ps1:1186-1299,1351-1363` and `C:\Workplace\Agents\github-copilot-fc\scripts\publish\publish-plugins.ps1:21-31,64-83`. These scripts show that `commands` is an official component field, component paths are copied into runtime bundles, and CLI plugins are installed from the built local bundle with `copilot plugin install`.

[^7]: `C:\Workplace\Agents\github-copilot-fc\scripts\publish\publish-prompts.ps1:10-17,39-43,58-83,99-122`. This script publishes prompt files from `prompts/` to VS Code Stable and Insiders user prompt directories.

[^8]: `C:\Workplace\Agents\github-copilot-fc\scripts\publish\publish-instructions.ps1:26-29`. This script explicitly says CLI instruction publishing is intentionally excluded because concatenating all instruction files would overload the CLI context window.

[^9]: `C:\Workplace\Agents\github-copilot-fc\.github\prompts\publishPrompt.prompt.md:1-27`. This prompt file shows the workspace's pattern for command-like reusable prompts: YAML frontmatter with `name`, `description`, `argument-hint`, and `agent`, plus a body that runs the publish script.


[^11]: [github/awesome-copilot](https://github.com/github/awesome-copilot) — `eng/update-plugin-commands-to-skills.mjs`. This maintainer script converts plugin `./commands/foo.md` entries into `./skills/foo/`, which is a strong indicator that command files are Markdown single-file definitions.

[^12]: [anthropics/claude-code](https://github.com/anthropics/claude-code) — repository tree includes `.claude/commands/`. This confirms the Claude Code directory layout that Copilot CLI now says it supports.
