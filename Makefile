PROJECT := thingsdiary-mac.xcodeproj
SCHEME := thingsdiary-mac
CONFIGURATION ?= Debug
DERIVED_DATA ?= .build
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/thingsdiary.app
SWIFT_FORMAT ?= xcrun swift-format
SWIFT_SOURCE_DIRS := thingsdiary-mac thingsdiary-macTests thingsdiary-macUITests

.PHONY: all build run format lint

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

format:
	$(SWIFT_FORMAT) format --in-place --recursive --parallel $(SWIFT_SOURCE_DIRS)

lint:
	$(SWIFT_FORMAT) lint --strict --recursive --parallel $(SWIFT_SOURCE_DIRS)
