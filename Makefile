# CapTrack – build the .app bundle with nothing but the Swift toolchain.
#
#   make            build build/CapTrack.app (universal, ad-hoc signed)
#   make run        build and launch it
#   make install    copy it to /Applications
#   make zip        build/CapTrack-<version>.zip for a GitHub release
#   make test       run the unit tests
#   make preview    re-render the README screenshots
#   make og-image   render the social preview image for GitHub (Art/og-image.jpg)
#   make clean

APP        := CapTrack
VERSION    ?= 1.0.0
BUILD      ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
BUNDLE_ID  ?= io.github.danielstgt.captrack
MIN_OS     := 14.0
ARCHS      ?= --arch arm64 --arch x86_64
# Ad-hoc signature by default. Pass SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.
SIGN_IDENTITY ?= -

BUILD_DIR  := build
APP_DIR    := $(BUILD_DIR)/$(APP).app
CONTENTS   := $(APP_DIR)/Contents
ICONSET    := $(BUILD_DIR)/AppIcon.iconset
ICNS       := $(BUILD_DIR)/AppIcon.icns
BIN_PATH    = $(shell swift build -c release $(ARCHS) --show-bin-path)

.PHONY: all build app run install zip test preview og-image clean

all: app

build:
	swift build -c release $(ARCHS)

$(ICNS): Assets/logo.svg Scripts/generate-icon.swift
	rm -rf $(ICONSET)
	swift Scripts/generate-icon.swift Assets/logo.svg $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)

app: build $(ICNS)
	rm -rf $(APP_DIR)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp "$(BIN_PATH)/$(APP)" $(CONTENTS)/MacOS/$(APP)
	cp $(ICNS) $(CONTENTS)/Resources/AppIcon.icns
	sed -e 's/__VERSION__/$(VERSION)/g' -e 's/__BUILD__/$(BUILD)/g' \
	    -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__MIN_OS__/$(MIN_OS)/g' \
	    Resources/Info.plist > $(CONTENTS)/Info.plist
	printf 'APPL????' > $(CONTENTS)/PkgInfo
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(APP_DIR)
	@echo "Built $(APP_DIR) ($(VERSION))"

run: app
	open $(APP_DIR)

install: app
	rm -rf "/Applications/$(APP).app"
	cp -R $(APP_DIR) /Applications/
	@echo "Installed /Applications/$(APP).app"

zip: app
	rm -f $(BUILD_DIR)/$(APP)-$(VERSION).zip
	ditto -c -k --keepParent $(APP_DIR) $(BUILD_DIR)/$(APP)-$(VERSION).zip
	@echo "Created $(BUILD_DIR)/$(APP)-$(VERSION).zip"

test:
	swift test

preview: app
	$(CONTENTS)/MacOS/$(APP) --render-preview Assets

og-image:
	./Art/generate-og-image.swift

clean:
	rm -rf $(BUILD_DIR) .build
