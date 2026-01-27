# usage: make [CONFIG=debug|release]

ifeq ($(CONFIG), debug)
	CFLAGS=-Onone -g
else
	CFLAGS=-O
endif

PLIST=$(shell grep -A1 $(1) src/Info.plist | tail -1 | cut -d'>' -f2 | cut -d'<' -f1)
HAS_SIGN_IDENTITY=$(shell security find-identity -v -p codesigning | grep -q "Apple Development" && echo 1 || echo 0)


Menuscript.app: SDK_PATH=$(shell xcrun --show-sdk-path --sdk macosx)
Menuscript.app: src/* examples/*
	@mkdir -p Menuscript.app/Contents/MacOS/
	swiftc ${CFLAGS} src/main.swift -target x86_64-apple-macos10.13 \
	-emit-executable -sdk ${SDK_PATH} -o bin_x64
	swiftc ${CFLAGS} src/main.swift -target arm64-apple-macos10.13 \
	-emit-executable -sdk ${SDK_PATH} -o bin_arm64
	lipo -create bin_x64 bin_arm64 -o Menuscript.app/Contents/MacOS/Menuscript
	@rm bin_x64 bin_arm64
	@echo 'APPL????' > Menuscript.app/Contents/PkgInfo
	@mkdir -p Menuscript.app/Contents/Resources/
	@cp src/AppIcon.icns Menuscript.app/Contents/Resources/AppIcon.icns
	@rm -rf Menuscript.app/Contents/Resources/examples/
	@cp -R examples/ Menuscript.app/Contents/Resources/examples/
	@cp src/Info.plist Menuscript.app/Contents/Info.plist
	@touch Menuscript.app
	@echo
ifeq ($(HAS_SIGN_IDENTITY),1)
	codesign -v -s 'Apple Development' --options=runtime --timestamp Menuscript.app
else
	codesign -v -s - Menuscript.app
endif
	@echo
	@echo 'Verify Signature...'
	@echo
	codesign -dvv Menuscript.app
	@echo
	codesign -vvv --deep --strict Menuscript.app
ifeq ($(HAS_SIGN_IDENTITY),1)
	@echo
	-spctl -vvv --assess --type exec Menuscript.app
endif


.PHONY: clean
clean:
	rm -rf Menuscript.app bin_x64 bin_arm64


.PHONY: release
release: VERSION=$(call PLIST,CFBundleShortVersionString)
release: Menuscript.app
	tar -czf "Menuscript_${VERSION}.tar.gz" Menuscript.app
