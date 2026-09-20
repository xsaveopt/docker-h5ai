setup() {
  load helper
  new_case_dir
}

teardown() {
  remove_case_dir
}

@test "check_rw reports a writable mount" {
  case_body() {
    REQUIRED_RW=""
    check_rw "$CASE_DIR" "bind mount $CASE_DIR"
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"read/write OK"* ]] || return 1
  [[ $output == *"FATAL=0"* ]] || return 1
}

@test "check_rw fails on a missing required volume" {
  case_body() {
    REQUIRED_RW="$CASE_DIR/absent"
    check_rw "$CASE_DIR/absent" "required volume $CASE_DIR/absent"
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"ERROR"* ]] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_rw warns on a missing optional mount" {
  case_body() {
    REQUIRED_RW=""
    check_rw "$CASE_DIR/absent" "bind mount $CASE_DIR/absent"
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"WARN"* ]] || return 1
  [[ $output == *"FATAL=0"* ]] || return 1
}

@test "check_rw fails on an unwritable required volume" {
  skip_as_root
  chmod 500 "$CASE_DIR"

  case_body() {
    REQUIRED_RW="$CASE_DIR"
    check_rw "$CASE_DIR" "required volume $CASE_DIR"
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"cannot read+write"* ]] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
  [[ $output == *"fix on host: chown -R $(id -u):$(id -g)"* ]] || return 1
}

@test "check_rw warns on an unwritable optional mount" {
  skip_as_root
  chmod 500 "$CASE_DIR"

  case_body() {
    REQUIRED_RW=""
    check_rw "$CASE_DIR" "bind mount $CASE_DIR"
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"is not writable"* ]] || return 1
  [[ $output == *"FATAL=0"* ]] || return 1
}

@test "check_rw prints the host chown hint under userns" {
  skip_as_root
  chmod 500 "$CASE_DIR"

  case_body() {
    REQUIRED_RW="$CASE_DIR"
    USERNS=1
    HOST_UID=100033
    HOST_GID=100033
    check_rw "$CASE_DIR" "required volume $CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"chown -R 100033:100033"* ]] || return 1
}

@test "check_perms warns on a world-writable dir" {
  chmod 777 "$CASE_DIR"

  case_body() {
    check_perms "$CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"loose permissions"* ]] || return 1
}

@test "check_perms stays quiet on a tight dir" {
  chmod 750 "$CASE_DIR"

  case_body() {
    check_perms "$CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_perms stays quiet on a missing dir" {
  case_body() {
    check_perms "$CASE_DIR/absent"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_flags warns on noexec where the app executes" {
  case_body() {
    mount_opt() { printf 'noexec\n'; }
    EXEC_MOUNTS="$CASE_DIR"
    check_flags "$CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"mounted noexec"* ]] || return 1
}

@test "check_flags ignores noexec elsewhere" {
  case_body() {
    mount_opt() { printf 'noexec\n'; }
    EXEC_MOUNTS="/somewhere/else"
    check_flags "$CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_flags stays quiet without noexec" {
  case_body() {
    mount_opt() { printf '\n'; }
    EXEC_MOUNTS="$CASE_DIR"
    check_flags "$CASE_DIR"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}
