# Changelog

## [0.1.0] - 2026-11-11

### ✨ Introduce new features

- Add :NitEdit
- Give the comment buffers their own filetype
- Add a Neovim to try nitpick in
- Label nits the Conventional Comments way

### 👷 Add or update CI build system

- Release through the Presswerk GitHub App
- Release with Presswerk
- Build and cache the flake on GitHub Actions

### 📝 Add or update documentation

- Rework the help after a read-through
- Sharpen the help's introduction
- Settle the description and tagline

### ♻️ Refactor code

- Name the flake outputs in kebab-case
- Restructure the flake with flake-parts

### 🚚 Move or rename resources (e.g.: files, paths, routes)

- Read the project's review prompt from .nitpick/
- Move the agent integrations to integrations/

### ⚡️ Improve performance

- Cache Presswerk in the release job
- Take nix-fast-build from the flake's nixpkgs in CI

### 🎨 Improve structure / format of the code

- Use inherit for release versions

### 🍱 Add or update assets

- Add logo

### 🔥 Remove code or files

- Drop the nixvim module

### 💄 Add or update the UI and style files

- Start a multiline nit's bracket with ŋ

### 🎉 Begin a project

- Begin nitpick.nvim

### ✅ Add, update, or pass tests

- Let the tests run against built packages

### 🔧 Add or update configuration files

- Use Presswerk's release metadata

