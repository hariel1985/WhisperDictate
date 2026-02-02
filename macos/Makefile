# WhisperDictate macOS Build

APP_NAME = WhisperDictate
APP_BUNDLE = $(APP_NAME).app
VERSION = 1.0.0

# Directories
SRC_DIR = src
BUILD_DIR = build
BUNDLE_DIR = $(APP_BUNDLE)/Contents

# Compiler settings
SWIFT = swiftc
SWIFT_FLAGS = -O -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreGraphics -framework ServiceManagement

.PHONY: all clean build install run dmg

all: build

build: $(BUILD_DIR)/$(APP_NAME)
	@echo "✓ Build complete"

$(BUILD_DIR)/$(APP_NAME): $(SRC_DIR)/main.swift
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUNDLE_DIR)/MacOS
	@mkdir -p $(BUNDLE_DIR)/Resources
	$(SWIFT) $(SWIFT_FLAGS) -o $(BUNDLE_DIR)/MacOS/$(APP_NAME) $(SRC_DIR)/main.swift
	@cp $(APP_BUNDLE)/Contents/Info.plist $(BUNDLE_DIR)/ 2>/dev/null || true
	@touch $(BUILD_DIR)/$(APP_NAME)
	@echo "✓ Built $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(BUNDLE_DIR)/MacOS/$(APP_NAME)
	@echo "✓ Cleaned"

install: build
	@rm -rf /Applications/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) /Applications/
	@codesign --force --deep --sign - /Applications/$(APP_BUNDLE)
	@echo "✓ Installed to /Applications/$(APP_BUNDLE)"

run: build
	@./$(BUNDLE_DIR)/MacOS/$(APP_NAME) &
	@echo "✓ Running $(APP_NAME)"

dmg: build
	@rm -f $(APP_NAME)-$(VERSION).dmg
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@hdiutil create -volname "$(APP_NAME)" -srcfolder $(APP_BUNDLE) -ov -format UDZO $(APP_NAME)-$(VERSION).dmg
	@echo "✓ Created $(APP_NAME)-$(VERSION).dmg"
