.PHONY: build test install clean

build:
	swiftc -O Sources/qrscan/main.swift -o qrscan

test: build
	bash tests/run-tests.sh
	bash tests/test-glue.sh

install:
	bash install.sh

clean:
	rm -f qrscan
	rm -rf tests/fixtures
