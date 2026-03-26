# CMS Family & Friends – Build & Run without Xcode
# Requires: Swift toolchain (comes with Xcode CLI tools: xcode-select --install)

.PHONY: build run release clean install app deploy-local

# Debug build
build:
	swift build

# Run (debug)
run: build
	.build/debug/CMSFamilyFriends

# Release build (optimized)
release:
	swift build -c release

# Run (release)
run-release: release
	.build/release/CMSFamilyFriends

# Create macOS .app bundle from release build
app: release
	@echo "Creating CMSFamilyFriends.app bundle..."
	@mkdir -p "CMSFamilyFriends.app/Contents/MacOS"
	@mkdir -p "CMSFamilyFriends.app/Contents/Resources"
	@cp .build/release/CMSFamilyFriends "CMSFamilyFriends.app/Contents/MacOS/"
	@cp CMSFamilyFriends/Resources/AppIcon.icns "CMSFamilyFriends.app/Contents/Resources/"
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<plist version="1.0"><dict>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleExecutable</key><string>CMSFamilyFriends</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleIdentifier</key><string>com.cmsfamilyfriends.app</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleIconFile</key><string>AppIcon</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleName</key><string>CMS Family &amp; Friends</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundlePackageType</key><string>APPL</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleShortVersionString</key><string>1.0.0</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleVersion</key><string>1</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>LSMinimumSystemVersion</key><string>14.0</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>NSHighResolutionCapable</key><true/>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>LSUIElement</key><false/>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>NSCalendarsUsageDescription</key><string>CMS Family and Friends needs calendar access to detect meetings with your contacts.</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>NSContactsUsageDescription</key><string>CMS Family and Friends needs access to your contacts to sync names, phone numbers and email addresses.</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>NSDesktopFolderUsageDescription</key><string>CMS Family and Friends needs access to local databases for iMessage, WhatsApp and call history.</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '</dict></plist>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@# Code signing with persistent self-signed certificate (stable CDHash for macOS TCC/FDA permissions)
	@codesign --force --deep -s "CMSFamilyFriends Dev Signing" --identifier com.cmsfamilyfriends.app "CMSFamilyFriends.app"
	@echo "✓ CMSFamilyFriends.app created and signed. Open with: open CMSFamilyFriends.app"

# Install to /Applications
install: app
	cp -R CMSFamilyFriends.app /Applications/
	@echo "✓ Installed to /Applications/CMS Family & Friends.app"

# Build, install, restart and launch local app from /Applications
deploy-local: app
	@echo "Stopping running CMSFamilyFriends instances..."
	@pkill -f "/Applications/CMSFamilyFriends.app/Contents/MacOS/CMSFamilyFriends" || true
	@pkill -f "$$(pwd)/CMSFamilyFriends.app/Contents/MacOS/CMSFamilyFriends" || true
	@echo "Installing app to /Applications..."
	@rm -rf "/Applications/CMSFamilyFriends.app"
	@cp -R "CMSFamilyFriends.app" "/Applications/"
	@echo "Launching /Applications/CMSFamilyFriends.app..."
	@open "/Applications/CMSFamilyFriends.app"
	@echo "✓ deploy-local complete"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
	rm -rf CMSFamilyFriends.app

# Show help
help:
	@echo "CMS Family & Friends – Build targets:"
	@echo "  make build       – Debug build"
	@echo "  make run         – Build & run (debug)"
	@echo "  make release     – Optimized release build"
	@echo "  make run-release – Build & run (release)"
	@echo "  make app         – Create .app bundle"
	@echo "  make install     – Install to /Applications"
	@echo "  make deploy-local – Build, install, restart & launch from /Applications"
	@echo "  make clean       – Remove build artifacts"
