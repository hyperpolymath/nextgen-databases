# SPDX-License-Identifier: PMPL-1.0-or-later
# Makefile for Lith NIF

.PHONY: all clean test install

# Erlang paths
ERL_INCLUDE_PATH ?= $(shell erl -noshell -eval 'io:format("~s/usr/include", [code:root_dir()])' -s init stop)
ERL_LIB_PATH ?= $(shell erl -noshell -eval 'io:format("~s/usr/lib", [code:root_dir()])' -s init stop)

# Lith path (set this to your Lith installation)
LITH_PATH ?= $(HOME)/Documents/hyperpolymath-repos/lith

# Output directory
PRIV_DIR = ../priv

# Zig build options
ZIG_BUILD_FLAGS = -Doptimize=ReleaseSafe

all: $(PRIV_DIR)/lith_nif.so

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(PRIV_DIR)/lith_nif.so: src/lith_nif.zig $(PRIV_DIR)
	ERL_INCLUDE_PATH=$(ERL_INCLUDE_PATH) zig build $(ZIG_BUILD_FLAGS)

# Build Lith first if needed
lith:
	cd $(LITH_PATH)/core-zig && zig build

# Compile Erlang module
erl: src/lith_nif.erl
	erlc -o ../ebin src/lith_nif.erl

clean:
	rm -rf zig-cache zig-out $(PRIV_DIR)/lith_nif.so

test:
	zig build test

# Install to system Erlang lib directory
install: all
	cp $(PRIV_DIR)/lith_nif.so $(ERL_LIB_PATH)/

# Development: build and copy to priv
dev: all erl
	@echo "NIF built successfully"
	@echo "Library: $(PRIV_DIR)/lith_nif.so"
