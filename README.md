# zsh-git-persona

---

![Picking a persona with git-switch, and the banner it prints](git-switch.jpg)

Git will happily let you commit as one person and push as another. It never warns
you, the push succeeds, and the wrong name is on that history for good.
`zsh-git-persona` makes that impossible: a **persona** ties one account's commit
identity, SSH key and `gh` login together, and switches them as a unit. Add as
many as you have accounts.

- [Why](#why)
- [Installation](#installation)
- [Commands](#commands)
  - [Adding a persona](#adding-a-persona)
  - [What a switch actually sets](#what-a-switch-actually-sets)
- [Where your personas live](#where-your-personas-live)
- [Configuration](#configuration)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Changelog](#changelog)
- [Licence](#licence)

## Why

Git treats **authorship** and **authentication** as unrelated, and nothing
warns you when they disagree:

- `user.email` is free text stamped into the commit. Git never verifies it.
- The token is what GitHub actually enforces.

So a commit can be signed as one account and pushed with another's credentials.
It succeeds, and the wrong name is on the history permanently. Setting only the
email, as most multi-account guides suggest, does not prevent this.

This plugin moves identity, key and login together, and `git-who` tells you when
something is out of step.

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

**Other plugin managers**

```zsh
zinit light asifshirazi/zsh-git-persona
```

```zsh
antidote bundle asifshirazi/zsh-git-persona
```

```zsh
sheldon add git-persona --github asifshirazi/zsh-git-persona
```

**Plain zsh**

```zsh
source /path/to/zsh-git-persona/git-persona.plugin.zsh
```

Then `source ~/.zshrc` (or `exec zsh`) and run `git-add`.

### Quick start

A persona is built around an SSH key, so you need one per account in `~/.ssh`
before `git-add` has anything to offer. If you already have them, skip the first
line.

```zsh
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519_work
git-add          # add your first persona, once per account
git-switch       # pick one, any time
git-who          # check which one is live
```

The `-C` comment is where the commit email comes from. Add the matching `.pub`
to that account under [Settings > SSH keys](https://github.com/settings/keys),
and see [Requirements](#requirements) for the detail.

## Commands

| Command | Does |
|---|---|
| `git-add` | Add a persona. Signs you into `gh`, reads the rest from the key and the account. |
| `git-switch` | Pick a persona from an arrow-key list and switch to it. |
| `git-<persona>` | Switch straight to that persona. Created for each one you add. |
| `git-who` | Show the persona in force, and warn if its parts disagree. |
| `git-remove` | Drop a persona, its `~/.ssh/config` alias, and its `gh` token. |
| `git-id-locals` | Find repos pinned to their own identity that ignore the global one. |
| `git-id-locals --clear` | Unpin them, so they all follow the global identity. |
| `git-id-icons` | Check whether your font has the glyphs. |

### Adding a persona

`git-add` lists the private keys in `~/.ssh` and asks three things. Everything
else it works out for itself:

```text
   keys in ~/.ssh  up/down, enter to pick
   > id_ed25519_work
     id_ed25519_personal

   email from id_ed25519_work.pub: ada@acme.example
   short name, used as git-<name>: work

   sign in to the github account this persona should use
   the one-time code is copied to your clipboard automatically
   ...
   signed in as ada-at-acme
   name from github: Ada Lovelace
```

The commit email comes from the key's `.pub` comment, the display name from
your GitHub profile, and the colours from a built-in palette. When it finishes
it switches you straight into the new persona.

### What a switch actually sets

All global, so one command governs every repo on the machine:

| | |
|---|---|
| `user.name`, `user.email` | `~/.gitconfig` |
| `core.sshCommand` | `~/.gitconfig` |
| Active `gh` account | `~/.config/gh/hosts.yml` |

It survives new shells and reboots. A repo with its own `user.email` still
outranks the global one; `git-who` flags that and `git-id-locals --clear` fixes
it.

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

## Configuration

Set any of these in `~/.zshrc` **before** the plugin loads.

| Variable | Default | Purpose |
|---|---|---|
| `GIT_ID_PROFILE_FILE` | `~/.config/git-persona/profiles.zsh` | Where personas are stored |
| `GIT_ID_SSH_CONFIG` | `~/.ssh/config` | Which ssh config to maintain |
| `GIT_ID_SCAN_ROOTS` | common code dirs | Where `git-id-locals` looks |
| `GIT_ID_MENU` | `arrows` | `numbers` to disable arrow-key pickers |
| `GIT_ID_AUTO_LOGIN` | `ask` | `always` or `never` for `gh auth login` |
| `GIT_ID_PALETTE` | 10 colours | Accents handed to new personas, neutral once used up |
| `GIT_ID_SEG_*` | muted tones | Colours of the readout bars |

## Requirements

- zsh, git, and the [GitHub CLI](https://cli.github.com) (`gh`)
- **An SSH key per account, in `~/.ssh`, each with its `.pub` beside it.** A
  persona is built around a key, so `git-add` has nothing to offer without one.
  The `.pub` is what the commit email is read from. Create one per account with:

  ```zsh
  ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519_work
  ```

  Then add the public half to that GitHub account under
  [Settings > SSH keys](https://github.com/settings/keys).
- A [Nerd Font](https://www.nerdfonts.com) is **optional**. Without one you get
  ASCII markers instead of icons and the layout is unaffected. Run
  `git-id-icons` to check. Outside a UTF-8 locale it falls back automatically.

Developed on macOS. Everything works elsewhere except two extras, which switch
themselves off rather than failing:

- **Device code to clipboard** needs `pbcopy`, `wl-copy`, `xclip` or `xsel`, and
  a BSD `script(1)`. Otherwise `gh auth login` simply runs normally.
- **`~/.ssh/config` file mode** is preserved via `stat`, with a GNU fallback.

## Troubleshooting

**`git-persona: no persona named 'x'`.** Run `git-switch` with no argument to
see what exists, or `git-add` to create it.

**Commits still show the wrong name.** A repo with its own `user.email` outranks
the global one. `git-who` says `overridden on this repo` when that is happening;
`git-id-locals` lists every repo doing it and `--clear` unpins them.

**Pushes still authenticate as the wrong account.** The `gh` account is separate
from the commit identity, and `gh`'s active account is machine-wide rather than
per shell, so a switch in one terminal moves it for all of them. `git-who` shows
which account is live next to the key.

**Boxes instead of icons.** No Nerd Font. Run `git-id-icons`: a blank between
brackets means the font has no glyph there. Nothing but the icons is affected.

**`git-add` shows no keys to pick from.** There are no private keys in `~/.ssh`.
Keys are found by content rather than by filename, so anything without a
`PRIVATE KEY` header is skipped. Generate one with `ssh-keygen`, as under
[Requirements](#requirements), then run `git-add` again. You can also type a
path at the prompt if your key lives elsewhere.

**It asked for the email instead of reading it.** The key has no `.pub` beside
it, or that file's comment is a hostname rather than an address, which is what
`ssh-keygen` writes when given no `-C`. Type the email and carry on, or
regenerate the public half with `ssh-keygen -y -f <key> > <key>.pub`.

**Edited the persona file by hand and nothing changed.** Run `source ~/.zshrc`.
Additions and removals are both picked up: a new block gets its `git-<persona>`
command, and a deleted one has its command removed.

**An eleventh persona looks grey.** The palette holds ten accents. Beyond that
personas fall back to a neutral colour and work normally. Set `accent` and
`shadow` in the block by hand, or extend `GIT_ID_PALETTE`, to colour them.

## Uninstalling

```zsh
omz plugin disable git-persona && rm -rf $ZSH_CUSTOM/plugins/git-persona
```

Your personas stay in `~/.config/git-persona/`, and the last identity a switch
wrote stays in `~/.gitconfig`. Delete both by hand if you want them gone.

## Changelog

Every release is listed in [CHANGELOG.md](CHANGELOG.md). Current version 1.0.1,
which `git-who` and the plugin report as `$GIT_ID_VERSION` if you need it for a
bug report.

## Licence

[MIT](LICENSE)
