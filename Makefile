PROJECT := thingsdiary-mac.xcodeproj
SCHEME := thingsdiary-mac
CONFIGURATION ?= Debug
DERIVED_DATA ?= .build
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/thingsdiary-mac.app

.PHONY: all build run

all: build

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

run: build
	open "$(APP)"
