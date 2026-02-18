# Building from source for testing

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
3. [x] clone [intranet-data-gen](https://github.com/interpretica-io/intranet-data-gen)
	+ [x] run: `./generate.sh out`
	+ [x] `./out/` -> `../intranet-data`
		+ `mv ./interpretica-io/intranet-data-gen/out/ ./interpretica-io/intranet-data` - VERY IMPORTANT TO KEEP `/` AT THE END OF SOURCE PATH!
4. [x] plugin builds -> `.so` -> `./isabelle-core/`
5. [run `mongo` db OCI container](#mongo-oci-script)
6. run `isabelle-core`: [`bash @ isabelle-core`](#isabelle-core-run-wrapper-script)

## Scripts

### Mongo OCI script

```sh
#!/usr/bin/env bash

local prefix="path/to/data/parent/"
local db="database_name"

podman run \
	--pub 27017:27017 \
	--name mongo-${db} \
	--volume ${prefix}/${db}-data:/data/db:Z \
	--volume ${logs}:/var/log/mongodb:Z \
	--detach \
	docker.io/library/mongo:7.0
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

cd ./isabelle-platform/isabelle-core && \
	make && \
	(killall isabelle-core || true) && \
	./run.sh \
		--data-path ../data-intranet \
		--database intranet \
		--plugin-dir . \
		--cookie-http-insecure \
		--first-run

# After build is done, just for testing - run like this
cd ./isabelle-platform/isabelle-core && \
	(killall isabelle-core || true) && \
	./run.sh \
		--data-path ../data-intranet \
		--database intranet \
		--plugin-dir . \
		--cookie-http-insecure
```
