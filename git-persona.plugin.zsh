# =============================================================================
#  git-persona  ·  switch between git personas
# =============================================================================
#  git-<persona>                                switch to that persona
#  git-switch                                   pick one from a list instead
#  git-who                                      show the persona in play
#  git-add                                      add an account, and switch to it
#  git-remove                                   drop an account
#  git-persona-uninstall                        remove everything it created
#  git-id-locals                                find repos pinned to their own id
#  git-id-locals --clear                        unpin them, so all follow global
#  git-id-icons                                 check the Nerd Font glyphs
#
#  A switch sets three things, all of them global so one command governs every
#  repo on the machine: user.name and user.email, core.sshCommand, and the
#  active gh CLI account.
#
#  That last one matters for HTTPS remotes, where gh is what actually
#  authorises a push, while user.email only decides the name printed on the
#  commit. Keeping one without the other is how commits end up signed by one
#  account and pushed by another.
#
#  Requires zsh, git and the gh CLI. The readout draws Nerd Font glyphs and
#  powerline separators, so set the terminal to a Nerd Font patched typeface or
#  expect tofu boxes in place of the icons; run git-id-icons to check. Layout
#  never depends on them, and a terminal too narrow for the wordmark falls back
#  to a compact header rather than wrapping into confetti.
#
#  macOS is the developed-on platform. Elsewhere everything works except two
#  extras that degrade rather than fail: the device code is only copied to the
#  clipboard where a clipboard command exists, and ~/.ssh/config keeps its file
#  mode only where stat is understood.
# =============================================================================

# -----------------------------------------------------------------------------
#  Profile storage.  Fields live under a "profile.field" key in one flat map,
#  which keeps a whole profile readable as a single block below instead of
#  scattering its fields across six parallel arrays.
#
#  Both are reset on every source, so re-sourcing ~/.zshrc redefines the
#  profiles rather than appending a second copy of each.
# -----------------------------------------------------------------------------
typeset -g GIT_ID_VERSION='1.1.6'

typeset -gA GIT_ID_FIELD=()
typeset -ga GIT_ID_ORDER=()

# Fenced region inside the data file that the two editing commands work in.
# Nothing outside the markers is read or rewritten, so a header, notes or
# hand-written blocks around them survive untouched.
typeset -g GIT_ID_MARK_OPEN='# >>> git-id profiles >>>'
typeset -g GIT_ID_MARK_CLOSE='# <<< git-id profiles <<<'

