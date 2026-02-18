# Permission issues

## Diagnosis

**Root cause**: `UID 525286` = Podman rootless user namespace mapping:

+ In rootless Podman, `hostusername` (UID 1000) has a subUID range typically starting at `524288`.
+ Inside the container, MongoDB runs as uid `999` (the `mongod` system user).
+ This maps to host UID `524288 + 999 - 1 = 525286` — exactly what you see.
+ The directory was created/owned by the container's mongodb user, which the host sees as unmapped `UID 525286`.

**SELinux is not the problem** — label `container_file_t` is already correct, no `:Z` needed.

### Fix: Give the container's `mongodb` user ownership

```bash
# Tell Podman's user namespace to set owner to UID 999 (mongodb inside container)
podman unshare chown 999 /var/mnt/data/myrepo/interpretica-io/intranet-data
```

Or transfer to host user `hostusername` (UID 1000) instead:

```bash
sudo chown 1000 /var/mnt/data/myrepo/interpretica-io/intranet-data
# then make it group-writable so container can also write:
chmod g+w /var/mnt/data/myrepo/interpretica-io/intranet-data
```

### Recreate MongoDB container (no `:Z` needed — label already correct)

```bash
podman stop mongo-intranet && podman rm mongo-intranet
podman run -d --name mongo-intranet \
  -p 27017:27017 \
  -v /var/mnt/data/myrepo/interpretica-io/intranet-data:/data/db \
  docker.io/library/mongo:7.0 --logappend

# Verify MongoDB can write:
podman exec -it mongo-intranet mongosh --eval "db.test.insertOne({ok:1})"

# Import:
./run.sh --data-path ../data-intranet --database intranet --first-run
```
