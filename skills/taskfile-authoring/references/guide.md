# Taskfile Guide

Comprehensive guide to Taskfile features and usage patterns.
Last verified: 2026-09-13

## Table of Contents

1. [Running Taskfiles](#running-taskfiles)
2. [Environment Variables](#environment-variables)
3. [Including Other Taskfiles](#including-other-taskfiles)
4. [Variables and Templating](#variables-and-templating)
5. [Task Dependencies](#task-dependencies)
6. [Sources and Generates](#sources-and-generates)
7. [Preconditions](#preconditions)
8. [Cross-Platform Compatibility](#cross-platform-compatibility)
9. [Advanced Features](#advanced-features)

## Running Taskfiles

### Supported File Names

Task looks for files in this priority order:
1. `Taskfile.yml`
2. `taskfile.yml`
3. `Taskfile.yaml`
4. `taskfile.yaml`
5. `Taskfile.dist.yml`
6. `taskfile.dist.yml`
7. `Taskfile.dist.yaml`
8. `taskfile.dist.yaml`

The `.dist` variants allow projects to have one committed file while allowing individual overrides.

### Running from Subdirectories

If a Taskfile isn't in the current directory, Task walks up the file tree until it finds one. Use `{{.USER_WORKING_DIR}}` for reusable tasks:

```yaml
version: '3'
tasks:
  up:
    dir: '{{.USER_WORKING_DIR}}'
    preconditions:
      - test -f docker-compose.yml
    cmds:
      - docker-compose up -d
```

### Global Taskfile

Run with `--global` (or `-g`) to look for `$HOME/{T,t}askfile.{yml,yaml}`:

```yaml
version: '3'
tasks:
  from-working-directory:
    dir: '{{.USER_WORKING_DIR}}'
    cmds:
      - pwd
```

### Running from stdin

```sh
task -t - < ./Taskfile.yml
# OR
cat ./Taskfile.yml | task -t -
```

### Remote Taskfiles

```sh
$ task --taskfile https://raw.githubusercontent.com/go-task/task/main/website/src/public/Taskfile.yml task: [hello] echo "Hello Task!"
```

## Environment Variables

### Task-level Environment Variables

```yaml
version: '3'
tasks:
  greet:
    cmds:
      - echo $GREETING
    env:
      GREETING: Hey, there!
```

### Global Environment Variables

```yaml
version: '3'
env:
  GREETING: Hey, there!
tasks:
  greet:
    cmds:
      - echo $GREETING
```

### .env Files

```yaml
version: '3'
env:
  ENV: testing
dotenv: ['.env', '{{.ENV}}/.env', '{{.HOME}}/.env']
tasks:
  greet:
    cmds:
      - echo "Using $KEYNAME and endpoint $ENDPOINT"
```

When the same variable is defined in multiple dotenv files, the first file takes precedence:

```yaml
version: '3'
dotenv:
  - .env.local # Highest priority
  - .env.{{.ENV}} # Environment-specific
  - .env # Base defaults
```

## Including Other Taskfiles

### Basic Includes

```yaml
version: '3'
includes:
  docs: ./documentation
  docker: ./DockerTasks.yml
```

Tasks available as `task docs:serve` or `task docker:build`.

### Remote Taskfiles

```yaml
version: '3'
includes:
  my-remote-namespace: https://raw.githubusercontent.com/go-task/task/main/website/src/public/Taskfile.yml
```

### OS-Specific Taskfiles

```yaml
version: '3'
includes:
  build: ./Taskfile_{{OS}}.yml
```

### Directory of Included Taskfile

```yaml
version: '3'
includes:
  docs:
    taskfile: ./docs/Taskfile.yml
    dir: ./docs
```

### Optional Includes

```yaml
version: '3'
includes:
  tests:
    taskfile: ./tests/Taskfile.yml
    optional: true
```

### Internal Includes

```yaml
version: '3'
includes:
  tests:
    taskfile: ./taskfiles/Utils.yml
    internal: true
```

### Flatten Includes

```yaml
version: '3'
includes:
  common:
    taskfile: ./common.yml
    flatten: true
```

### Excludes

```yaml
version: '3'
includes:
  shared:
    taskfile: ./shared.yml
    excludes: [internal-setup, 'debug:*', 'experimental:*']
```

### Aliases for Namespaces

```yaml
version: '3'
includes:
  database:
    taskfile: ./db.yml
    aliases: [db, data]
```

## Variables and Templating

### Static Variables

```yaml
version: '3'
vars:
  APP_NAME: myapp
  VERSION: 1.0.0
  DEBUG: true
  FEATURES: [auth, logging, metrics]
```

### Dynamic Variables (sh)

```yaml
version: '3'
vars:
  COMMIT_HASH: sh: git rev-parse HEAD
  BUILD_TIME: sh: date -u +"%Y-%m-%dT%H:%M:%SZ"
```

### Variable References (ref)

```yaml
version: '3'
vars:
  BASE_VERSION: 1.0.0
  FULL_VERSION: ref: .BASE_VERSION
```

### Map Variables (map)

```yaml
version: '3'
vars:
  CONFIG: map:
    database:
      host: localhost
      port: 5432
    cache:
      type: redis
      ttl: 3600
```

### Secret Variables

```yaml
version: '3'
vars:
  API_KEY:
    value: 'sk-1234567890abcdef'
    secret: true
  DB_PASSWORD:
    sh: vault read -field=password secret/db
    secret: true
```

### Variable Ordering

Variables can reference previously defined variables:

```yaml
version: '3'
vars:
  GREETING: Hello
  TARGET: World
  MESSAGE: '{{.GREETING}} {{.TARGET}}!'
```

## Task Dependencies

### Simple Dependencies

```yaml
version: '3'
tasks:
  deploy:
    deps: [build, test]
    cmds:
      - ./deploy.sh
```

### Dependencies with Variables

```yaml
version: '3'
tasks:
  advanced-deploy:
    deps:
      - task: build
        vars:
          ENVIRONMENT: production
      - task: test
        vars:
          COVERAGE: true
    cmds:
      - ./deploy.sh
```

### Silent Dependencies

```yaml
version: '3'
tasks:
  main:
    deps:
      - task: setup
        silent: true
    cmds:
      - echo "Main task"
```

### Loop Dependencies

```yaml
version: '3'
tasks:
  test-all:
    deps:
      - for: [unit, integration, e2e]
        task: test
        vars:
          TEST_TYPE: '{{.ITEM}}'
    cmds:
      - echo "All tests completed"
```

## Sources and Generates

### Basic Usage

```yaml
version: '3'
tasks:
  build:
    cmds:
      - go build -o bin/app .
    sources:
      - '*.go'
      - go.mod
      - go.sum
    generates:
      - bin/app
    method: checksum
```

### Method Options

- `checksum` (default): Compare file checksums
- `timestamp`: Compare modification times
- `none`: Always run

## Preconditions

```yaml
version: '3'
tasks:
  deploy:
    preconditions:
      - test -f deploy.key
      - sh: test "$ENV" = "production"
        msg: "Not in production environment"
    cmds:
      - ./deploy.sh
```

## Cross-Platform Compatibility

Task uses mvdan/sh, a native Go sh interpreter. Write sh/bash-like commands that work across platforms:

```yaml
version: '3'
tasks:
  clean:
    cmds:
      - rm -rf dist/
      - rm -f *.log
```

### Platform-Specific Commands

```yaml
version: '3'
tasks:
  open:
    cmds:
      - cmd: open .
        platforms: [darwin]
      - cmd: xdg-open .
        platforms: [linux]
      - cmd: start .
        platforms: [windows]
```

## Advanced Features

### Watch Mode

```yaml
version: '3'
tasks:
  dev:
    cmds:
      - npm run dev
    run: once
    interval: 1s
```

### Prompt Before Execution

```yaml
version: '3'
tasks:
  deploy:
    prompt: "Deploy to production?"
    cmds:
      - ./deploy.sh
```

### Task Aliases

```yaml
version: '3'
tasks:
  build:
    aliases: [compile, make]
    cmds:
      - go build ./...
```

### Internal Tasks

```yaml
version: '3'
tasks:
  helper:
    internal: true
    cmds:
      - echo "This won't show in --list"
```

### Shell Options

```yaml
version: '3'
set: [errexit, nounset, pipefail]
tasks:
  strict:
    cmds:
      - set -euo pipefail
      - echo "Strict mode"
```

### Output Control

```yaml
version: '3'
output: group
tasks:
  build:
    cmds:
      - go build ./...
```

### Silent Mode

```yaml
version: '3'
tasks:
  quiet:
    silent: true
    cmds:
      - echo "No task metadata printed"
```

### Interrupt Handling

```yaml
version: '3'
tasks:
  long-running:
    cmds:
      - ./long-process.sh
    interruptible: true
```

### Timeout

```yaml
version: '3'
tasks:
  slow:
    cmds:
      - ./slow-operation.sh
    timeout: 30s
```

### User Working Directory

```yaml
version: '3'
tasks:
  relative:
    dir: '{{.USER_WORKING_DIR}}'
    cmds:
      - pwd
```