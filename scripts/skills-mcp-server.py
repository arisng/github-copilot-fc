from mcp.server.fastmcp import FastMCP
import os
import sys

# Initialize the MCP Server
mcp = FastMCP("Skills")

# Define where skills live (relative to this script)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SKILLS_ROOT = os.path.join(os.path.dirname(BASE_DIR), "skills")

@mcp.tool()
def list_available_skills() -> str:
    """
    Returns a list of all available skill folders in the library.
    Use this to discover what capabilities are available.
    """
    if not os.path.exists(SKILLS_ROOT):
        return "Error: 'skills' directory not found."
    
    skills = [d for d in os.listdir(SKILLS_ROOT) if os.path.isdir(os.path.join(SKILLS_ROOT, d)) and not d.startswith('_')]
    return f"Available Skills: {', '.join(skills)}"

@mcp.tool()
def inspect_skill(skill_name: str) -> str:
    """
    Reads the 'skill.md' file for a specific skill to understand how to use it.
    """
    skill_path = os.path.join(SKILLS_ROOT, skill_name, "skill.md")
    if not os.path.exists(skill_path):
        return f"Error: Skill '{skill_name}' not found or missing skill.md."
    
    with open(skill_path, 'r', encoding='utf-8') as f:
        return f.read()

@mcp.tool()
def run_skill_script(skill_name: str, script_name: str, arguments: str = "") -> str:
    """
    Prepares the command to execute a specific script inside a skill folder.
    Use this to get the command string, then execute it using the run_in_terminal tool.
    Args:
        skill_name: Name of the skill folder (e.g., 'vn_payroll')
        script_name: Name of the script to run (e.g., 'calc_tax.py')
        arguments: Command line arguments as a single string (e.g., '--salary 50000000')
    """
    # Security: Prevent directory traversal
    if ".." in skill_name or ".." in script_name:
        return "Error: Invalid path."

    script_path = os.path.join(SKILLS_ROOT, skill_name, script_name)
    
    if not os.path.exists(script_path):
        return f"Error: Script '{script_name}' not found in skill '{skill_name}'."

    # Select interpreter
    cmd = []
    if script_name.endswith(".py"):
        cmd = [sys.executable, script_path] # Use current python env
    elif script_name.endswith(".ps1"):
        cmd = ["pwsh", "-File", script_path]
    elif script_name.endswith(".sh"):
        cmd = ["bash", script_path]
    else:
        return "Error: Unsupported file type. Only .py, .ps1, and .sh are allowed."

    # Add arguments
    if arguments:
        cmd.extend(arguments.split())

    # Return the command for the LLM to execute using run_in_terminal
    command_str = " ".join(cmd)
    return f"To execute the script, use the #tool:runCommands with the following command: {command_str}"

if __name__ == "__main__":
    mcp.run()