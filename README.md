# docker-h5ai

Super simple Docker image for serving files with h5ai + basic auth.

## Run

```bash
docker run --rm -p 8080:8080 \
	-v .:/app/files:ro \
	-e HT_PASSWORD="your-password" \
	docker-h5ai
```

- Mount your host files into `/app/files`.
- Set `HT_PASSWORD` to the password you want for HTTP basic auth.
- Log in with username `admin` and the password from `HT_PASSWORD`. The username is fixed and cannot be changed.

## Behind a reverse proxy on a subpath

h5ai builds every link from the path its `index.php` is served at, so serving it at `/` and proxying it under `/files/` produces asset links pointing at `/_h5ai/...` that miss the prefix.
Set `BASE_PATH` to the subpath and the container serves itself there instead:

```bash
-e BASE_PATH=/files
```

Your proxy has to forward the prefix unchanged rather than strip it, so `https://host/files/x` must arrive as `/files/x`.
In nginx that means `proxy_pass http://h5ai:8080;` with no trailing path, in Caddy `reverse_proxy` rather than `handle_path`, and in Traefik no `StripPrefix` middleware.
Leave `BASE_PATH` unset to serve at the root as before.

## Notes

The container runs unprivileged as uid 33 and listens on port 8080.
Everything it writes at runtime, the auth file, the nginx temp paths and the php-fpm socket, lives under `/tmp/h5ai`, so with a read-only root filesystem you need a tmpfs at `/tmp`.

On start it runs a short set of preflight checks and reports what it found in the logs: how it is running, whether the auth password is set, whether its runtime and cache directories are writable, and how each mount looks from inside the container.
A missing `HT_PASSWORD` or an unwritable `/tmp` stops the container instead of leaving you with a server that rejects everything.
