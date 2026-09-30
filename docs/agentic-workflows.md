# Agentic Workflows

## Before editing

- Read the root `AGENTS.md` and only the topic guides relevant to the task.
- Inspect adjacent source and tests before choosing names or architecture.
- Check `git status` and preserve unrelated or pre-existing user changes.
- Prefer the smallest coherent change that solves the requested behavior.

## Safe autonomous work

Agents may inspect files and history and run local, non-destructive checks such
as `git diff`, `git status`, `rg`, `./check_code_line_lengths.sh`, `swift test`,
and `swift build`. Do not push, publish, deploy, modify git history, install
software, open network exposure, or terminate unverified processes unless the
user explicitly requests it.

Ask before actions that are destructive or that materially expand scope,
including changing public behavior without a stated migration, removing
persisted compatibility, changing signing/distribution, or weakening a network
or process-ownership safeguard.

## Implementation and verification

- Keep edits focused; do not overwrite unrelated work in a dirty tree.
- Add or update tests with behavioral changes. A documentation-only change does
  not require manufactured tests.
- Run the narrowest useful check while iterating and the full applicable gate
  before handoff.
- Never claim a command passed unless it was run in the current worktree.
- Review the final diff for accidental generated files, secrets, unrelated
  formatting, and violations of these guides.

The handoff should lead with the outcome, list validation actually performed,
and call out any unverified visual behavior, residual risk, or follow-up work.
