# Building from source for testing

> [!IMPORTANT]
> ALL OPERATIONS PERFORMED ON [`intranet`](https://github.com/interpretica-io/intranet) EXAMPLE PROJECT

## Checklist

1. [x] fork `isabelle-core` to `${prefix}/isabelle-core` of your choice
	+ [x] build: `cargo build`
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
	+ [ ] copy with something like `cp ./*/isabelle-plugin-*/target/debug/*.so ${prefix}/isabelle-core/target/debug/`
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

Use [`tools/mongo-setup.sh`](../../../../tools/mongo-setup.sh):

```sh
# Foreground (see logs directly):
./tools/mongo-setup.sh \
	--prefix ./$(id -un) \
	--db intranet \
	--port 27017

# Background:
./tools/mongo-setup.sh \
	--prefix ./$(id -un) \
	--db intranet \
	--port 27017 \
	--detach \
	--logappend

# Separate logs directory:
./tools/mongo-setup.sh \
	--prefix ./$(id -un) \
	--prefix-logs ./$(id -un)/logs \
	--db intranet \
	--detach

# All options:
./tools/mongo-setup.sh --help
```

### `isabelle-core` run wrapper script

```sh
#!/usr/bin/env bash

local platform_fork_root="$(id -un)" # can be anything you specify, for me it's my username
local prefix="./${platform_fork_root}" # can be anything you specify, for me it's a relative path from current work dir

# Link data (example)
# `-r` important for correct path resolving
# without it `ln` writes a literal path that can be incorrect and should be absolute
ln -rs \
	./interpretica-io/intranet-data \
	${prefix}/data-intranet

# IMPORTANT: FIRST RUN TO IMPORT SYSTEM DATA!!!

(cd ${prefix}/isabelle-core && make) && \
(killall isabelle-core || true) && \
${prefix}/isabelle-core/run.sh \
	--data-path ./isabelle-platform/data-intranet \
	--database intranet \
	--plugin-dir . \
	--cookie-http-insecure \
	--first-run

# After build is done, just for testing - run like this

(killall isabelle-core || true) && \
${prefix}/isabelle-core/run.sh \
	--data-path ./isabelle-platform/data-intranet \
	--database intranet \
	--plugin-dir . \
	--cookie-http-insecure
```
