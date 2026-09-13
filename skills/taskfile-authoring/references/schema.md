# Taskfile Schema Reference

Taskfile schema version 3 reference.
Last verified: 2026-09-13

## Root Schema

### version
- **Type:** string or number
- **Required:** Yes
- **Valid values:** `"3"`, `3`, or any valid semver string
- **Description:** Version of the Taskfile schema

```yaml
version: '3'
```

### output
- **Type:** string or object
- **Default:** `interleaved`
- **Options:** `interleaved`, `group`, `prefixed`
- **Description:** Controls how task output is displayed

```yaml
# Simple string format
output: group

# Advanced object format
output:
  group:
    begin: "::group::{{.TASK}}"
    end: "::endgroup::"
    error_only: false
```

### method
- **Type:** string
- **Default:** `checksum`
- **Options:** `checksum`, `timestamp`, `none`
- **Description:** Default method for checking if tasks are up-to-date

```yaml
method: timestamp
```

### includes
- **Type:** map[string]Include
- **Description:** Include other Taskfiles

```yaml
includes:
  # Simple string format
  docs: ./Taskfile.yml
  
  # Full object format
  backend:
    taskfile: ./backend
    dir: ./backend
    optional: false
    flatten: false
    internal: false
    aliases: [api]
    excludes: [internal-task]
    vars:
      SERVICE_NAME: backend
    checksum: abc123...
```

### vars
- **Type:** map[string]Variable
- **Description:** Global variables available to all tasks

```yaml
vars:
  # Simple values
  APP_NAME: myapp
  VERSION: 1.0.0
  DEBUG: true
  PORT: 8080
  FEATURES: [auth, logging]
  
  # Dynamic variables
  COMMIT_HASH: sh: git rev-parse HEAD
  
  # Variable references
  BUILD_VERSION: ref: .VERSION
  
  # Map variables
  CONFIG:
    map:
      database: postgres
      cache: redis
```

### env
- **Type:** map[string]Variable
- **Description:** Global environment variables

```yaml
env:
  NODE_ENV: production
  DATABASE_URL: sh: echo $DATABASE_URL
```

### tasks
- **Type:** map[string]Task
- **Description:** Task definitions

```yaml
tasks:
  # Simple string format
  hello: echo "Hello World"
  
  # Array format
  build:
    - go mod tidy
    - go build ./...
  
  # Full object format
  deploy:
    desc: Deploy the application
    cmds:
      - ./scripts/deploy.sh
```

### silent
- **Type:** bool
- **Default:** false
- **Description:** Suppress task name and command output by default

```yaml
silent: true
```

### dotenv
- **Type:** []string
- **Description:** Load environment variables from .env files

```yaml
dotenv:
  - .env.local # Highest priority
  - .env # Lowest priority
```

### run
- **Type:** string
- **Default:** `always`
- **Options:** `always`, `once`, `when_changed`
- **Description:** Default execution behavior for tasks

```yaml
run: once
```

### interval
- **Type:** string
- **Default:** `100ms`
- **Pattern:** `^[0-9]+(?:m|s|ms)$`
- **Description:** Watch interval for file changes

```yaml
interval: 1s
```

### set
- **Type:** []string
- **Options:** `allexport`, `a`, `errexit`, `e`, `noexec`, `n`, `noglob`, `f`, `nounset`, `u`, `xtrace`, `x`, `pipefail`
- **Description:** POSIX shell options for all commands

```yaml
set: [errexit, nounset, pipefail]
```

### shopt
- **Type:** []string
- **Options:** `expand_aliases`, `globstar`, `nullglob`
- **Description:** Bash shell options for all commands

```yaml
shopt: [globstar]
```

### use_gitignore
- **Type:** bool
- **Default:** false
- **Description:** Exclude files matched by .gitignore rules

```yaml
use_gitignore: true
```

## Include Configuration

### taskfile
- **Type:** string
- **Required:** Yes
- **Description:** Path to the Taskfile or directory to include

### dir
- **Type:** string
- **Description:** Working directory for included tasks

### optional
- **Type:** bool
- **Default:** false
- **Description:** Don't error if the included file doesn't exist

### flatten
- **Type:** bool
- **Default:** false
- **Description:** Include tasks without namespace prefix

### internal
- **Type:** bool
- **Default:** false
- **Description:** Hide included tasks from command line and --list

### aliases
- **Type:** []string
- **Description:** Alternative names for the namespace

### excludes
- **Type:** []string
- **Description:** Task names or namespace patterns to exclude

### vars
- **Type:** map[string]Variable
- **Description:** Variables to pass to the included Taskfile

