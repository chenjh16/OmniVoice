APP_NAME := OmniVoice
EXECUTABLE := OmniVoice
ENABLE_E2E ?= 0
EXECUTABLE_PRODUCT := $(if $(filter 1 true yes,$(ENABLE_E2E)),OmniVoiceE2E,OmniVoice)
BUNDLE_ID ?= dev.local.omnivoice
CONFIGURATION ?= release
SIGN_IDENTITY ?= -
INSTALL_DIR ?= /Applications
BUILD_ROOT := .build
APP_BUNDLE := $(BUILD_ROOT)/$(APP_NAME).app
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
EXECUTABLE_PATH := $(BUILD_ROOT)/$(CONFIGURATION)/$(EXECUTABLE_PRODUCT)
CONFIG_TEMPLATE := config/omnivoice.config.example.jsonc
USER_CONFIG ?= $(HOME)/.config/omnivoice/config.jsonc

.PHONY: build run dev-run install stop-installed verify cleanup-legacy config-template clean test check

build:
	swift build -c $(CONFIGURATION) --product $(EXECUTABLE_PRODUCT)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$(APP_BUNDLE)/Contents/Info.plist" >/dev/null
	test -f "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"

dev-run: build
	"$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE)"

stop-installed:
	@echo "stopping any running $(APP_NAME) from $(INSTALLED_APP)"
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@for _ in 1 2 3 4 5 6 7 8 9 10; do \
		if ! pgrep -f "$(INSTALLED_APP)/Contents/MacOS/$(EXECUTABLE)" >/dev/null 2>&1; then \
			exit 0; \
		fi; \
		sleep 0.2; \
	done; \
	if pgrep -f "$(INSTALLED_APP)/Contents/MacOS/$(EXECUTABLE)" >/dev/null 2>&1; then \
		pkill -TERM -f "$(INSTALLED_APP)/Contents/MacOS/$(EXECUTABLE)" >/dev/null 2>&1 || true; \
		sleep 0.5; \
	fi; \
	if pgrep -f "$(INSTALLED_APP)/Contents/MacOS/$(EXECUTABLE)" >/dev/null 2>&1; then \
		pkill -KILL -f "$(INSTALLED_APP)/Contents/MacOS/$(EXECUTABLE)" >/dev/null 2>&1 || true; \
	fi

install: build stop-installed
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	$(MAKE) verify APP_BUNDLE="$(INSTALLED_APP)"

run: install
	open "$(INSTALLED_APP)"

config-template:
	mkdir -p "$$(dirname "$(USER_CONFIG)")"
	@if [ -f "$(USER_CONFIG)" ] && [ "$(FORCE)" != "1" ]; then \
		echo "$(USER_CONFIG) already exists; use FORCE=1 to overwrite"; \
	else \
		cp "$(CONFIG_TEMPLATE)" "$(USER_CONFIG)"; \
		chmod 600 "$(USER_CONFIG)"; \
		echo "created $(USER_CONFIG)"; \
	fi

cleanup-legacy:
	rm -rf "/Applications/Omni Voice.app" ".build/Omni Voice.app"
	-defaults delete dev.local.omni-voice >/dev/null 2>&1
	-security delete-generic-password -s omni-voice -a base_url >/dev/null 2>&1
	-security delete-generic-password -s omni-voice -a api_key >/dev/null 2>&1
	-security delete-generic-password -s omni-voice -a default_model >/dev/null 2>&1
	rm -rf "$$HOME/Library/Logs/Omni Voice" "$$HOME/.config/omni-voice"
	-tccutil reset Microphone dev.local.omni-voice >/dev/null 2>&1
	-tccutil reset Accessibility dev.local.omni-voice >/dev/null 2>&1
	-tccutil reset ListenEvent dev.local.omni-voice >/dev/null 2>&1

verify:
	test -d "$(APP_BUNDLE)"
	test -f "$(APP_BUNDLE)/Contents/MacOS/$(EXECUTABLE)"
	test -f "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$(APP_BUNDLE)/Contents/Info.plist" >/dev/null
	/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$(APP_BUNDLE)/Contents/Info.plist" >/dev/null
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

test:
	swift test

check:
	git diff --check
	swift test
	$(MAKE) build
	$(MAKE) verify APP_BUNDLE="$(APP_BUNDLE)"

clean:
	rm -rf .build
