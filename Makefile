XCODEBUILD := xcodebuild -project Scythe.xcodeproj -scheme Scythe -destination 'platform=macOS'

.PHONY: generate build run test logs package

generate:
	xcodegen generate

build: generate
	$(XCODEBUILD) build

# `open` on a running app only activates the old instance, so quit it first or
# a rebuild launches yesterday's binary.
run: build
	@pkill -x Scythe && sleep 1 || true
	open "$$($(XCODEBUILD) -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ { print $$3; exit }')/Scythe.app"

test: generate
	swift test --package-path Packages/ScytheCore
	$(XCODEBUILD) test

logs:
	/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.mxttbennett.scythe"'

# What a release ships, built the way CI builds it — ad-hoc signed regardless of
# any Config/Local.xcconfig on this machine.
package:
	Scripts/package-release.sh
