# Caffeinator Makefile
# Build commands for VS Code workflow

.PHONY: build run clean release install-cli uninstall-cli open dmg installer

# Default target
all: build

# Build debug version
build:
	@echo "Building Caffeinator (Debug)..."
	xcodebuild -project Caffeinator.xcodeproj -scheme Caffeinator -configuration Debug build

# Build release version
release:
	@echo "Building Caffeinator (Release)..."
	xcodebuild -project Caffeinator.xcodeproj -scheme Caffeinator -configuration Release build

# Build CLI only
build-cli:
	@echo "Building CaffeinatorCLI..."
	xcodebuild -project Caffeinator.xcodeproj -scheme CaffeinatorCLI -configuration Release build

# Run the app
run: build
	@echo "Running Caffeinator..."
	open ~/Library/Developer/Xcode/DerivedData/Caffeinator-*/Build/Products/Debug/Caffeinator.app

# Clean build artifacts
clean:
	@echo "Cleaning..."
	xcodebuild -project Caffeinator.xcodeproj -scheme Caffeinator clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/Caffeinator-*

# Open in Xcode
open:
	open Caffeinator.xcodeproj

# Install CLI to /usr/local/bin (requires sudo)
install-cli: build-cli
	@echo "Installing CLI..."
	@CLI_PATH=$$(find ~/Library/Developer/Xcode/DerivedData/Caffeinator-*/Build/Products -name "CaffeinatorCLI" -type f 2>/dev/null | head -1); \
	if [ -n "$$CLI_PATH" ]; then \
		sudo cp "$$CLI_PATH" /usr/local/bin/caffeinator; \
		sudo chmod +x /usr/local/bin/caffeinator; \
		echo "CLI installed to /usr/local/bin/caffeinator"; \
	else \
		echo "Error: CLI binary not found. Build first."; \
		exit 1; \
	fi

# Uninstall CLI
uninstall-cli:
	@echo "Uninstalling CLI..."
	sudo rm -f /usr/local/bin/caffeinator
	@echo "CLI uninstalled"

# Create DMG installer
dmg:
	@echo "Creating DMG installer..."
	./scripts/create-dmg.sh

# Alias for dmg
installer: dmg

# Show help
help:
	@echo "Caffeinator Build Commands"
	@echo ""
	@echo "  make build       - Build debug version"
	@echo "  make release     - Build release version"
	@echo "  make build-cli   - Build CLI tool only"
	@echo "  make run         - Build and run the app"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make open        - Open project in Xcode"
	@echo "  make install-cli - Install CLI to /usr/local/bin"
	@echo "  make uninstall-cli - Remove CLI from /usr/local/bin"
	@echo "  make dmg         - Create DMG installer"
	@echo "  make installer   - Alias for 'make dmg'"
	@echo "  make help        - Show this help"
