.PHONY: all dev build dmg test clean install help
all: build
build:
	./tools/build-app.sh
dmg:
	./tools/build-dmg.sh
test:
	swift test -Xswiftc -warnings-as-errors
dev: build
	open -n dist/Caffeinator.app --args --show
install: build
	@echo "Quit the existing Caffeinator app before installing."
	@test -z "$$(pgrep -x caffeinator)" || (echo "Caffeinator is running; stop its session and quit first."; exit 1)
	ditto dist/Caffeinator.app /Applications/Caffeinator.app
clean:
	swift package clean
help:
	@echo "make build   Build an ad-hoc-signed native app in dist/"
	@echo "make dmg     Build and verify a distributable DMG"
	@echo "make test    Run Swift core tests"
	@echo "make dev     Build and open the native app"
	@echo "make install Copy the app to /Applications after quitting the existing app"