### checksum
- **Type:** string
- **Description:** Expected checksum of the included file

## Variable Types

### Static Variables
```yaml
vars:
  APP_NAME: myapp
  PORT: 8080
  DEBUG: true
  FEATURES: [auth, logging, metrics]
```

### Dynamic Variables (sh)
```yaml
vars:
  COMMIT_HASH: sh: git rev-parse HEAD
  BUILD_TIME: sh: date -u +"%Y-%m-%dT%H:%M:%SZ"
```

### Variable References (ref)
```yaml
vars:
  BASE_VERSION: 1.0.0
  FULL_VERSION: ref: .BASE_VERSION
```

### Map Variables (map)
```yaml
vars:
  CONFIG:
    map:
      database:
        host: localhost
        port: 5432
      cache:
        type: redis
        ttl: 3600
```

### Secret Variables
```yaml
vars:
  API_KEY:
    value: 'sk-1234567890abcdef'
    secret: true
  DB_PASSWORD:
    sh: vault read -field=password secret/db
    secret: true
```

## Task Properties

### cmds
- **Type:** []Command
- **Description:** Commands to execute

```yaml
tasks:
  build:
    cmds:
      - go build ./...
      - echo "Build complete"
```

### cmd
- **Type:** string
- **Description:** Single command (alternative to cmds)

```yaml
tasks:
  test:
    cmd: go test ./...
```

### deps
- **Type:** []Dependency
- **Description:** Tasks to run before this task

```yaml
tasks:
  deploy:
    deps: [build, test]
    cmds:
      - ./deploy.sh
```

### desc
- **Type:** string
- **Description:** Short description shown in --list

```yaml
tasks:
  test:
    desc: Run unit tests
```

### summary
- **Type:** string
- **Description:** Detailed description shown in --summary

```yaml
tasks:
  deploy:
    summary: |
      Deploy the application to production environment.
      This includes building, testing, and uploading artifacts.
```

### prompt
- **Type:** string or []string
- **Description:** Prompts shown before task execution

```yaml
tasks:
  deploy:
    prompt: "Deploy to production?"
```

### aliases
- **Type:** []string
- **Description:** Alternative names for the task

```yaml
tasks:
  build:
    aliases: [compile, make]
```

### method
- **Type:** string
- **Default:** `checksum`
- **Options:** `checksum`, `timestamp`, `none`
- **Description:** Method for checking if task is up-to-date

### generates
- **Type:** []string
- **Description:** Files created by the task

```yaml
tasks:
  build:
    generates:
      - bin/app
```

### sources
- **Type:** []string
- **Description:** Files that trigger re-run when changed

```yaml
tasks:
  build:
    sources:
      - '*.go'
      - go.mod
```

### preconditions
- **Type:** []Precondition
- **Description:** Conditions that must be true for task to run

```yaml
tasks:
  deploy:
    preconditions:
      - test -f deploy.key
      - sh: test "$ENV" = "production"
        msg: "Not in production environment"
```

### dir
- **Type:** string
- **Description:** Working directory for the task

```yaml
tasks:
  build:
    dir: ./cmd
```

### env
- **Type:** map[string]Variable
- **Description:** Task-specific environment variables

```yaml
tasks:
  build:
    env:
      CGO_ENABLED: "0"
```

### silent
- **Type:** bool
- **Description:** Suppress task name and command output

```yaml
tasks:
  quiet:
    silent: true
```

### interactive
- **Type:** bool
- **Description:** Allow interactive input

```yaml
tasks:
  prompt-user:
    interactive: true
```

### run
- **Type:** string
- **Options:** `always`, `once`, `when_changed`
- **Description:** Execution behavior

```yaml
tasks:
  dev:
    run: once
```

### platforms
- **Type:** []string
- **Description:** Restrict task to specific platforms

```yaml
tasks:
  open:
    platforms: [darwin]
```

### internal
- **Type:** bool
- **Description:** Hide from --list

```yaml
tasks:
  helper:
    internal: true
```

### cmd
- **Type:** string or object
- **Description:** Single command with options

```yaml
tasks:
  build:
    cmd:
      cmd: go build ./...
      set: [errexit]
      shopt: [globstar]
      interactive: false
      silent: false
      dir: ./cmd
      env:
        CGO_ENABLED: "0"
      platforms: [linux, darwin]
      timeout: 5m
      quiet: false
```

### loop
- **Type:** object
- **Description:** Loop over items

```yaml
tasks:
  test-all:
    cmds:
      - for: [unit, integration, e2e]
        cmd: go test ./.../{{.ITEM}}
```