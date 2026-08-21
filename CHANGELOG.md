# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-08-21

Documentation only. No change to how the plugin behaves.

### Documentation

- Spelled out the SSH key prerequisite. A persona is built around a key, so
  `git-add` has nothing to offer without at least one private key in `~/.ssh`
  with its `.pub` beside it. This is now stated in Quick start with the
  `ssh-keygen` line to satisfy it, and in full under Requirements.
- Added two troubleshooting entries for the ways that bites: no keys found at
  all, and a key whose missing or hostname-only `.pub` makes the commit email
  fall back to a prompt.
- Shortened the install and uninstall commands to use `$ZSH_CUSTOM` directly,
  matching the convention the rest of the oh-my-zsh ecosystem uses. oh-my-zsh
  sets the variable itself, and the command already required `omz`, so the
  longer fallback was guarding a case that could not arise.
- Added this changelog.

## [1.0.0] - 2026-08-21

First public release.

### Added

- **Personas.** A persona ties one account's commit identity, SSH key and `gh`
  login together. Switching moves all three at once, so a commit can no longer
  be authored by one account and pushed with another's credentials.
- **`git-add`.** Adds a persona in three answers. It lists the private keys in
  `~/.ssh`, reads the commit email from the key's `.pub` comment, signs you in
  to GitHub, and takes the display name from that profile. On macOS the one-time
  device code is copied to the clipboard as `gh` prints it.
- **`git-switch`.** Arrow-key picker over your personas, starting on whichever
  is already in force. Accepts a number or a name as an argument, so it works in
  a script too.
- **`git-<persona>`.** One command per persona, generated from the persona file.
- **`git-who`.** Shows the persona in force and warns when its parts disagree,
  including when a repo's own `user.email` is overriding the global one.
- **`git-remove`.** Drops a persona, its `~/.ssh/config` alias and its `gh`
  token. The confirmation lists everything that will go before you answer, and
  a token shared with another persona is kept.
- **`git-id-locals`.** Finds repos pinned to their own identity that ignore the
  global one. `--clear` unpins them.
- **`git-id-icons`.** Prints each glyph repeated between brackets, so a font
  missing one is obvious rather than silently costing a column of alignment.
- **Separate persona file.** Accounts live in
  `~/.config/git-persona/profiles.zsh`, never in the plugin, so the plugin can
  be updated or shared without carrying anyone's accounts. Created on first
  `git-add`; installing writes nothing.
- **`~/.ssh/config` upkeep.** `git-add` writes a `Host` alias for the key and
  `git-remove` deletes it, matched by `IdentityFile` rather than by alias name.

### Notes

- Requires zsh, git and the [GitHub CLI](https://cli.github.com).
- A Nerd Font is optional. Without one, ASCII markers stand in for the icons and
  the layout is unchanged. Outside a UTF-8 locale it falls back automatically.
- Developed on macOS. Everything works elsewhere except two extras that switch
  themselves off rather than failing: copying the device code to the clipboard,
  and preserving the `~/.ssh/config` file mode.

[1.0.1]: https://github.com/asifshirazi/zsh-git-persona/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/asifshirazi/zsh-git-persona/releases/tag/v1.0.0
