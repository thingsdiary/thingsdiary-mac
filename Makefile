PROJECT := thingsdiary-mac.xcodeproj
SCHEME := thingsdiary-mac
CONFIGURATION ?= Debug
DERIVED_DATA ?= .build
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/thingsdiary.app
VERSION ?= 0.0.0
SERVER_BASE_URL ?= https://cloud.thingsdiary.io/api
LOCAL_BASE_URL ?= http://127.0.0.1:8081/api
SWIFT_FORMAT ?= xcrun swift-format
SWIFT_SOURCE_DIRS := thingsdiary-mac thingsdiary-macTests thingsdiary-macUITests

.PHONY: all build dmg run run-local format lint

all: build

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

dmg:
	./scripts/build-dmg.sh "$(VERSION)"

run: build
	open -n -F --env "THINGSDIARY_BASE_URL=$(SERVER_BASE_URL)" "$(APP)"

run-local: build
	open -n -F --env "THINGSDIARY_BASE_URL=$(LOCAL_BASE_URL)" "$(APP)"

format:
	$(SWIFT_FORMAT) format --in-place --recursive --parallel $(SWIFT_SOURCE_DIRS)

lint:
	$(SWIFT_FORMAT) lint --strict --recursive --parallel $(SWIFT_SOURCE_DIRS)
