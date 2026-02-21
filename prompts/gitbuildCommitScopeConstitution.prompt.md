---
name: gitbuildCommitScopeConstitution
description: Build and maintain a constitution defining valid scopes for atomic commits in a git repository
argument-hint: The path to the git repository (defaults to current working directory)
metadata:
  version: 1.0.1
  author: arisng
---
Use the git-commit-scope-constitution skill to build or update a living constitution for the specified git repository (default to current working directory). Follow the skill's workflow to analyze repository structure, extract historical scopes, and create or update the scope constitution and inventory files in the .github directory.
