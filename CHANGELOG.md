# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.3] - 2026-08-24

### Changed

- **Switching is about 30x faster**, from roughly 5.8s to 0.2s. Reading gh's
  active account and its list of known accounts both went through
  `gh auth status`, which validates every token it holds over the network: about
  1.2s for the active account, and 4.4s for all three. Neither answer needs a
  token proved good, and both are in `~/.config/gh/hosts.yml`, so they are now
  read from there. `git-who` drops from about 1.3s to 0.06s for the same reason.

  Falls back to `gh auth status` whenever the file cannot answer — missing,
  unreadable, unparseable, or a token supplied through `GH_TOKEN` /
  `GITHUB_TOKEN`, which gh honours over the file. A layout change upstream costs
  the speed, never correctness.

### Fixed

- **Removing the persona that was in force left its identity in `~/.gitconfig`.**
  `git-remove` dropped the persona block, the `~/.ssh/config` alias and the gh
  token, but never the name and email the persona had written globally. The next
  commit was therefore authored as an account that no longer existed, and pushed
  on whatever token gh promoted in its place — the exact mismatch this plugin
  exists to prevent, reachable through the plugin's own command.

  Now, when the removed persona is the live one: it switches to the first
  remaining persona, moving gh with it rather than swapping one mismatch for
  another. When it was the last persona, `user.name`, `user.email` and
  `core.sshCommand` are cleared, so git asks who you are instead of signing as a
  ghost. Removing a persona that is *not* in force still leaves `~/.gitconfig`
  untouched. The confirmation says which of the three is about to happen.

- **The removal confirmation could give the wrong reason for keeping a gh
  token.** "kept, another profile uses it" was printed whenever the token was
  not going to be dropped, including when the account had simply never been
  logged in. The two cases now read differently.

### Added

- **`git-add` can generate the ssh key for you.** The key list now ends with
  `+ generate a new key`, and a run with no keys at all goes straight there
  instead of prompting for the path of a file that does not exist. It explains
  what it is about to do in four lines, makes an ed25519 pair with the account's
  address as the comment, copies the public half to your clipboard, and opens
  <https://github.com/settings/ssh/new> so it can be pasted in. The public key
  is printed as well, in case the clipboard is clobbered on the way to the
  browser.

  Because the comment is set to the address you gave, the email step that
  follows reads it back rather than asking again. Existing files are never
  overwritten, and `ssh-keygen` prompts for the passphrase itself.

- **Switching offers to re-author the commits you have not pushed yet.** Making
  a commit under one persona and then switching before pushing was the one route
  left to the mismatch this plugin exists to prevent, because `git commit` never
  checks permissions and by push time both halves agree again. A switch now
  notices and asks:

  ```text
     2 unpushed commits authored as old@example.com
     re-author to New Name <new@example.com>? [y/N]
  ```

  Deliberately narrow, and never silent:

  - Only commits reachable from `HEAD` but from no remote branch. Those have
    never left the machine, so nothing needs a force push and no clone breaks.
    Anything already pushed is shared history and is left alone.
  - Only commits authored by another of *your* personas. A cherry-pick or a
    mailed patch from a colleague keeps its author.
  - Refuses, without changing anything, on a dirty tree, a detached `HEAD`, a
    rebase already in progress, or a merge among the pending commits.
  - Asked, never assumed. Rewriting commits changes their hashes, which is not
    something a config switch should do behind your back. Declining leaves a
    note in the readout so it is not forgotten.

## [1.0.3] - 2026-08-24

### Fixed

- **A persona could clone and push to repositories its account had no access
  to.** Switching personas moved `gh`'s active account, but nothing made git
  ask `gh` for the password. Git collects credential helpers from every config
  scope, and on macOS `/etc/gitconfig` ships `helper = osxkeychain`, which
  answers first with whichever token it cached on the first push. That token is
  bound to one account permanently, so over HTTPS every persona authenticated
  as that one account regardless of which was selected. `git-add` now runs `gh
  auth setup-git`, and both `git-who` and every switch warn when HTTPS auth is
  not routed through `gh`.

  Machines where `gh auth login` was completed with HTTPS as the preferred
  protocol were already configured correctly and never saw this; those set up
  over SSH were affected.

- **The wrong SSH key could be used when ssh-agent held more than one.**
  `core.sshCommand` was written as `ssh -i <key>`, but `-i` only adds a key to
  the ones ssh offers; agent keys are still offered first and GitHub accepts the
  first that matches any account, so the persona was effectively decided by
  agent order. Now written with `-o IdentitiesOnly=yes`.

### Documentation

- Requirements explain the HTTPS credential-helper dependency and how to check
  it; "What a switch actually sets" now covers SSH and HTTPS auth separately.

## [1.0.2] - 2026-08-21

### Fixed

- **The uninstall command left the plugin directory behind.** `omz plugin
  disable` exits non-zero when the plugin is not currently enabled, so the `&&`
  skipped the removal. Reinstalling then failed with `destination path already
  exists and is not an empty directory`. It now uses a semicolon, so the removal
  runs whether or not the plugin was enabled.

### Documentation

- Documented how to update an existing install with `git pull`, and added a
  troubleshooting entry for the `destination path already exists` error that
  cloning over one produces.

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

[1.0.2]: https://github.com/asifshirazi/zsh-git-persona/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/asifshirazi/zsh-git-persona/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/asifshirazi/zsh-git-persona/releases/tag/v1.0.0
