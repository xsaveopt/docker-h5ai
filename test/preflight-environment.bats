setup() {
  load helper
  new_case_dir
}

teardown() {
  remove_case_dir
}

@test "check_clock warns on a clock before 2024" {
  case_body() {
    date() {
      case "${2:-}" in
        +%Y) printf '1999\n' ;;
        *) command date "$@" ;;
      esac
    }
    check_clock
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"system clock looks wrong (UTC year=1999)"* ]] || return 1
}

@test "check_clock stays quiet with a sane clock and TZ" {
  case_body() {
    TZ=UTC
    check_clock
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_clock accepts a current year" {
  case_body() {
    date() {
      case "${2:-}" in
        +%Y) printf '2026\n' ;;
        *) command date "$@" ;;
      esac
    }
    unset TZ
    check_clock
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output != *"looks wrong"* ]] || return 1
}

@test "check_ports warns on a held port" {
  case_body() {
    listening_ports() { printf '80\n8080\n9000\n'; }
    PORTS_INTERNAL="8080"
    check_ports
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"port 8080 is already in use"* ]] || return 1
}

@test "check_ports stays quiet on a free port" {
  case_body() {
    listening_ports() { printf '80\n9000\n'; }
    PORTS_INTERNAL="8080"
    check_ports
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_ports skips when no ports are declared" {
  case_body() {
    listening_ports() { printf '8080\n'; }
    PORTS_INTERNAL=""
    check_ports
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "map_host_id maps an id inside the range" {
  printf '         0     100000      65536\n' > "$CASE_DIR/uid_map"

  case_body() {
    map_host_id 33 "$CASE_DIR/uid_map"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "100033" ] || return 1
}

@test "map_host_id reports an id outside the range" {
  printf '         0     100000      65536\n' > "$CASE_DIR/uid_map"

  case_body() {
    map_host_id 70000 "$CASE_DIR/uid_map"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "?" ] || return 1
}

@test "map_host_id reads the matching range of several" {
  printf '         0          0          1\n         1     200000      65536\n' > "$CASE_DIR/uid_map"

  case_body() {
    map_host_id 5 "$CASE_DIR/uid_map"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "200004" ] || return 1
}

@test "map_host_id reports an unreadable map" {
  case_body() {
    map_host_id 33 "$CASE_DIR/missing_map"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ "$output" = "?" ] || return 1
}

@test "is_secret matches only listed names" {
  case_body() {
    ENV_SECRET="HT_PASSWORD OTHER_TOKEN"
    is_secret HT_PASSWORD && printf 'exact match\n'
    is_secret OTHER_TOKEN && printf 'second match\n'
    is_secret HT_PASSWOR || printf 'no prefix match\n'
    is_secret BASE_PATH || printf 'no unrelated match\n'
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"exact match"* ]] || return 1
  [[ $output == *"second match"* ]] || return 1
  [[ $output == *"no prefix match"* ]] || return 1
  [[ $output == *"no unrelated match"* ]] || return 1
}

@test "report_env prints the configuration table" {
  case_body() {
    ENV_REPORT="HT_PASSWORD BASE_PATH TZ"
    ENV_SECRET="HT_PASSWORD"
    HT_PASSWORD=hunter2
    BASE_PATH=/files
    unset TZ
    report_env
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"****** (set)"* ]] || return 1
  [[ $output != *"hunter2"* ]] || return 1
  [[ $output == *"/files"* ]] || return 1
  [[ $output == *"- (unset)"* ]] || return 1
}

@test "report_env skips an empty report list" {
  case_body() {
    ENV_REPORT=""
    report_env
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_caps notes an all-dropped set" {
  printf 'Name:\tbash\nCapInh:\t0000000000000000\nCapEff:\t0000000000000000\n' > "$CASE_DIR/status"

  case_body() {
    awk() { command awk "$1" "$CASE_DIR/status"; }
    check_caps
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"capabilities: all dropped (CapEff=0000000000000000); good"* ]] || return 1
  [[ $output != *"WARN"* ]] || return 1
}

@test "check_caps notes the docker default set" {
  printf 'Name:\tbash\nCapEff:\t00000000a80425fb\n' > "$CASE_DIR/status"

  case_body() {
    awk() { command awk "$1" "$CASE_DIR/status"; }
    check_caps
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"capabilities: docker default set only (chown dac_override fowner fsetid kill setgid setuid setpcap net_bind_service net_raw sys_chroot mknod audit_write setfcap)"* ]] || return 1
  [[ $output != *"WARN"* ]] || return 1
}

@test "check_caps warns on capabilities beyond the default" {
  printf 'Name:\tbash\nCapEff:\t000000c0a82435fb\n' > "$CASE_DIR/status"

  case_body() {
    awk() { command awk "$1" "$CASE_DIR/status"; }
    check_caps
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"elevated capabilities present beyond the docker default: net_admin sys_admin perfmon bpf"* ]] || return 1
  [[ $output == *"cap_drop"* ]] || return 1
}

@test "check_caps notes an unreadable status" {
  case_body() {
    awk() { return 1; }
    check_caps
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"capabilities: could not read /proc/self/status"* ]] || return 1
}

@test "check_net skips unless enabled" {
  case_body() {
    getent() { printf 'called\n'; }
    unset PREFLIGHT_NET_CHECK
    check_net
    PREFLIGHT_NET_CHECK=0
    check_net
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_net reports working DNS" {
  case_body() {
    getent() { [ "$1 $2" = "hosts cloudflare.com" ]; }
    PREFLIGHT_NET_CHECK=1
    NET_TCP_TARGET="127.0.0.1:1"
    check_net
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"outbound DNS OK (resolved cloudflare.com)"* ]] || return 1
}

@test "check_net warns on failed DNS and TCP" {
  case_body() {
    getent() { return 2; }
    PREFLIGHT_NET_CHECK=1
    NET_TCP_TARGET="127.0.0.1:1"
    check_net
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"outbound DNS failed (could not resolve cloudflare.com)"* ]] || return 1
  [[ $output == *"outbound TCP to 127.0.0.1:1 failed; egress may be blocked"* ]] || return 1
}
