all: build

CODESIGN_IDENTITY ?= -
SWIFT_SOURCES = src/ShoveIt.swift src/NotificationPosition.swift src/NotificationGeometry.swift src/DisplayPositionStore.swift

build:
	@mkdir -p ShoveIt.app/Contents/MacOS
	@mkdir -p ShoveIt.app/Contents/Resources
	@cp src/Info.plist ShoveIt.app/Contents/
	@cp src/assets/app-icon/icon.icns ShoveIt.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png ShoveIt.app/Contents/Resources/
	swiftc $(SWIFT_SOURCES) -o ShoveIt.app/Contents/MacOS/ShoveIt-x86_64 -O -target x86_64-apple-macos14.0
	swiftc $(SWIFT_SOURCES) -o ShoveIt.app/Contents/MacOS/ShoveIt-arm64 -O -target arm64-apple-macos14.0
	lipo -create -output ShoveIt.app/Contents/MacOS/ShoveIt ShoveIt.app/Contents/MacOS/ShoveIt-x86_64 ShoveIt.app/Contents/MacOS/ShoveIt-arm64
	rm ShoveIt.app/Contents/MacOS/ShoveIt-x86_64 ShoveIt.app/Contents/MacOS/ShoveIt-arm64
	codesign --entitlements src/ShoveIt.entitlements -fvs "$(CODESIGN_IDENTITY)" ShoveIt.app

test:
	swiftc -o /tmp/ShoveItTests src/NotificationPosition.swift src/NotificationGeometry.swift src/DisplayPositionStore.swift tests/NotificationGeometryTests.swift tests/DisplayPositionStoreTests.swift tests/TestRunner.swift -target arm64-apple-macos14.0
	/tmp/ShoveItTests

run:
	@open ShoveIt.app

clean:
	@rm -rf ShoveIt.app ShoveIt.app.tar.gz /tmp/ShoveItTests

publish:
	@tar --uid=0 --gid=0 -czf ShoveIt.app.tar.gz ShoveIt.app
	@shasum -a 256 ShoveIt.app.tar.gz | cut -d ' ' -f 1