# git-id-profile <name> <field> <value> [<field> <value> ...]
git-id-profile() {
  emulate -L zsh
  setopt local_options

  local profile=$1; shift
  if [[ -z $profile ]]; then
    print -u2 'git-id-profile: needs a profile name'
    return 1
  fi

  [[ -n ${GIT_ID_FIELD[$profile.name]} ]] || GIT_ID_ORDER+=( $profile )

  while (( $# >= 2 )); do
    GIT_ID_FIELD[$profile.$1]=$2
    shift 2
  done

  # An odd trailing argument means a field was given no value, which would
  # otherwise be stored as an empty string and look deliberate.
  if (( $# )); then
    print -u2 "git-id-profile: ${profile}: field '$1' has no value"
    return 1
  fi
}

# Read one field, or nothing if unset.
_gid_f() { print -r -- ${GIT_ID_FIELD[$1.$2]} }

# =============================================================================
#  PERSONAS  ·  loaded from a separate data file
# =============================================================================
#  The personas live in GIT_ID_PROFILE_FILE, not here. This file is code and
#  nothing else, so git-add and git-remove never rewrite it: a bad write costs
#  a profile list rather than a working shell, and the script can be replaced
#  or version-controlled without anybody's accounts embedded in it.
#
#  Run git-add to create a persona, or edit the data file directly. It
#  documents its own format, and is seeded with an empty fence if missing.
# =============================================================================
typeset -g GIT_ID_PROFILE_FILE=${GIT_ID_PROFILE_FILE:-$HOME/.config/git-persona/profiles.zsh}

# Create the data file, and its directory, if either is missing. Only the two
# markers are load-bearing; the prose above them is for whoever opens it.
#
# A function rather than a one-off block, because git-add calls it again: a
# file deleted after the shell started would otherwise leave git-add reporting
# a missing fence on a first run that ought to just work.
_gid_seed_profiles() {
  [[ -e $GIT_ID_PROFILE_FILE ]] && return 0
  mkdir -p ${GIT_ID_PROFILE_FILE:h} 2>/dev/null || return 1
  print -rl -- \
    '# git-persona personas. Data only, written by git-add and git-remove.' \
    '# The code lives in the git-persona plugin that reads this file.' \
    '' \
    "$GIT_ID_MARK_OPEN" \
    "$GIT_ID_MARK_CLOSE" > $GIT_ID_PROFILE_FILE
}

# Deliberately not called at load. Merely installing a plugin should not create
# files in somebody's home, and an absent data file just means no profiles yet.
# git-add calls it when there is actually something to write.

# Sourced, not parsed: the blocks are calls to git-id-profile, defined above.
[[ -r $GIT_ID_PROFILE_FILE ]] && source $GIT_ID_PROFILE_FILE

# -----------------------------------------------------------------------------
#  Where git-id-locals goes looking for repos pinned to their own identity.
#
#  Several common code roots, of which only the ones that exist are walked, so
#  the default does something sensible without knowing anybody's layout. Set it
#  to your own if your repos live elsewhere; the walk is unbounded in depth, so
#  pointing it at $HOME works but is slow.
# -----------------------------------------------------------------------------
(( ${+GIT_ID_SCAN_ROOTS} )) || \
  typeset -ga GIT_ID_SCAN_ROOTS=( ~/Source ~/Projects ~/Developer ~/code ~/src ~/dev ~/work ~/repos )

# -----------------------------------------------------------------------------
#  How the pickers in git-switch and git-remove read a choice.
#
#    arrows   up/down to move, enter to pick   (default)
#    numbers  type the number, as before
#
#  Arrows need a tty either way, so a pipe or a script falls back to the
#  numbered prompt on its own. Digits work in the arrow menu too.
# -----------------------------------------------------------------------------
: ${GIT_ID_MENU:=arrows}

# -----------------------------------------------------------------------------
#  What to do when a profile's gh account has no token yet.
#
#    ask     prompt, and run gh auth login if you say yes   (default)
#    always  run it without asking
#    never   only warn, never open a browser
#
#  Any of these only applies at an interactive prompt. A switch inside a script
#  or a subshell always just warns, since gh auth login would sit there waiting
#  on a browser with nobody to answer it.
# -----------------------------------------------------------------------------
: ${GIT_ID_AUTO_LOGIN:=ask}

# =============================================================================
#  Everything below is machinery. Accounts are edited in the data file above,
#  by git-add and git-remove or by hand.
# =============================================================================

: ${GIT_ID_NEUTRAL:=244}          # accent for a persona this does not know
: ${GIT_ID_SHADOW:=238}           # its companion shadow

# True when the locale can represent the glyphs below.
#
# This has to be asked before defining them, not after: under LC_ALL=C a
# $'\uXXXX' above 0xFF is an error rather than a fallback, so an unguarded
# definition prints "character not in range" on every single shell start and
# leaves the icons unset. A colleague sshing in without locale forwarding, or
# anything running under LANG=C, hits exactly that.
_gid_unicode() { [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *[Uu][Tt][Ff]* ]] }

# Written as \u escapes on purpose. A literal glyph here is one editor or one
# copy-paste away from being silently dropped, and an empty icon costs a cell of
# alignment without ever announcing itself. Run git-id-icons to check them.
#
# The ASCII stand-ins are all one cell wide, same as the glyphs, so the bars
# line up either way and only the pictures are lost.
if _gid_unicode; then
  typeset -gA GIT_ID_ICONS=(
    mark   $'\uf09b'                # github, on the eyebrow
    name   $'\uf007'                # who you are
    mail   $'\uf0e0'                # email
    key    $'\uf084'                # ssh identity file
    auth   $'\uf023'                # gh account answering for https pushes
    sign   $'\uf0c1'                # commit signing key
    scope  $'\uf2c1'                # where the identity is configured
    repo   $'\uf401'                # repository
    head   $'\ue0a0'                # branch
    warn   $'\uf071'                # the warning line
  )
  # Powerline separators: a rounded cap opens the bar, solid arrows carry each
  # hand-off, a rounded cap closes it.
  typeset -g GIT_ID_CAP_L=$'\ue0b6'
  typeset -g GIT_ID_SEP=$'\ue0b0'
  typeset -g GIT_ID_CAP_R=$'\ue0b4'
  typeset -g GIT_ID_DOT=$'\u00b7'
else
  typeset -gA GIT_ID_ICONS=(
    mark   '@'   name   '~'   mail   '@'
    key    '#'   auth   '%'   scope  '='
    sign   '&'
    repo   '/'   head   '+'   warn   '!'
  )
  typeset -g GIT_ID_CAP_L=' '
  typeset -g GIT_ID_SEP='|'
  typeset -g GIT_ID_CAP_R=' '
  typeset -g GIT_ID_DOT='-'
fi

# Segment palette, deliberately muted rather than keyed to the profile accents,
# so the bars stay readable next to whatever colours a prompt theme is already
# using. Dark text throughout, which is what makes a filled segment legible.
: ${GIT_ID_SEG_FG:=235}           # text on every segment
: ${GIT_ID_SEG_CREAM:=187}
: ${GIT_ID_SEG_BLUE:=110}
: ${GIT_ID_SEG_SAGE:=108}
: ${GIT_ID_SEG_TAN:=180}
: ${GIT_ID_SEG_WARN:=179}

# -----------------------------------------------------------------------------
#  Calvin S, three rows per glyph. Rows within a glyph are equal width; the
#  renderer relies on that, so keep it true if you add characters. Glyphs sit
#  flush against each other, no letter spacing.
# -----------------------------------------------------------------------------
typeset -gA GIT_ID_FONT=(
  A $'╔═╗\n╠═╣\n╩ ╩'
  B $'╔╗ \n╠╩╗\n╚═╝'
  C $'╔═╗\n║  \n╚═╝'
  D $'╔╦╗\n ║║\n═╩╝'
  E $'╔═╗\n║╣ \n╚═╝'
  F $'╔═╗\n╠╣ \n╚  '
  G $'╔═╗\n║ ╦\n╚═╝'
  H $'╦ ╦\n╠═╣\n╩ ╩'
  I $'╦\n║\n╩'
  J $' ╦\n ║\n╚╝'
  K $'╦╔═\n╠╩╗\n╩ ╩'
  L $'╦  \n║  \n╩═╝'
  M $'╔╦╗\n║║║\n╩ ╩'
  N $'╔╗╔\n║║║\n╝╚╝'
  O $'╔═╗\n║ ║\n╚═╝'
  P $'╔═╗\n╠═╝\n╩  '
  Q $'╔═╗\n║ ║\n╚═╝'
  R $'╦═╗\n╠╦╝\n╩╚═'
  S $'╔═╗\n╚═╗\n╚═╝'
  T $'╔╦╗\n ║ \n ╩ '
  U $'╦ ╦\n║ ║\n╚═╝'
  V $'╦  ╦\n╚╗╔╝\n ╚╝ '
  W $'╦ ╦\n║║║\n╚╩╝'
  X $'═╗ ╦\n╔╩╦╝\n╩ ╚═'
  Y $'╦ ╦\n╚╦╝\n ╩ '
  Z $'╔═╗\n╔═╝\n╚═╝'
  0 $'╔═╗\n║ ║\n╚═╝'
  1 $' ╦ \n ║ \n ╩ '
  2 $'╔═╗\n╔═╝\n╚═╝'
  3 $'╔═╗\n ═╣\n╚═╝'
  4 $'╦ ╦\n╚═╣\n  ╩'
  5 $'╔═╗\n╚═╗\n╚═╝'
  6 $'╔═╗\n╠═╗\n╚═╝'
  7 $'╔═╗\n  ║\n  ╩'
  8 $'╔═╗\n╠═╣\n╚═╝'
  9 $'╔═╗\n╚═╣\n╚═╝'
  '-' $'   \n═══\n   '
  ' ' $'  \n  \n  '
)

# -----------------------------------------------------------------------------
#  Primitives
# -----------------------------------------------------------------------------

# Build a run of $1 copies of $2 into REPLY.
_gid_fill() {
  local -i n=$1
  local c=${2- }
  REPLY=''
  while (( n-- > 0 )); do REPLY+=$c; done
}

# Set the array _gid_wm to the three plain rows of $1, and _gid_wmW to its width.
_gid_word() {
  local word=${(U)1}
  local -a g
  local c
  local -i j r
  _gid_wm=( '' '' '' )
  for (( j = 1; j <= ${#word}; j++ )); do
    c=$word[j]
    [[ -n ${GIT_ID_FONT[$c]} ]] || c=' '
    g=( "${(@f)GIT_ID_FONT[$c]}" )
    for (( r = 1; r <= 3; r++ )); do _gid_wm[r]+=$g[r]; done
  done
  _gid_wmW=${(m)#_gid_wm[1]}
}

# Render the segments held in _gid_sb (backgrounds) and _gid_st (texts) as one
# powerline bar into REPLY, with its display width in _gid_barW. Each hand-off
# paints the arrow in the outgoing segment's colour over the incoming one, which
# is the whole trick behind a seamless bar.
_gid_bar() {
  local X=$'\e[0m'
  local out='' prev=''
  local -i i w=0
  for (( i = 1; i <= ${#_gid_sb}; i++ )); do
    if (( i == 1 )); then
      out+="${X}"$'\e[38;5;'"${_gid_sb[i]}"'m'"${GIT_ID_CAP_L}"
    else
      out+=$'\e[38;5;'"${prev}"';48;5;'"${_gid_sb[i]}"'m'"${GIT_ID_SEP}"
    fi
    out+=$'\e[38;5;'"${GIT_ID_SEG_FG}"';48;5;'"${_gid_sb[i]}"'m'"${_gid_st[i]}"
    (( w += ${(m)#_gid_st[i]} + 1 ))
    prev=${_gid_sb[i]}
  done
  out+="${X}"$'\e[38;5;'"${prev}"'m'"${GIT_ID_CAP_R}${X}"
  REPLY=$out
  _gid_barW=$(( w + 1 ))
}

# Print the staged bar, or break it into one bar per segment when it will not
# fit the terminal. Segments are indivisible, so wrapping one is never right.
_gid_emit() {
  local pad=$1
  local -i cols=$2
  _gid_bar
  if (( _gid_barW + ${#pad} <= cols )); then
    print -r -- "${pad}${REPLY}"
    return
  fi
  local -a sb=( "${_gid_sb[@]}" ) st=( "${_gid_st[@]}" )
  local -i i
  for (( i = 1; i <= ${#sb}; i++ )); do
    _gid_sb=( "$sb[i]" ); _gid_st=( "$st[i]" )
    _gid_bar
    print -r -- "${pad}${REPLY}"
  done
}

# -----------------------------------------------------------------------------
#  The readout
#    $1 title   $2 label   $3 name   $4 email   $5 key   $6 repo   $7 head
#    $8 notes   $9 scope   $10 accent   $11 shadow   $12 gh
#
#  $8 carries one note per line; each gets its own warning bar, because two
#  concatenated warnings make a segment too wide to split.
# -----------------------------------------------------------------------------
_gid_render() {
  emulate -L zsh
  setopt local_options

  local title=$1 label=$2 name=$3 email=$4 key=$5 repo=$6 head=$7 note=$8
  local scope=$9 accent=${10:-$GIT_ID_NEUTRAL} shadow=${11:-$GIT_ID_SHADOW}
  local gh=${12} sign=${13}

  local X=$'\e[0m'
  local A=$'\e[38;5;'"${accent}"'m'
  local S=$'\e[38;5;'"${shadow}"'m'
  local DIM=$'\e[38;5;243m'
  local TXT=$'\e[38;5;250m'
  local HI=$'\e[1;38;5;255m'
  local NTE=$'\e[38;5;179m'

  local pad='   '
  # zsh reports COLUMNS=0 when there is no terminal attached (a pipe, a
  # subshell, a cron run). :- will not catch that, since zero is set rather
  # than empty, so test the value itself and assume room.
  local -i cols=${COLUMNS:-0}
  (( cols <= 0 )) && cols=100

  print

  # ---- header: the title on the left, the wordmark set to its right ----------
  local -a _gid_wm; local -i _gid_wmW
  _gid_word "$label"

  local eyebrow="${GIT_ID_ICONS[mark]}  ${title}"
  local eyepaint="${A}${GIT_ID_ICONS[mark]}${X}  ${DIM}${title}${X}"
  local -i eyeW=${(m)#eyebrow}
  local gutter='    '
  local -i r

  # The wordmark is box-drawing characters, so outside a UTF-8 locale it would
  # come out as mojibake and its measured width would be wrong on top of that.
  # Both art branches are skipped there, leaving the compact header that the
  # narrow-terminal case already uses.
  if ! _gid_unicode; then
    print -r -- "${pad}${eyepaint}"
    print -r -- "${pad}${HI}${(U)label}${X}"
  elif (( ${#pad} + eyeW + ${#gutter} + _gid_wmW <= cols )); then
    # The title sits on the middle row so it reads as centred against the art.
    _gid_fill $eyeW ' '
    local blank=$REPLY
    local wc
    for (( r = 1; r <= 3; r++ )); do
      # Baseline row in the shadow tone, which seats the letters instead of
      # leaving them floating.
      (( r == 3 )) && wc=$S || wc=$A
      if (( r == 2 )); then
        print -r -- "${pad}${eyepaint}${gutter}${wc}${_gid_wm[r]}${X}"
      else
        print -r -- "${pad}${blank}${gutter}${wc}${_gid_wm[r]}${X}"
      fi
    done
  elif (( ${#pad} + _gid_wmW <= cols )); then
    # Not side by side, but the art still fits: stack them.
    print -r -- "${pad}${eyepaint}"
    print
    for (( r = 1; r <= 3; r++ )); do
      (( r == 3 )) && print -r -- "${pad}${S}${_gid_wm[r]}${X}" \
                   || print -r -- "${pad}${A}${_gid_wm[r]}${X}"
    done
  else
    print -r -- "${pad}${eyepaint}"
    print -r -- "${pad}${HI}${(U)label}${X}"
  fi

  print

  # ---- segment bars ----------------------------------------------------------
  local -a _gid_sb _gid_st
  local -i _gid_barW

  # Who: the profile mark leads in the accent, then name, then email.
  _gid_sb=( "$accent" "$GIT_ID_SEG_CREAM" "$GIT_ID_SEG_BLUE" )
  _gid_st=(
    " ${GIT_ID_ICONS[mark]} "
    " ${GIT_ID_ICONS[name]}  ${name} "
    " ${GIT_ID_ICONS[mail]}  ${email} "
  )
  [[ -n $scope ]] && {
    _gid_sb+=( "$GIT_ID_SEG_SAGE" )
    _gid_st+=( " ${GIT_ID_ICONS[scope]}  ${scope} " )
  }
  _gid_emit "$pad" $cols

  # Where: the key and the gh account that answers for a push, then the repo
  # and the branch it is sitting on. Key and gh sit together because they are
  # the same question asked of two transports, ssh and https.
  _gid_sb=( "$GIT_ID_SEG_SAGE" )
  _gid_st=( " ${GIT_ID_ICONS[key]}  ${key} " )
  [[ -n $gh ]] && {
    _gid_sb+=( "$GIT_ID_SEG_BLUE" )
    _gid_st+=( " ${GIT_ID_ICONS[auth]}  gh: ${gh} " )
  }
  # Signing sits on the same row as key and gh because it is the same key
  # answering a third question: not who opened the connection, but who the
  # commit itself claims to be from.
  [[ -n $sign ]] && {
    _gid_sb+=( "$GIT_ID_SEG_CREAM" )
    _gid_st+=( " ${GIT_ID_ICONS[sign]}  ${sign} " )
  }
  if [[ -n $repo ]]; then
    _gid_sb+=( "$GIT_ID_SEG_TAN" "$GIT_ID_SEG_CREAM" )
    _gid_st+=( " ${GIT_ID_ICONS[repo]}  ${repo} " " ${GIT_ID_ICONS[head]}  ${head} " )
  fi
  _gid_emit "$pad" $cols

  local n
  for n in ${(f)note}; do
    [[ -n $n ]] || continue
    _gid_sb=( "$GIT_ID_SEG_WARN" )
    _gid_st=( " ${GIT_ID_ICONS[warn]}  ${n} " )
    _gid_emit "$pad" $cols
  done

  print
}

# -----------------------------------------------------------------------------
#  Repo probe.  Fills _gid_repo / _gid_head in the caller, returns 1 outside a
#  repo.  It sets no note of its own, because what is worth saying about a bare
#  directory differs between switching and reporting.
# -----------------------------------------------------------------------------
_gid_probe() {
  _gid_repo=''; _gid_head=''

  git rev-parse --is-inside-work-tree &>/dev/null || return 1

  _gid_repo=${$(git rev-parse --show-toplevel):t}
  _gid_head=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [[ -z $_gid_head ]]; then
    local sha=$(git rev-parse --short HEAD 2>/dev/null)
    [[ -n $sha ]] && _gid_head="detached at ${sha}" || _gid_head='no commits yet'
  fi
  return 0
}

# -----------------------------------------------------------------------------
#  gh CLI account
# -----------------------------------------------------------------------------

# Print the gh account active for github.com, or nothing. Parses the human
# readout because gh exposes no machine-readable form of this; ~/.config/gh
# holds it too, but that is internal layout and tokens may live in the keyring
# instead. A parse miss returns empty, which every caller treats as unknown
# rather than as an error, so a gh output change degrades the display and never
# blocks a switch.
# gh's own account list, which is a local file. Worth reading directly:
# `gh auth status` validates every token it holds over the network, which costs
# about a second per account and made a switch take five. Nothing here needs a
# token proved good, only the names gh knows and which one is active, and both
# are answered offline.
#
# Falls back to gh whenever the file cannot answer, so a layout change upstream
# degrades to the old speed rather than to a wrong answer.
_gid_gh_hosts() {
  print -r -- "${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml"
}

# gh ignores hosts.yml entirely when a token comes from the environment, so the
# file is not authoritative then and the slow path is the correct one.
_gid_gh_env_token() {
  [[ -n ${GH_TOKEN:-${GITHUB_TOKEN:-}} ]]
}

# The active account, from the `user:` key of the github.com block. Indentation
# is matched exactly as gh writes it, so an account named "user" nested under
# `users:` cannot be mistaken for the key.
_gid_gh_active() {
  command -v gh &>/dev/null || return 1

  local f=$(_gid_gh_hosts) out=''
  if ! _gid_gh_env_token && [[ -r $f ]]; then
    out=$(awk '
      /^github\.com:/       { inhost = 1; next }
      /^[^[:space:]]/       { inhost = 0 }
      inhost && /^    user:/ { sub(/^    user:[[:space:]]*/, ""); print; exit }
    ' $f 2>/dev/null)
    [[ -n $out ]] && { print -r -- $out; return }
  fi

  local line=$(gh auth status --active --hostname github.com 2>/dev/null \
               | grep -m1 'Logged in to')
  [[ $line =~ 'account ([^[:space:]]+)' ]] && print -r -- $match[1]
}

# True when $1 is one of the accounts gh already holds a token for.
_gid_gh_known() {
  local f=$(_gid_gh_hosts)
  if ! _gid_gh_env_token && [[ -r $f ]]; then
    local -a users=( ${(f)"$(awk '
      /^github\.com:/          { inhost = 1; next }
      /^[^[:space:]]/          { inhost = 0; inusers = 0 }
      inhost && /^    users:/  { inusers = 1; next }
      inusers && /^    [^ ]/   { inusers = 0 }
      inusers && /^        [^ ]+:/ { sub(/:.*$/, ""); gsub(/ /, ""); print }
    ' $f 2>/dev/null)"} )
    (( ${#users} )) && { (( ${users[(Ie)$1]} )); return }
  fi
  gh auth status 2>&1 | grep -q "account ${1} "
}

# Print "<login>\t<display name>" for gh account $1, or nothing.
#
# gh api always answers as the *active* account and offers no way to target
# another, so a non-active one has to be made active for the call. The previous
# account is put back on every exit path, including failure, so reading an
# identity never leaves the machine authenticated as somebody else.
#
# .name is null for plenty of accounts, hence the // "" and the caller's
# fallback to the login.
_gid_gh_identity() {
  local want=$1 prev out
  command -v gh &>/dev/null || return 1
  _gid_gh_known $want || return 1

  prev=$(_gid_gh_active)
  local -i restore=0
  if [[ -n $want && $want != $prev ]]; then
    gh auth switch --hostname github.com --user "$want" &>/dev/null || return 1
    restore=1
  fi

  out=$(gh api user --jq '[.login, (.name // "")] | @tsv' 2>/dev/null)

  (( restore )) && [[ -n $prev ]] && \
    gh auth switch --hostname github.com --user "$prev" &>/dev/null

  [[ -n $out ]] || return 1
  print -r -- $out
}

# -----------------------------------------------------------------------------
#  Platform seams. Everything the script needs that differs between systems is
#  answered here rather than assumed inline, so a colleague on another OS gets
#  a feature switched off instead of a command that silently misbehaves.
# -----------------------------------------------------------------------------

# The command that reads stdin onto the clipboard, or nothing if there is none.
_gid_clip_cmd() {
  local c
  for c in pbcopy wl-copy 'xclip -selection clipboard' 'xsel --clipboard --input'; do
    command -v ${c%% *} &>/dev/null && { print -r -- $c; return }
  done
}

# True for a BSD script(1), which takes `script [-q] [-t n] <file> <command>`.
# GNU script spells the same job `script -q -c <command> <file>` and means
# something else entirely by -t, so its output would go unread and its
# arguments be misparsed. Checked by OSTYPE rather than by running script
# --version, because BSD script would take that as a filename and open a shell.
_gid_script_bsd() { [[ $OSTYPE == (darwin|freebsd|netbsd|openbsd)* ]] }

# Octal file mode, across BSD and GNU stat. Empty if neither answers.
_gid_mode_of() {
  local m
  m=$(stat -f %Lp "$1" 2>/dev/null) || m=$(stat -c %a "$1" 2>/dev/null)
  print -r -- $m
}

# Run `gh auth login`, putting the one-time device code on the clipboard the
# instant gh prints it.
#
# gh exposes no way to obtain that code programmatically, so its output is read
# instead. It cannot simply be piped: gh needs a terminal for its prompts, and
# a pipe would leave it waiting on an Enter that can never arrive. script(1)
# solves both halves at once, handing gh a real pty while mirroring everything
# it prints into a file, which a background watcher then greps.
#
# script returns the child's exit status on macOS (verified: a child exiting 7
# makes script exit 7), so a cancelled login is still reported as a failure.
_gid_gh_login_run() {
  # admin:ssh_signing_key is not among gh's defaults, and asking for it here is
  # the only cheap moment: adding it later means a second browser round-trip
  # through `gh auth refresh`. gh adds it on top of its usual scopes.
  local -a cmd=( gh auth login --hostname github.com --git-protocol https --web
                 --scopes admin:ssh_signing_key )

  # Without a clipboard, or on a platform whose script(1) this does not know
  # how to drive, the login still has to work: fall through to running it
  # plainly rather than degrading it.
  local -a clip=( ${(z)$(_gid_clip_cmd)} )
  (( ${#clip} )) && _gid_script_bsd || { $cmd; return }

  local log=''
  log=$(mktemp) || { $cmd; return }

  # Polls rather than tailing: tail -f would hold the transcript open past the
  # end of the login, and the file is being written by a pty either way.
  # Stops early once the log is gone, so it never outlives the command below.
  (
    local code=''
    local -i i=0
    while (( i++ < 300 )); do
      [[ -e $log ]] || break
      code=$(grep -m1 -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' $log 2>/dev/null)
      [[ -n $code ]] && { printf %s $code | $clip; break }
      sleep 0.2
    done
  ) &!

  # -t 0 is load-bearing. Without it macOS script buffers the whole transcript
  # and writes nothing until the command exits, by which point the code has
  # already been needed and the login is over. Verified: with the default
  # buffering the log is still 0 bytes several seconds in.
  script -q -t 0 $log $cmd
  local -i rc=$?
  rm -f $log
  return $rc
}

# Offer to log $1 in, and return 0 only if it is genuinely there afterwards.
#
# Gated on an interactive terminal because gh auth login takes over the tty and
# waits on a browser. In a script, a subshell or a pipeline there is nobody to
# answer, and an unattended switch would hang instead of warning. That is why
# this asks rather than simply running: a switch is a cheap, frequent command,
# and a browser window is not what you expect from one.
_gid_gh_login() {
  local want=$1

  [[ $GIT_ID_AUTO_LOGIN == never ]] && return 1
  [[ -o interactive ]] || return 1
  [[ -t 0 && -t 1 ]]   || return 1

  if [[ $GIT_ID_AUTO_LOGIN != always ]]; then
    print
    read -q "REPLY?   ${want} is not logged into gh. log in now? [y/N] " || {
      print; return 1
    }
    print
  fi

  print
  _gid_gh_login_run || return 1

  # gh cannot be told which account to authorise, the browser decides. If the
  # wrong one was picked, say so rather than reporting a success that would
  # leave the next push on someone else's token.
  _gid_gh_known $want
}

# -----------------------------------------------------------------------------
#  HTTPS credentials
#
#  Switching gh only governs https traffic if git actually asks gh for the
#  password. It does not by default. Git accumulates credential helpers from
#  every scope, and on macOS /etc/gitconfig ships `helper = osxkeychain`, which
#  answers first and hands back whichever token it cached on the very first
#  push. That token belongs to one account for ever, so every persona would
#  clone and push as that account no matter what gh says.
#
#  `gh auth setup-git` is what fixes it: it writes an empty helper (which
#  clears everything inherited, osxkeychain included) followed by gh's own.
#  gh runs it during `gh auth login` only when https is chosen as the preferred
#  protocol, so a machine set up over ssh silently lacks it.
# -----------------------------------------------------------------------------

# The helper git would really use for github.com, after the whole
# system/global/local chain has been resolved. --get-urlmatch is the only way
# to ask; reading credential.helper directly misses the per-host sections.
_gid_cred_helper() {
  git config --get-urlmatch credential.helper https://github.com 2>/dev/null
}

# True when that helper is gh. Matched on the word, not on a path, because
# setup-git writes an absolute one that differs per platform: /opt/homebrew on
# apple silicon, /usr/local on intel, /usr/bin on linux.
_gid_cred_ok() {
  [[ $(_gid_cred_helper) == *gh*auth*git-credential* ]]
}

# Idempotent, and cheap enough to call on any path that already has gh in hand.
# Returns non-zero without touching anything when gh is absent, so callers can
# report rather than assume.
_gid_cred_setup() {
  command -v gh &>/dev/null || return 1
  gh auth setup-git 2>/dev/null
  _gid_cred_ok
}

# -----------------------------------------------------------------------------
#  Re-authoring commits that have not been pushed
#
#  Committing under one persona and pushing under another is the exact failure
#  this plugin exists to prevent, and switching in between is the one route
#  still open. So a switch offers to correct the commits that are still local.
#
#  Strictly limited to commits reachable from HEAD but from no remote branch.
#  Those have never left the machine, so rewriting them needs no force push and
#  breaks nobody's clone. Anything already pushed is left alone: correcting it
#  means rewriting shared history, which is a decision for a person, not for a
#  side effect of switching personas.
# -----------------------------------------------------------------------------

# Commits on HEAD that no remote knows about, oldest last.
_gid_pending() {
  git rev-list HEAD --not --remotes 2>/dev/null
}

# The author emails of those commits that belong to some other persona of
# yours. A cherry-pick or a mailed patch from a colleague is authored by
# someone with no persona here, and must never be reattributed to you.
_gid_pending_foreign() {
  local target=$1 p='' e='' seen=''
  local -a mine=() found=()
  for p in $GIT_ID_ORDER; do mine+=( $(_gid_f $p email) ); done

  for e in ${(f)"$(git log --format='%ae' HEAD --not --remotes 2>/dev/null)"}; do
    [[ $e == $target ]] && continue                 # already correct
    (( ${mine[(Ie)$e]} )) || continue               # not one of yours, leave it
    [[ $seen == *"|$e|"* ]] && continue             # dedupe
    seen="${seen}|${e}|"
    found+=( $e )
  done
  print -rl -- $found
}

# Rewrite the pending commits authored by $2.. to "$name <$email>".
# Returns non-zero and explains itself rather than leaving a half-done rebase.
_gid_reauthor() {
  local name=$1 email=$2; shift 2
  local -a old=( $@ )
  (( ${#old} )) || return 0

  # A rebase cannot start from a dirty tree, and finding that out halfway
  # through is worse than refusing now.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    print -u2 '   uncommitted changes, commit or stash them first'
    return 1
  fi
  local gd=$(git rev-parse --git-dir)
  if [[ -d $gd/rebase-merge || -d $gd/rebase-apply ]]; then
    print -u2 '   a rebase is already in progress'
    return 1
  fi
  if [[ -z $(git symbolic-ref -q HEAD) ]]; then
    print -u2 '   detached HEAD, checkout a branch first'
    return 1
  fi
  # Replaying a merge rewrites its parents too, which can quietly drop a side
  # of the history. Not worth the risk for a convenience.
  if [[ -n $(git rev-list --merges HEAD --not --remotes 2>/dev/null) ]]; then
    print -u2 '   pending commits include a merge, re-author by hand'
    return 1
  fi

  local -a pending=( ${(f)"$(_gid_pending)"} )
  (( ${#pending} )) || return 0

  # Oldest pending commit's parent is where the replay starts. A repository
  # whose very first commit is still unpushed has no such parent, hence --root.
  local base=$(git rev-parse --verify -q "${pending[-1]}^" 2>/dev/null)
  local -a from=( ${base:---root} )

  # Passed through the environment rather than interpolated into the --exec
  # string, so an apostrophe in a name cannot end up as shell syntax. The exec
  # runs under sh, so grep does the matching: -F fixed, -x whole line, one
  # pattern per line.
  local ex='if git log -1 --format=%ae | grep -qxF "$GIT_PERSONA_OLD"; then'
  # --allow-empty because amending a commit that carries no changes is refused
 # otherwise, and an empty commit is a perfectly ordinary thing to have made.
 ex+=' git commit --amend --no-edit --allow-empty --author="$GIT_PERSONA_NEW"; fi'

  GIT_PERSONA_OLD=${(F)old} GIT_PERSONA_NEW="${name} <${email}>" \
    git -c advice.detachedHead=false rebase --empty=keep $from --exec $ex >/dev/null 2>&1 || {
      git rebase --abort 2>/dev/null
      print -u2 '   could not replay the commits, nothing was changed'
      return 1
    }
  return 0
}

# Point gh at the account behind profile $1. Sets _gid_gh in the caller to
# whatever is active afterwards, and appends to _gid_notes when the intent
# could not be carried out.
#
# Deliberately never fatal: failing to switch gh still leaves the identity
# correctly set, and the warning bar says which account the push will really
# use. Silently aborting the whole switch would be worse.
_gid_gh_switch() {
  local profile=$1
  local want=$(_gid_f $profile gh)

  if ! command -v gh &>/dev/null; then
    _gid_gh='gh not installed'
    _gid_notes+=( 'gh is not on PATH, so https pushes are unmanaged' )
    return
  fi

  local active=$(_gid_gh_active)

  # No account mapped. Say plainly whose token the push will carry, since it
  # is now guaranteed not to match the name on the commit.
  if [[ -z $want ]]; then
    _gid_gh=${active:-none}
    # No login is offered here, unlike the not-logged-in case below: with the
    # gh field empty there is no account to log in as. Only editing the profile
    # fixes this, so the note says so.
    _gid_notes+=(
      "no gh account for ${profile}, pushes still go out as ${active:-whoever is active}. run: gh auth login"
    )
    return
  fi

  # Already there. Worth skipping: the switch touches the login keychain and
  # macOS may prompt for it.
  if [[ $active == $want ]]; then
    _gid_gh=$want
    return
  fi

  # Distinguish "not logged in" from a switch that failed for some other
  # reason. gh's own error for the former is easy to misread as a bug in the
  # profile map, when the fix is one login away, so offer to run it here.
  if ! _gid_gh_known $want; then
    if _gid_gh_login $want; then
      active=$(_gid_gh_active)          # login makes the new account active
      if [[ $active == $want ]]; then
        _gid_gh=$want
        return
      fi
    else
      _gid_gh=${active:-none}
      _gid_notes+=(
        "${want} is not logged into gh, pushes go out as ${active:-whoever is active}. run: gh auth login"
      )
      return
    fi
  fi

  local out
  if out=$(gh auth switch --hostname github.com --user "$want" 2>&1); then
    _gid_gh=$want
  else
    _gid_gh=${active:-unknown}
    # Last line only: gh prefixes multi-line errors with a banner that would
    # swamp the bar.
    _gid_notes+=( "gh could not switch to ${want}: ${out##*$'\n'}" )
  fi
}

# =============================================================================
#  ~/.ssh/config
#
#  Blocks are matched to profiles by IdentityFile, never by name. Aliases
#  written by hand need not follow the profile names, and often do not, so the
#  key path is the only thing the two sides genuinely agree on. Matching on the
#  alias would silently find nothing and leave the block behind.
#
#  A block runs from its Host line to the line before the next one, and takes
#  the comment lines immediately above it along, since that is where the human
#  label sits. Removing a block without them would leave its label orphaned
#  above somebody else's Host.
#
#  Every write keeps a .bak and preserves the original mode. ssh refuses to use
#  a config it considers too permissive, so the mode is not incidental.
# =============================================================================
typeset -g GIT_ID_SSH_CONFIG=${GIT_ID_SSH_CONFIG:-$HOME/.ssh/config}

# Absolute, ~-expanded form of a key path, for comparing two spellings of one
# file (~/.ssh/id_rsa_x against /Users/you/.ssh/id_rsa_x).
_gid_keypath() { print -r -- ${${1/#\~/$HOME}:A} }

# Replace the ssh config with stdin, atomically, keeping a backup and the mode.
_gid_ssh_write() {
  local tmp=${GIT_ID_SSH_CONFIG}.tmp.$$
  cat > $tmp || { rm -f $tmp; return 1 }
  local mode=$(_gid_mode_of $GIT_ID_SSH_CONFIG)
  cp -p $GIT_ID_SSH_CONFIG ${GIT_ID_SSH_CONFIG}.bak 2>/dev/null
  mv $tmp $GIT_ID_SSH_CONFIG || return 1
  [[ -n $mode ]] && chmod $mode $GIT_ID_SSH_CONFIG
  return 0
}

# Print the Host aliases whose IdentityFile is $1, one per line.
_gid_ssh_hosts_for() {
  local want=$(_gid_keypath $1)
  [[ -r $GIT_ID_SSH_CONFIG ]] || return 0

  local -a lines=( "${(@f)$(<$GIT_ID_SSH_CONFIG)}" ) w=()
  local host=''
  local -i i=0
  for (( i = 1; i <= ${#lines}; i++ )); do
    if [[ ${lines[i]} =~ '^[[:space:]]*[Hh]ost[[:space:]]+(.+)$' ]]; then
      w=( ${=match[1]} ); host=$w[1]
    elif [[ -n $host && ${lines[i]} =~ '^[[:space:]]*[Ii]dentity[Ff]ile[[:space:]]+(.+)$' ]]; then
      w=( ${=match[1]} )
      [[ $(_gid_keypath ${w[1]//\"/}) == $want ]] && print -r -- $host
    fi
  done
}

# Delete every Host block whose IdentityFile is $1. Prints the aliases removed.
_gid_ssh_remove() {
  local want=$(_gid_keypath $1)
  [[ -w $GIT_ID_SSH_CONFIG ]] || return 1

  local -a lines=( "${(@f)$(<$GIT_ID_SSH_CONFIG)}" )
  local -i n=${#lines} i=0 j=0
  local -a starts=()
  for (( i = 1; i <= n; i++ )); do
    [[ ${lines[i]} =~ '^[[:space:]]*[Hh]ost[[:space:]]' ]] && starts+=( $i )
  done
  (( ${#starts} )) || return 0

  # Walk each Host line backwards over its label comments, then over any blank
  # lines above those, so a block owns its own separator.
  local -a rs=()
  for (( j = 1; j <= ${#starts}; j++ )); do
    i=$starts[j]
    while (( i > 1 )) && [[ ${lines[i-1]} =~ '^[[:space:]]*#' ]]; do (( i-- )); done
    while (( i > 1 )) && [[ -z ${lines[i-1]//[[:space:]]/} ]];  do (( i-- )); done
    rs+=( $i )
  done

  local -a mask=() removed=() w=()
  for (( i = 1; i <= n; i++ )); do mask[i]=1; done

  local -i s=0 e=0 drop=0
  local host=''
  for (( j = 1; j <= ${#rs}; j++ )); do
    s=$rs[j]
    (( e = j < ${#rs} ? rs[j+1] - 1 : n ))
    drop=0; host=''
    for (( i = s; i <= e; i++ )); do
      if [[ ${lines[i]} =~ '^[[:space:]]*[Hh]ost[[:space:]]+(.+)$' ]]; then
        w=( ${=match[1]} ); host=$w[1]
      elif [[ ${lines[i]} =~ '^[[:space:]]*[Ii]dentity[Ff]ile[[:space:]]+(.+)$' ]]; then
        w=( ${=match[1]} )
        [[ $(_gid_keypath ${w[1]//\"/}) == $want ]] && drop=1
      fi
    done
    if (( drop )); then
      removed+=( $host )
      for (( i = s; i <= e; i++ )); do mask[i]=0; done
    fi
  done

  (( ${#removed} )) || return 0

  local -a out=()
  for (( i = 1; i <= n; i++ )); do (( mask[i] )) && out+=( "${lines[i]}" ); done
  print -rl -- "${(@)out}" | _gid_ssh_write || return 1

  print -rl -- "${(@)removed}"
}

# Append a Host block for $1 pointing at key $2. Prints the alias, or returns
# 2 when an alias of that name is already present.
_gid_ssh_add() {
  local profile=$1 key=$2
  local alias="github.com-${profile}"

  if [[ ! -e $GIT_ID_SSH_CONFIG ]]; then
    # A fresh machine may have no ~/.ssh at all, and touch cannot create a file
    # inside a directory that does not exist. 700 because ssh refuses to use a
    # key directory others can read.
    [[ -d ${GIT_ID_SSH_CONFIG:h} ]] || {
      mkdir -p ${GIT_ID_SSH_CONFIG:h} 2>/dev/null || return 1
      chmod 700 ${GIT_ID_SSH_CONFIG:h}
    }
    touch $GIT_ID_SSH_CONFIG 2>/dev/null || return 1
    chmod 600 $GIT_ID_SSH_CONFIG
  fi
  [[ -w $GIT_ID_SSH_CONFIG ]] || return 1

  grep -qE "^[[:space:]]*[Hh]ost[[:space:]]+${alias}([[:space:]]|\$)" \
    $GIT_ID_SSH_CONFIG && return 2

  # Nothing worth backing up when the file was empty or just created, and a
  # stray empty config.bak next to a fresh config only looks like debris.
  [[ -s $GIT_ID_SSH_CONFIG ]] && cp -p $GIT_ID_SSH_CONFIG ${GIT_ID_SSH_CONFIG}.bak 2>/dev/null

  # Separate from whatever precedes it, but only if the file does not already
  # end blank, so repeated adds do not open up a gap each time.
  local last=$(tail -n1 $GIT_ID_SSH_CONFIG 2>/dev/null)
  {
    [[ -s $GIT_ID_SSH_CONFIG && -n ${last//[[:space:]]/} ]] && print
    print -r -- "# ${profile}"
    print -r -- "Host ${alias}"
    print -r -- "  HostName github.com"
    print -r -- "  User git"
    print -r -- "  IdentityFile ${key}"
  } >> $GIT_ID_SSH_CONFIG || return 1

  print -r -- $alias
}

# -----------------------------------------------------------------------------
#  Commit signing
#
#  An ssh key used for a push is an authentication key: it proves who opened
#  the transport, and github discards that once the push lands. The Verified
#  badge comes from a signature inside the commit object, which git writes only
#  when told to. Same keypair either way, so nothing here generates a key; it
#  points git at the public half and registers that half a second time, because
#  github tracks authentication keys and signing keys as separate things.
# -----------------------------------------------------------------------------

# ssh signing needs git 2.34. Below that `gpg.format=ssh` is rejected outright
# and every commit fails, so the caller skips the whole thing rather than
# leaving a machine that cannot commit.
#
# Matched by regex rather than by field position. `git --version` is not one
# shape: homebrew prints "git version 2.55.0", but Apple's prints
# "git version 2.39.5 (Apple Git-154)", so taking the last field yields
# "Git-154)" there. That reached `local -i`, which evaluates its right-hand
# side as arithmetic, and the stray paren was a hard error on every switch.
# Taking the first N.M anywhere in the string is indifferent to whatever a
# distribution appends.
_gid_sign_supported() {
  emulate -L zsh
  local raw=$(git --version 2>/dev/null)
  # No version to read means no promise can be made, and the callers all treat
  # a failure here as "leave signing alone", which is the safe direction.
  [[ $raw =~ '([0-9]+)\.([0-9]+)' ]] || return 1
  # Only ever digits by this point, so the arithmetic cannot be fed a word.
  local -i maj=$match[1] min=$match[2]
  (( maj > 2 || (maj == 2 && min >= 34) ))
}

# The public half of $1, re-derived if it is missing. Pointing user.signingkey
# at a file that does not exist breaks *every* commit on the machine, and a
# private key alone is enough to recompute it, so this is a repair rather than
# a reason to give up.
_gid_pubkey() {
  local key=${1/#\~/$HOME}
  [[ -n $key ]] || return 1
  [[ -r ${key}.pub ]] && { print -r -- "${key}.pub"; return 0 }
  [[ -r $key ]] || return 1
  ssh-keygen -y -f "$key" > "${key}.pub" 2>/dev/null || {
    rm -f -- "${key}.pub" 2>/dev/null   # a half-written file is worse than none
    return 1
  }
  chmod 644 "${key}.pub" 2>/dev/null
  print -r -- "${key}.pub"
}

# Point git at $1 for signing, globally, alongside the identity the switch has
# just written. Returns 1 with nothing written when it cannot be done safely,
# so the caller can say why instead of the next commit failing with git's own
# wording.
_gid_sign_set() {
  local key=$1
  _gid_sign_supported || return 2

  # Declared on its own line: `local pub=$(...)` returns local's status, not
  # the substitution's, so the failure would be swallowed and signing switched
  # on with an empty key, which stops commits outright.
  local pub
  pub=$(_gid_pubkey "$key") || return 3
  [[ -n $pub ]] || return 3

  git config --global gpg.format      ssh
  git config --global user.signingkey "$pub"
  git config --global commit.gpgsign  true
  git config --global tag.gpgsign     true
}

# Undo the above. Takes the scope so the per-repo cleanups can reuse it, and
# runs everywhere the identity itself is cleared: commit.gpgsign left behind
# without a signingkey is the one state that stops commits altogether, so this
# half matters more than setting it did.
_gid_sign_clear() {
  local -a where=( ${@:---global} )
  git config $where --unset-all commit.gpgsign  2>/dev/null
  git config $where --unset-all tag.gpgsign     2>/dev/null
  git config $where --unset-all user.signingkey 2>/dev/null
  git config $where --unset-all gpg.format      2>/dev/null
  return 0
}

# True when the account gh is currently acting as already lists $1 as a signing
# key. Compares the key material, field 2, because titles are free text and the
# same key uploaded twice carries two different ones.
_gid_sign_registered() {
  local pub=$1
  command -v gh &>/dev/null || return 1
  local material=${${=$(<$pub)}[2]}
  [[ -n $material ]] || return 1
  gh api /user/ssh_signing_keys --jq '.[].key' 2>/dev/null \
    | grep -qF -- "$material"
}

# Register the public half as a signing key. Best effort throughout: a failure
# here costs the badge, never the key or the persona, so it warns and returns
# rather than aborting whatever called it.
_gid_sign_upload() {
  local pub=$1 title=$2
  local X=$'\e[0m' OK=$'\e[38;5;108m' WARN=$'\e[38;5;179m'
  local DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'

  command -v gh &>/dev/null || {
    print -r -- "   ${DIM}add it as a Signing Key too: https://github.com/settings/ssh/new${X}" >&2
    return 1
  }

  if _gid_sign_registered "$pub"; then
    print -r -- "   ${OK}signing key${X}  ${DIM}already registered on github${X}" >&2
    return 0
  fi

  # Uploading needs a scope that gh does not request by default, so an older
  # login has a token that cannot do this. Ask for it rather than reporting the
  # 404 github answers with when the scope is missing.
  if ! gh auth status 2>&1 | grep -q 'admin:ssh_signing_key'; then
    print -r -- "   ${WARN}gh cannot upload signing keys with its current scopes${X}" >&2
    print -r -- "   ${DIM}run: gh auth refresh -h github.com -s admin:ssh_signing_key${X}" >&2
    return 1
  fi

  if gh ssh-key add "$pub" --type signing --title "$title" >/dev/null 2>&1; then
    print -r -- "   ${OK}signing key${X}  ${DIM}registered on github as ${HI}${title}${X}" >&2
    return 0
  fi

  print -r -- "   ${WARN}could not register the signing key${X}" >&2
  print -r -- "   ${DIM}add it by hand at https://github.com/settings/ssh/new, type: Signing Key${X}" >&2
  return 1
}

# -----------------------------------------------------------------------------
#  Switch
# -----------------------------------------------------------------------------
_gid_switch() {
  emulate -L zsh
  setopt local_options

  local profile=$1
  if [[ -z ${GIT_ID_FIELD[$profile.name]} ]]; then
    print -u2 "git-persona: no persona named '${profile}'"
    print -u2 "available: ${GIT_ID_ORDER}"
    return 1
  fi

  local name=$(_gid_f $profile name)
  local email=$(_gid_f $profile email)
  local key=$(_gid_f $profile key)
  local accent=${$(_gid_f $profile accent):-$GIT_ID_NEUTRAL}
  local shadow=${$(_gid_f $profile shadow):-$GIT_ID_SHADOW}

  local -a _gid_notes=()
  local _gid_gh=''

  # Global, not per-repo: one switch has to govern every repo on the machine,
  # including ones cloned later. Writing it here also means a switch works from
  # a bare directory, which the old per-repo write could not do.
  git config --global user.name       "$name"
  git config --global user.email      "$email"
  #
  # IdentitiesOnly=yes is not optional. -i only *adds* a key to the list ssh
  # offers; ssh-agent's keys are still offered first, and github accepts the
  # first one that matches any account, so with several keys in the agent the
  # persona would be decided by agent order rather than by this line. The flag
  # goes after -i, which git-who's parser relies on.
  git config --global core.sshCommand "ssh -i ${key/#\~/$HOME} -o IdentitiesOnly=yes"

  # The same key, now also answering for the commit itself. Cleared rather than
  # left half-set on any failure: commit.gpgsign pointing at a key git cannot
  # read stops every commit on the machine, which is far worse than an unsigned
  # one, so each failure path says what happened and leaves signing off.
  _gid_sign_set "$key"
  case $? in
    0) ;;
    2) _gid_sign_clear
       _gid_notes+=( 'git is older than 2.34, so commits cannot be ssh-signed and will not show as Verified' ) ;;
    3) _gid_sign_clear
       _gid_notes+=( "no public half for ${key} and it could not be derived, so commits are not signed" ) ;;
  esac

  # The env var beats core.sshCommand, and being per-shell it is the one thing
  # that could answer differently in two tabs. Clearing it lets the global
  # config be the single source, which is the whole point of switching here.
  unset GIT_SSH_COMMAND

  _gid_gh_switch "$profile"

  # Switching gh is only half of https auth. If git is not asking gh for the
  # password, the account above governs nothing over https and the push goes
  # out on a stale cached token instead.
  if command -v gh &>/dev/null && ! _gid_cred_ok; then
    _gid_notes+=(
      'https auth does not go through gh, so clone and push ignore this account. run: gh auth setup-git'
    )
  fi

  # Commits made under the previous persona that have not left the machine yet.
  # Offered, never silent: rewriting commits changes their hashes, and doing
  # that as an unannounced side effect of a switch would be indefensible even
  # when it is safe. Only asked when there is something to fix.
  if _gid_probe && [[ -o interactive && -t 0 ]]; then
    local -a _gid_bad=( ${(f)"$(_gid_pending_foreign $email)"} )
    if (( ${#_gid_bad} )); then
      local -i _gid_n=$(git rev-list --count HEAD --not --remotes 2>/dev/null)
      print
      print -r -- "   ${_gid_n} unpushed commit$( (( _gid_n == 1 )) || print -n s ) authored as ${_gid_bad}"
      if read -q "REPLY?   re-author to ${name} <${email}>? [y/N] "; then
        print
        if _gid_reauthor "$name" "$email" $_gid_bad; then
          _gid_notes+=( "re-authored ${_gid_n} unpushed commit$( (( _gid_n == 1 )) || print -n s ) as ${email}" )
        fi
      else
        print
        _gid_notes+=( "${_gid_n} unpushed commit$( (( _gid_n == 1 )) || print -n s ) still authored as ${_gid_bad}" )
      fi
    fi
  fi

  # Local config beats global, so a repo carrying its own user.email would
  # quietly ignore everything set above and keep committing as the old
  # identity. That is the drift being fixed, so clear it on sight.
  local _gid_repo _gid_head
  if _gid_probe; then
    if [[ -n $(git config --local --get-regexp '^(user\.(name|email|signingkey)|core\.sshcommand|commit\.gpgsign|tag\.gpgsign|gpg\.format)$' 2>/dev/null) ]]; then
      git config --local --unset-all user.name       2>/dev/null
      git config --local --unset-all user.email      2>/dev/null
      git config --local --unset-all core.sshCommand 2>/dev/null
      _gid_sign_clear --local
      _gid_notes+=(
        "cleared a per-repo identity in ${_gid_repo} that would have overridden this"
      )
    fi
  fi

  local _gid_sign=$(git config --global user.signingkey 2>/dev/null)
  [[ -n $_gid_sign ]] && _gid_sign="signing: ${_gid_sign:t}" || _gid_sign='unsigned'

  _gid_render 'PERSONA SWITCHED' "$profile" \
              "$name" "$email" "$key" "$_gid_repo" "$_gid_head" \
              "${(F)_gid_notes}" 'global, applies everywhere' \
              "$accent" "$shadow" "$_gid_gh" "$_gid_sign"
}

# One git-<name> command per profile, defined from whatever the data file
# loaded, so a new account needs no second edit here to become callable.
#
# Sourcing can only ever *add* functions, so an already-running shell keeps
# every command a previous version of this file defined. That is how a rename
# leaves both spellings working, and how a profile deleted by hand stays
# callable until the next new terminal. Both are cleared here first.
() {
  local p=''

  # Names this file used to own. Kept as an explicit list because guessing at
  # "any git-* function" would take out commands another plugin defined.
  for p in git-setup; do   # names this file used to own
    (( ${+functions[$p]} )) && unfunction $p
  done

  # Commands the last load created that are no longer profiles.
  for p in $GIT_ID_COMMANDS; do
    (( ${GIT_ID_ORDER[(Ie)$p]} )) || unfunction git-$p 2>/dev/null
  done

  for p in $GIT_ID_ORDER; do
    functions[git-$p]="_gid_switch ${(q)p}"
  done
}

# Remembered so the next load can tell which commands it is responsible for.
typeset -ga GIT_ID_COMMANDS=( $GIT_ID_ORDER )

# -----------------------------------------------------------------------------
#  Stale per-repo identities
#
#  A switch only clears the repo you are standing in, so repos configured under
#  the old per-repo scheme keep their own user.email and go on ignoring every
#  switch you make. This finds them.
#
#  Reports by default and only clears when asked, because the two cases look
#  identical from here: drift to be swept up, and a repo somebody deliberately
#  pinned. Reading the list first is how you tell them apart.
#
#  Scans GIT_ID_SCAN_ROOTS, set further up this file.
# -----------------------------------------------------------------------------
git-id-locals() {
  emulate -L zsh
  setopt local_options null_glob no_case_glob

  local clear=0
  [[ $1 == (--clear|-c) ]] && clear=1

  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'
  local WARN=$'\e[38;5;179m' OK=$'\e[38;5;108m'
  local root gitdir repo email
  local -i n=0

  print
  for root in $GIT_ID_SCAN_ROOTS; do
    [[ -d $root ]] || continue
    # (N/) keeps this to directories and stays quiet on no match. Depth is
    # unbounded, so a huge tree makes this slow rather than wrong.
    for gitdir in $root/**/.git(N/); do
      repo=${gitdir:h}
      email=$(git -C "$repo" config --local user.email 2>/dev/null)
      [[ -n $email ]] || continue
      (( n++ ))
      if (( clear )); then
        git -C "$repo" config --local --unset-all user.name       2>/dev/null
        git -C "$repo" config --local --unset-all user.email      2>/dev/null
        git -C "$repo" config --local --unset-all core.sshCommand 2>/dev/null
        ( cd "$repo" && _gid_sign_clear --local )
        print -r -- "   ${OK}cleared${X}  ${repo/#$HOME/~}  ${DIM}was ${email}${X}"
      else
        print -r -- "   ${WARN}pinned${X}   ${repo/#$HOME/~}  ${DIM}${email}${X}"
      fi
    done
  done

  if (( n == 0 )); then
    print -r -- "   ${OK}nothing pinned${X}  ${DIM}every repo follows the global identity${X}"
  elif (( ! clear )); then
    print
    print -r -- "   ${HI}${n}${X} ${DIM}repo(s) ignore the global identity. clear them with:${X}"
    print -r -- "   ${HI}git-id-locals --clear${X}"
  fi
  print
}

# -----------------------------------------------------------------------------
#  Glyph check. Every row repeats one icon eight times between brackets, which
#  amplifies a width error until it is impossible to miss: if a row ends short
#  of the reference row, that glyph is rendering zero-width in this terminal and
#  the layout will drift by one cell per icon. A blank between brackets means
#  the font has no glyph there at all.
# -----------------------------------------------------------------------------
git-id-icons() {
  emulate -L zsh
  local k g
  print
  print -r -- "   reference  [M][M][M][M][M][M][M][M]"
  for k in ${(ok)GIT_ID_ICONS}; do
    g=${GIT_ID_ICONS[$k]}
    print -r -- "   ${(r:9:)k}  [$g][$g][$g][$g][$g][$g][$g][$g]"
  done
  print
}

# =============================================================================
#  Adding and removing profiles
#
#  Both rewrite the fenced region of this file and then apply the same change
#  to the running shell, so a new profile is usable immediately without a
#  reload. Every write goes through _gid_write, which stages to a temp file and
#  keeps a .bak, so an interrupted edit cannot leave a half-written data file.
#
#  Both write to GIT_ID_PROFILE_FILE. Neither ever touches this script.
# =============================================================================

# Accents handed out to new profiles, in order, skipping any already in use.
# The first three are the colours the original profiles were given by hand, so
# a rebuilt-from-scratch config comes back in the same order it started.
#
# Shadows are not listed because they are computed, see _gid_shadow_for.
(( ${+GIT_ID_PALETTE} )) || \
  typeset -ga GIT_ID_PALETTE=( 208 45 141 114 210 117 213 156 173 220 )

# Names that would collide with a command this file already defines.
typeset -ga GIT_ID_RESERVED=( who add remove switch persona-uninstall id-profile id-locals id-icons )

# Print the profiles as a numbered list, each in its own accent, with a dot
# against the one whose email matches the identity currently in force.
#
# Shared by git-switch and git-remove so the numbering is the same in both. Two
# lists that look alike but number differently is a way to remove the wrong
# account.
_gid_list() {
  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m' OK=$'\e[38;5;108m'
  local here=$(git config user.email 2>/dev/null)
  local p='' accent='' mark=''
  local -i i=0
  for (( i = 1; i <= ${#GIT_ID_ORDER}; i++ )); do
    p=${GIT_ID_ORDER[i]}
    accent=$'\e[38;5;'"${$(_gid_f $p accent):-$GIT_ID_NEUTRAL}"'m'
    if [[ -n $here && $(_gid_f $p email) == $here ]]; then
      mark="${OK}*${X}"
    else
      mark=' '
    fi
    printf '   %s %s%d.%s %s%-12s%s %s%s  %s  gh: %s%s\n' \
      "$mark" "$HI" $i "$X" "$accent" "$p" "$X" \
      "$DIM" "$(_gid_f $p email)" "$GIT_ID_DOT" "$(_gid_f $p gh)" "$X"
  done
}

# Arrow-key picker over the array named $1, preselecting index $2. Prints the
# chosen 1-based index, nothing if cancelled, and returns 1 when it cannot run
# at all so the caller can fall back to a numbered prompt.
#
# Items arrive pre-formatted, colours and padding included, so this knows
# nothing about profiles or keys and can drive any list.
#
# Drawing goes to /dev/tty, never to stdout: the caller reads the answer
# through $(...), and anything painted on stdout would be captured as part of
# it instead of appearing on screen. The fd is for output only, since read -k
# reads the terminal directly rather than stdin and rejects a -u fd.
#
# -s on the reads is load-bearing. Without it the terminal echoes each arrow
# press as a literal ^[[B into the middle of the list, shifting every line it
# lands on and leaving the redraw permanently misaligned.
_gid_choose() {
  emulate -L zsh
  setopt local_options

  local -a items=( "${(@P)1}" )
  local -i n=${#items} sel=${2:-1}
  (( n )) || return 1
  [[ $GIT_ID_MENU == numbers ]] && return 1
  (( sel >= 1 && sel <= n )) || sel=1

  local tty
  { exec {tty}<>/dev/tty } 2>/dev/null || return 1

  local X=$'\e[0m' HI=$'\e[1;38;5;255m'

  # The cursor is hidden for the duration, so it has to come back on every
  # exit, interrupts included, or the terminal is left without one.
  local -i restored=0
  _gid_choose_restore() { (( restored )) || printf '\e[?25h' >&$tty; restored=1 }
  trap '_gid_choose_restore; return 130' INT
  printf '\e[?25l' >&$tty

  local key='' rest=''
  local -i drawn=0 i=0
  while true; do
    (( drawn )) && printf '\e[%dA' $n >&$tty
    drawn=1
    for (( i = 1; i <= n; i++ )); do
      # \r before the clear pins the cursor to column 0. Moving up preserves
      # the column, so without it any stray output would offset the whole list.
      if (( i == sel )); then
        printf '\r\e[2K   %s>%s %s\n' "$HI" "$X" "${items[i]}" >&$tty
      else
        printf '\r\e[2K     %s\n' "${items[i]}" >&$tty
      fi
    done

    read -s -k 1 key || { sel=0; break }
    case $key in
      # An arrow is ESC [ A. Some terminals send ESC O A in application mode,
      # so both are accepted. The timeout stops a bare Escape from hanging.
      $'\e')
        rest=''
        read -s -k 2 -t 1 rest 2>/dev/null
        case $rest in
          '[A'|'OA') (( sel = sel > 1 ? sel - 1 : n )) ;;
          '[B'|'OB') (( sel = sel < n ? sel + 1 : 1 )) ;;
          '')        sel=0; break ;;
        esac ;;
      k) (( sel = sel > 1 ? sel - 1 : n )) ;;
      j) (( sel = sel < n ? sel + 1 : 1 )) ;;
      $'\n'|$'\r') break ;;
      q|$'\003') sel=0; break ;;
      # A digit still works, so muscle memory from the numbered list survives.
      [1-9]) (( key >= 1 && key <= n )) && { sel=$key; break } ;;
    esac
  done

  trap - INT
  _gid_choose_restore
  exec {tty}>&-
  unfunction _gid_choose_restore

  (( sel )) && print -r -- $sel
  return 0
}

# Arrow picker over the profiles. Prints the chosen profile name, nothing if
# cancelled, 1 if the picker cannot run. Starts on the profile already in
# force, so Enter alone is a no-op rather than a jump to whatever is first.
_gid_menu() {
  emulate -L zsh
  setopt local_options

  local X=$'\e[0m' DIM=$'\e[38;5;243m' OK=$'\e[38;5;108m'
  local here=$(git config user.email 2>/dev/null)
  local -a lines=()
  local p='' accent='' cur=''
  local -i i=0 sel=1

  for (( i = 1; i <= ${#GIT_ID_ORDER}; i++ )); do
    p=${GIT_ID_ORDER[i]}
    accent=$'\e[38;5;'"${$(_gid_f $p accent):-$GIT_ID_NEUTRAL}"'m'
    if [[ -n $here && $(_gid_f $p email) == $here ]]; then
      cur="${OK}*${X}"; sel=$i
    else
      cur=' '
    fi
    lines+=( "$(printf '%s %s%-12s%s %s%s  %s  gh: %s%s' \
      "$cur" "$accent" "$p" "$X" "$DIM" "$(_gid_f $p email)" \
      "$GIT_ID_DOT" "$(_gid_f $p gh)" "$X")" )
  done

  local idx=''
  idx=$(_gid_choose lines $sel) || return 1
  [[ -n $idx ]] && print -r -- ${GIT_ID_ORDER[idx]}
  return 0
}

# Resolve a list answer, which may be a number or a name, to a profile name.
# An out-of-range number falls through as a name so the caller reports it as
# "no profile named 9" rather than silently acting on something else.
_gid_pick() {
  if [[ $1 == <-> ]] && (( $1 >= 1 && $1 <= ${#GIT_ID_ORDER} )); then
    print -r -- ${GIT_ID_ORDER[$1]}
  else
    print -r -- $1
  fi
}

# Prompt for a value into REPLY, falling back to a default on an empty answer.
_gid_ask() {
  local prompt=$1 default=$2 hint=''
  local DIM=$'\e[38;5;243m' X=$'\e[0m'
  [[ -n $default ]] && hint=" ${DIM}[${default}]${X}"
  REPLY=''
  read -r "REPLY?   ${prompt}${hint}: "
  [[ -z $REPLY ]] && REPLY=$default
}

# Replace the data file's contents with stdin, atomically and with a backup.
_gid_write() {
  local tmp=${GIT_ID_PROFILE_FILE}.tmp.$$
  cat > $tmp || { rm -f $tmp; return 1 }

  # A truncated write would silently drop every account, so refuse anything
  # that lost the fence. Cheap insurance against a full disk or a killed pipe.
  if ! grep -q "^${GIT_ID_MARK_CLOSE}\$" $tmp; then
    print -u2 'git-persona: refusing to write, the persona fence went missing'
    rm -f $tmp
    return 1
  fi

  cp -p $GIT_ID_PROFILE_FILE ${GIT_ID_PROFILE_FILE}.bak 2>/dev/null
  mv $tmp $GIT_ID_PROFILE_FILE
}

# The darker companion of an xterm-256 accent.
#
# Indices 16-231 are a 6x6x6 cube, index = 16 + 36r + 6g + b. Scaling each
# component to 0.6 and rounding reproduces all three hand-picked shadows
# exactly (208->130, 45->31, 141->97), so every colour the palette hands out
# lands in the same tone as the ones chosen by eye.
#
# Rounding is done as (c*6 + 5) / 10 in integer arithmetic rather than with
# rint(), because zsh/mathfunc is not loaded by default and its absence shows
# up as an empty result rather than an error.
_gid_shadow_for() {
  local -i i=$1
  # Outside the cube there is no meaningful darker companion, so fall back.
  (( i >= 16 && i <= 231 )) || { print -r -- $GIT_ID_SHADOW; return }
  i=$(( i - 16 ))
  local -i r=$(( i / 36 )) g=$(( (i % 36) / 6 )) b=$(( i % 6 ))
  print -r -- $(( 16 + 36*((r*6+5)/10) + 6*((g*6+5)/10) + ((b*6+5)/10) ))
}

# First palette accent no profile is already using, with its derived shadow.
_gid_next_colours() {
  local accent p used
  for accent in $GIT_ID_PALETTE; do
    used=0
    for p in $GIT_ID_ORDER; do
      [[ $(_gid_f $p accent) == $accent ]] && { used=1; break }
    done
    (( used )) || { print -r -- "$accent $(_gid_shadow_for $accent)"; return }
  done
  print -r -- "$GIT_ID_NEUTRAL $GIT_ID_SHADOW"
}

# Opener for the desktop browser, or nothing when there is no desktop to open
# on: a headless box gets the url printed instead.
_gid_open_cmd() {
  local c=''
  for c in open xdg-open wslview; do
    command -v $c &>/dev/null && { print -r -- $c; return }
  done
  return 1
}

# Generate a key, then hand the public half to github.
#
# Offered from git-add's key list because a persona is built around a key, and
# somebody adding their second account usually has to make one first. Doing it
# here rather than sending them away means the comment is set to the commit
# email, which is what git-add reads back, so the address is typed once.
#
# Prints the chosen path on stdout. Everything else goes to stderr so the
# caller can capture it.
_gid_keygen() {
  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'
  local OK=$'\e[38;5;108m' WARN=$'\e[38;5;179m'
  # Never `path`: zsh ties that name to PATH, so a local one empties the
  # command search path for the rest of the function.
  local email='' name='' keyfile=''

  {
    print
    print -r -- "   ${HI}Generate an ssh key${X}"
    print -r -- "   ${DIM}an ed25519 key pair. the private half stays in ~/.ssh,${X}"
    print -r -- "   ${DIM}the public half goes to github. the comment becomes${X}"
    print -r -- "   ${DIM}the email on your commits, so use the account's address.${X}"
    print -r -- "   ${DIM}a passphrase is optional, press enter twice to skip it.${X}"
    print
  } >&2

  while true; do
    _gid_ask 'email for this account' '' >&2
    email=$REPLY
    [[ $email =~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' ]] && break
    print -r -- "   ${WARN}that does not look like an email address${X}" >&2
  done

  # Defaulted from the address so the file says which account it belongs to,
  # which is the thing people misremember when picking from the list later.
  local suggest="id_ed25519_${${(L)email%%@*}//[^a-z0-9]/}"
  while true; do
    _gid_ask 'file name in ~/.ssh' "$suggest" >&2
    name=${REPLY:t}                       # a path here would be confusing
    keyfile=$HOME/.ssh/$name
    if [[ -z $name ]]; then
      print -r -- "   ${WARN}a name is required${X}" >&2
    elif [[ -e $keyfile || -e $keyfile.pub ]]; then
      # Overwriting a private key destroys access to everything it opens, and
      # ssh-keygen's own prompt is easy to answer wrongly in a hurry.
      print -r -- "   ${WARN}${name} already exists in ~/.ssh${X}" >&2
    else
      break
    fi
  done

  [[ -d ~/.ssh ]] || { mkdir -p ~/.ssh && chmod 700 ~/.ssh } || {
    print -r -- "   ${WARN}could not create ~/.ssh${X}" >&2; return 1
  }

  print >&2
  ssh-keygen -t ed25519 -C "$email" -f "$keyfile" >&2 || {
    print -r -- "   ${WARN}ssh-keygen failed, nothing was written${X}" >&2
    return 1
  }
  print >&2
  print -r -- "   ${OK}created${X}  ${HI}~/.ssh/${name}${X}" >&2

  # ---- hand the public half over ---------------------------------------------
  local pubtext=$(<$keyfile.pub)
  local clip=$(_gid_clip_cmd)
  if [[ -n $clip ]]; then
    print -rn -- "$pubtext" | ${=clip} 2>/dev/null \
      && print -r -- "   ${OK}public key copied to your clipboard${X}" >&2
  fi

  local url='https://github.com/settings/ssh/new'
  local opener=$(_gid_open_cmd)
  if [[ -n $opener ]]; then
    print -r -- "   ${DIM}opening ${url}${X}" >&2
    $opener $url >/dev/null 2>&1
  else
    print -r -- "   ${DIM}add it at ${url}${X}" >&2
  fi

  # Printed as well as copied: a clipboard can be clobbered between here and
  # the browser, and this is the one thing that cannot be recovered by guessing.
  print >&2
  print -r -- "   ${DIM}${pubtext}${X}" >&2
  print >&2
  read -r "?   press enter once the key is added on github " >&2
  print >&2

  print -r -- "~/.ssh/${name}"
}

# -----------------------------------------------------------------------------
#  git-add  ·  add an account
# -----------------------------------------------------------------------------
git-add() {
  emulate -L zsh
  setopt local_options

  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'
  local OK=$'\e[38;5;108m' WARN=$'\e[38;5;179m'

  [[ -o interactive && -t 0 ]] || {
    print -u2 'git-add: needs an interactive terminal'
    return 1
  }
  _gid_seed_profiles
  [[ -w $GIT_ID_PROFILE_FILE ]] || {
    print -u2 "git-add: cannot write ${GIT_ID_PROFILE_FILE}"
    return 1
  }

  # Declared once, up front. Re-declaring a name that already exists in this
  # scope makes zsh echo "i=3" into the middle of the wizard.
  local -i i=0

  print
  print -r -- "   ${HI}Add a persona${X}  ${DIM}ctrl-c to abort${X}"
  print

  # ---- ssh key ---------------------------------------------------------------
  # Asked first because the key carries the email, so answering this one
  # answers two questions. Offered as a list because the filename is the part
  # people misremember.
  #
  # Keys are identified by content, not by name. A filename blocklist only
  # excludes what somebody thought of, and it was wrong the moment this script
  # started leaving config.bak next to the keys. A private key always opens
  # with a PRIVATE KEY header, so ask the file instead.
  local -a keys=()
  local f=''
  for f in ~/.ssh/*(.N^-@); do
    head -n1 $f 2>/dev/null | grep -q 'PRIVATE KEY' && keys+=( $f )
  done
  local key=''
  local -a keylines=()
  local kidx=''

  # An extra entry rather than a separate question. Somebody adding their
  # second account usually has to make its key first, and sending them off to
  # ssh-keygen and back loses the thread of what they were doing.
  local -i newidx=$(( ${#keys} + 1 ))
  local newlabel='generate a new key'

  if (( ${#keys} )); then
    print -r -- "   ${DIM}keys in ~/.ssh${X}  ${DIM}up/down, enter to pick${X}"
    print
    for (( i = 1; i <= ${#keys}; i++ )); do keylines+=( "${keys[i]:t}" ); done
    keylines+=( "+ ${newlabel}" )

    if kidx=$(_gid_choose keylines 1); then
      # The picker ran. An empty answer is a deliberate cancel, not a fallback.
      [[ -n $kidx ]] || { print; print -r -- "   ${DIM}cancelled${X}"; print; return 1 }
      if (( kidx == newidx )); then
        key=$(_gid_keygen) || return 1
      else
        key="~/.ssh/${keys[$kidx]:t}"
        print
      fi
    else
      # No tty, or arrows turned off: the numbered list still works, and a
      # path can be typed for a key living outside ~/.ssh.
      for (( i = 1; i <= ${#keys}; i++ )); do
        print -r -- "     ${HI}${i}.${X} ${keys[i]:t}"
      done
      print -r -- "     ${HI}${newidx}.${X} ${newlabel}"
      print
    fi
  else
    # Nothing to choose from. Offering a prompt for a path that does not exist
    # yet would be a dead end, so go straight to making one.
    print -r -- "   ${DIM}no ssh keys found in ~/.ssh${X}"
    key=$(_gid_keygen) || return 1
  fi

  if [[ -z $key ]]; then
    _gid_ask "ssh key, by number or path" "${keys[1]:t}"
    if [[ $REPLY == <-> ]] && (( REPLY == newidx )); then
      key=$(_gid_keygen) || return 1
    elif [[ $REPLY == <-> ]] && (( REPLY >= 1 && REPLY <= ${#keys} )); then
      key="~/.ssh/${keys[$REPLY]:t}"
    elif [[ $REPLY == /* || $REPLY == '~'* ]]; then
      key=$REPLY
    else
      key="~/.ssh/${REPLY}"
    fi
  fi

  # ---- email, from the key's .pub comment ------------------------------------
  # ssh-keygen puts a comment in field 3 and it is conventionally the address
  # the key was generated for, so this is usually exactly the commit email.
  #
  # Usually, not always: a key made without -C gets user@host instead, which
  # would look plausible and end up stamped on every commit. So take it only
  # when it really is an address, and ask when it is not.
  local email='' pub=${${key/#\~/$HOME}}.pub
  [[ -r $pub ]] && email=$(awk 'NR==1 {print $3}' $pub 2>/dev/null)

  # Shape alone is not enough. ssh-keygen's default comment is user@host, and
  # on macOS that renders as <user>@<machine>.local, which satisfies any
  # reasonable email pattern. So the domain is checked against the shapes a
  # local hostname takes as well.
  local dom=${(L)email#*@} hostshort=${(L)${HOST:-$(hostname)}%%.*}
  if [[ $email =~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' ]] \
     && [[ $dom != *.local && $dom != *.lan && $dom != localhost* ]] \
     && [[ -z $hostshort || $dom != ${hostshort}* ]]; then
    print -r -- "   ${DIM}email from ${pub:t}:${X} ${email}"
  else
    [[ -n $email ]] && print -r -- \
      "   ${WARN}${pub:t} carries a hostname, not an email${X} ${DIM}(${email})${X}"
    _gid_ask 'email, as it appears on commits' ''; email=$REPLY
  fi

  # ---- short name ------------------------------------------------------------
  # Before the sign-in, so every typed answer is out of the way in one run
  # rather than being separated by a browser round-trip. It is also the only
  # question that can be rejected, and rejecting it after a login would mean
  # retyping on the far side of the slowest step.
  local profile
  while true; do
    _gid_ask 'short name, used as git-<name>' ''
    profile=$REPLY
    if [[ -z $profile ]]; then
      print -r -- "   ${WARN}a name is required${X}"
    # A regex, not a [a-z0-9-]## glob: that needs EXTENDED_GLOB, which
    # emulate -L zsh does not turn on, so the ## would be matched literally and
    # every name on earth would be rejected.
    elif [[ ! $profile =~ '^[a-z0-9-]+$' ]]; then
      print -r -- "   ${WARN}lowercase letters, digits and dashes only${X}"
    elif (( ${GIT_ID_RESERVED[(Ie)$profile]} )); then
      print -r -- "   ${WARN}'${profile}' is reserved, git-${profile} already exists${X}"
    elif [[ -n ${GIT_ID_FIELD[$profile.name]} ]]; then
      print -r -- "   ${WARN}'${profile}' already exists, use git-remove first${X}"
    else
      break
    fi
  done

  # ---- gh account ------------------------------------------------------------
  # Always a fresh login, never a pick from what is already in the keyring.
  # Signing in is the only step that proves which account is being added, and
  # it hands back the username and the display name as a side effect, so two
  # more questions never have to be asked.
  local gh=''
  if ! command -v gh &>/dev/null; then
    print -r -- "   ${WARN}gh is not installed${X}"
    _gid_ask 'github username for push, pull and clone' ''; gh=$REPLY
  else
    print
    print -r -- "   ${DIM}sign in to the github account this profile should use${X}"
    [[ -n $(_gid_clip_cmd) ]] && print -r -- \
      "   ${DIM}the one-time code is copied to your clipboard automatically${X}"
    print
    if _gid_gh_login_run; then
      # Read the account back rather than trusting anything typed: a login
      # makes its account active, and the browser decides which one that is.
      gh=$(_gid_gh_active)
      print
      if [[ -n $gh ]]; then
        print -r -- "   ${OK}signed in as${X} ${HI}${gh}${X}"
      else
        print -r -- "   ${WARN}signed in, but gh did not report which account${X}"
        _gid_ask 'github username' ''; gh=$REPLY
      fi
    else
      print
      print -r -- "   ${WARN}sign-in did not complete${X}"
      _gid_ask 'github username for push, pull and clone' ''; gh=$REPLY
    fi
  fi

  # ---- route https through gh ------------------------------------------------
  # Done here rather than on every switch, because it is a one-time property of
  # the machine, not of the persona. Without it `gh auth switch` moves the
  # active account but git never asks gh for a password, so every persona
  # clones and pushes on whatever token the system keychain cached first.
  if command -v gh &>/dev/null && ! _gid_cred_ok; then
    if _gid_cred_setup; then
      print -r -- "   ${OK}https auth${X}  ${DIM}routed through gh${X}"
    else
      print -r -- "   ${WARN}could not route https auth through gh. run: gh auth setup-git${X}"
    fi
  fi

  # ---- register the key for signing ------------------------------------------
  # After the login, because it has to land on the account being added rather
  # than on whichever one happened to be active. Same key as the one above, a
  # second registration: github keeps authentication keys and signing keys in
  # separate lists, and only the signing list produces the Verified badge.
  local signpub=$(_gid_pubkey "$key")
  if [[ -n $signpub ]]; then
    _gid_sign_upload "$signpub" "${profile} (signing)"
  else
    print -r -- "   ${WARN}no public half for ${key}, so commits cannot be signed${X}"
  fi

  # Signing in as an account another profile already owns would give two
  # commands the same token and quietly diverge them, so say so now.
  local other
  for other in $GIT_ID_ORDER; do
    [[ $(_gid_f $other gh) == $gh && -n $gh ]] && {
      print -r -- "   ${WARN}${gh} is already used by git-${other}${X}"
      break
    }
  done

  # ---- full name, from the github account ------------------------------------
  # Asked of GitHub rather than of the user. Falls back to a prompt when the
  # account has no display name set, or when gh cannot answer at all.
  local name='' ghinfo=''
  [[ -n $gh ]] && ghinfo=$(_gid_gh_identity $gh)
  if [[ -n $ghinfo ]]; then
    name=${ghinfo#*$'\t'}
    [[ -z $name ]] && name=${ghinfo%%$'\t'*}
    print -r -- "   ${DIM}name from github:${X} ${name}"
  else
    _gid_ask 'full name, as it appears on commits' ''; name=$REPLY
  fi

  # ---- colours ---------------------------------------------------------------
  # Not asked. Two xterm indices is not a decision worth interrupting an
  # account setup for, and the palette picks better than a prompt would: the
  # next unused accent, with a shadow derived to match the existing tone.
  # Edit the block afterwards if a particular colour is wanted.
  local pair=$(_gid_next_colours)
  local accent=${pair%% *} shadow=${pair##* }

  # ---- write -----------------------------------------------------------------
  # Built as lines and joined, not appended with $(...), which strips the
  # trailing newline off every substitution and would fold the whole block onto
  # a single line. (qq) does the quoting, so a name like O'Brien cannot produce
  # a data file that fails to parse, taking every account down with it.
  local -a b=()
  b+=( "$(printf 'git-id-profile %-26s \\' "$profile")" )
  b+=( "$(printf '    name    %-30s \\' "${(qq)name}")"   )
  b+=( "$(printf '    email   %-30s \\' "${(qq)email}")"  )
  b+=( "$(printf '    key     %-30s \\' "${(qq)key}")"    )
  b+=( "$(printf '    gh      %-30s \\' "${(qq)gh}")"     )
  b+=( "$(printf '    accent  %-30s \\' "$accent")"       )
  b+=( "$(printf '    shadow  %s'       "$shadow")"       )
  local block=${(F)b}

  local -a lines=( "${(@f)$(<$GIT_ID_PROFILE_FILE)}" )
  local -i idx=0
  for (( i = 1; i <= ${#lines}; i++ )); do
    [[ ${lines[i]} == $GIT_ID_MARK_CLOSE ]] && { idx=$i; break }
  done
  if (( idx == 0 )); then
    print -u2 "git-add: could not find the persona fence in ${GIT_ID_PROFILE_FILE}"
    return 1
  fi

  # (@) on both slices, or the quotes join each slice into one long line and
  # the rewritten file is a single unparseable blob.
  print -rl -- "${(@)lines[1,idx-1]}" '' "$block" "${(@)lines[idx,-1]}" \
    | _gid_write || return 1

  # ---- apply to this shell ---------------------------------------------------
  git-id-profile $profile \
    name "$name" email "$email" key "$key" gh "$gh" \
    accent "$accent" shadow "$shadow"
  functions[git-$profile]="_gid_switch ${(q)profile}"

  print
  print -r -- "   ${OK}added${X}  ${HI}git-${profile}${X}  ${DIM}saved to ${GIT_ID_PROFILE_FILE/#$HOME/~}${X}"

  # ---- ssh config ------------------------------------------------------------
  # A Host alias so the key can be reached over ssh too. Unused while remotes
  # stay HTTPS, but git-remove deletes these, so git-add has to create them or
  # the file would only ever shrink.
  local -a _gid_notes=()
  local sshalias=''
  sshalias=$(_gid_ssh_add $profile "$key")
  case $? in
    0) print -r -- "   ${OK}ssh alias${X}  ${HI}${sshalias}${X}  ${DIM}added to ${GIT_ID_SSH_CONFIG/#$HOME/~}${X}" ;;
    2) print -r -- "   ${DIM}ssh alias github.com-${profile} already present, left alone${X}" ;;
    *) _gid_notes+=( "could not write ${GIT_ID_SSH_CONFIG/#$HOME/~}, no ssh alias was added" ) ;;
  esac

  # Anything that went wrong above is worth saying before the switch runs and
  # paints its own banner over the top of it.
  local n=''
  for n in $_gid_notes; do
    [[ -n $n ]] && print -r -- "   ${WARN}${n}${X}"
  done

  # Switch straight into it. Adding an account is only ever done in order to
  # use it, so making that a second command would be a step for its own sake.
  # _gid_switch draws the full banner, which is why nothing is rendered here.
  _gid_switch $profile
}

# -----------------------------------------------------------------------------
#  git-switch  ·  pick an account and switch to it
#
#  The same thing git-<name> does, for when the name is not at hand. Takes a
#  number or a name as an argument too, so it stays usable from a script where
#  a picker would hang.
# -----------------------------------------------------------------------------
git-switch() {
  emulate -L zsh
  setopt local_options

  local X=$'\e[0m' HI=$'\e[1;38;5;255m' DIM=$'\e[38;5;243m'
  local profile=$1

  (( ${#GIT_ID_ORDER} )) || {
    print -u2 'git-switch: no profiles configured, run git-add'
    return 1
  }

  if [[ -z $profile ]]; then
    [[ -o interactive && -t 0 ]] || {
      print -u2 "git-switch: needs an interactive terminal, or a profile name"
      print -u2 "available: ${GIT_ID_ORDER}"
      return 1
    }
    print
    print -r -- "   ${HI}Switch persona${X}  ${DIM}up/down, enter to pick, q to cancel${X}"
    print
    if ! profile=$(_gid_menu); then
      # No tty, or arrows turned off: the numbered prompt still works.
      _gid_list
      print
      _gid_ask 'switch to which, by number or name' ''
      profile=$(_gid_pick $REPLY)
    fi
    print
    [[ -n $profile ]] || { print -r -- "   ${DIM}nothing chosen${X}"; print; return 1 }
  else
    # An argument may be a number too, so the list can be read once and acted
    # on later without retyping the name.
    profile=$(_gid_pick $profile)
  fi

  # _gid_switch reports an unknown name and lists what exists, so there is no
  # second check here.
  _gid_switch $profile
}

# -----------------------------------------------------------------------------
#  git-remove  ·  drop an account
# -----------------------------------------------------------------------------
git-remove() {
  emulate -L zsh
  setopt local_options

  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'
  local OK=$'\e[38;5;108m' WARN=$'\e[38;5;179m'

  [[ -o interactive && -t 0 ]] || {
    print -u2 'git-remove: needs an interactive terminal'
    return 1
  }
  (( ${#GIT_ID_ORDER} )) || {
    print -u2 'git-remove: no profiles configured'
    return 1
  }

  local profile=$1

  if [[ -z $profile ]]; then
    print
    print -r -- "   ${HI}Configured personas${X}  ${DIM}up/down, enter to pick, q to cancel${X}"
    print
    if ! profile=$(_gid_menu); then
      _gid_list
      print
      _gid_ask 'remove which, by number or name' ''
      profile=$(_gid_pick $REPLY)
    fi
    print
    [[ -n $profile ]] || {
      print -r -- "   ${DIM}nothing removed${X}"; print; return 1
    }
  fi

  [[ -n ${GIT_ID_FIELD[$profile.name]} ]] || {
    print -u2 "git-remove: no persona named '${profile}'"
    return 1
  }

  # Work out everything that will be touched before asking, so the prompt is a
  # complete account of what is about to happen rather than a surprise
  # afterwards.
  #
  # Every name here is declared with an assignment. A bare `local p` on a name
  # already declared in this scope makes zsh echo "p=<value>" into the middle
  # of the prompt, which is what used to leak out under the remove question.
  local ghacct=$(_gid_f $profile gh) profkey=$(_gid_f $profile key)
  local dologout='' other='' ghshared=''
  if [[ -n $ghacct ]] && command -v gh &>/dev/null && _gid_gh_known $ghacct; then
    dologout=$ghacct
    # A gh account shared by another profile has to survive this, or removing
    # one profile would break the other's pushes.
    for other in $GIT_ID_ORDER; do
      [[ $other == $profile ]] && continue
      [[ $(_gid_f $other gh) == $ghacct ]] && { dologout=''; ghshared=$other; break }
    done
  fi

  local -a sshhosts=()
  [[ -n $profkey ]] && sshhosts=( ${(f)"$(_gid_ssh_hosts_for $profkey)"} )
  sshhosts=( ${sshhosts:#} )

  # Removing the persona that is currently in force used to leave its name and
  # email sitting in ~/.gitconfig, so the next commit was still authored by an
  # account that no longer existed, pushed on whichever token gh promoted in
  # its place. Worked out before the write, while the profile can still be read.
  local profemail=$(_gid_f $profile email) islive=''
  [[ -n $profemail && $(git config --global user.email) == $profemail ]] && islive=1
  local -a rest=( ${GIT_ID_ORDER:#$profile} )

  print
  print -r -- "   ${HI}remove ${profile}${X} ${DIM}($(_gid_f $profile email))${X}"
  print -r -- "     ${DIM}·${X} persona block from ${GIT_ID_PROFILE_FILE:t}"
  (( ${#sshhosts} )) && print -r -- \
    "     ${DIM}·${X} ${sshhosts} from ${GIT_ID_SSH_CONFIG/#$HOME/~}"
  [[ -n $dologout ]] && print -r -- \
    "     ${DIM}·${X} gh token for ${dologout}"
  # Two different reasons for not logging out, and saying the wrong one is
  # worse than saying nothing: "another profile uses it" was printed even when
  # the account had simply never been logged in.
  [[ -n $ghshared ]] && print -r -- \
    "     ${DIM}·${X} ${DIM}gh token for ${ghacct} kept, git-${ghshared} uses it too${X}"
  [[ -n $ghacct && -z $dologout && -z $ghshared ]] && print -r -- \
    "     ${DIM}·${X} ${DIM}no gh token for ${ghacct} to drop, it is not logged in${X}"
  print -r -- "     ${DIM}·${X} ${DIM}ssh key files are never touched${X}"
  if [[ -n $islive ]]; then
    if (( ${#rest} )); then
      print -r -- "     ${DIM}·${X} this is the persona in force, so ${HI}git-${rest[1]}${X}${DIM} takes over${X}"
    else
      print -r -- "     ${DIM}·${X} this is the last persona, so the identity in ~/.gitconfig is cleared"
    fi
  else
    print -r -- "     ${DIM}·${X} ${DIM}~/.gitconfig is not touched, another persona is in force${X}"
  fi
  print

  read -q "REPLY?   confirm? [y/N] " || {
    print; print -r -- "   ${DIM}nothing removed${X}"; print; return 1
  }
  print

  # Drop the block: its opening line, then every continuation line, ending on
  # the first that does not carry a trailing backslash.
  #
  # Blank lines are buffered rather than printed straight out, so the blank
  # that separates this block from the one above it disappears with it. Absorb
  # the trailing blank instead and each add-then-remove cycle would leave one
  # extra line behind; this way the round trip is byte for byte.
  awk -v nm="$profile" '
    $0 ~ "^git-id-profile[ \t]+" nm "([ \t]|$)" { drop = 1; nb = 0 }
    drop { if ($0 !~ /\\[ \t]*$/) drop = 0; next }
    /^[ \t]*$/ { nb++; next }
    { while (nb-- > 0) print ""; nb = 0; print }
    END { while (nb-- > 0) print "" }
  ' $GIT_ID_PROFILE_FILE | _gid_write || return 1

  # ---- apply to this shell ---------------------------------------------------
  local k
  for k in ${(k)GIT_ID_FIELD}; do
    [[ $k == ${profile}.* ]] && unset "GIT_ID_FIELD[$k]"
  done
  GIT_ID_ORDER=( ${GIT_ID_ORDER:#$profile} )
  unfunction git-$profile 2>/dev/null

  print -r -- "   ${OK}removed${X}  ${HI}git-${profile}${X}  ${DIM}backup at ${GIT_ID_PROFILE_FILE/#$HOME/~}.bak${X}"

  # ---- ssh config ------------------------------------------------------------
  # Matched by IdentityFile, so this catches aliases whose names bear no
  # relation to the profile, which is every one of the hand-written ones.
  if (( ${#sshhosts} )); then
    local -a gone=( ${(f)"$(_gid_ssh_remove $profkey)"} )
    gone=( ${gone:#} )
    if (( ${#gone} )); then
      print -r -- "   ${OK}ssh alias${X}  ${HI}${gone}${X}  ${DIM}removed from ${GIT_ID_SSH_CONFIG/#$HOME/~}${X}"
    else
      print -r -- "   ${WARN}could not edit ${GIT_ID_SSH_CONFIG/#$HOME/~}${X}"
    fi
  fi

  # ---- gh token --------------------------------------------------------------
  # Only when the confirmation listed it, so this can never be a surprise.
  if [[ -n $dologout ]]; then
    if gh auth logout --hostname github.com --user "$dologout" &>/dev/null; then
      print -r -- "   ${OK}logged out${X}  ${HI}${dologout}${X}  ${DIM}token dropped from the keyring${X}"
    else
      print -r -- "   ${WARN}could not log ${dologout} out${X} ${DIM}run: gh auth logout --user ${dologout}${X}"
    fi
  fi

  # ---- the identity left behind ----------------------------------------------
  # Only when the removed persona was the live one. Any other case means
  # ~/.gitconfig describes a persona that still exists, and rewriting it would
  # change who the next commit is authored by for no reason.
  if [[ -z $islive ]]; then
    print
    return 0
  fi

  if (( ${#rest} )); then
    # A full switch rather than three git config writes, so gh moves too.
    # Leaving gh where it is would swap one mismatch for another.
    print -r -- "   ${DIM}that was the persona in force, switching to ${rest[1]}${X}"
    _gid_switch $rest[1]
    return 0
  fi

  # Nothing left to switch to. Clearing beats leaving a dead identity in place:
  # git then asks who you are on the next commit, which is the honest answer.
  git config --global --unset-all user.name       2>/dev/null
  git config --global --unset-all user.email      2>/dev/null
  git config --global --unset-all core.sshCommand 2>/dev/null
  _gid_sign_clear
  print -r -- "   ${OK}identity cleared${X}  ${DIM}no personas left, git will ask who you are${X}"
  print
}

# -----------------------------------------------------------------------------
#  git-persona-uninstall  ·  undo everything git-add created
#
#  A plugin has no uninstall hook. Removal is just rm -rf of its directory, and
#  no plugin manager runs code on the way out, so the cleanup that ought to
#  happen then has to be a command you run first. This undoes what git-add
#  wrote, then prints the single line that deletes the plugin itself.
#
#  Deliberately narrow, matching git-remove's contract:
#    - ssh key files are never touched
#    - gh logins are left signed in; drop them with gh auth logout
#    - ~/.gitconfig is cleared only when the identity in force is one of ours
# -----------------------------------------------------------------------------
git-persona-uninstall() {
  emulate -L zsh
  setopt local_options

  local X=$'\e[0m' DIM=$'\e[38;5;243m' HI=$'\e[1;38;5;255m'
  local OK=$'\e[38;5;108m' WARN=$'\e[38;5;179m'

  [[ -o interactive && -t 0 ]] || {
    print -u2 'git-persona-uninstall: needs an interactive terminal'
    return 1
  }

  # Worked out before asking, so the prompt is the whole story. The live
  # identity counts as ours only when its email matches a configured persona;
  # anything else in ~/.gitconfig was set by hand and is left untouched.
  local file=$GIT_ID_PROFILE_FILE dir=${GIT_ID_PROFILE_FILE:h}
  local liveemail=$(git config --global user.email 2>/dev/null)
  local islive='' p
  for p in $GIT_ID_ORDER; do
    [[ -n $liveemail && $(_gid_f $p email) == $liveemail ]] && { islive=1; break }
  done

  local pl=''; (( ${#GIT_ID_ORDER} == 1 )) || pl='s'

  print
  print -r -- "   ${HI}Uninstall git-persona${X}  ${DIM}ctrl-c to abort${X}"
  print
  print -r -- "   ${DIM}removes${X}"
  (( ${#GIT_ID_ORDER} )) && print -r -- \
    "     ${DIM}·${X} ${#GIT_ID_ORDER} persona${pl} and their ssh aliases in ${GIT_ID_SSH_CONFIG/#$HOME/~}"
  print -r -- "     ${DIM}·${X} ${file:t} and its backup, and ${dir/#$HOME/~} if it is left empty"
  [[ -n $islive ]] && print -r -- \
    "     ${DIM}·${X} the identity in ~/.gitconfig ${DIM}(it is one of ours)${X}"
  print -r -- "   ${DIM}keeps${X}"
  print -r -- "     ${DIM}·${X} ${DIM}ssh key files, always${X}"
  print -r -- "     ${DIM}·${X} ${DIM}gh logins — run gh auth logout to drop those${X}"
  [[ -z $islive ]] && print -r -- \
    "     ${DIM}·${X} ${DIM}~/.gitconfig, its identity is not one of ours${X}"
  print

  read -q "REPLY?   confirm? [y/N] " || {
    print; print -r -- "   ${DIM}nothing removed${X}"; print; return 1
  }
  print

  # ---- ssh aliases -----------------------------------------------------------
  # Matched by IdentityFile, so hand-named aliases go too, exactly as git-remove
  # does it, one persona at a time.
  local -a allgone=() gone=()
  local key=''
  for p in $GIT_ID_ORDER; do
    key=$(_gid_f $p key)
    [[ -n $key ]] || continue
    gone=( ${(f)"$(_gid_ssh_remove $key)"} )
    allgone+=( ${gone:#} )
  done
  (( ${#allgone} )) && print -r -- \
    "   ${OK}ssh aliases${X}  ${HI}${allgone}${X}  ${DIM}removed from ${GIT_ID_SSH_CONFIG/#$HOME/~}${X}"

  # ---- gitconfig identity ----------------------------------------------------
  if [[ -n $islive ]]; then
    git config --global --unset-all user.name       2>/dev/null
    git config --global --unset-all user.email      2>/dev/null
    git config --global --unset-all core.sshCommand 2>/dev/null
    _gid_sign_clear
    print -r -- "   ${OK}identity cleared${X}  ${DIM}from ~/.gitconfig, git will ask who you are${X}"
  fi

  # ---- the data --------------------------------------------------------------
  # The file and its backup by name, then the directory only if that left it
  # empty. Never rm -rf the parent: a custom GIT_ID_PROFILE_FILE could point at
  # $HOME, and rmdir refuses a non-empty directory, which is the safe failure.
  if [[ -e $file || -e ${file}.bak ]]; then
    rm -f -- $file ${file}.bak 2>/dev/null
    print -r -- "   ${OK}removed${X}  ${HI}${file:t}${X}  ${DIM}and its backup${X}"
  fi
  if rmdir -- $dir 2>/dev/null; then
    print -r -- "   ${OK}removed${X}  ${HI}${dir/#$HOME/~}${X}"
  elif [[ -d $dir ]]; then
    print -r -- "   ${DIM}kept ${dir/#$HOME/~}, it holds other files${X}"
  fi

  # ---- forget it in this shell -----------------------------------------------
  # The functions and profiles live in memory until the shell restarts. Drop
  # them so this session matches the disk we just cleared.
  for p in $GIT_ID_ORDER; do unfunction git-$p 2>/dev/null; done
  local k
  for k in ${(k)GIT_ID_FIELD}; do unset "GIT_ID_FIELD[$k]"; done
  GIT_ID_ORDER=()

  # ---- the plugin itself -----------------------------------------------------
  # Not deleted here: a sourced plugin cannot tell which manager installed it,
  # and guessing wrong leaves a half-removed install. Print the line instead.
  print
  print -r -- "   ${DIM}data gone. remove the plugin with:${X}"
  if [[ -n $ZSH_CUSTOM ]]; then
    print -r -- "     ${HI}omz plugin disable git-persona; rm -rf \$ZSH_CUSTOM/plugins/git-persona${X}"
  else
    print -r -- "     ${HI}rm -rf <the git-persona directory>${X} ${DIM}and drop it from your plugin list${X}"
  fi
  print -r -- "   ${DIM}then start a new shell${X}"
  print
}

# -----------------------------------------------------------------------------
#  Who am I right now
# -----------------------------------------------------------------------------
git-who() {
  emulate -L zsh
  setopt local_options

  local _gid_repo _gid_head scope=''
  local -a _gid_notes=()
  local inrepo=1
  _gid_probe || inrepo=0

  # The effective identity: what git would actually stamp on the next commit.
  local name=$(git config user.name 2>/dev/null)
  local email=$(git config user.email 2>/dev/null)

  # A local override is now a fault rather than a feature: the identity is
  # meant to be global, so anything repo-scoped is drift left over from the
  # old scheme and will outrank the profile you think you are on.
  scope='global, applies everywhere'
  if (( inrepo )) && [[ -n $(git config --local user.email 2>/dev/null) ]]; then
    scope='overridden on this repo'
    _gid_notes+=(
      'this repo sets its own user.email, so it ignores the global identity. run: git-id-locals --clear'
    )
  fi

  # The same check the switch makes, repeated here because git-who is where
  # someone looks when a clone came back with the wrong account's access.
  if command -v gh &>/dev/null && ! _gid_cred_ok; then
    _gid_notes+=(
      "https auth uses ${${$(_gid_cred_helper):-no helper}##*/}, not gh, so clone and push ignore the account above. run: gh auth setup-git"
    )
  fi

  # Read the key from config, not from the environment: config is what a fresh
  # shell will use, and that is the answer worth reporting. A leftover export
  # from a tab opened before the last switch still wins locally though, so say
  # so rather than printing a key that is not the one in force here.
  local key='none set, ssh picks its own'
  local cfgssh=$(git config core.sshCommand 2>/dev/null)
  [[ -n $cfgssh ]] && key=${${cfgssh##*-i }%% *}

  if [[ -n $GIT_SSH_COMMAND ]]; then
    local envkey=${${GIT_SSH_COMMAND##*-i }%% *}
    [[ $envkey == $key ]] || _gid_notes+=(
      "GIT_SSH_COMMAND in this shell overrides the global key with ${envkey/#$HOME/~}"
    )
    key=$envkey
  fi
  key=${key/#$HOME/\~}

  # Match the live email back to a known profile, and borrow its colours.
  local label='unmatched' accent=$GIT_ID_NEUTRAL shadow=$GIT_ID_SHADOW p
  for p in $GIT_ID_ORDER; do
    if [[ $(_gid_f $p email) == $email ]]; then
      label=$p
      accent=${$(_gid_f $p accent):-$GIT_ID_NEUTRAL}
      shadow=${$(_gid_f $p shadow):-$GIT_ID_SHADOW}
      break
    fi
  done

  if [[ -z $name && -z $email ]]; then
    name='(unset)'; email='(unset)'; label='none'; scope=''
    accent=$GIT_ID_NEUTRAL; shadow=$GIT_ID_SHADOW
    _gid_notes+=( 'no user.name or user.email is configured' )
  fi

  # Signing state, reported next to the key because the two are set together
  # and come apart quietly. Three things have to line up for a Verified badge
  # and only the last is visible from here, so the notes name whichever is
  # missing rather than leaving an unsigned commit to be discovered on github.
  local sign='' signkey=$(git config user.signingkey 2>/dev/null)
  local signon=$(git config --type=bool commit.gpgsign 2>/dev/null)
  local signfmt=$(git config gpg.format 2>/dev/null)

  if [[ $signon == true && -n $signkey ]]; then
    sign="signing: ${${signkey/#$HOME/\~}:t}"
    # The one state that breaks every commit rather than just leaving it
    # unsigned, so it is a warning and not a quiet dash.
    [[ -r ${signkey/#\~/$HOME} ]] || _gid_notes+=(
      "user.signingkey points at ${signkey}, which cannot be read, so every commit will fail"
    )
    [[ $signfmt == ssh ]] || _gid_notes+=(
      "commit.gpgsign is on but gpg.format is ${signfmt:-gpg}, not ssh, so the ssh key above is not what signs"
    )
  elif [[ $signon == true ]]; then
    sign='signing: no key'
    _gid_notes+=(
      'commit.gpgsign is on with no user.signingkey, so every commit will fail. run: git-switch <persona>'
    )
  else
    sign='unsigned'
    _gid_notes+=(
      'commits are not signed, so they will not show as Verified on github. run: git-switch <persona>'
    )
  fi

  # What a push would actually authenticate as. The whole point of showing it
  # next to the email: these two are set independently and drift apart quietly,
  # so a mismatch is worth saying out loud rather than leaving to be inferred.
  local gh=$(_gid_gh_active)
  [[ -z $gh ]] && gh='none'

  # Three ways this goes wrong, and an unmapped profile is the quiet one: with
  # nothing to compare against there is no mismatch to detect, yet the push is
  # still going out under some other account's token.
  if [[ -n ${GIT_ID_FIELD[$label.name]} ]]; then
    local want=$(_gid_f $label gh)
    if [[ -z $want ]]; then
      _gid_notes+=(
        "no gh account mapped for ${label}, so https pushes go out as ${gh}"
      )
    elif [[ $gh != $want ]]; then
      _gid_notes+=( "commits say ${label}, but https pushes authenticate as ${gh}" )
    fi
  fi

  _gid_render 'CURRENT PERSONA' "$label" \
              "$name" "$email" "$key" "$_gid_repo" "$_gid_head" \
              "${(F)_gid_notes}" "$scope" "$accent" "$shadow" "$gh" "$sign"
}
