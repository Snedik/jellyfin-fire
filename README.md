# Jellyfin Fire

Jellyfin Android app for Fire TV, with SyncPlay support for the integrated player.

This repository doesn't contain the app's source code. It contains only the changes, which the build applies to the original source of [jellyfin-android](https://github.com/jellyfin/jellyfin-android):

| Path | Contents |
|---|---|
| `upstream.conf` | Upstream repository and version (tag, branch or commit) the changes are based on |
| `patches/` | Changes to upstream files, one patch per topic, applied in order |
| `overlay/` | New files, copied into the source tree as-is |
| `fire.sh` | Build script |

## Patches

1. **Separate package and launcher integration**: package `org.jellyfin.mobile.fire` (installs next to the official app), Leanback launcher, banner
2. **TV layout, scaling and focus handling**: TV layout of the web client, viewport/scaling, focus recovery, no battery-optimization prompt on TV
3. **Remote control in the integrated player**: OK/left/right/up/down, focus highlight, no stacked players
4. **SyncPlay for the integrated player**: the native player behaves like the web player towards SyncPlay; commands from other devices (play, pause, seek, next episode), join/leave/waiting hints; queue handover when a group is created during playback
5. **WebView debugging setting** (Settings → Developer)
6. **Fix integrated player crash** on Android 9 / Fire TV ([PR #2224](https://github.com/jellyfin/jellyfin-android/pull/2224))

## Building

Requirements: JDK 21, Android SDK (`ANDROID_HOME` or `local.properties`), signing key.

The signing data is read from `~/.jellyfin-fire/signing.properties` (or the file in `JELLYFIN_FIRE_SIGNING`) and must never be committed:

```properties
keystore.file=/home/me/.jellyfin-fire/release.jks
keystore.password=...
signing.key.alias=...
signing.key.password=...
```

```bash
./fire.sh build      # → dist/JellyfinFire-<version>.apk
```

The original source is cloned into `work/jellyfin-android` (cached and reused on rebuilds), reset to the version from `upstream.conf`, and then patches and overlay are applied.

## Making changes

```bash
./fire.sh prepare                      # work/jellyfin-android = upstream + patches + overlay
cd work/jellyfin-android
# edit files …
git commit --amend -a                  # change the latest patch, or:
git rebase -i <upstream ref>           # edit the matching patch ("edit"), or create a new commit = new patch
cd ../..
./fire.sh export                       # rewrite patches/ and overlay/ from work/
```

- Edits to **overlay files** don't need a commit: `export` copies them back to `overlay/`.
- All **other changes** must be committed in `work/jellyfin-android`; each commit becomes one patch.

## Moving to a new upstream version

```bash
./fire.sh update v2.8.0
```

If all patches apply, you're done: test, run `./fire.sh export`, commit. If a patch no longer fits, the script stops at that patch:

```bash
cd work/jellyfin-android
# resolve the conflicts in the affected files
git add <files> && git am --continue
cd ../.. && ./fire.sh export
```

## CI

`.github/workflows/build.yml` builds the APK on every push to `main`, for pull requests and manually (Actions → Build → Run workflow), and attaches it to the run as the **JellyfinFire** artifact. A tag `v*` (e.g. `v2.7.3-fire1`) additionally creates a GitHub release with the APK.

The signing key only exists as encrypted repository secrets (Settings → Secrets and variables → Actions):

| Secret | Contents |
|---|---|
| `KEYSTORE_BASE64` | Keystore, base64-encoded (`base64 -w0 release.jks`) |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |
