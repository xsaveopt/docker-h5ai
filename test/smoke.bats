setup_file() {
  if [ -z "${H5AI_IMAGE:-}" ]; then
    skip "set H5AI_IMAGE to a built image to run the container smoke tests"
  fi
  export SMOKE_PASSWORD="smoke-secret"
}

setup() {
  [ -n "${H5AI_IMAGE:-}" ] || skip "set H5AI_IMAGE to a built image to run the container smoke tests"
  SMOKE_CONTAINERS=()
}

teardown() {
  local cid
  for cid in "${SMOKE_CONTAINERS[@]}"; do
    docker rm -f "$cid" >/dev/null 2>&1 || true
  done
}

start_h5ai() {
  local cid
  cid="$(docker run -d --health-interval=1s --health-start-period=0s "$@" "$H5AI_IMAGE")"
  SMOKE_CONTAINERS+=("$cid")
  CID="$cid"
  ADDR="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cid")"
}

wait_for() {
  local url="$1" i
  for i in $(seq 1 60); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "$url")" = "200" ]; then
      return 0
    fi
    [ "$(docker inspect -f '{{.State.Running}}' "$CID")" = "true" ] || break
    sleep 0.5
  done
  docker logs "$CID" 2>&1
  return 1
}

wait_healthy() {
  local i state
  for i in $(seq 1 60); do
    state="$(docker inspect -f '{{.State.Health.Status}}' "$CID")"
    [ "$state" = "healthy" ] && return 0
    sleep 0.5
  done
  printf 'health status: %s\n' "$state"
  return 1
}

http_code() {
  curl -s -o /dev/null -w '%{http_code}' "$@"
}

@test "smoke: basic auth rejects missing and wrong credentials" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD"
  wait_for "http://$ADDR:8080/health"

  [ "$(http_code "http://$ADDR:8080/")" = "401" ] || return 1
  [ "$(http_code -u "admin:wrong" "http://$ADDR:8080/")" = "401" ] || return 1
  [ "$(http_code -u "nobody:$SMOKE_PASSWORD" "http://$ADDR:8080/")" = "401" ] || return 1
}

@test "smoke: the index is rendered by php-fpm over the socket" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD"
  wait_for "http://$ADDR:8080/health"

  run curl -s -u "admin:$SMOKE_PASSWORD" -w '\n%{http_code}' "http://$ADDR:8080/"

  [ "${lines[-1]}" = "200" ] || return 1
  [[ $output == *"h5ai"* ]] || return 1
  [[ $output != *"<?php"* ]] || return 1
}

@test "smoke: /health answers without credentials" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD"
  wait_for "http://$ADDR:8080/health"

  run curl -s -w '\n%{http_code}' "http://$ADDR:8080/health"

  [ "${lines[-1]}" = "200" ] || return 1
  [ "${lines[0]}" = "up" ] || return 1
}

@test "smoke: the private directory is denied even with credentials" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD"
  wait_for "http://$ADDR:8080/health"

  [ "$(http_code -u "admin:$SMOKE_PASSWORD" "http://$ADDR:8080/_h5ai/private/")" = "403" ] || return 1
  [ "$(http_code -u "admin:$SMOKE_PASSWORD" "http://$ADDR:8080/_h5ai/private/conf/options.json")" = "403" ] || return 1
}

@test "smoke: the image healthcheck reports healthy" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD"

  wait_healthy
}

@test "smoke: BASE_PATH serves under the prefix" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD" -e BASE_PATH=/files
  wait_for "http://$ADDR:8080/files/health"

  run curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://$ADDR:8080/files"
  [ "$output" = "301 http://$ADDR:8080/files/" ] || return 1

  [ "$(http_code "http://$ADDR:8080/files/")" = "401" ] || return 1
  [ "$(http_code "http://$ADDR:8080/health")" = "404" ] || return 1
  [ "$(http_code -u "admin:$SMOKE_PASSWORD" "http://$ADDR:8080/files/_h5ai/private/")" = "403" ] || return 1
  [ "$(http_code -u "admin:$SMOKE_PASSWORD" "http://$ADDR:8080/_h5ai/public/index.php")" = "404" ] || return 1

  run curl -s -u "admin:$SMOKE_PASSWORD" -w '\n%{http_code}' "http://$ADDR:8080/files/"
  [ "${lines[-1]}" = "200" ] || return 1
  [[ $output == *"/files/_h5ai/"* ]] || return 1
}

@test "smoke: the healthcheck follows BASE_PATH" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD" -e BASE_PATH=/files

  wait_healthy
}

@test "smoke: the container refuses to start without a password" {
  start_h5ai

  run docker wait "$CID"
  [ "$output" = "1" ] || return 1

  run docker logs "$CID"
  [[ $output == *"HT_PASSWORD is not set"* ]] || return 1
  [[ $output == *"preflight failed; refusing to start"* ]] || return 1
}

@test "smoke: an overridden RUNTIME_DIR still serves" {
  start_h5ai -e HT_PASSWORD="$SMOKE_PASSWORD" -e RUNTIME_DIR=/tmp/h5ai-runtime
  wait_for "http://$ADDR:8080/health"

  [ "$(http_code "http://$ADDR:8080/")" = "401" ] || return 1
  [ "$(http_code -u "admin:$SMOKE_PASSWORD" "http://$ADDR:8080/")" = "200" ] || return 1
}
