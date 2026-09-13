# Task Installation Guide

Task offers many installation methods. Choose the one that best fits your environment.
Last verified: 2026-09-13

## Official Package Managers

These installation methods are maintained by the Task team and are always up-to-date.

### Linux Package Repositories

**dnf (Fedora):**
```sh
# Set up repository
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.rpm.sh' | sudo -E bash
# Install Task
dnf install task
```

**apt (Debian/Ubuntu):**
```sh
# Set up repository
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | sudo -E bash
# Install Task
apt install task
```

**apk (Alpine):**
```sh
# Set up repository
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.alpine.sh' | sudo -E bash
# Install Task
apk add task
```

### macOS

**Homebrew (official tap):**
```sh
brew install go-task/tap/go-task
```

**Homebrew (official repository):**
```sh
brew install go-task
```

**Macports:**
```sh
port install go-task
```

### Windows

**WinGet:**
```sh
winget install Task.TaskCommunity
```

**Chocolatey:**
```sh
choco install go-task
```

**Scoop:**
```sh
scoop install task
```

### Cross-Platform

**npm:**
```sh
npm install -g @go-task/cli
```

**pip:**
```sh
pip install go-task-bin
```

**Snap (Linux):**
```sh
sudo snap install task --classic
```

## Community-Maintained Package Managers

These installation methods are maintained by the community and may not always be up-to-date.

### Mise (aqua/ubi backends recommended)
```sh
mise use -g aqua:go-task/task@latest
mise install
# OR
mise use -g ubi:go-task/task
mise install
```

### Arch Linux (pacman)
```sh
pacman -S go-task
```

### Fedora (dnf)
```sh
dnf install go-task
```

### FreeBSD (Ports)
```sh
pkg install task
```

### Nix
```sh
nix-env -iA nixpkgs.go-task
```

### pacstall
```sh
pacstall -I go-task-deb
```

### pkgx
```sh
pkgx task
# OR if you have pkgx integration enabled:
task
```

## Binary Installation

Download the binary from the [releases page](https://github.com/go-task/task/releases) on GitHub and add to your `$PATH`.

DEB, RPM and APK packages are also available.

The `task_checksums.txt` file contains the SHA-256 checksum for each file.

### Install Script

Useful for CI environments. Installs to `./bin` by default:

```sh
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d
```

Override installation directory with `-b`:

```sh
# Install to ~/.local/bin
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin

# Install to /usr/local/bin (all users)
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
```

**Warning:** On macOS and Windows, `~/.local/bin` and `~/bin` are not added to `$PATH` by default.

Install a specific version:

```sh
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d v3.36.0
```

Parameters are order-specific, to set both installation directory and version:

```sh
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin v3.42.1
```

## GitHub Actions

Official GitHub Action to install Task in your workflows:

```yaml
- name: Install Task
  uses: go-task/setup-task@v1
```

## Build From Source

Ensure you have a supported version of Go installed. Check the minimum required version in the `go.mod` file.

Install globally:
```sh
go install github.com/go-task/task/v3/cmd/task@latest
```

Install into another directory:
```sh
env GOBIN=/bin go install github.com/go-task/task/v3/cmd/task@latest
```

**Tip:** For CI environments, use the install script instead – it's faster and more stable.

## Go Tool

Add Task as a tool in your Go project:
```sh
go get -tool github.com/go-task/task/v3/cmd/task@latest
```

Then call with `go tool`:
```sh
go tool task {arguments...}
```

Go will compile Task on demand before calling it.

## Shell Completions

Some installation methods automatically install completions. If not, run:

```sh
task --completion <shell>
```

### Option 1: Load completions in shell startup (Recommended)

**Bash:**
```bash
# ~/.bashrc
eval "$(task --completion bash)"
```

**Zsh:**
```zsh
# ~/.zshrc
eval "$(task --completion zsh)"
```

**Fish:**
```fish
# ~/.config/fish/config.fish
task --completion fish | source
```

**PowerShell:**
```powershell
# $PROFILE\Microsoft.PowerShell_profile.ps1
Invoke-Expression (&task --completion powershell | Out-String)
```

**Nushell:**
```nu
# ~/.config/nushell/config.nu
mkdir ($nu.data-dir | path join "vendor/autoload")
task --completion nu | save --force ($nu.data-dir | path join "vendor/autoload/task-completions.nu")
```

### Option 2: Copy script to completions directory

Requires manual updates when Task is updated.

**Bash:**
```sh
task --completion bash > /etc/bash_completion.d/task
```

**Zsh:**
```sh
task --completion zsh > /usr/local/share/zsh/site-functions/_task
```

**Fish:**
```sh
task --completion fish > ~/.config/fish/completions/task.fish
```

**Nushell:**
```nu
task --completion nu | save --force ($nu.data-dir | path join "vendor/autoload/task-completions.nu")
```

### Zsh customization

The Zsh completion supports the standard verbose zstyle to control whether task descriptions are shown. By default, descriptions are shown. To disable:

```zsh
zstyle ':completion:*:task' verbose no
```