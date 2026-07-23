# Common Tasks

Step-by-step procedures for recurring maintenance tasks in this orchestrator repo.

## Adding a new component repository

1. Add an entry to `repos.yaml`:

   ```yaml
   components/dotfiles-<name>:
     type: git
     url: git@github.com:yohi/dotfiles-<name>.git
     version: master
   ```

2. Run `make sync` to clone it into `components/`.
3. Create a `Makefile` in the new component repo with `setup` and `link` targets
   (see `docs/ARCHITECTURE.md` for the required layout).

## Checking component status

```bash
# List all checked-out components
ls -la components/

# Git status across all components
vcs status components/

# Git diff across all components
vcs diff components/
```
