param(
    [Parameter(Mandatory=$true)]
    [string]$Type,
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [switch]$Force,
    [string]$CopilotHome
)

# “publish-artifact.ps1” is a thin wrapper around the real publishing helpers.
# It simply forwards the user’s arguments to the appropriate helper script and
# emits a single diagnostic line so that callers know the command ran.
#
# Pattern matching is performed inside each helper (publish-agents, publish-prompts,
# etc.).  Those scripts all accept wildcard names (`*`/`?`) and will warn if the
# pattern matches nothing.  To avoid PowerShell globbing the pattern against the
# current directory, quote it at the command line: e.g. `-Name "ralphV2*"`.
#
# A `-Force` switch is provided here for helpers that support overwriting existing
# files, sparing callers from invoking them directly.
#
# A `-CopilotHome` value is forwarded to helpers that support the staging override
# (agent, instruction, hook); other helper types ignore it.


# always report that we are about to invoke something, even if the inner script is quiet
Write-Host "Publishing artifact type '$Type' with name(s) '$Name'..." -ForegroundColor Cyan

function Get-ForwardedArgs {
    # Builds the argument splat shared by helper invocations that accept -CopilotHome.
    $forwarded = @{}
    if ($CopilotHome) { $forwarded['CopilotHome'] = $CopilotHome }
    return $forwarded
}

switch ($Type.ToLower()) {
    "agent" {
        $forward = Get-ForwardedArgs
        & "$PSScriptRoot/publish-agents.ps1" -Agents $Name @forward
    }
    "instruction" {
        $forward = Get-ForwardedArgs
        & "$PSScriptRoot/publish-instructions.ps1" -Instructions $Name @forward
    }
    "prompt" {
        # call the prompt publisher directly using named params.  This avoids
        # unpredictable behaviour when using splatting and prevents the wildcard
        # string from being misinterpreted as a positional argument.
        if ($Force) {
            & "$PSScriptRoot/publish-prompts.ps1" -Prompts $Name -Force
        } else {
            & "$PSScriptRoot/publish-prompts.ps1" -Prompts $Name
        }
    }
    "skill" {
        if ($Force) {
            & "$PSScriptRoot/publish-skills.ps1" -Skills $Name -Force
        } else {
            & "$PSScriptRoot/publish-skills.ps1" -Skills $Name
        }
    }
    "toolset" {
        & "$PSScriptRoot/publish-toolsets.ps1" -Toolsets $Name
    }
    "hook" {
        $forward = Get-ForwardedArgs
        if ($Force) {
            & "$PSScriptRoot/publish-hooks.ps1" -Hooks $Name -Force @forward
        } else {
            & "$PSScriptRoot/publish-hooks.ps1" -Hooks $Name @forward
        }
    }
    "plugin" {
        if ($Force) {
            & "$PSScriptRoot/publish-plugins.ps1" -Plugins $Name -Force
        } else {
            & "$PSScriptRoot/publish-plugins.ps1" -Plugins $Name
        }
    }
    default {
        Write-Error "Unknown type: $Type. Supported types: agent, instruction, prompt, skill, toolset, hook, plugin"
        exit 1
    }
}