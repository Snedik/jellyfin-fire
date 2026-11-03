#!/usr/bin/env bash
# Builds "Jellyfin Fire" from the original jellyfin-android source plus the patches and files of this repo.
#
#   ./fire.sh build           fetch the upstream source, apply patches + overlay, build the signed APK
#   ./fire.sh prepare         only fetch the upstream source and apply patches + overlay (into work/)
#   ./fire.sh export          write changes made in work/ back to patches/ and overlay/
#   ./fire.sh update <ref>    move to another upstream version (tag, branch or commit) and re-apply
#
# Signing credentials are read from ~/.jellyfin-fire/signing.properties (never commit them),
# or from the file given in JELLYFIN_FIRE_SIGNING.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
source "$ROOT/upstream.conf"

WORK="$ROOT/work/jellyfin-android"
PATCHES="$ROOT/patches"
OVERLAY="$ROOT/overlay"
GIT=(git -c user.name="Jellyfin Fire" -c user.email="jellyfin-fire@localhost" -c advice.detachedHead=false)

die() { echo "error: $*" >&2; exit 1; }

fetch_upstream() {
    local ref="$1"
    if [[ ! -d "$WORK/.git" ]]; then
        mkdir -p "$(dirname "$WORK")"
        git clone --quiet "$UPSTREAM_URL" "$WORK"
    fi
    git -C "$WORK" fetch --quiet --tags origin
    git -C "$WORK" rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
        || git -C "$WORK" rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null \
        || die "upstream ref '$ref' not found"
}

resolve_ref() {
    git -C "$WORK" rev-parse --verify --quiet "$1^{commit}" || git -C "$WORK" rev-parse "origin/$1^{commit}"
}

apply_patches() {
    local base
    base=$(resolve_ref "$UPSTREAM_REF")
    git -C "$WORK" am --abort >/dev/null 2>&1 || true
    # Keep ignored files (Gradle build output) to speed up rebuilds
    git -C "$WORK" checkout --quiet --force --detach "$base"
    git -C "$WORK" clean --quiet -fd
    shopt -s nullglob
    local patches=("$PATCHES"/*.patch)
    if ((${#patches[@]})); then
        if ! "${GIT[@]}" -C "$WORK" am --quiet --3way "${patches[@]}"; then
            cat >&2 <<EOF

A patch doesn't apply to $UPSTREAM_REF anymore. Resolve it in $WORK:
  fix the conflicting files, then: git -C work/jellyfin-android add <files> && git -C work/jellyfin-android am --continue
Afterwards run: ./fire.sh export
EOF
            exit 1
        fi
    fi
    copy_overlay
    echo "Prepared $WORK ($UPSTREAM_REF + ${#patches[@]} patches + overlay)"
}

copy_overlay() {
    (cd "$OVERLAY" && find . -type f -print0) | while IFS= read -r -d '' file; do
        mkdir -p "$WORK/$(dirname "$file")"
        cp "$OVERLAY/$file" "$WORK/$file"
    done
}

cmd_prepare() {
    fetch_upstream "$UPSTREAM_REF"
    apply_patches
}

cmd_build() {
    cmd_prepare
    local signing="${JELLYFIN_FIRE_SIGNING:-$HOME/.jellyfin-fire/signing.properties}"
    [[ -f "$signing" ]] || die "signing properties not found: $signing"
    local version="${UPSTREAM_REF#v}"
    local args=(-Pjellyfin.version="$version")
    while IFS='=' read -r key value; do
        [[ -n "$key" && "$key" != \#* ]] && args+=(-P"$key=$value")
    done < "$signing"

    (cd "$WORK" && ./gradlew --no-daemon "${args[@]}" assembleLibreRelease)

    mkdir -p "$ROOT/dist"
    local apk
    apk=$(ls -1 "$WORK"/app/build/outputs/apk/libre/release/*.apk | head -1)
    cp "$apk" "$ROOT/dist/JellyfinFire-$version.apk"
    echo "Built dist/JellyfinFire-$version.apk"
}

cmd_export() {
    [[ -d "$WORK/.git" ]] || die "nothing to export, run ./fire.sh prepare first"
    [[ ! -d "$WORK/.git/rebase-apply" ]] || die "a patch is still being applied, finish it with git am --continue"
    local base
    base=$(resolve_ref "$UPSTREAM_REF")

    # Changes of overlay files go back to the overlay, all other changes have to be committed
    (cd "$OVERLAY" && find . -type f -print0) | while IFS= read -r -d '' file; do
        cp "$WORK/$file" "$OVERLAY/$file"
    done
    local overlay_files
    overlay_files=$(cd "$OVERLAY" && find . -type f | sed 's|^\./||')
    local uncommitted
    uncommitted=$(git -C "$WORK" status --porcelain --untracked-files=all | cut -c4- | grep -vxF "$overlay_files" || true)
    if [[ -n "$uncommitted" ]]; then
        die "uncommitted changes in work/ (commit them to a patch first):"$'\n'"$uncommitted"
    fi

    rm -f "$PATCHES"/*.patch
    git -C "$WORK" format-patch --quiet --zero-commit --no-signature -o "$PATCHES" "$base..HEAD"
    echo "Exported $(ls -1 "$PATCHES"/*.patch | wc -l) patches and the overlay"
}

cmd_update() {
    local ref="${1:-}"
    [[ -n "$ref" ]] || die "usage: ./fire.sh update <upstream tag, branch or commit>"
    fetch_upstream "$ref"
    sed -i "s|^UPSTREAM_REF=.*|UPSTREAM_REF=$ref|" "$ROOT/upstream.conf"
    UPSTREAM_REF="$ref"
    apply_patches
    echo "Updated to $ref. Test it, then run ./fire.sh export (rewrites the patches for $ref)."
}

case "${1:-build}" in
    build) cmd_build ;;
    prepare) cmd_prepare ;;
    export) cmd_export ;;
    update) shift; cmd_update "$@" ;;
    *) die "unknown command '$1' (build, prepare, export, update)" ;;
esac
