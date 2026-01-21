param(
    [Parameter(Mandatory=$true)]
    [string]$Type,
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [string]$Method = "Copy"
)

switch ($Type.ToLower()) {
    "agent" {
        & "$PSScriptRoot/publish-agents.ps1" -Agents $Name
    }
    "instruction" {
        & "$PSScriptRoot/publish-instructions.ps1" -Instructions $Name
    }
    "prompt" {
        & "$PSScriptRoot/publish-prompts.ps1" -Prompts $Name
    }
    "skill" {
        & "$PSScriptRoot/publish-skills.ps1" -Method $Method -Skills $Name
    }
    default {
        Write-Error "Unknown type: $Type. Supported types: agent, instruction, prompt, skill"
        exit 1
    }
}