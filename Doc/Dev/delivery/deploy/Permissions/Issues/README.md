# Permission issues

## Diagnosis

**Root cause**: `UID 525286` = Podman rootless user namespace mapping:

+ In rootless Podman, `hostusername` (UID 1000) has a subUID range typically starting at `524288`.
+ Inside the container, MongoDB runs as uid `999` (the `mongod` system user).
+ This maps to host UID `524288 + 999 - 1 = 525286` — exactly what you see.
+ The directory was created/owned by the container's mongodb user, which the host sees as unmapped `UID 525286`.

### Fix ownership

```bash
# transfer to host user `hostusername` (UID 1000) instead:
sudo chown 1000 ${your_path_to_build_area_root}/${db}-data
# then make it group-writable so container can also write:
chmod g+w ${your_path_to_build_area_root}/${db}-data
# Tell Podman's user namespace to set owner to UID 999 (mongodb inside container)
podman unshare chown 999 ${your_path_to_build_area_root}/${db}-data
```

### Recreate MongoDB container

Run [`mongo` db OCI container](../../../build/README.md#mongo-oci-script)
