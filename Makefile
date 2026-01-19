# Caffeinator Makefile
# Build commands for Tauri app

.PHONY: dev build dmg clean install help

# Default target
all: build

# Run development server
dev:
	@echo "Starting Caffeinator dev server..."
	bun run tauri dev

# Build release version (.app bundle only)
build:
	@echo "Building Caffeinator (Release)..."
	bun run tauri build --bundles app

# Build DMG (creates .app first, then DMG manually)
dmg: build
	@echo "Creating DMG..."
	cd src-tauri/target/release/bundle && \
	rm -f Caffeinator_*.dmg && \
	hdiutil create -volname "Caffeinator" -srcfolder macos/Caffeinator.app -ov -format UDZO Caffeinator_0.1.0_aarch64.dmg
	@echo "DMG created at src-tauri/target/release/bundle/Caffeinator_0.1.0_aarch64.dmg"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf dist target src-tauri/target

# Install to /Applications (requires the app to be built first)
install: build
	@echo "Installing to /Applications..."
	@if [ -d "src-tauri/target/release/bundle/macos/Caffeinator.app" ]; then \
		cp -r src-tauri/target/release/bundle/macos/Caffeinator.app /Applications/; \
		echo "Installed to /Applications/Caffeinator.app"; \
	else \
		echo "Error: App bundle not found. Build first with 'make build'"; \
		exit 1; \
	fi

# Show help
help:
	@echo "Caffeinator Build Commands"
	@echo ""
	@echo "  make dev      - Run development server with hot reload"
	@echo "  make build    - Build release .app bundle"
	@echo "  make dmg      - Build release and create DMG"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make install  - Build and install to /Applications"
	@echo "  make help     - Show this help"
