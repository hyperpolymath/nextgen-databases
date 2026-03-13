\ SPDX-License-Identifier: PMPL-1.0-or-later
\ Form.Journal - Append-only mutation log
\
\ Every mutation is journaled before being applied.
\ The journal enables crash recovery and provides provenance.
\
\ Part of Lithoglyph: Stone-carved data for the ages.

require lithoglyph-blocks.fs

\ ============================================================
\ Journal Constants
\ ============================================================

\ Journal magic: "FDBJ" = 0x4644424A
$4644424A constant JOURNAL-MAGIC

\ Entry header size: 48 bytes
48 constant ENTRY-HEADER-SIZE

\ Operation types
$0001 constant OP-DOC-INSERT
$0002 constant OP-DOC-UPDATE
$0003 constant OP-DOC-DELETE
$0004 constant OP-DOC-REPLACE
$0010 constant OP-EDGE-INSERT
$0011 constant OP-EDGE-DELETE
$0012 constant OP-EDGE-UPDATE
$0020 constant OP-COLLECTION-CREATE
$0021 constant OP-COLLECTION-DROP
$0030 constant OP-SCHEMA-CREATE
$0031 constant OP-SCHEMA-ALTER
$0040 constant OP-CONSTRAINT-ADD
$0041 constant OP-CONSTRAINT-DROP
$0050 constant OP-INDEX-CREATE
$0051 constant OP-INDEX-DROP
$0060 constant OP-MIGRATION-START
$0061 constant OP-MIGRATION-STEP
$0062 constant OP-MIGRATION-COMPLETE
$0063 constant OP-MIGRATION-ROLLBACK
$0070 constant OP-CHECKPOINT
$FF00 constant OP-IRREVERSIBLE

\ Entry flags
$01 constant EFLAG-COMMITTED
$02 constant EFLAG-ROLLED-BACK
$04 constant EFLAG-CHECKPOINT
$08 constant EFLAG-COMPRESSED
$10 constant EFLAG-IRREVERSIBLE

\ ============================================================
\ Journal Entry Structure
\ ============================================================
\ Offset  Size  Field
\ 0       8     sequence
\ 8       8     timestamp
\ 16      2     op_type
\ 18      2     flags
\ 20      4     forward_len
\ 24      4     inverse_len
\ 28      4     provenance_len
\ 32      8     affected_block
\ 40      4     checksum
\ 44      4     entry_len

