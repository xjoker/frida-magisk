# Antidetect Patchset

This directory is reserved for this repository's own anti-detection patchset.

The antidetect release track must be built from changes owned in this repository
or from private build artifacts produced by this repository's own pipeline.

Do not vendor third-party patch files, scripts, or release binaries directly.
External projects may only be used to identify detection vectors, design ideas,
and verification methods. Every file that enters this repository must be
re-authored for this project and reviewed against the checks below.

## Intake Rules

1. Extract the detection vector or behavior being addressed.
2. Reimplement the fix in this repository's structure and naming style.
3. Keep public workflow, script, and release metadata free of upstream project
   names.
4. Run syntax and surface checks before committing the file.
5. Document what the change is meant to hide or verify, not where the idea came
   from.

## Patch Goals

- Keep the public repository as a parameterized build framework only. Real
  antidetect profile values belong in a private fork, CI secret, or local
  profile file.
- Rename static runtime surfaces: process labels, thread labels, exported helper
  names, IPC labels, and generated agent names.
- Reduce filesystem fingerprints: runtime directory names, staged Gadget
  basenames, module package metadata, and predictable temporary paths.
- Reduce in-process string fingerprints in server and Gadget binaries.
- Keep official and antidetect outputs separate at package and release level.
- Add verification for observable surfaces before treating a build as useful.

## Non-Goals

- Do not claim complete undetectability.
- Do not add generic Java-layer bypass logic as a default module behavior.
- Do not hook high-risk target functions in the module itself.
- Do not bypass app-specific integrity checks without target-specific evidence.

## Required Verification

Every antidetect build should be checked against at least:

- Owned asset archives should use a separate archive checksum; unpacked payloads
  may additionally provide a `SHA256SUMS` manifest for the server/Gadget files.
- `strings` output for common Frida/Gadget/runtime markers.
- process command line and thread names.
- `/proc/<pid>/maps` and file descriptor exposure.
- server and Gadget attach smoke tests.
- target-specific business-path checks when a target app is being evaluated.

## Profile Contract

Antidetect builds default to the `tamaya` profile so forks can run the full
automation without first defining a private profile. Users who need private
surfaces can override any value through `ANTIDETECT_PROFILE_FILE`, the
`ANTIDETECT_PROFILE` CI secret, `workflow_dispatch` profile overrides, or
explicit environment variables. Public placeholder values are rejected by the
build and verification scripts.

`ANTIDETECT_PROFILE_NAME` is optional and defaults to `tamaya`. When no
overrides are provided, the build derives module identity, filenames, runtime
paths, listen ports, and native Zygisk surfaces from that profile.

Default-derived keys:

- `ANTIDETECT_MODULE_ID`
- `ANTIDETECT_MODULE_NAME`
- `ANTIDETECT_MODULE_DESCRIPTION`
- `ANTIDETECT_SERVER_BASENAME`
- `ANTIDETECT_RUNTIME_DIR`
- `ANTIDETECT_FRIDA_LISTEN`
- `ANTIDETECT_GADGET_BASENAME`
- `ANTIDETECT_GADGET_CONFIG_BASENAME`
- `ANTIDETECT_GADGET_LISTEN`

Optional keys:

- `ANTIDETECT_PROFILE_NAME`
- `ANTIDETECT_PID_BASENAME`
- `ANTIDETECT_FRIDA_MODE`
- `ANTIDETECT_GADGET_ON_LOAD`
- `ANTIDETECT_GADGET_RUNTIME`
- `ANTIDETECT_GADGET_INCLUDE_CHILDREN`
- `ANTIDETECT_ZYGISK_LOG_TAG`
- `ANTIDETECT_ZYGISK_MODULE_CLASS`
- `ANTIDETECT_ZYGISK_MODULE_FALLBACK`
- `ANTIDETECT_ZYGISK_RUNTIME_FALLBACK`
- `ANTIDETECT_ZYGISK_GADGET_FALLBACK`
- `ANTIDETECT_ZYGISK_OUTPUT_NAME`
