.SILENT:

.PHONY: compile

SOURCE_FOLDER=./src
last_folder=$(basename $(dirname $(dir)))

init-submodules:
	git submodule init

install: init-submodules update

update-cairo:
	git submodule update && (cd cairo && git fetch origin && git rebase origin/main) && cp -rf cairo/corelib .

update-cargo:
	cp cairo/Cargo.toml .
	sed -i '' -e 's|"crates|"cairo/crates|g' Cargo.toml
	sed -i '' -e 's/"tests",//' Cargo.toml

update: update-cairo update-cargo

build:
	cargo build

test: dir = ./tests
test:
	cargo run --bin cairo-test -- $(dir) --starknet 

format:
	cargo run --bin cairo-format -- --recursive $(SOURCE_FOLDER) --print-parsing-errors

check-format:
	cargo run --bin cairo-format -- --check --recursive $(SOURCE_FOLDER)

compile:
	~/Programming/scarb/target/debug/scarb build

starknet-compile:
	mkdir -p out && \
	  cargo run --bin starknet-compile -- $(SOURCE_FOLDER)/${file} out/$(shell basename $(file) .cairo).json

language-server:
	cargo build --bin cairo-language-server --release
