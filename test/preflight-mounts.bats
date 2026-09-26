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

@test "is_system_fs matches pseudo filesystems only" {
  case_body() {
    local fs
    for fs in proc sysfs cgroup2 tmpfs overlay devtmpfs fuse.lxcfs nsfs; do
      is_system_fs "$fs" && printf 'system %s\n' "$fs"
    done
    for fs in ext4 xfs btrfs zfs nfs4 fuse.sshfs 9p virtiofs; do
      is_system_fs "$fs" || printf 'real %s\n' "$fs"
    done
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "${#lines[@]}" -eq 16 ] || return 1
  [[ $output == *"system proc"* ]] || return 1
  [[ $output == *"system fuse.lxcfs"* ]] || return 1
  [[ $output == *"real ext4"* ]] || return 1
  [[ $output == *"real virtiofs"* ]] || return 1
}

@test "is_system_path matches container plumbing only" {
  case_body() {
    local p
    for p in / /proc /proc/sys /sys/fs/cgroup /dev /dev/shm /run /run/secrets /etc/hostname /etc/hosts /etc/resolv.conf; do
      is_system_path "$p" && printf 'system %s\n' "$p"
    done
    for p in /app/files /data /etc/h5ai /etc/hosts.d /runtime /device /tmp; do
      is_system_path "$p" || printf 'user %s\n' "$p"
    done
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "${#lines[@]}" -eq 18 ] || return 1
  [[ $output == *"system /run/secrets"* ]] || return 1
  [[ $output == *"user /app/files"* ]] || return 1
  [[ $output == *"user /etc/hosts.d"* ]] || return 1
  [[ $output == *"user /runtime"* ]] || return 1
}

@test "collect_mounts keeps only real bind mounts" {
  cat > "$CASE_DIR/mountinfo" <<'MOUNTS'
1 0 0:1 / / rw,relatime - overlay overlay rw
2 1 0:2 / /proc rw,nosuid - proc proc rw
3 1 0:3 / /dev rw,nosuid - tmpfs tmpfs rw
4 1 0:4 / /sys ro,nosuid - sysfs sysfs ro
5 1 8:1 /srv/files /app/files ro,relatime - ext4 /dev/sda1 rw
6 1 8:1 /srv/extra /app/files/extra rw,relatime shared:1 master:2 - xfs /dev/sdb1 rw
7 1 8:1 /etc/hostname /etc/hostname rw,relatime - ext4 /dev/sda1 rw
8 1 0:5 / /tmp rw - tmpfs tmpfs rw
9 1 8:1 /srv/files /app/files ro,relatime - ext4 /dev/sda1 rw
MOUNTS

  case_body() {
    awk() { command awk "$1" "$CASE_DIR/mountinfo"; }
    REQUIRED_RW=""
    collect_mounts
    printf '[%s]\n' "${MOUNTS[@]}"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "$(printf '[/app/files]\n[/app/files/extra]')" ] || return 1
}

@test "collect_mounts lists required dirs first without duplicates" {
  cat > "$CASE_DIR/mountinfo" <<'MOUNTS'
1 0 0:1 / / rw,relatime - overlay overlay rw
5 1 8:1 /srv/files /app/files rw,relatime - ext4 /dev/sda1 rw
6 1 8:1 /srv/data /data rw,relatime - ext4 /dev/sda1 rw
MOUNTS

  case_body() {
    awk() { command awk "$1" "$CASE_DIR/mountinfo"; }
    REQUIRED_RW="/data /cache /data"
    collect_mounts
    printf '[%s]\n' "${MOUNTS[@]}"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "$(printf '[/data]\n[/cache]\n[/app/files]')" ] || return 1
}

@test "collect_mounts is empty without mountinfo" {
  case_body() {
    awk() { return 1; }
    REQUIRED_RW=""
    collect_mounts
    printf 'COUNT=%s\n' "${#MOUNTS[@]}"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "COUNT=0" ] || return 1
}
