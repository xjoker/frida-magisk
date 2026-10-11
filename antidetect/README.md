# Antidetect asset hashes

`hashes.sha256` is the trust anchor for owned antidetect asset archives
(`frida-antidetect-assets-<version>.tar.xz` by default). The archive is
downloaded from a release, but its expected SHA-256 must come from this
committed file, so a tampered release asset (or its `.sha256` side file)
cannot vouch for itself.

To add or update an archive:

```bash
sha256sum frida-antidetect-assets-17.23.3.tar.xz >> antidetect/hashes.sha256
git add antidetect/hashes.sha256 && git commit -m "antidetect: pin assets 17.23.3"
```

Compute the hash from the file you built yourself, not from a downloaded copy.
Lines starting with `#` are ignored. If an entry is missing or does not match,
the build fails. `allow_unverified=true` (workflow_dispatch only) is an explicit
opt-in to skip this check and is noted in the release notes.

`scripts/prepare-antidetect-assets.sh` reads this file by default; override with
`ANTIDETECT_ARCHIVE_SHA256_FILE` for local experiments.
