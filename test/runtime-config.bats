setup() {
  load helper
  new_case_dir
}

teardown() {
  remove_case_dir
}

base_path_case() {
  if [ "$1" = "unset" ]; then
    unset BASE_PATH
  else
    BASE_PATH="$1"
  fi
  check_base_path
  printf 'NORM=%s FATAL=%s\n' "$BASE_PATH_NORM" "$FATAL"
}

@test "check_base_path leaves an unset prefix empty" {
  run in_entrypoint base_path_case unset

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"NORM= FATAL=0"* ]] || return 1
}

@test "check_base_path treats / as no prefix" {
  run in_entrypoint base_path_case /

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"NORM= FATAL=0"* ]] || return 1
}

@test "check_base_path adds the leading slash" {
  run in_entrypoint base_path_case files

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"NORM=/files FATAL=0"* ]] || return 1
}

@test "check_base_path strips the trailing slash" {
  run in_entrypoint base_path_case /files/

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"NORM=/files FATAL=0"* ]] || return 1
}

@test "check_base_path accepts a nested prefix" {
  run in_entrypoint base_path_case /a/b-c_d.e~f

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"NORM=/a/b-c_d.e~f FATAL=0"* ]] || return 1
}

@test "check_base_path rejects a prefix with a space" {
  run in_entrypoint base_path_case "/files with space"

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_base_path rejects shell characters" {
  run in_entrypoint base_path_case '/files$(id)'

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_base_path rejects a doubled slash" {
  run in_entrypoint base_path_case //files

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_runtime_dir creates the directory" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR/runtime"
    check_runtime_dir
    printf 'MODE=%s FATAL=%s\n' "$(stat -c '%a' "$RUNTIME_DIR")" "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"runtime directory ready"* ]] || return 1
  [[ $output == *"MODE=700 FATAL=0"* ]] || return 1
}

@test "check_runtime_dir fails when it cannot create the directory" {
  skip_as_root
  chmod 500 "$CASE_DIR"

  case_body() {
    RUNTIME_DIR="$CASE_DIR/runtime"
    check_runtime_dir
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"cannot create"* ]] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
  [[ $output == *"mount a tmpfs at /tmp"* ]] || return 1
}

@test "check_cache skips a cache dir that is not there" {
  case_body() {
    CACHE_DIR="$CASE_DIR/cache"
    check_cache
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_cache stays quiet on a writable cache" {
  case_body() {
    CACHE_DIR="$CASE_DIR"
    check_cache
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [ -z "$output" ] || return 1
}

@test "check_cache warns on a read-only cache" {
  skip_as_root
  chmod 500 "$CASE_DIR"

  case_body() {
    CACHE_DIR="$CASE_DIR"
    check_cache
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"thumbnails and archive downloads will be disabled"* ]] || return 1
}

@test "write_htpasswd stores the bcrypt hash" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    HT_PASSWORD=hunter2
    htpasswd() { printf 'admin:$2y$05$bcrypthash\n'; }
    write_htpasswd
    printf 'MODE=%s\n' "$(stat -c '%a' "$RUNTIME_DIR/htpasswd")"
    cat "$RUNTIME_DIR/htpasswd"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *'admin:$2y$05$bcrypthash'* ]] || return 1
  [[ $output == *"MODE=600"* ]] || return 1
}

@test "write_htpasswd falls back to md5" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    HT_PASSWORD=hunter2
    htpasswd() {
      if [ "$1" = "-nbB" ]; then
        printf 'bcrypt unsupported\n'
        return 3
      fi
      printf 'admin:$apr1$md5hash\n'
    }
    write_htpasswd
    cat "$RUNTIME_DIR/htpasswd"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"falling back to md5"* ]] || return 1
  [[ $output == *'admin:$apr1$md5hash'* ]] || return 1
}

@test "write_htpasswd exits when hashing fails" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    HT_PASSWORD=hunter2
    htpasswd() {
      printf 'no such user database\n'
      return 4
    }
    write_htpasswd
  }

  run in_entrypoint case_body

  [ "$status" -eq 1 ] || return 1
  [[ $output == *"htpasswd failed (exit 4)"* ]] || return 1
}

@test "write_server_conf serves from the root" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    BASE_PATH_NORM=""
    write_server_conf
    cat "$RUNTIME_DIR/server.conf"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"root /app;"* ]] || return 1
  [[ $output == *'try_files $uri $uri/ /_h5ai/public/index.php?$args;'* ]] || return 1
  [[ $output == *"location ^~ /_h5ai/private/ { deny all; }"* ]] || return 1
  [[ $output == *"location = /health {"* ]] || return 1
  [[ $output == *"auth_basic off;"* ]] || return 1
  [[ $output == *'fastcgi_param SCRIPT_FILENAME /tmp/h5ai/health.php;'* ]] || return 1
  [[ $output == *"return 503 \"degraded\";"* ]] || return 1
}

@test "write_server_conf serves under a base path prefix" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    BASE_PATH_NORM="/files"
    write_server_conf
    cat "$RUNTIME_DIR/server.conf"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"location = /files { return 301 /files/; }"* ]] || return 1
  [[ $output == *"alias /app/;"* ]] || return 1
  [[ $output == *'location ~ ^/files/(?<h5ai_script>.+\.php)$ {'* ]] || return 1
  [[ $output == *'fastcgi_param SCRIPT_FILENAME /app/$h5ai_script;'* ]] || return 1
  [[ $output == *'try_files $uri $uri/ /files/_h5ai/public/index.php?$args;'* ]] || return 1
  [[ $output != *"root /app;"* ]] || return 1
  [[ $output == *"location = /files/health {"* ]] || return 1
  [[ $output == *"location = /health {"$'\n'"        auth_basic off;"$'\n'"        return 404;"* ]] || return 1
  [[ $output == *'fastcgi_param SCRIPT_FILENAME /tmp/h5ai/health.php;'* ]] || return 1
  [[ $output == *"return 503 \"degraded\";"* ]] || return 1
}

@test "write_health_php writes the health script" {
  case_body() {
    RUNTIME_DIR="$CASE_DIR"
    write_health_php
    cat "$RUNTIME_DIR/health.php"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *'<?php'* ]] || return 1
  [[ $output == *'echo "up";'* ]] || return 1
}

@test "check_auth fails without a password" {
  case_body() {
    unset HT_PASSWORD
    check_auth
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"HT_PASSWORD is not set"* ]] || return 1
  [[ $output == *"-e HT_PASSWORD="* ]] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_auth fails on an empty password" {
  case_body() {
    HT_PASSWORD=""
    check_auth
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"FATAL=1"* ]] || return 1
}

@test "check_auth accepts a set password" {
  case_body() {
    HT_PASSWORD=hunter2
    check_auth
    printf 'FATAL=%s\n' "$FATAL"
  }

  run in_entrypoint case_body

  [ "$status" -eq 0 ] || return 1
  [[ $output == *"basic auth configured for user admin"* ]] || return 1
  [[ $output != *"hunter2"* ]] || return 1
  [[ $output == *"FATAL=0"* ]] || return 1
}
