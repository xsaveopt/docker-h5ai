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

The container runs unprivileged as uid 33 and listens on port 8080.
Everything it writes at runtime, the auth file, the nginx temp paths and the php-fpm socket, lives under `/tmp/h5ai`, so with a read-only root filesystem you need a tmpfs at `/tmp`.

On start it runs a short set of preflight checks and reports what it found in the logs: how it is running, whether the auth password is set, whether its runtime and cache directories are writable, and how each mount looks from inside the container.
A missing `HT_PASSWORD` or an unwritable `/tmp` stops the container instead of leaving you with a server that rejects everything.
