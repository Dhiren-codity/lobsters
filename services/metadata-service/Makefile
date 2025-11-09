.PHONY: build test run clean

build:
	go build -o metadata-service main.go

test:
	go test -v ./...

run:
	go run main.go

clean:
	rm -f metadata-service

install-deps:
	go mod download
	go mod tidy

