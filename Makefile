APP_NAME = TildeFix
APP_DIR = build/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS

.PHONY: build install clean uninstall

build:
	@mkdir -p $(MACOS_DIR) $(CONTENTS_DIR)/Resources
	swiftc -O TildeFix.swift -o $(MACOS_DIR)/$(APP_NAME)
	cp Info.plist $(CONTENTS_DIR)/Info.plist
	cp TildeFix.icns $(CONTENTS_DIR)/Resources/AppIcon.icns
	codesign --force --sign - $(APP_DIR)
	@echo "Built: $(APP_DIR)"

install: build
	@mkdir -p ~/Applications
	cp -R $(APP_DIR) ~/Applications/$(APP_NAME).app
	@echo "Installed to ~/Applications/$(APP_NAME).app"
	@echo ""
	@echo "Grant permissions in System Settings > Privacy & Security:"
	@echo "  1. Accessibility → add TildeFix.app"
	@echo "  2. Input Monitoring → add TildeFix.app"
	@echo ""
	@echo "Then run:  open ~/Applications/$(APP_NAME).app"

clean:
	rm -rf build

uninstall:
	pkill -f "TildeFix.app" 2>/dev/null || true
	rm -rf ~/Applications/$(APP_NAME).app
	rm -f ~/Library/LaunchAgents/com.local.TildeFix.plist
	@echo "Uninstalled. Remove TildeFix from Accessibility & Input Monitoring manually."
