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
