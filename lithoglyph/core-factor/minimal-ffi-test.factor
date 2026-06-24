! SPDX-License-Identifier: MPL-2.0
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
FUNCTION: int lith_get_version ( )

! Test it
: test-version ( -- )
    "Testing lith_get_version..." print
    lith_get_version "Version: " write . ;

! Run test
test-version
