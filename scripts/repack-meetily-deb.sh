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

version="$(dpkg-deb -f "$UPSTREAM_DEB" Version)"
arch="$(dpkg-deb -f "$UPSTREAM_DEB" Architecture)"
maintainer="$(dpkg-deb -f "$UPSTREAM_DEB" Maintainer 2>/dev/null || true)"

if [ -z "$maintainer" ]; then
  maintainer="Meetily Debian Builder <actions@github.com>"
fi

mkdir -p "$EXTRACTED" "$PACKAGE_ROOT"
dpkg-deb -x "$UPSTREAM_DEB" "$EXTRACTED"

install -d -m 0755 \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/opt/meetily/bin" \
  "$PACKAGE_ROOT/opt/meetily/lib/meetily" \
  "$PACKAGE_ROOT/usr/local/bin" \
  "$PACKAGE_ROOT/usr/local/share/applications" \
  "$PACKAGE_ROOT/usr/local/share/icons/hicolor/1024x1024/apps"

install -m 0755 "$EXTRACTED/usr/bin/meetily" "$PACKAGE_ROOT/opt/meetily/bin/meetily"
install -m 0755 "$EXTRACTED/usr/bin/llama-helper" "$PACKAGE_ROOT/opt/meetily/bin/llama-helper"
install -m 0755 "$EXTRACTED/usr/bin/ffmpeg" "$PACKAGE_ROOT/opt/meetily/bin/ffmpeg"

if [ -d "$EXTRACTED/usr/lib/meetily/templates" ]; then
  cp -a "$EXTRACTED/usr/lib/meetily/templates" "$PACKAGE_ROOT/opt/meetily/lib/meetily/"
fi

if [ -f "$EXTRACTED/usr/share/icons/hicolor/1024x1024/apps/meetily.png" ]; then
  install -m 0644 \
    "$EXTRACTED/usr/share/icons/hicolor/1024x1024/apps/meetily.png" \
    "$PACKAGE_ROOT/usr/local/share/icons/hicolor/1024x1024/apps/meetily.png"
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

cat > "$PACKAGE_ROOT/usr/local/share/applications/meetily.desktop" <<'DESKTOP'
[Desktop Entry]
Categories=Utility;
Comment=A Tauri App for meeting minutes
Exec=/usr/local/bin/meetily
StartupWMClass=meetily
Icon=meetily
Name=Meetily
Terminal=false
Type=Application
DESKTOP

cat > "$PACKAGE_ROOT/DEBIAN/control" <<CONTROL
Package: meetily
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: $maintainer
Depends: libwebkit2gtk-4.1-0, libgtk-3-0t64, libayatana-appindicator3-1, libssl3t64, libasound2t64, curl, jq
Description: Privacy-first AI meeting assistant
 Meetily captures, transcribes, and summarizes meetings locally.
 This package installs under /opt/meetily and avoids overwriting system ffmpeg.
CONTROL

cat > "$PACKAGE_ROOT/DEBIAN/postinst" <<'POSTINST'
#!/usr/bin/env bash
set -e
update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
exit 0
POSTINST
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postinst"

mkdir -p "$OUTPUT_DIR"
output="$OUTPUT_DIR/meetily_${version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$output"
echo "$output"
