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

make_stubs() {
  STUB_BIN="$CASE_DIR/bin"
  STUB_LOG="$CASE_DIR/calls.log"
  mkdir -p "$STUB_BIN"
  : > "$STUB_LOG"
  cat > "$STUB_BIN/nginx" <<'STUB'
#!/usr/bin/env bash
printf 'nginx %s\n' "$*" >> "$STUB_LOG"
case " $* " in
  *" -t "*)
    [ -n "${NGINX_TEST_OUTPUT:-}" ] && printf '%s\n' "$NGINX_TEST_OUTPUT"
    exit "${NGINX_TEST_STATUS:-0}"
    ;;
esac
printf '%s\n' "$$" > "$STUB_DIR/nginx.pid"
[ -n "${NGINX_EXIT:-}" ] && { sleep "${NGINX_DELAY:-0}"; exit "$NGINX_EXIT"; }
exec sleep 30
STUB
  cat > "$STUB_BIN/php-fpm8.5" <<'STUB'
#!/usr/bin/env bash
printf 'php-fpm %s\n' "$*" >> "$STUB_LOG"
printf '%s\n' "$$" > "$STUB_DIR/php-fpm.pid"
[ -n "${PHP_FPM_EXIT:-}" ] && exit "$PHP_FPM_EXIT"
exec sleep 30
STUB
  cat > "$STUB_BIN/htpasswd" <<'STUB'
#!/usr/bin/env bash
printf 'htpasswd %s\n' "$1" >> "$STUB_LOG"
printf 'admin:$2y$05$stubhash\n'
STUB
  chmod +x "$STUB_BIN/nginx" "$STUB_BIN/php-fpm8.5" "$STUB_BIN/htpasswd"
  export STUB_LOG STUB_DIR="$CASE_DIR"
}

stub_command() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

run_main() {
  (
    export ENTRYPOINT_SOURCE_ONLY=0
    export PATH="$STUB_BIN:$PATH"
    export RUNTIME_DIR="${RUNTIME_DIR:-$CASE_DIR/runtime}"
    "$@"
  ) 2>&1 </dev/null
}

entrypoint_main() {
  run_main bash "$ENTRYPOINT" "$@"
}

process_gone() {
  local pid
  [ -f "$1" ] || return 0
  pid="$(cat "$1")"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done
  return 1
}

require_userns() {
  if ! unshare -U --map-user=33 --map-group=33 true 2>/dev/null; then
    skip "user namespaces are not available"
  fi
  return 0
}

require_mountns() {
  if ! unshare -Urm true 2>/dev/null; then
    skip "mount namespaces are not available"
  fi
  return 0
}