\ Entry header field accessors
: entry-sequence     ( addr -- addr' ) ;
: entry-timestamp    ( addr -- addr' ) 8 + ;
: entry-op-type      ( addr -- addr' ) 16 + ;
: entry-flags        ( addr -- addr' ) 18 + ;
: entry-forward-len  ( addr -- addr' ) 20 + ;
: entry-inverse-len  ( addr -- addr' ) 24 + ;
: entry-provenance-len ( addr -- addr' ) 28 + ;
: entry-affected     ( addr -- addr' ) 32 + ;
: entry-checksum     ( addr -- addr' ) 40 + ;
: entry-len          ( addr -- addr' ) 44 + ;
: entry-forward      ( addr -- addr' ) ENTRY-HEADER-SIZE + ;

\ Get inverse payload address
: entry-inverse ( addr -- addr' )
  dup entry-forward swap entry-forward-len @ + ;

\ Get provenance payload address
: entry-provenance ( addr -- addr' )
  dup entry-inverse swap entry-inverse-len @ + ;

\ ============================================================
\ Journal State
\ ============================================================

variable journal-file-id
variable journal-sequence     \ Current sequence number
variable journal-head         \ Last committed sequence
variable journal-checkpoint   \ Last checkpoint sequence
variable journal-entry-count
variable journal-file-size

\ Journal entry buffer (max 64KB per entry)
65536 constant MAX-ENTRY-SIZE
create entry-buffer MAX-ENTRY-SIZE allot

\ ============================================================
\ Journal File Operations
\ ============================================================

\ Open journal file
: open-journal ( addr len -- flag )
  r/w open-file if
    drop false
  else
    journal-file-id ! true
  then ;

\ Create new journal file
: create-journal ( addr len -- flag )
  w/o create-file if
    drop false
  else
    journal-file-id !
    \ Write journal header (first block)
    clear-block
    JOURNAL-MAGIC block-buffer !
    1 block-buffer 4 + !  \ version
    0 block-buffer 24 + ! \ journal head
    0 block-buffer 32 + ! \ checkpoint
    0 block-buffer 40 + ! \ entry count
    BLOCK-SIZE block-buffer 48 + ! \ file size
    block-buffer BLOCK-SIZE journal-file-id @ write-file if
      drop false
    else
      drop
      0 journal-sequence !
      0 journal-head !
      0 journal-checkpoint !
      0 journal-entry-count !
      BLOCK-SIZE journal-file-size !
      true
    then
  then ;

\ Close journal file
: close-journal ( -- )
  journal-file-id @ close-file drop ;

\ Flush journal to disk (ensure durability)
: flush-journal ( -- )
  journal-file-id @ flush-file drop ;

\ ============================================================
\ Journal Entry Creation
\ ============================================================

\ Clear entry buffer
: clear-entry ( -- )
  entry-buffer MAX-ENTRY-SIZE 0 fill ;

\ Initialize entry header
: init-entry ( op-type affected-block -- )
  clear-entry
  \ Increment sequence
  1 journal-sequence +!
  journal-sequence @ entry-buffer entry-sequence !
  now-microseconds entry-buffer entry-timestamp !
  swap entry-buffer entry-op-type w!
  0 entry-buffer entry-flags w!
  entry-buffer entry-affected !
  0 entry-buffer entry-forward-len !
  0 entry-buffer entry-inverse-len !
  0 entry-buffer entry-provenance-len ! ;

\ Set forward payload
: set-forward-payload ( addr len -- )
  dup entry-buffer entry-forward-len !
  entry-buffer entry-forward swap move ;

\ Set inverse payload
: set-inverse-payload ( addr len -- )
  dup entry-buffer entry-inverse-len !
  entry-buffer entry-inverse swap move ;

\ Set provenance payload
: set-provenance-payload ( addr len -- )
  dup entry-buffer entry-provenance-len !
  entry-buffer entry-provenance swap move ;

\ Compute entry length
: compute-entry-len ( -- len )
  ENTRY-HEADER-SIZE
  entry-buffer entry-forward-len @ +
  entry-buffer entry-inverse-len @ +
  entry-buffer entry-provenance-len @ + ;

\ Finalize entry (compute checksum and length)
: finalize-entry ( -- )
  compute-entry-len dup entry-buffer entry-len !
  \ Compute checksum over entire entry except checksum field
  entry-buffer swap crc32c
  entry-buffer entry-checksum ! ;

\ ============================================================
\ Journal Writing
\ ============================================================

\ Append entry to journal
: append-entry ( -- flag )
  finalize-entry
  \ Seek to end of journal
  journal-file-size @ journal-file-id @ reposition-file if
    drop false exit
  then
  drop
  \ Write entry
  entry-buffer entry-buffer entry-len @
  journal-file-id @ write-file if
    drop false exit
  then
  drop
  \ Update file size
  entry-buffer entry-len @ journal-file-size +!
  \ Update entry count
  1 journal-entry-count +!
  true ;

\ Mark entry as committed
: commit-entry ( -- )
  EFLAG-COMMITTED entry-buffer entry-flags w@ or
  entry-buffer entry-flags w!
  journal-sequence @ journal-head ! ;

\ Write checkpoint entry
: write-checkpoint ( -- flag )
  OP-CHECKPOINT 0 init-entry
  EFLAG-CHECKPOINT entry-buffer entry-flags w@ or
  entry-buffer entry-flags w!
  append-entry if
    commit-entry
    journal-head @ journal-checkpoint !
    true
  else
    false
  then ;

\ ============================================================
\ Journal Reading
\ ============================================================

\ Read entry at offset
: read-entry-at ( offset -- flag )
  journal-file-id @ reposition-file if
    drop false exit
  then
  drop
  \ Read header first
  entry-buffer ENTRY-HEADER-SIZE journal-file-id @ read-file if
    drop false exit
  then
  ENTRY-HEADER-SIZE <> if false exit then
  \ Read rest of entry
  entry-buffer entry-len @ ENTRY-HEADER-SIZE - dup 0> if
    entry-buffer ENTRY-HEADER-SIZE + swap
    journal-file-id @ read-file if
      drop false exit
    then
    drop
  else
    drop
  then
  true ;

\ Validate entry checksum
: validate-entry ( -- flag )
  entry-buffer entry-checksum @
  entry-buffer entry-buffer entry-len @ crc32c
  = ;

\ ============================================================
\ Journal Replay (Crash Recovery)
\ ============================================================

\ Apply a single journal entry by replaying its forward payload
: replay-entry ( -- flag )
  entry-buffer entry-op-type w@
  case
    OP-DOC-INSERT of
      \ Recreate document block from forward payload
      entry-buffer entry-affected @
      TYPE-DOCUMENT over init-block-header
      entry-buffer entry-forward
      entry-buffer entry-forward-len @
      dup 0> if
        set-block-payload
        block-buffer write-block
      else
        2drop drop true  \ Empty payload, skip
      then
    endof
    OP-DOC-UPDATE of
      \ Overwrite block with forward payload (new data)
      entry-buffer entry-affected @
      block-buffer read-block if
        entry-buffer entry-forward
        entry-buffer entry-forward-len @
        dup 0> if
          set-block-payload
          entry-buffer entry-affected @
          block-buffer write-block
        else
          2drop true
        then
      else
        false
      then
    endof
    OP-DOC-DELETE of
      \ Mark block as deleted
      entry-buffer entry-affected @ free-block true
    endof
    OP-SCHEMA-CREATE of
      \ Recreate schema block from forward payload
      entry-buffer entry-affected @
      TYPE-SCHEMA over init-block-header
      entry-buffer entry-forward
      entry-buffer entry-forward-len @
      dup 0> if
        set-block-payload
        block-buffer write-block
      else
        2drop drop true
      then
    endof
    OP-COLLECTION-CREATE of
      \ Collection metadata is in-memory only; skip block replay
      true
    endof
    OP-CHECKPOINT of
      true  \ Checkpoints are markers, nothing to replay
    endof
    \ Default: skip unknown operations
    true swap
  endcase ;

\ Replay uncommitted entries for crash recovery
: replay-journal ( -- )
  0 >r  \ r: replayed count
  BLOCK-SIZE  \ Start after journal header block
  begin
    dup journal-file-size @ <
  while
    dup read-entry-at if
      validate-entry if
        entry-buffer entry-flags w@
        dup EFLAG-COMMITTED and 0= swap
        EFLAG-ROLLED-BACK and 0= and if
          \ Entry not committed and not rolled back — replay it
          ." Replaying entry seq=" entry-buffer entry-sequence @ .
          ."  op=" entry-buffer entry-op-type w@ .op-type cr
          replay-entry if
            \ Mark as committed after successful replay
            commit-entry
            r> 1+ >r
          else
            ." Warning: failed to replay entry seq="
            entry-buffer entry-sequence @ . cr
          then
        then
      else
        ." Warning: corrupt entry at offset " dup . cr
      then
      entry-buffer entry-len @ +
    else
      ." Error reading entry at offset " dup . cr
      drop r> drop exit
    then
  repeat
  drop
  r> dup 0> if
    ." Replay complete: " . ." entries recovered" cr
    flush-db  \ Ensure all replayed data is durable
  else
    drop ." No entries to replay" cr
  then ;

\ ============================================================
\ Canonical Rendering
\ ============================================================

\ Render operation type
: .op-type ( op -- )
  case
    OP-DOC-INSERT of ." DOC_INSERT" endof
    OP-DOC-UPDATE of ." DOC_UPDATE" endof
    OP-DOC-DELETE of ." DOC_DELETE" endof
    OP-EDGE-INSERT of ." EDGE_INSERT" endof
    OP-EDGE-DELETE of ." EDGE_DELETE" endof
    OP-COLLECTION-CREATE of ." COLLECTION_CREATE" endof
    OP-COLLECTION-DROP of ." COLLECTION_DROP" endof
    OP-CHECKPOINT of ." CHECKPOINT" endof
    OP-IRREVERSIBLE of ." IRREVERSIBLE" endof
    ." UNKNOWN"
  endcase ;

\ Render entry flags
: .entry-flags ( flags -- )
  ." ["
  dup EFLAG-COMMITTED and if ." COMMITTED " then
  dup EFLAG-ROLLED-BACK and if ." ROLLED_BACK " then
  dup EFLAG-CHECKPOINT and if ." CHECKPOINT " then
  dup EFLAG-COMPRESSED and if ." COMPRESSED " then
  dup EFLAG-IRREVERSIBLE and if ." IRREVERSIBLE " then
  drop
  ." ]" ;

\ Render journal entry header
: .entry-header ( addr -- )
  ." JOURNAL seq=" dup entry-sequence @ .
  ."  op=" dup entry-op-type w@ .op-type
  ."  timestamp=" dup entry-timestamp @ . cr
  ."   affected_block=" dup entry-affected @ .
  ."  flags=" entry-flags w@ .entry-flags cr ;

\ ============================================================
\ High-Level Journal Operations
\ ============================================================

\ Begin journaled operation
: begin-journal-op ( op-type block-id -- )
  init-entry ;

\ End journaled operation (append and commit)
: end-journal-op ( -- flag )
  append-entry if
    commit-entry
    true
  else
    false
  then ;

\ Rollback uncommitted operation
: rollback-journal-op ( -- )
  EFLAG-ROLLED-BACK entry-buffer entry-flags w@ or
  entry-buffer entry-flags w! ;

\ Write-ahead log pattern: journal → flush → write block → commit → flush
\ Caller must have already called begin-journal-op and set payloads.
\ ( block-id addr -- flag )
: wal-write-block
  \ Step 1: Append journal entry to disk
  append-entry 0= if 2drop false exit then
  \ Step 2: Flush journal for durability (WAL guarantee)
  flush-journal
  \ Step 3: Write the actual data block
  write-block 0= if
    rollback-journal-op false exit
  then
  \ Step 4: Mark journal entry as committed
  commit-entry
  \ Step 5: Flush commit marker
  flush-journal
  true ;

\ ============================================================
\ Initialization
\ ============================================================

: init-journal ( -- )
  0 journal-sequence !
  0 journal-head !
  0 journal-checkpoint !
  0 journal-entry-count !
  BLOCK-SIZE journal-file-size !
  clear-entry ;

init-journal
