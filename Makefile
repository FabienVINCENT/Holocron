APP := Holocron
SCHEME := Holocron
CONFIG ?= Release
BUILD_DIR := build
DIST_DIR := dist

.PHONY: all generate build test run dmg clean

all: build

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) CODE_SIGN_IDENTITY=- build

test: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) CODE_SIGN_IDENTITY=- test

run: build
	open $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP).app

dmg: build
	./scripts/make-dmg.sh $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP).app $(DIST_DIR)

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) $(APP).xcodeproj
