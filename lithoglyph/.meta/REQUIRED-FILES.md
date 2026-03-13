# Required Repository Files

The following files **MUST** be present and kept up-to-date in every repository:

## Mandatory Dotfiles

| File | Purpose |
|------|---------|
| `.gitignore` | Exclude build artifacts, secrets, and temp files |
| `.gitattributes` | Enforce LF line endings and diff settings |
| `.editorconfig` | Consistent editor settings across IDEs |
| `.tool-versions` | asdf version pinning for reproducible builds |

## Mandatory SCM Files

| File | Purpose |
|------|---------|
| `META.scm` | Architecture decisions, development practices |
| `STATE.scm` | Project state, phase, milestones |
| `ECOSYSTEM.scm` | Ecosystem positioning, related projects |
| `PLAYBOOK.scm` | Executable plans, procedures |
| `AGENTIC.scm` | AI agent operational gating |
| `NEUROSYM.scm` | Symbolic semantics, proof obligations |

## Build System

| File | Purpose |
|------|---------|
| `justfile` | Task runner (replaces Makefile) |
| `Mustfile` | Deployment state contract |

**IMPORTANT**: Makefiles are FORBIDDEN. Use `just` for all tasks.

## Validation

These files are checked by:
- CI workflow validation
- Pre-commit hooks (when configured)
- Repository standardization scripts

## Updates

When updating these files:
1. Use templates from `rsr-template-repo` as reference
2. Ensure SPDX license header is present
3. Test changes locally before pushing
4. Keep language-specific sections relevant to the repo

## See Also

- [RSR (Rhodium Standard Repositories)](https://github.com/hyperpolymath/rhodium-standard-repositories)
- [Mustfile Specification](https://github.com/hyperpolymath/mustfile)
- [SCM Format Family](https://github.com/hyperpolymath/meta-scm)
