#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${FRIDA_ASSET_DIR:-$ROOT/assets/antidetect}"
VERSION="${ANTIDETECT_VERSION:-${FRIDA_VERSION:-}}"
SOURCE_DIR="${ANTIDETECT_ASSET_DIR:-$ROOT/assets/antidetect-source}"
SOURCE_ARCHIVE="${ANTIDETECT_ASSET_ARCHIVE:-}"
ARCHIVE_SHA256_FILE="${ANTIDETECT_ARCHIVE_SHA256_FILE:-}"
PAYLOAD_SHA256SUMS_FILE="${ANTIDETECT_PAYLOAD_SHA256SUMS_FILE:-${ANTIDETECT_SHA256SUMS_FILE:-}}"
ALLOW_UNVERIFIED="${ANTIDETECT_ALLOW_UNVERIFIED:-0}"
ARCHES=(arm arm64 x86 x86_64)

if [[ -z "$VERSION" ]]; then
  echo "ANTIDETECT_VERSION or FRIDA_VERSION is required." >&2
  exit 1
fi

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available." >&2
    return 1
  fi
}

expected_sha256() {
  local file="$1"
  local sums_file="$2"
  local name
  name="$(basename "$file")"
  awk -v name="$name" '
    $2 == name || $2 == "./" name { print $1; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$sums_file"
}

verify_file() {
  local file="$1"
  local sums_file="$2"
  local expected actual
  expected="$(expected_sha256 "$file" "$sums_file")"
  actual="$(sha256_file "$file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 mismatch for $(basename "$file"): expected $expected got $actual" >&2
    exit 1
  fi
}

extract_archive() {
  local archive="$1"
  local dst="$2"
  mkdir -p "$dst"
  case "$archive" in
    *.tar.xz|*.txz) tar -xJf "$archive" -C "$dst" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dst" ;;
    *.zip) unzip -q "$archive" -d "$dst" ;;
    *)
      echo "Unsupported ANTIDETECT_ASSET_ARCHIVE format: $archive" >&2
      exit 1
      ;;
  esac
}

find_asset() {
  local base="$1"
  local candidate
  local matches=()
  for candidate in "$SOURCE_DIR/$base" "$SOURCE_DIR/$base.xz" "$SOURCE_DIR/$base.gz"; do
    [[ -f "$candidate" ]] && matches+=("$candidate")
  done
  if [[ "${#matches[@]}" -eq 0 ]]; then
    while IFS= read -r candidate; do
      matches+=("$candidate")
    done < <(find "$SOURCE_DIR" -type f \( -name "$base" -o -name "$base.xz" -o -name "$base.gz" \) | sort)
  fi
  if [[ "${#matches[@]}" -ne 1 ]]; then
    echo "Expected exactly one asset for $base under $SOURCE_DIR, found ${#matches[@]}." >&2
    return 1
  fi
  echo "${matches[0]}"
}

copy_asset() {
  local src="$1"
  local dst="$2"
  case "$src" in
    *.xz) xz -dc "$src" > "$dst" ;;
    *.gz) gzip -dc "$src" > "$dst" ;;
    *) cp "$src" "$dst" ;;
  esac
}

prepare_source() {
  if [[ -n "$SOURCE_ARCHIVE" ]]; then
    [[ -f "$SOURCE_ARCHIVE" ]] || {
      echo "ANTIDETECT_ASSET_ARCHIVE does not exist: $SOURCE_ARCHIVE" >&2
      exit 1
    }
    SOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/antidetect-assets.XXXXXX")"
    cleanup_dirs+=("$SOURCE_DIR")

    if [[ -z "$ARCHIVE_SHA256_FILE" && -f "$SOURCE_ARCHIVE.sha256" ]]; then
      ARCHIVE_SHA256_FILE="$SOURCE_ARCHIVE.sha256"
    fi
    if [[ -n "$ARCHIVE_SHA256_FILE" ]]; then
      verify_file "$SOURCE_ARCHIVE" "$ARCHIVE_SHA256_FILE"
      archive_verified=1
    fi
    extract_archive "$SOURCE_ARCHIVE" "$SOURCE_DIR"
  elif [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Antidetect assets are missing." >&2
    echo "Provide ANTIDETECT_ASSET_DIR or ANTIDETECT_ASSET_ARCHIVE from this project's own build output." >&2
    exit 1
  fi

  if [[ -z "$PAYLOAD_SHA256SUMS_FILE" && -f "$SOURCE_DIR/SHA256SUMS" ]]; then
    PAYLOAD_SHA256SUMS_FILE="$SOURCE_DIR/SHA256SUMS"
  fi
}

require_verification_or_opt_in() {
  local file="$1"
  if [[ -n "$PAYLOAD_SHA256SUMS_FILE" ]]; then
    verify_file "$file" "$PAYLOAD_SHA256SUMS_FILE"
  elif [[ "${archive_verified:-0}" != "1" && "$ALLOW_UNVERIFIED" != "1" ]]; then
    echo "No SHA-256 verification available for $(basename "$file")." >&2
    echo "Provide ANTIDETECT_PAYLOAD_SHA256SUMS_FILE, ANTIDETECT_ARCHIVE_SHA256_FILE, or set ANTIDETECT_ALLOW_UNVERIFIED=1." >&2
    exit 1
  fi
}

cleanup_dirs=()
archive_verified=0
trap 'for dir in "${cleanup_dirs[@]}"; do rm -rf "$dir"; done' EXIT

prepare_source
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/antidetect-stage.XXXXXX")"
cleanup_dirs+=("$stage_dir")

for arch in "${ARCHES[@]}"; do
  server_base="frida-server-$VERSION-android-$arch"
  gadget_base="frida-gadget-$VERSION-android-$arch.so"
  server_src="$(find_asset "$server_base")"
  gadget_src="$(find_asset "$gadget_base")"

  if [[ -z "$server_src" || ! -f "$server_src" ]]; then
    echo "Missing $server_base under $SOURCE_DIR" >&2
    exit 1
  fi
  if [[ -z "$gadget_src" || ! -f "$gadget_src" ]]; then
    echo "Missing $gadget_base under $SOURCE_DIR" >&2
    exit 1
  fi

  require_verification_or_opt_in "$server_src"
  require_verification_or_opt_in "$gadget_src"
  copy_asset "$server_src" "$stage_dir/$server_base"
  copy_asset "$gadget_src" "$stage_dir/$gadget_base"
  chmod 0755 "$stage_dir/$server_base"
  chmod 0644 "$stage_dir/$gadget_base"
done

mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -type f \( -name 'frida-server-*-android-*' -o -name 'frida-gadget-*-android-*.so' \) -delete
for asset in "$stage_dir"/*; do
  mv "$asset" "$OUT/"
  echo "$OUT/$(basename "$asset")"
done
