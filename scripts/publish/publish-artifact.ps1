param(
    [Parameter(Mandatory=$true)]
    [string]$Type,
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [string]$Method = "Copy"
)

switch ($Type.ToLower()) {
    "agent" {
        & "$PSScriptRoot/publish-agents.ps1" -Agents ($Name -split ' ')
    }
    "instruction" {
        & "$PSScriptRoot/publish-instructions.ps1" -Instructions ($Name -split ' ')
    }
    "prompt" {
        & "$PSScriptRoot/publish-prompts.ps1" -Prompts ($Name -split ' ')
    }
    "skill" {
        & "$PSScriptRoot/publish-skills.ps1" -Method $Method -Skills ($Name -split ' ')
    }
    "toolset" {
        & "$PSScriptRoot/publish-toolsets.ps1" -Toolsets ($Name -split ' ')
    }
    default {
        Write-Error "Unknown type: $Type. Supported types: agent, instruction, prompt, skill, toolset"
        exit 1
    }
}