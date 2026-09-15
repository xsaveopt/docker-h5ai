# docker-h5ai

A small Docker image that serves a directory through the h5ai file browser, running on nginx and php-fpm behind HTTP basic auth.
Images are published to ghcr.io/xsaveopt/docker-h5ai, with a version tag and latest for each release and dev tracking the main branch.

## Run

Mount the files you want to browse into /app/files and set the password:

```sh
docker run --rm -p 8080:8080 \
	-v {path}:/app/files:ro \
	-e HT_PASSWORD={password} \
	ghcr.io/xsaveopt/docker-h5ai
```

Log in with the username admin and the password from HT_PASSWORD.
The username is fixed.

| Variable | Meaning |
| --- | --- |
| `HT_PASSWORD` | Password for the admin user. The container refuses to start without it. |
| `BASE_PATH` | Subpath to serve under, like /files. Unset serves at the root. |
| `PREFLIGHT_NET_CHECK` | Set to 1 to test outbound DNS and TCP during startup. |

## Behind a reverse proxy on a subpath

h5ai builds every link from the path its index.php is served at, so serving it at the root and proxying it under /files/ leaves asset links pointing at /_h5ai/... without the prefix.
Setting BASE_PATH to that subpath makes the container serve itself there, which means the proxy has to pass the prefix through unchanged, so a request for /files/x must arrive as /files/x.
In nginx that is a proxy_pass with no path after the upstream address, in Caddy a plain reverse_proxy (handle_path strips the prefix), and in Traefik a router without a StripPrefix middleware.

## Runtime

The container runs as uid 33 and listens on port 8080.
Everything it writes at runtime, the auth file, the nginx temp paths and the php-fpm socket, lives under /tmp/h5ai, so a read-only root filesystem needs a tmpfs at /tmp.
Thumbnails and archive downloads also need /app/_h5ai/public/cache to be writable, and h5ai disables them when it is not.

On start a short set of preflight checks reports in the logs how the container is running, which settings are in effect, whether its runtime and cache directories are writable, and how each mount looks from inside.
A missing HT_PASSWORD, an invalid BASE_PATH or an unwritable /tmp stops the container before nginx and php-fpm start.

## License

GPL-2.0, see LICENSE.
