# CapTrack – build the .app bundle with nothing but the Swift toolchain.
#
#   make            build build/CapTrack.app (universal, ad-hoc signed)
#   make run        build and launch it
#   make install    copy it to /Applications
#   make zip        build/CapTrack-<version>.zip for a GitHub release
#   make test       run the unit tests
#   make preflight  check that the selected toolchain can build CapTrack
#   make preview    re-render the README screenshots
#   make og-image   render the social preview image for GitHub (Art/og-image.jpg)
#   make clean

APP        := CapTrack
VERSION    ?= 1.0.2
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

# Toolchain. CapTrack needs Xcode: the bare Command Line Tools 27.0 ship the macOS 27
# SDK, in which SwiftUI's @State is a macro, but not the plugin that expands it. When
# xcode-select points at the Command Line Tools and Xcode is installed, build with
# Xcode instead. An explicit DEVELOPER_DIR is always respected.
XCODE_DEVELOPER_DIR  ?= /Applications/Xcode.app/Contents/Developer
ACTIVE_DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null)
ifeq ($(origin DEVELOPER_DIR),undefined)
  ifneq (,$(findstring /CommandLineTools,$(ACTIVE_DEVELOPER_DIR)))
    ifneq (,$(wildcard $(XCODE_DEVELOPER_DIR)/usr/bin/xcodebuild))
      export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)
    endif
  endif
endif

.PHONY: all build app run install zip test preflight preview og-image clean

all: app

# Fail fast, with an explanation, instead of minutes into a build that cannot succeed.
# Both checks target known Command Line Tools problems; Xcode passes them untouched.
preflight:
	@dev="$${DEVELOPER_DIR:-$$(xcode-select -p)}"; \
	echo "Toolchain: $$dev"; \
	echo "           $$(swift --version 2>/dev/null | head -1)"; \
	if ls "$$dev"/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface >/dev/null 2>&1; then \
	    echo "error: stale PackageDescription interfaces from an older Command Line Tools release shadow the"; \
	    echo "       current ones, so no Package.swift compiles. Remove them:"; \
	    echo "       sudo rm $$dev/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface"; \
	    echo "       See README.md, section Troubleshooting."; \
	    exit 1; \
	fi; \
	mkdir -p $(BUILD_DIR); \
	printf 'import SwiftUI\nstruct V: View { @State private var n = 0; var body: some View { Text(verbatim: "\\(n)") } }\n' > $(BUILD_DIR)/preflight.swift; \
	if ! swiftc -typecheck $(BUILD_DIR)/preflight.swift 2>$(BUILD_DIR)/preflight.log; then \
	    echo "error: this toolchain cannot compile SwiftUI:"; \
	    grep -m1 'error:' $(BUILD_DIR)/preflight.log | sed 's/^/       /'; \
	    echo "       CapTrack needs Xcode 26 or newer; the Command Line Tools 27.0 lack the SwiftUI macro plugin."; \
	    echo "       Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
	    echo "       See README.md, section Troubleshooting."; \
	    exit 1; \
	fi

build: preflight
	swift build -c release $(ARCHS)

$(ICNS): Assets/logo.svg Scripts/generate-icon.swift
	rm -rf $(ICONSET)
	swift Scripts/generate-icon.swift Assets/logo.svg $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)

# The products directory depends on the toolchain, so ask the same `swift` that built.
app: build $(ICNS)
	rm -rf $(APP_DIR)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/$(APP)" $(CONTENTS)/MacOS/$(APP)
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

test: preflight
	swift test

preview: app
	$(CONTENTS)/MacOS/$(APP) --render-preview Assets

og-image:
	./Art/generate-og-image.swift

clean:
	rm -rf $(BUILD_DIR) .build
