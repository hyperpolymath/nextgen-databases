\ SPDX-License-Identifier: PMPL-1.0-or-later
\ Test harness for Form.Blocks
\
\ Part of Lithoglyph: Stone-carved data for the ages.

include ../src/lithoglyph-blocks.fs

\ ============================================================
\ Test Utilities
\ ============================================================

variable test-count
variable pass-count
variable fail-count

: test-start ( -- )
  0 test-count !
  0 pass-count !
  0 fail-count !
  cr ." ========================================" cr
  ." Form.Blocks Test Suite" cr
  ." ========================================" cr ;

: test ( c-addr u -- )
  1 test-count +!
  cr ." TEST: " type ."  ... " ;

: pass ( -- )
  1 pass-count +!
  ." PASS" ;

: fail ( -- )
  1 fail-count +!
  ." FAIL" ;

: assert= ( n1 n2 -- )
  = if pass else fail then ;

: assert-true ( flag -- )
  if pass else fail then ;

: assert-false ( flag -- )
  if fail else pass then ;

: test-summary ( -- )
  cr ." ========================================" cr
  ." Results: "
  pass-count @ . ." passed, "
  fail-count @ . ." failed, "
  test-count @ . ." total" cr
  ." ========================================" cr ;

\ ============================================================
\ Actual Tests
\ ============================================================

test-start

\ Test constants
s" BLOCK-SIZE is 4096" test
BLOCK-SIZE 4096 assert=

s" HEADER-SIZE is 64" test
HEADER-SIZE 64 assert=

s" PAYLOAD-SIZE is 4032" test
PAYLOAD-SIZE 4032 assert=

s" TYPE-DOCUMENT is $0011" test
TYPE-DOCUMENT $0011 assert=

\ Test block buffer allocation
s" block-buffer is allocated" test
block-buffer 0<> assert-true

\ Test clear-block
s" clear-block works" test
clear-block
block-buffer @ 0 assert=

\ Test CRC32C initialization
s" CRC32C table initialized (entry 1 non-zero)" test
crc32c-table 1 cells + @ 0<> assert-true

\ Test CRC32C calculation using block-buffer
s" CRC32C of buffer data is computed" test
\ Debug: show block-buffer address
\ ." block-buffer addr = " block-buffer . cr
\ Write some bytes to block-buffer payload area and compute CRC
$41 block-buffer block-payload c!
$42 block-buffer block-payload 1+ c!
$43 block-buffer block-payload 2 + c!
$44 block-buffer block-payload 3 + c!
block-buffer block-payload 4 crc32c 0<> assert-true

\ Test block header initialization
s" init-block-header sets magic" test
TYPE-DOCUMENT 1 init-block-header
block-buffer blk-magic l@ BLOCK-MAGIC assert=

s" init-block-header sets version" test
block-buffer block-version w@ 1 assert=

s" init-block-header sets type" test
block-buffer block-type w@ TYPE-DOCUMENT assert=

s" init-block-header sets block-id" test
block-buffer block-id @ 1 assert=

\ Test block validation
s" valid-magic? works" test
block-buffer valid-magic? assert-true

s" valid-type? works" test
block-buffer valid-type? assert-true

s" valid-payload-len? works" test
block-buffer valid-payload-len? assert-true

\ Test payload setting
s" set-block-payload works" test
s" test payload" drop 12 set-block-payload
block-buffer block-payload-len l@ 12 assert=

s" checksum is computed" test
block-buffer block-checksum l@ 0<> assert-true

test-summary

bye
