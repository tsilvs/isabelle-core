# Building from source for testing

> [!IMPORTANT]
> ALL OPERATIONS PERFORMED ON [`intranet`](https://github.com/interpretica-io/intranet) EXAMPLE PROJECT

## Checklist

1. [x] fork `isabelle-core` -> `cargo build`
2. clone:
	+ [x] [`intranet`](https://github.com/interpretica-io/intranet)
		+ [x] build: `trunk build`
		+ [x] serve: `trunk serve`
	+ [x] [`isabelle-plugin-intranet`](https://github.com/interpretica-io/isabelle-plugin-intranet)
		+ [x] build: `cargo build`
	+ [x] [`isabelle-plugin-web`](https://github.com/interpretica-io/isabelle-plugin-web)
		+ [x] build: `cargo build`
	+ [x] [`isabelle-plugin-security`](https://github.com/isabelle-platform/isabelle-plugin-security)
		+ [x] build: `cargo build`
3. [x] plugin builds -> `.so` -> `./isabelle-core/`
4. [ ] clone [intranet-data-gen](https://github.com/interpretica-io/intranet-data-gen)
	+ [ ] run `./interpretica-io/intranet-data-gen/generate.sh ./interpretica-io/intranet-data/`
5. [run `mongo` db OCI container](#mongo-oci-script)
6. run `isabelle-core`: [`bash @ isabelle-core`](#isabelle-core-run-wrapper-script)

## Scripts

### Mongo OCI script

> [!CAUTION]
> BEFORE ANYTHING ELSE: VERIFY YOU DON'T HAVE [THESE PERMISSION ISSUES](../deploy/Permissions/Issues/README.md)!
>
> **ESPECIALLY IF YOU'RE RUNNING RHEL / FEDORA FAMILY OF DISTROS!!!**
>
> Read, verify, adjust & run [`check-fs` tool script](../../../../tools/check-fs.sh)

```sh
#!/usr/bin/env bash

# example parameters

local prefix="path/to/data/parent/"
local logs="path/to/logs/root/"
local db="intranet"

# Prepare data directory
mkdir -p ${prefix}/${db}-data
sudo chown 1000 ${prefix}/${db}-data
# make it group-writable so container can also write:
chmod g+w ${prefix}/${db}-data
podman unshare chown 999 ${prefix}/${db}-data

# Prepare logs directory
mkdir -p ${logs}/${db}-logs
sudo chown 1000 ${logs}/${db}-logs
# make it group-writable so container can also write:
chmod g+w ${logs}/${db}-logs
podman unshare chown 999 ${logs}/${db}-logs

# Vacate the container name
podman stop mongo-${db} && podman rm mongo-${db}

# Run the container
podman run \
	--pub 27017:27017 \
	--name mongo-${db} \
	--volume ${prefix}/${db}-data:/data/db:Z \
	--volume ${logs}/${db}-logs:/var/log/mongodb:Z \
	--detach \
	docker.io/library/mongo:7.0

# --detach is only when you don't need logs in terminal
```

### `isabelle-core` run wrapper script

```sh
#!/usr/bin/env bash

# Link data (example)
# `-r` important for correct path resolving
# without it `ln` writes a literal path that can be incorrect and should be absolute
ln -rs \
	./interpretica-io/intranet-data \
	./isabelle-platform/data-intranet

# IMPORTANT: FIRST RUN TO IMPORT SYSTEM DATA!!!

(cd ./isabelle-platform/isabelle-core && make) && \
(killall isabelle-core || true) && \
./isabelle-platform/isabelle-core/run.sh \
	--data-path ./isabelle-platform/data-intranet \
	--database intranet \
	--plugin-dir . \
	--cookie-http-insecure \
	--first-run

# After build is done, just for testing - run like this

(killall isabelle-core || true) && \
./isabelle-platform/isabelle-core/run.sh \
	--data-path ./isabelle-platform/data-intranet \
	--database intranet \
	--plugin-dir . \
	--cookie-http-insecure
```
