# Contributing Guide

Thank you for contributing to **RoboCup_ARM**.
This guide defines a consistent workflow for code, models, and documentation changes.

## 1) Scope and Principles

- Keep changes focused. One PR should solve one clear problem.
- Do not mix unrelated changes in the same commit/PR.
- Prefer reproducibility: avoid machine-specific paths and temporary local settings.
- Keep behavior stable unless the PR explicitly targets a behavior change.

## 2) Branch Naming

Use short, descriptive branch names:

- `feat/<short-name>` for new features
- `fix/<short-name>` for bug fixes
- `docs/<short-name>` for documentation-only changes
- `refactor/<short-name>` for code structure improvements without behavior changes
- `chore/<short-name>` for maintenance tasks

## 3) Commit Message Convention

Use conventional commit prefixes:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `refactor: ...`
- `chore: ...`

Good commit message examples:

- `fix: stabilize cube edge yaw guard trigger`
- `docs: clarify auto grasp startup steps`
- `chore: add mp4 tracking via Git LFS`

## 4) Local Validation Before Commit

Before committing, run these checks:

1. Project starts correctly:
   - `run('scripts/run_oneclick.m')`
2. Auto-grasp startup flow works:
   - Wait for `Vision Preview`
   - Click preview window to focus
   - Press `Space` or `S` to start auto loop
3. If your change affects world/map behavior:
   - Verify both `Test World 1` and `Test World 2`
   - Press `Ctrl + D` after world toggle in `RoboCup_ARM.slx`
4. If your change affects cube edge strategy:
   - Verify edge trigger conditions
   - Confirm no regression for non-cube targets
5. Basic script quality:
   - No syntax/runtime errors in touched scripts
   - Optional: run MATLAB `checkcode` on modified `.m` files

## 5) Pull Request Requirements

Each PR should include:

- Purpose: what problem this PR solves
- Change summary: main files/modules touched
- Validation steps: exactly how you tested
- Result evidence: key logs, screenshots, or short clips when useful
- Risk notes: known limitations or side effects

Avoid:

- Unrelated formatting-only edits across many files
- Mixing model, logic, and documentation changes without clear reason

## 6) File and Encoding Rules

- Keep MATLAB source files in readable UTF-8/ASCII (avoid garbled text).
- Do not commit local temporary files or generated cache artifacts.
- Keep comments concise and technical.

## 7) Large Files and Git LFS

Use Git LFS for large binary assets, especially:

- `*.mp4`
- Large model files if frequently updated

Typical workflow:

1. `git lfs track "*.mp4"`
2. `git add .gitattributes <large-file>`
3. `git commit -m "chore: ..."`

## 8) Dependencies

If you add/update dependencies:

- Update `README.md` accordingly
- For Python packages, update `requirement.txt`
- Explain why the dependency is needed in PR description

## 9) Collaboration Etiquette

- Discuss major architecture changes before implementation.
- Keep review comments actionable and specific.
- When uncertain, prefer smaller incremental PRs.

