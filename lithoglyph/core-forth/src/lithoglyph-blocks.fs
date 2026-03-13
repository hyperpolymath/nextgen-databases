\ SPDX-License-Identifier: PMPL-1.0-or-later
\ Form.Blocks - Fixed-size block storage layer
\
\ This is the truth core of Lithoglyph. All data goes through here.
\ No business logic - just blocks, journals, and integrity.
\
\ Lithoglyph = litho (stone) + glyph (carved symbol)
\ Forth sculpts data onto disk like carving glyphs in stone.

\ Reset to clean Forth vocabulary to avoid gforth BLOCKS extension conflicts
only forth definitions

\ ============================================================
\ Constants
\ ============================================================

4096 constant BLOCK-SIZE        \ 4 KiB blocks
64 constant HEADER-SIZE         \ 64-byte fixed header
BLOCK-SIZE HEADER-SIZE - constant PAYLOAD-SIZE  \ 4032 bytes

\ Magic bytes: "LGH\0" = 0x4C474800 (Lithoglyph)
$4C474800 constant BLOCK-MAGIC

\ Block types
$0000 constant TYPE-FREE
$0001 constant TYPE-SUPERBLOCK
$0010 constant TYPE-COLLECTION-META
$0011 constant TYPE-DOCUMENT
$0012 constant TYPE-DOCUMENT-OVERFLOW
$0020 constant TYPE-EDGE-META
$0021 constant TYPE-EDGE
$0030 constant TYPE-INDEX-ROOT
$0031 constant TYPE-INDEX-INTERNAL
$0032 constant TYPE-INDEX-LEAF
$0040 constant TYPE-JOURNAL-SEGMENT
$0050 constant TYPE-SCHEMA
$0051 constant TYPE-CONSTRAINT
$0060 constant TYPE-MIGRATION

\ Block flags (bitmask)
$01 constant FLAG-COMPRESSED
$02 constant FLAG-ENCRYPTED
$04 constant FLAG-CHAINED
$08 constant FLAG-DELETED

\ ============================================================
\ Block Header Structure
\ ============================================================
\ Offset  Size  Field
\ 0       4     magic
\ 4       2     version
\ 6       2     block_type
\ 8       8     block_id
\ 16      8     sequence
\ 24      8     created_at
\ 32      8     modified_at
\ 40      4     payload_len
\ 44      4     checksum
\ 48      8     prev_block_id
\ 56      4     flags
\ 60      4     reserved

