# CMS Family & Friends – Build & Run without Xcode
# Requires: Swift toolchain (comes with Xcode CLI tools: xcode-select --install)

.PHONY: build run release clean install app

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
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<plist version="1.0"><dict>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleExecutable</key><string>CMSFamilyFriends</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleIdentifier</key><string>com.cmsfamilyfriends.app</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleName</key><string>CMS Family &amp; Friends</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundlePackageType</key><string>APPL</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleShortVersionString</key><string>1.0.0</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>CFBundleVersion</key><string>1</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>LSMinimumSystemVersion</key><string>14.0</string>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '<key>NSHighResolutionCapable</key><true/>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo '</dict></plist>' >> "CMSFamilyFriends.app/Contents/Info.plist"
	@echo "✓ CMSFamilyFriends.app created. Open with: open CMSFamilyFriends.app"

# Install to /Applications
install: app
	cp -R CMSFamilyFriends.app /Applications/
	@echo "✓ Installed to /Applications/CMS Family & Friends.app"

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
	@echo "  make clean       – Remove build artifacts"
