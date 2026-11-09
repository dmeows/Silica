#!/usr/bin/env bash
#
# Packs Silica.app into a compressed DMG that opens to a styled window: the app and
# an Applications shortcut side by side on background.tiff, with the app icon as the
# volume icon.
#
#   scripts/dmg/make-dmg.sh path/to/Silica.app path/to/Silica-1.2.0.dmg
#
# Finder lays the window out (via layout.applescript), so this needs a logged-in
# session, and the first run asks to let your terminal control Finder. The DMG is
# not signed or notarized here; scripts/release.sh does that.
#
# To change the background, edit make-background.swift and rebuild the TIFF:
#
#   swift scripts/dmg/make-background.swift scripts/dmg
#   tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png \
#       -out scripts/dmg/background.tiff
#   rm scripts/dmg/background.png scripts/dmg/background@2x.png

set -euo pipefail

APP=${1:?usage: make-dmg.sh <Silica.app> <output.dmg>}
OUT=${2:?usage: make-dmg.sh <Silica.app> <output.dmg>}
DIR=$(cd "$(dirname "$0")" && pwd)
VOLUME=Silica

die() { echo "error: $*" >&2; exit 1; }

[[ -d $APP ]] || die "no app at $APP"
# Finder finds the volume by name, so another one called Silica would get the layout.
[[ ! -e /Volumes/$VOLUME ]] || die "eject the volume named $VOLUME first"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/silica-dmg.XXXXXX")
DEVICE=
cleanup() {
    [[ -n $DEVICE ]] && hdiutil detach -quiet -force "$DEVICE" 2>/dev/null
    rm -rf "$STAGE"
}
trap cleanup EXIT

# Contents: the app, a link to /Applications, and the background, hidden from
# Finder (unless it's set to show all files).
mkdir -p "$STAGE/content/.background"
ditto "$APP" "$STAGE/content/Silica.app"
ln -s /Applications "$STAGE/content/Applications"
cp "$DIR/background.tiff" "$STAGE/content/.background/background.tiff"
chflags hidden "$STAGE/content/.background"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE/content" \
    -fs HFS+ -format UDRW -ov "$STAGE/rw.dmg"

ATTACHED=$(hdiutil attach -readwrite -noverify -noautoopen "$STAGE/rw.dmg")
DEVICE=$(awk '/Apple_HFS/ { print $1 }' <<<"$ATTACHED")
MOUNT=/Volumes/$VOLUME
[[ -n $DEVICE && -d $MOUNT ]] || die "couldn't mount the image at $MOUNT"

osascript "$DIR/layout.applescript" "$VOLUME" >/dev/null

# The volume icon goes in after Finder is done with the volume: the app icon as
# .VolumeIcon.icns, and the custom-icon flag in the volume's Finder info.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
chflags hidden "$MOUNT/.VolumeIcon.icns"
xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"

# Finder writes the layout to .DS_Store on its own schedule.
for _ in {1..40}; do
    [[ -f $MOUNT/.DS_Store ]] && break
    sleep 0.25
done
[[ -f $MOUNT/.DS_Store ]] || die "Finder didn't save the window layout"
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
sync

hdiutil detach -quiet "$DEVICE" || hdiutil detach -quiet -force "$DEVICE"
DEVICE=
hdiutil convert -quiet "$STAGE/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"