\ Header field accessors (offset from block start)
: blk-magic      ( addr -- addr' ) ;
: block-version    ( addr -- addr' ) 4 + ;
: block-type       ( addr -- addr' ) 6 + ;
: block-id         ( addr -- addr' ) 8 + ;
: block-sequence   ( addr -- addr' ) 16 + ;
: block-created    ( addr -- addr' ) 24 + ;
: block-modified   ( addr -- addr' ) 32 + ;
: block-payload-len ( addr -- addr' ) 40 + ;
: block-checksum   ( addr -- addr' ) 44 + ;
: block-prev       ( addr -- addr' ) 48 + ;
: block-flags      ( addr -- addr' ) 56 + ;
: block-reserved   ( addr -- addr' ) 60 + ;
: block-payload    ( addr -- addr' ) HEADER-SIZE + ;

\ ============================================================
\ Memory Buffer for Block Operations
\ ============================================================

create block-buffer BLOCK-SIZE allot

\ Initialize block buffer to zeros
: clear-block ( -- )
  block-buffer BLOCK-SIZE 0 fill ;

\ ============================================================
\ CRC32C Implementation (Castagnoli polynomial)
\ ============================================================

\ CRC32C lookup table
create crc32c-table 256 cells allot

\ Initialize CRC32C table (Castagnoli polynomial: 0x1EDC6F41)
: init-crc32c-table ( -- )
  256 0 do
    i
    8 0 do
      dup 1 and if
        1 rshift $82F63B78 xor
      else
        1 rshift
      then
    loop
    crc32c-table i cells + !
  loop ;

\ Calculate CRC32C of memory region
\ Use a variable to hold the address since DO/LOOP uses return stack
variable crc-addr
: crc32c ( addr len -- crc )
  swap crc-addr !   \ save addr; stack: len
  $FFFFFFFF swap    \ stack: crc len
  0 ?do             \ use ?do to handle len=0; stack: crc
    crc-addr @ i + c@  \ read byte at addr+i; stack: crc byte
    over $FF and xor   \ XOR with low byte of crc; stack: crc index
    cells crc32c-table + @  \ lookup in table; stack: crc table-value
    swap 8 rshift xor  \ combine: (crc >> 8) XOR table-value; stack: new-crc
  loop
  $FFFFFFFF xor ;   \ final XOR

\ ============================================================
\ Block Validation
\ ============================================================

\ Check if block has valid magic bytes
: valid-magic? ( addr -- flag )
  blk-magic l@ BLOCK-MAGIC = ;

\ Check if block type is known
: valid-type? ( addr -- flag )
  block-type w@
  dup TYPE-FREE = swap
  dup TYPE-SUPERBLOCK = swap
  dup TYPE-DOCUMENT = swap
  dup TYPE-EDGE = swap
  dup TYPE-JOURNAL-SEGMENT = swap
  drop
  or or or or ;

\ Check payload length is within bounds
: valid-payload-len? ( addr -- flag )
  block-payload-len l@ PAYLOAD-SIZE <= ;

\ Compute and verify checksum
: valid-checksum? ( addr -- flag )
  dup block-payload swap block-payload-len l@
  crc32c
  swap block-checksum l@ = ;

\ Full block validation
: validate-block ( addr -- flag )
  dup valid-magic? 0= if drop false exit then
  dup valid-type? 0= if drop false exit then
  dup valid-payload-len? 0= if drop false exit then
  valid-checksum? ;

\ ============================================================
\ Block Creation
\ ============================================================

variable next-block-id
variable current-sequence

\ Get current timestamp (Unix microseconds)
\ gforth's utime returns double-cell microseconds since epoch
: now-microseconds ( -- u )
  utime drop ;  \ On 64-bit, low cell holds full value

\ Initialize a new block header
\ Note: Use l! for 32-bit fields, w! for 16-bit, ! for 64-bit
: init-block-header ( type block-id -- )
  clear-block
  block-buffer block-id !          \ 64-bit
  block-buffer block-type w!       \ 16-bit
  BLOCK-MAGIC block-buffer blk-magic l!  \ 32-bit magic
  1 block-buffer block-version w!  \ 16-bit version
  now-microseconds block-buffer block-created !   \ 64-bit
  now-microseconds block-buffer block-modified !  \ 64-bit
  current-sequence @ block-buffer block-sequence !  \ 64-bit
  0 block-buffer block-prev !      \ 64-bit
  0 block-buffer block-flags l!    \ 32-bit
  0 block-buffer block-reserved l! \ 32-bit
  0 block-buffer block-payload-len l! ; \ 32-bit

\ Set block payload and compute checksum
: set-block-payload ( src-addr len -- )
  dup PAYLOAD-SIZE > if
    drop drop
    ." Error: payload too large" cr
    exit
  then
  dup block-buffer block-payload-len l!   \ 32-bit store
  block-buffer block-payload swap move
  \ Compute checksum
  block-buffer block-payload
  block-buffer block-payload-len l@       \ 32-bit fetch
  crc32c
  block-buffer block-checksum l! ;        \ 32-bit store

\ ============================================================
\ Block I/O
\ ============================================================

variable db-file-id

\ Open database file
: open-db ( addr len -- flag )
  r/w open-file if
    drop false
  else
    db-file-id ! true
  then ;

\ Close database file
: close-db ( -- )
  db-file-id @ close-file drop ;

\ Flush database file to disk (ensure durability)
: flush-db ( -- )
  db-file-id @ flush-file drop ;

\ Read block from file
: read-block ( block-id addr -- flag )
  swap BLOCK-SIZE * db-file-id @ reposition-file if
    drop false exit
  then
  drop
  BLOCK-SIZE db-file-id @ read-file if
    drop false
  else
    BLOCK-SIZE =
  then ;

\ Write block to file
: write-block ( block-id addr -- flag )
  swap BLOCK-SIZE * db-file-id @ reposition-file if
    drop false exit
  then
  drop
  BLOCK-SIZE db-file-id @ write-file if
    drop false
  else
    drop true
  then ;

\ ============================================================
\ Superblock Operations
\ ============================================================

create superblock-uuid 16 allot
variable superblock-journal-head
variable superblock-checkpoint
variable superblock-total-blocks
variable superblock-free-blocks
create superblock-name 64 allot

\ Initialize superblock
: init-superblock ( -- )
  TYPE-SUPERBLOCK 0 init-block-header
  \ UUID would be generated here
  0 superblock-journal-head !
  0 superblock-checkpoint !
  1 superblock-total-blocks !
  0 superblock-free-blocks ! ;

\ Read superblock from database
: read-superblock ( -- flag )
  0 block-buffer read-block if
    block-buffer validate-block if
      block-buffer block-type w@ TYPE-SUPERBLOCK = if
        \ Parse superblock payload
        true
      else
        false
      then
    else
      false
    then
  else
    false
  then ;

\ Write superblock to database
: write-superblock ( -- flag )
  0 block-buffer write-block ;

\ ============================================================
\ Block Allocation
\ ============================================================

\ Allocate new block ID
: alloc-block-id ( -- id )
  next-block-id @
  1 next-block-id +!
  1 superblock-total-blocks +! ;

\ Free a block (mark as deleted)
: free-block ( block-id -- )
  block-buffer read-block if
    FLAG-DELETED block-buffer block-flags l@ or
    block-buffer block-flags l!
    block-buffer write-block drop
    1 superblock-free-blocks +!
  then ;

\ ============================================================
\ Canonical Rendering
\ ============================================================

\ Render block type as string
: .block-type ( type -- )
  case
    TYPE-FREE of ." FREE" endof
    TYPE-SUPERBLOCK of ." SUPERBLOCK" endof
    TYPE-DOCUMENT of ." DOCUMENT" endof
    TYPE-EDGE of ." EDGE" endof
    TYPE-JOURNAL-SEGMENT of ." JOURNAL_SEGMENT" endof
    ." UNKNOWN"
  endcase ;

\ Render block flags
: .block-flags ( flags -- )
  ." ["
  dup FLAG-COMPRESSED and if ." COMPRESSED " then
  dup FLAG-ENCRYPTED and if ." ENCRYPTED " then
  dup FLAG-CHAINED and if ." CHAINED " then
  dup FLAG-DELETED and if ." DELETED " then
  drop
  ." ]" ;

\ Render block header (canonical format)
: .block-header ( addr -- )
  ." BLOCK block_id=" dup block-id @ .
  ."  version=" dup block-version w@ .
  ."  type=" dup block-type w@ .block-type cr
  ."   sequence=" dup block-sequence @ .
  ."  created=" dup block-created @ . cr
  ."   payload_len=" dup block-payload-len l@ .
  ."  checksum=0x" dup block-checksum l@ hex . decimal cr
  ."   flags=" block-flags l@ .block-flags cr ;

\ ============================================================
\ Initialization
\ ============================================================

: init-blocks ( -- )
  init-crc32c-table
  0 next-block-id !
  0 current-sequence !
  clear-block ;

\ Entry point
init-blocks
