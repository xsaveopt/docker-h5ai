setup() {
  load helper
  new_case_dir
  make_stubs
  export HT_PASSWORD=hunter2
  unset BASE_PATH PREFLIGHT_NET_CHECK NGINX_DELAY NGINX_EXIT PHP_FPM_EXIT NGINX_TEST_STATUS NGINX_TEST_OUTPUT
}

teardown() {
  remove_case_dir
}

@test "main refuses to start without a password" {
  unset HT_PASSWORD

  run entrypoint_main

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"HT_PASSWORD is not set"* ]] || return 1
  [[ $output == *"preflight failed; refusing to start"* ]] || return 1
  [[ $output == *"does not change ownership of your mounts"* ]] || return 1
  [[ $output != *"launching services"* ]] || return 1
  [ ! -s "$STUB_LOG" ] || return 1
  [ ! -e "$CASE_DIR/runtime/htpasswd" ] || return 1
}

@test "main refuses to start on an invalid base path" {
  export BASE_PATH="/bad path"

  run entrypoint_main

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"is not a usable path prefix"* ]] || return 1
  [[ $output == *"preflight failed; refusing to start"* ]] || return 1
  [ ! -s "$STUB_LOG" ] || return 1
}

@test "main refuses to start when the runtime dir cannot be created" {
  skip_as_root
  mkdir "$CASE_DIR/locked"
  chmod 500 "$CASE_DIR/locked"
  export RUNTIME_DIR="$CASE_DIR/locked/runtime"

  run entrypoint_main

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"cannot create $CASE_DIR/locked/runtime"* ]] || return 1
  [[ $output == *"preflight failed; refusing to start"* ]] || return 1
  [ ! -s "$STUB_LOG" ] || return 1
}

@test "main refuses to start when the runtime dir exists but cannot be taken over" {
  skip_as_root
  mkdir -p "$CASE_DIR/runtime"
  chmod 500 "$CASE_DIR/runtime"
  stub_command chmod 'printf "chmod: changing permissions of %s: Operation not permitted\n" "$2" >&2; exit 1'

  run entrypoint_main

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"$CASE_DIR/runtime is not writable by uid=$(id -u)"* ]] || return 1
  [[ $output == *"preflight failed; refusing to start"* ]] || return 1
}

@test "main warns when running as root" {
  stub_command id 'case "$1" in -u|-g) printf "0\n" ;; *) printf "uid=0(root) gid=0(root)\n" ;; esac'
  export NGINX_EXIT=0

  run entrypoint_main

  [[ $output == *"running as uid=0 (root); this image is built to run unprivileged"* ]] || return 1
  [[ $output != *"(non-root)"* ]] || return 1
}

@test "main notes the unprivileged ids" {
  stub_command id 'case "$1" in -u|-g) printf "33\n" ;; *) printf "uid=33 gid=33\n" ;; esac'
  export NGINX_EXIT=0

  run entrypoint_main

  [[ $output == *"all processes run as uid=33 gid=33 (non-root)"* ]] || return 1
  [[ $output != *"running as uid=0"* ]] || return 1
  [[ $output != *"user namespace remapping is active"* ]] || return 1
}

@test "main detects user namespace remapping" {
  require_userns
  local outer_uid outer_gid
  outer_uid="$(id -u)"
  outer_gid="$(id -g)"
  export NGINX_EXIT=0

  run run_main unshare -U --map-user=33 --map-group=33 bash "$ENTRYPOINT"

  [[ $output == *"user namespace remapping is active"* ]] || return 1
  [[ $output == *"inside uid=33 maps to HOST uid=${outer_uid}; inside gid=33 maps to HOST gid=${outer_gid}"* ]] || return 1
  [[ $output == *"chown to the HOST ids above, not 33:33"* ]] || return 1
}

@test "main checks every bind mount in the loop" {
  require_mountns
  mkdir -p "$CASE_DIR/source" "$CASE_DIR/rw-mount" "$CASE_DIR/ro-mount"
  chmod 777 "$CASE_DIR/source"
  export NGINX_EXIT=0

  run run_main unshare -Urm bash -c 'mount --bind "$1" "$2" && mount --bind "$1" "$3" && mount -o remount,bind,ro "$3" && exec bash "$4"' _ \
    "$CASE_DIR/source" "$CASE_DIR/rw-mount" "$CASE_DIR/ro-mount" "$ENTRYPOINT"

  [[ $output == *"bind mount $CASE_DIR/rw-mount: read/write OK ($CASE_DIR/rw-mount)"* ]] || return 1
  [[ $output == *"loose permissions on $CASE_DIR/rw-mount (mode 777"* ]] || return 1
  [[ $output == *"bind mount $CASE_DIR/ro-mount: $CASE_DIR/ro-mount is read-only [mounted read-only]; skipping"* ]] || return 1
  [[ $output == *"preflight complete; launching services"* ]] || return 1
}

@test "main writes the runtime files before checking nginx" {
  export NGINX_EXIT=0

  run entrypoint_main

  [ -f "$CASE_DIR/runtime/server.conf" ] || return 1
  [ -f "$CASE_DIR/runtime/health.php" ] || return 1
  [ "$(cat "$CASE_DIR/runtime/htpasswd")" = 'admin:$2y$05$stubhash' ] || return 1
  [ "$(head -n 2 "$STUB_LOG")" = "$(printf 'htpasswd -nbB\nnginx -p /etc/nginx -c nginx.conf -t')" ] || return 1
}

@test "main refuses to start when nginx rejects its configuration" {
  export NGINX_TEST_STATUS=1
  export NGINX_TEST_OUTPUT="nginx: [emerg] unknown directive in server.conf"

  run entrypoint_main

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"nginx rejected its configuration; refusing to start"* ]] || return 1
  [[ $output == *"nginx: [emerg] unknown directive in server.conf"* ]] || return 1
  [ "$(cat "$STUB_LOG")" = "$(printf 'htpasswd -nbB\nnginx -p /etc/nginx -c nginx.conf -t')" ] || return 1
}

@test "main execs a passed command instead of the services" {
  run entrypoint_main printf 'passthrough %s\n' ok

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"passthrough ok"* ]] || return 1
  [[ $(cat "$STUB_LOG") != *"php-fpm"* ]] || return 1
  [ "$(grep -c '^nginx' "$STUB_LOG")" -eq 1 ] || return 1
}

@test "main passes the exit status of a passed command" {
  run entrypoint_main bash -c 'exit 7'

  [ "$status" -eq 7 ] || return 1
}

@test "main starts nginx and php-fpm in the foreground" {
  export NGINX_EXIT=0 NGINX_DELAY=1

  run entrypoint_main

  grep -qx "nginx -p /etc/nginx -c nginx.conf" "$STUB_LOG" || return 1
  grep -qx "php-fpm -F -O -y /etc/h5ai/php-fpm.conf" "$STUB_LOG" || return 1
}

@test "main stops php-fpm and exits with the status when nginx dies" {
  export NGINX_EXIT=3

  run entrypoint_main

  [ "$status" -eq 3 ] || return 1
  [[ $output == *"nginx exited (status 3); shutting down"* ]] || return 1
  process_gone "$CASE_DIR/php-fpm.pid" || return 1
}

@test "main stops nginx and exits with the status when php-fpm dies" {
  export PHP_FPM_EXIT=5

  run entrypoint_main

  [ "$status" -eq 5 ] || return 1
  [[ $output == *"php-fpm exited (status 5); shutting down"* ]] || return 1
  process_gone "$CASE_DIR/nginx.pid" || return 1
}
