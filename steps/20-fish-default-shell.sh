#!/usr/bin/env bash
# sss-name: Make fish the default shell
# sss-description: chsh to fish; for directory-service accounts (LDAP/AD) not in /etc/passwd, switch to fish from the shell startup file instead
# sss-default: on
# sss-requires: fish
# sss-needs-root: optional

fish_path=$(command -v fish) || die "fish is not installed"
me=$(id -un)
current=$(getent passwd "$me" | cut -d: -f7)

if [ "$current" = "$fish_path" ]; then already_done "login shell is already $fish_path"; fi

if grep -q "^$me:" /etc/passwd; then
  # Local account: change the real login shell.
  grep -qxF "$fish_path" /etc/shells || { printf '%s\n' "$fish_path" | as_root tee -a /etc/shells >/dev/null; }
  as_root usermod -s "$fish_path" "$me"
  log "login shell for $me changed from $current to $fish_path"
  exit 0
fi

# Not in /etc/passwd: the account comes from a directory service (LDAP, AD/SSSD, NIS),
# so usermod/chsh cannot change it. Switch to fish from the shell's startup file instead.
# Only interactive shells are affected, so scp, rsync and `ssh host command` still run in $current.
case "$(basename "${current:-bash}")" in
  bash) # an ssh login runs a *login* bash: it reads the first of these, not ~/.bashrc
        rc="$HOME/.profile"
        for f in "$HOME/.bash_profile" "$HOME/.bash_login"; do [ -f "$f" ] && { rc="$f"; break; }; done ;;
  zsh)  rc="$HOME/.zshrc" ;;
  *)    die "$me is a directory-service account whose login shell ($current) I can't hook. Ask an admin to set its shell to $fish_path in the directory." ;;
esac
log "$me is not in /etc/passwd (directory-service account); using $rc instead of chsh"
replace_block "$rc" fish-shell <<'BLK'
# Switch to fish for interactive logins. Skip once with: NO_FISH=1
if [[ $- == *i* ]] && [ -z "${FISH_VERSION:-}" ] && [ -z "${NO_FISH:-}" ] && command -v fish >/dev/null 2>&1; then
  exec fish
fi
BLK
if [ "$BLOCK_CHANGED" = 0 ]; then already_done "$rc already switches to fish"; fi
log "note: the login shell itself is still $current; ask an admin to change it in the directory for a true default"
log "interactive $(basename "$current") logins now switch to fish via $rc (skip with NO_FISH=1)"
