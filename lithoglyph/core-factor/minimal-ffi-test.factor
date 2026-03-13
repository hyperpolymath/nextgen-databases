! SPDX-License-Identifier: PMPL-1.0-or-later
! Minimal FFI test - just test version function

USING: alien alien.c-types alien.libraries kernel io ;

IN: minimal-ffi-test

! Load library
<< "lithoglyph-bridge" {
    { [ os linux? ] [ "core-factor/libbridge.so" ] }
    { [ os macosx? ] [ "core-factor/libbridge.dylib" ] }
    { [ os windows? ] [ "core-factor/bridge.dll" ] }
} cond cdecl add-library >>

! Declare simplest function
LIBRARY: lithoglyph-bridge
FUNCTION: int fdb_get_version ( )

! Test it
: test-version ( -- )
    "Testing fdb_get_version..." print
    fdb_get_version "Version: " write . ;

! Run test
test-version
