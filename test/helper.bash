REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/entrypoint.sh"

export ENTRYPOINT_SOURCE_ONLY=1

if ! stat -c '%a' "$REPO_ROOT" >/dev/null 2>&1 && command -v gstat >/dev/null 2>&1; then
  stat() { gstat "$@"; }
fi

in_entrypoint() {
  ( . "$ENTRYPOINT"; set +e; "$@" ) 2>&1
}

new_case_dir() {
  mkdir -p "$REPO_ROOT/.tmp"
  CASE_DIR="$(mktemp -d "$REPO_ROOT/.tmp/entrypoint-tests.XXXXXX")"
}

remove_case_dir() {
  [ -n "${CASE_DIR:-}" ] || return 0
  chmod -R u+rwX "$CASE_DIR" 2>/dev/null || true
  rm -rf "$CASE_DIR"
}

skip_as_root() {
  if [ "$(id -u)" = "0" ]; then
    skip "uid 0 writes anywhere"
  fi
  return 0
}
