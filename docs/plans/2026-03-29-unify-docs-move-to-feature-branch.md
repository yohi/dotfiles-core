# Plan: Move documentation changes to feature branch

For each component:
1. Create `feature/unify-docs` at the current `master` HEAD.
2. Push `feature/unify-docs` to origin.
3. Reset `master` to the previous commit (HEAD^).
4. Verify results.

Components:
- [x] dotfiles-zsh
- [x] dotfiles-vim
- [x] dotfiles-git
- [x] dotfiles-term
- [x] dotfiles-ide
- [x] dotfiles-ai
- [x] dotfiles-gnome
- [x] dotfiles-system
