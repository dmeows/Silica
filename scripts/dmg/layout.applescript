-- Lays out the mounted DMG's Finder window: 640 × 400 points of content, no toolbar
-- or status bar, 128 pt icons on background.tiff. Icon positions are their centers
-- and must match the ones make-background.swift draws the arrow between.
--
--   osascript scripts/dmg/layout.applescript <volume name>

on run {volumeName}
	tell application "Finder"
		tell disk volumeName
			open
			set dmgWindow to container window
			set current view of dmgWindow to icon view
			set toolbar visible of dmgWindow to false
			set statusbar visible of dmgWindow to false
			set pathbar visible of dmgWindow to false
			-- Bounds include the title bar, which is 28 points tall.
			set bounds of dmgWindow to {200, 120, 840, 548}

			set viewOptions to icon view options of dmgWindow
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 128
			set text size of viewOptions to 13
			set shows item info of viewOptions to false
			set shows icon preview of viewOptions to false
			set background picture of viewOptions to file ".background:background.tiff"

			-- Finder on macOS 27 shows icons 45 points below the position they're set
			-- to (and reports the position it shows), so these put the icon centers at
			-- y = 185, on the background's arrow.
			set position of item "Silica.app" to {170, 140}
			set position of item "Applications" to {470, 140}
			-- Below the window, for Finders set to show hidden files. make-dmg.sh adds
			-- .VolumeIcon.icns later, and Finder puts it on this row too.
			set position of item ".background" to {265, 409}
			set extension hidden of item "Silica.app" to true

			-- Closing and reopening makes Finder write the layout to .DS_Store.
			close
			open
			update without registering applications
			delay 1
			close
		end tell
	end tell
end run
