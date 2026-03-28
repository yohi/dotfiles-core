# Design: Unify Component README.md and AGENTS.md

## 1. Overview
Ensure consistency across all component repositories (`components/dotfiles-*`) by unifying the descriptions regarding their relationship with `dotfiles-core` in `README.md` and `AGENTS.md`.

## 2. Requirements
- **README.md (Japanese)**: Add a standardized "Management and Dependencies" section immediately after the "Overview" section.
- **AGENTS.md (English)**: Add a standardized "COMPONENT LAYOUT CONVENTION" section early in the file.
- **Scope**: All components listed in `repos.yaml`.

## 3. Standard Templates

### 3.1 README.md (Japanese)
To be inserted after the "Overview" (概要) section:

```markdown
## 管理と依存関係

本リポジトリは [dotfiles-core](https://github.com/yohi/dotfiles-core) によって管理されるコンポーネントの一つです。

### ⚠️ 単体使用時の注意点
本リポジトリは `dotfiles-core` の共通 Makefile ルール（`common-mk`）に依存しています。単体で使用（クローン）する場合は、以下の手順が必要です：

1. `common-mk` ディレクトリを本リポジトリの親ディレクトリに配置するか、パスを適切に設定してください。
2. `make help` を実行して、正しく設定されていることを確認してください。

推奨される使用方法は、`dotfiles-core` から `make setup` を実行することです。
```

### 3.2 AGENTS.md (English)
To be inserted before the `## STRUCTURE` or `## PROJECT KNOWLEDGE BASE` section:

```markdown
## COMPONENT LAYOUT CONVENTION

This repository is part of the **dotfiles polyrepo** orchestrated by [dotfiles-core](https://github.com/yohi/dotfiles-core).
All changes MUST comply with the central layout rules. Please refer to the central [ARCHITECTURE.md](https://raw.githubusercontent.com/yohi/dotfiles-core/refs/heads/master/docs/ARCHITECTURE.md) for the full, authoritative rules and constraints.
```

## 4. Target Components
- dotfiles-zsh
- dotfiles-vim
- dotfiles-git
- dotfiles-term
- dotfiles-ide
- dotfiles-ai
- dotfiles-gnome
- dotfiles-system

## 5. Verification Strategy
- Manually verify each file's content after modification.
- Ensure no broken links or formatting issues (markdownlint).
