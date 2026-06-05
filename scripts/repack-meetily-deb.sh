#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 UPSTREAM_DEB OUTPUT_DIR" >&2
  exit 2
fi

UPSTREAM_DEB="$(realpath "$1")"
OUTPUT_DIR="$(realpath "$2")"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

EXTRACTED="$WORK_DIR/extracted"
PACKAGE_ROOT="$WORK_DIR/package"

upstream_version="$(dpkg-deb -f "$UPSTREAM_DEB" Version)"
build_revision="${BUILD_REVISION:-meetily1}"
version="$upstream_version"
if [ -n "$build_revision" ] && [[ "$version" != *"+$build_revision" ]]; then
  version="${version}+${build_revision}"
fi
arch="$(dpkg-deb -f "$UPSTREAM_DEB" Architecture)"
maintainer="$(dpkg-deb -f "$UPSTREAM_DEB" Maintainer 2>/dev/null || true)"

if [ -z "$maintainer" ]; then
  maintainer="Meetily Debian Builder <actions@github.com>"
fi

mkdir -p "$EXTRACTED" "$PACKAGE_ROOT"
dpkg-deb -x "$UPSTREAM_DEB" "$EXTRACTED"

first_existing_file() {
  local path
  for path in "$@"; do
    if [ -f "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

install_app_binary() {
  local name="$1"
  local source
  source="$(first_existing_file \
    "$EXTRACTED/usr/bin/$name" \
    "$EXTRACTED/opt/meetily/bin/$name")"
  install -m 0755 "$source" "$PACKAGE_ROOT/opt/meetily/bin/$name"
}

install -d -m 0755 \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/opt/meetily/bin" \
  "$PACKAGE_ROOT/opt/meetily/lib/meetily" \
  "$PACKAGE_ROOT/usr/local/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/48x48/apps" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/64x64/apps" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/128x128/apps" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/256x256/apps" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/512x512/apps" \
  "$PACKAGE_ROOT/usr/share/pixmaps"

install_app_binary meetily
install_app_binary llama-helper
install_app_binary ffmpeg

if [ -d "$EXTRACTED/usr/lib/meetily/templates" ]; then
  cp -a "$EXTRACTED/usr/lib/meetily/templates" "$PACKAGE_ROOT/opt/meetily/lib/meetily/"
elif [ -d "$EXTRACTED/opt/meetily/lib/meetily/templates" ]; then
  cp -a "$EXTRACTED/opt/meetily/lib/meetily/templates" "$PACKAGE_ROOT/opt/meetily/lib/meetily/"
fi

icon_source="$(find "$EXTRACTED" -path '*/share/icons/hicolor/*/apps/meetily.png' -print -quit 2>/dev/null || true)"
if [ -z "$icon_source" ]; then
  icon_source="$(first_existing_file \
    "$EXTRACTED/usr/share/pixmaps/meetily.png" \
    "$EXTRACTED/usr/local/share/pixmaps/meetily.png" 2>/dev/null || true)"
fi

if [ -n "$icon_source" ]; then
  install -m 0644 "$icon_source" "$PACKAGE_ROOT/usr/share/pixmaps/meetily.png"
  for size in 48 64 128 256 512; do
    target="$PACKAGE_ROOT/usr/share/icons/hicolor/${size}x${size}/apps/meetily.png"
    if command -v convert >/dev/null 2>&1; then
      convert "$icon_source" -resize "${size}x${size}" "$target"
    else
      install -m 0644 "$icon_source" "$target"
    fi
    chmod 0644 "$target"
  done
fi

cat > "$PACKAGE_ROOT/usr/local/bin/meetily" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/meetily"
export PATH="$APP_ROOT/bin:$PATH"
export MEETILY_LLAMA_HELPER="$APP_ROOT/bin/llama-helper"
export RESOURCE_DIR="$APP_ROOT/lib/meetily"

exec "$APP_ROOT/bin/meetily" "$@"
WRAPPER
chmod 0755 "$PACKAGE_ROOT/usr/local/bin/meetily"

cat > "$PACKAGE_ROOT/usr/local/bin/meetily-update" <<'UPDATER'
#!/usr/bin/env bash
set -euo pipefail

REPOS=(
  "Zackriya-Solutions/meetily"
  "Zackriya-Solutions/meeting-minutes"
  "lucky-verma/meetily-deb-builder"
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

install_deb() {
  local deb="$1"
  sudo apt install -y "$deb"
}

for repo in "${REPOS[@]}"; do
  json="$TMP_DIR/latest.json"
  if ! curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$json"; then
    continue
  fi

  tag="$(jq -r '.tag_name // empty' "$json")"
  url="$(jq -r '.assets[]? | select(.name | test("(?i)meetily.*amd64.*\\.deb$")) | .browser_download_url' "$json" | head -n 1)"

  if [ -n "$url" ]; then
    deb="$TMP_DIR/meetily.deb"
    echo "Downloading Meetily $tag from $repo..."
    curl -fL "$url" -o "$deb"
    install_deb "$deb"
    echo "Meetily updated to $tag."
    exit 0
  fi
done

cat >&2 <<'EOF'
No Linux Meetily .deb release asset was found.

Run the meetily-deb-builder GitHub Actions workflow and install the uploaded
artifact, or publish a release from that repository so meetily-update can fetch
it automatically.
EOF
exit 1
UPDATER
chmod 0755 "$PACKAGE_ROOT/usr/local/bin/meetily-update"

cat > "$PACKAGE_ROOT/usr/share/applications/meetily.desktop" <<'DESKTOP'
[Desktop Entry]
Categories=Utility;
Comment=A Tauri App for meeting minutes
Exec=/usr/local/bin/meetily
Keywords=Meeting;Minutes;Transcription;AI;
StartupWMClass=meetily
Icon=meetily
Name=Meetily
StartupNotify=true
Terminal=false
Type=Application
DESKTOP
chmod 0644 "$PACKAGE_ROOT/usr/share/applications/meetily.desktop"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<CONTROL
Package: meetily
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: $maintainer
Depends: libwebkit2gtk-4.1-0, libgtk-3-0t64, libayatana-appindicator3-1, libssl3t64, libasound2t64, hicolor-icon-theme, curl, jq
Description: Privacy-first AI meeting assistant
 Meetily captures, transcribes, and summarizes meetings locally.
 This package installs under /opt/meetily and avoids overwriting system ffmpeg.
CONTROL
chmod 0644 "$PACKAGE_ROOT/DEBIAN/control"

cat > "$PACKAGE_ROOT/DEBIAN/postinst" <<'POSTINST'
#!/usr/bin/env bash
set -e
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
exit 0
POSTINST
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postinst"

cat > "$PACKAGE_ROOT/DEBIAN/postrm" <<'POSTRM'
#!/usr/bin/env bash
set -e
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
exit 0
POSTRM
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postrm"

mkdir -p "$OUTPUT_DIR"
output="$OUTPUT_DIR/meetily_${version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$output"
echo "$output"
