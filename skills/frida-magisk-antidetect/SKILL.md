---
name: frida-magisk-antidetect
description: Use this when working on this repository's official/antidetect module flavors, server/Gadget runtime profiles, or optional Frida JS probes for authorized target testing.
---

# Frida Magisk Antidetect Workflow

Use this skill only inside this repository.

## Hard Rules

- Do not copy external patch files, scripts, binaries, workflow fragments, or release metadata.
- Do not write specific third-party stealth project names into repository files, CI, release notes, or artifact names.
- Keep official and antidetect release tracks separate.
- Keep runtime bypass logic optional and target-scoped. Do not enable global Java/native hooks by default.
- Prefer root-cause, verifiable changes over broad string replacement.

## Build Tracks

- Official package:
  - `FRIDA_PACKAGE_FLAVOR=official`
  - keeps default server/Gadget names and ports.
- Antidetect package:
  - `FRIDA_PACKAGE_FLAVOR=antidetect`
  - defaults to the `tamaya` profile when no private profile is supplied.
  - uses `package.env` as the surface profile for server basename, Gadget basename, runtime dir, ports, and Gadget load policy.
  - must include server, Gadget, and Zygisk injector entries for each packaged ABI.

## Private Profile

Antidetect builds run with the default `tamaya` profile when no private profile
is supplied. Use `ANTIDETECT_PROFILE_FILE` locally or the `ANTIDETECT_PROFILE`
CI secret in forks when private surfaces are needed. The file format is plain
`KEY=VALUE` lines. Environment variables override file values. GitHub
`workflow_dispatch` supports a `profile_overrides` input for manual `KEY=VALUE`
overrides, but those inputs are not as private as secrets.

`ANTIDETECT_PROFILE_NAME` is optional and defaults to `tamaya`. The default
profile derives paths, ports, module IDs, file names, and native names from this
value unless a specific `ANTIDETECT_*` override is set.

Default-derived profile keys:

- `ANTIDETECT_MODULE_ID`
- `ANTIDETECT_MODULE_NAME`
- `ANTIDETECT_MODULE_DESCRIPTION`
- `ANTIDETECT_SERVER_BASENAME`
- `ANTIDETECT_RUNTIME_DIR`
- `ANTIDETECT_FRIDA_LISTEN`
- `ANTIDETECT_GADGET_BASENAME`
- `ANTIDETECT_GADGET_CONFIG_BASENAME`
- `ANTIDETECT_GADGET_LISTEN`

Optional native keys:

- `ANTIDETECT_ZYGISK_LOG_TAG`
- `ANTIDETECT_ZYGISK_MODULE_CLASS`
- `ANTIDETECT_ZYGISK_MODULE_FALLBACK`
- `ANTIDETECT_ZYGISK_RUNTIME_FALLBACK`
- `ANTIDETECT_ZYGISK_GADGET_FALLBACK`
- `ANTIDETECT_ZYGISK_OUTPUT_NAME`

## Recommended Flow

1. Build or fetch this repository's own server/Gadget assets.
2. Run `scripts/prepare-antidetect-assets.sh` for antidetect assets.
3. Set `FRIDA_PACKAGE_FLAVOR=antidetect`; optionally provide `ANTIDETECT_PROFILE_FILE`.
4. Build the Zygisk injector with `scripts/build-zygisk-injector.sh`.
5. Build packages with `scripts/build-module.sh`.
6. Verify antidetect ZIPs with `scripts/verify-antidetect-package.sh`.
7. For runtime testing, start with observe-only JS probes before adding any target-specific hook.

## Optional Runtime JS

Use `scripts/frida/antidetect-baseline.js` as the starting point.

Default behavior:

- requires explicit opt-in configuration through `rpc.exports.configure`.
- requires a non-empty target package name unless `allowGlobal: true` is explicitly set for a short experiment.
- installs no Interceptor hooks at load time.
- observes `android_dlopen_ext` only after opt-in.
- observes `/proc` reads only when `observeProc: true` is explicitly set.
- does not rewrite `/proc` output or hide mappings by default.

Only add target-specific bypass logic after observe mode shows which probe is actually being used. Keep any such logic outside default module behavior.

## Low-Touch Rules

- Avoid broad Java hooks as a default.
- Avoid hooking hot target functions first.
- Avoid hooking normal `dlopen` first; prefer narrower loader points when a load event is required.
- Prefer static offsets, passive memory reads, and target-scoped probes before adding Interceptor hooks.
- Treat every extra hook as a detectable behavior change and validate app survival plus the business path.

## Checks Before Finishing

- `bash -n module/action.sh module/customize.sh scripts/*.sh`
- YAML parse for workflows.
- `scripts/verify-antidetect-package.sh dist/frida-magisk-antidetect-*.zip`
- scan repository changes for forbidden external project names.
- explain remaining detection surfaces honestly; never claim complete undetectability.
