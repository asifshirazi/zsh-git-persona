# zsh-git-persona

---

![Picking a persona with git-switch, and the banner it prints](git-switch.jpg)

Git will happily let you commit as one person and push as another. It never warns
you, the push succeeds, and the wrong name is on that history for good.
`zsh-git-persona` makes that impossible: a **persona** ties one account's commit
identity, SSH key and `gh` login together, and switches them as a unit. Add as
many as you have accounts.

## Installation

**oh-my-zsh**, clone, enable and reload in one go:

```zsh
git clone https://github.com/asifshirazi/zsh-git-persona.git $ZSH_CUSTOM/plugins/git-persona && omz plugin enable git-persona && exec zsh
```

`omz` is oh-my-zsh's own CLI, so it edits `plugins=(...)` correctly whether yours
is on one line or several, and says so rather than duplicating if the plugin is
already enabled. On an oh-my-zsh too old to have it, add `git-persona` to
`plugins=(...)` in `~/.zshrc` by hand, then run `source ~/.zshrc` or `exec zsh`.
Either picks it up in the shell you already have open.

### Quick start

Run `git-add`. It walks you through everything and offers to generate an SSH
key when you have none, so there is nothing to set up first.

```zsh
git-add          # add your first persona; makes a key if you have none
git-switch       # pick one, any time
git-who          # check which one is live
```

The commit email comes from the key's `.pub` comment. Add the matching public
half to that account under [Settings > SSH keys](https://github.com/settings/keys),
and see [Requirements](#requirements) for the detail.

## Updating

```zsh
git -C $ZSH_CUSTOM/plugins/git-persona pull && exec zsh
```

Pull rather than clone again. Cloning over an existing install fails with
`destination path already exists and is not an empty directory`.

Your personas are not touched. They live in `~/.config/git-persona/`, outside
the plugin directory, so updating and even reinstalling leaves them alone.

## Commands

| Command | Does |
|---|---|
| `git-add` | Add a persona. Signs you into `gh`, reads the rest from the key and the account. |
| `git-switch` | Pick a persona from an arrow-key list and switch to it. |
| `git-<persona>` | Switch straight to that persona. Created for each one you add. |
| `git-who` | Show the persona in force, and warn if its parts disagree. |
| `git-remove` | Drop a persona, its `~/.ssh/config` alias, and its `gh` token. Key files are never deleted. |
| `git-persona-uninstall` | Undo everything the plugin created: persona data, `~/.ssh/config` aliases, and the live `~/.gitconfig` identity. Keeps `gh` logins and key files. |
| `git-id-locals` | Find repos pinned to their own identity that ignore the global one. |
| `git-id-locals --clear` | Unpin them, so they all follow the global identity. |
| `git-id-icons` | Check whether your font has the glyphs. |

### Commits waiting to be pushed

`git commit` never checks permissions. It writes to `.git/` on your own disk,
with no server involved, so any repo will accept a commit under any identity.
Permission exists only at push time. That leaves one way to end up with the
wrong name on a commit: commit under one persona, switch, then push — by which
point both halves agree again and nothing looks wrong.

So a switch checks, and asks:

```text
   2 unpushed commits authored as old@example.com
   re-author to New Name <new@example.com>? [y/N]
```

It is deliberately narrow:

- **Unpushed only.** Commits reachable from `HEAD` but from no remote branch.
  They have never left your machine, so nothing needs a force push and nobody's
  clone breaks. Already-pushed commits are shared history and are left alone.
- **Yours only.** Only commits authored by another of your personas. A
  cherry-pick or a mailed patch from a colleague keeps its author.
- **It refuses rather than half-finishing.** A dirty tree, a detached `HEAD`, a
  rebase in progress, or a merge among the pending commits all stop it with an
  explanation, having changed nothing.
- **Never silent.** Rewriting commits changes their hashes, so it is always a
  question. Say no and the readout reminds you the mismatch is still there.

To fix a commit that is *already* pushed you have to rewrite shared history
yourself, which is a decision worth making deliberately:

```zsh
git commit --amend --reset-author --author="Name <you@example.com>"
git push --force-with-lease
```

## Where your personas live

In `~/.config/git-persona/profiles.zsh`, never in the plugin. One readable
block per persona, safe to edit by hand:

```zsh
git-id-profile personal                    \
    name    'Your Name'                    \
    email   'you@example.com'              \
    key     '~/.ssh/id_rsa_personal'       \
    gh      'yourname'                     \
    accent  208                            \
    shadow  130
```

The file is created on your first `git-add`. Installing the plugin writes
nothing.

## Requirements

- zsh, git, and the [GitHub CLI](https://cli.github.com) (`gh`)
- **HTTPS auth routed through `gh`.** Switching personas moves `gh`'s active
  account, but that only governs `git clone` and `git push` if git actually
  asks `gh` for the password. It does not by default: git collects credential
  helpers from every scope, and on macOS `/etc/gitconfig` ships
  `helper = osxkeychain`, which answers first with whichever token it cached on
  your very first push. That token belongs to one account permanently, so
  **every persona would clone and push as that one account.**

  `git-add` runs `gh auth setup-git` for you, and `git-who` warns if it is ever
  undone. To check or fix it by hand:

  ```zsh
  git config --get-urlmatch credential.helper https://github.com   # want: gh
  gh auth setup-git                                                # if not
  ```
- A [Nerd Font](https://www.nerdfonts.com) is **optional**. Without one you get
  ASCII markers instead of icons and the layout is unaffected. Run
  `git-id-icons` to check. Outside a UTF-8 locale it falls back automatically.

## Uninstalling

Run `git-persona-uninstall` first, then remove the plugin:

```zsh
git-persona-uninstall                                                  # clean up what it created
omz plugin disable git-persona; rm -rf $ZSH_CUSTOM/plugins/git-persona # then remove the plugin
```

## Changelog

Every release is listed in [CHANGELOG.md](CHANGELOG.md). Current version 1.1.4.
The plugin sets `$GIT_ID_VERSION`, so `print $GIT_ID_VERSION` gives you the
number for a bug report.

## Licence

[MIT](LICENSE)
