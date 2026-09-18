# Waza CI Integration

Patterns for gating skill regressions in CI, based on waza v0.38.7 and its `examples/ci/` templates. Authoritative source: https://github.com/microsoft/waza/blob/main/examples/ci/README.md.

## Recommended flow

1. Author `eval.yaml` in the skill directory (see `waza-eval-format.md`).
2. Capture a baseline: `waza run skills/<name>/eval.yaml -o baseline.json` and commit it.
3. On PR: run eval → `waza gate --baseline baseline.json --current results.json --format github-actions`.
4. Update baseline deliberately when intentional behavior changes merge.

## Minimal GitHub Actions job

```yaml
jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.26'
      - run: go install github.com/microsoft/waza@latest
      - run: waza run skills/my-skill/eval.yaml -o results.json --reporter junit:results.xml
        env:
          # Copilot auth for the copilot-sdk executor
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
      - run: waza gate --baseline baseline.json --current results.json --max-regression-pct 5 --format github-actions
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: waza-results
          path: |
            results.json
            results.xml
```

## Exit code handling

`waza gate` exit 1 = pass-rate regression, 2 = golden failure (takes precedence), 3 = config error. The GitHub Actions format emits `::error::` / `::warning::` annotations plus a step summary.

## Cost control

- `executor: mock` in eval.yaml for structural dry-runs (no LLM cost).
- `trials_per_task: 1` on PRs, `3+` on merge to main.
- `--tags fast` on PRs; run the full tagged suite nightly.
- `waza run --cache` with `.waza-cache/` committed to `.gitignore` for local reuse.
