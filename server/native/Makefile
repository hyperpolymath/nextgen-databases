# SPDX-License-Identifier: PMPL-1.0-or-later
# Makefile for Lith NIF

# Erlang paths
ERL_INCLUDE = $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)/erts-$(shell erl -eval 'io:format("~s", [erlang:system_info(version)])' -s init stop -noshell)/include

# Lith library path
LITH_LIB_DIR = ../../../lith/ffi/zig/zig-out/lib

# Compiler flags
CFLAGS = -fPIC -O2 -Wall -I$(ERL_INCLUDE)
LDFLAGS = -shared -L$(LITH_LIB_DIR) -llith

# Output
TARGET = ../priv/lith_nif.so

.PHONY: all clean

all: $(TARGET)

$(TARGET): lith_nif.c
	@mkdir -p ../priv
	$(CC) $(CFLAGS) lith_nif.c -o $(TARGET) $(LDFLAGS)
	@echo "Built $(TARGET)"

clean:
	rm -f $(TARGET)
	rm -rf ../priv
