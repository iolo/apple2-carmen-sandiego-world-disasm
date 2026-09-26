; po/Z: $4000, 1045 bytes, sha256 68e8757759051ad499c595036871fc1bc607f44b56d862220e1d675f2a9473f2
; Mixed 6502 and 65816 disk-access code. Remaining boundaries need review.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

; Firmware entries called by the downloaded UniDisk controller program.
; Their precise services are not yet identified.
Z_CONTROLLER_ROUTINE_72           := $0072
Z_CONTROLLER_ROUTINE_7B           := $007B
; Controller RAM fields used only by the downloaded program. The host's
; $E8 is separately reused as the low byte of a calculated block index.
Z_CONTROLLER_EXPECTED_VALUE       := $14
Z_CONTROLLER_SELECTOR_BIT         := $16
Z_CONTROLLER_READ_ATTEMPTS        := $E8
Z_PENDING_PROLOGUES               := $E5

; Called with eight data bytes inline after the caller JSR.
Z_ENTRY: lda     #$08
        jsr     Z_SKIP_INLINE_BYTES
        ldy     #$07
        lda     ($E0),y
        sta     Z_INLINE_FIELD_7
        tax
        iny
        lda     ($E0),y
        sta     Z_INLINE_FIELD_8
        jsr     Z_COUNT_FROM_HIGH_NIBBLE
        sta     Z_SCAN_MATCH_COUNT
        ldx     #$07
Z_TRY_SLOT: stx     $E4
        jsr     Z_SEARCH_SMARTPORT_SLOT
        bcc     Z_RETURN_TO_CALLER
        ldx     $E4
        dex
        bne     Z_TRY_SLOT
        lda     #$33
Z_RETURN_TO_CALLER:  php
        pha
        txa
        pha
        tya
        pha
        jsr     Z_SWAP_ZP_E0_ED
        pla
        tay
        pla
        tax
        pla
        plp
        rts

; Probe this slot, then try each device reported by its SmartPort controller.
Z_SEARCH_SMARTPORT_SLOT:  jsr Z_PROBE_SMARTPORT_ROM
        bcs     Z_DEVICE_NOT_USABLE
        lda     #$00
        sta     $E2
        jsr     Z_SMARTPORT_STATUS
        ldx     Z_DEVICE_COUNT
        inx
        stx     $E3
        ldx     #$01
Z_TRY_NEXT_DEVICE:  stx     $E2
        stx     Z_CONTROL_UNIT
        stx     Z_READ_UNIT
        jsr     Z_TRY_SMARTPORT_DEVICE
        bcc     Z_RETURN_DEVICE_SEARCH
        ldx     $E2
        inx
        cpx     $E3
        bcc     Z_TRY_NEXT_DEVICE
Z_RETURN_DEVICE_SEARCH:  rts

; Read a block and compare the supplied signature before choosing a drive path.
Z_TRY_SMARTPORT_DEVICE:  lda #$03
        jsr     Z_SMARTPORT_STATUS
        lda     Z_DIB_FLAGS
        and     #$10
        beq     Z_DEVICE_NOT_USABLE
        lda     Z_DEVICE_TYPE
; DIB device type $01 is a 3.5-inch drive.
        cmp     #$01
        bne     Z_DEVICE_NOT_USABLE
        jsr     Z_READ_AND_MATCH_SIGNATURE
        bcs     Z_DEVICE_NOT_USABLE
        lda     Z_DEVICE_SUBTYPE
; Subtype $00 is UniDisk 3.5; $C0 is AppleDisk 3.5.
        cmp     #$00
        beq     Z_UNIDISK_PATH
        cmp     #$C0
        bne     Z_DEVICE_NOT_USABLE
        lda     #$05
        ldx     #<Z_APPLEDISK_SET_HOOK_LIST
        ldy     #>Z_APPLEDISK_SET_HOOK_LIST
        jsr     Z_SMARTPORT_CONTROL
        jsr     Z_USE_DISKII_BYTE_PORT
        jsr     Z_CALCULATE_BLOCK_INDEX
        jsr     Z_SMARTPORT_READ_BLOCK
        lda     #$06
        ldx     #<Z_APPLEDISK_RESET_HOOK_LIST
        ldy     #>Z_APPLEDISK_RESET_HOOK_LIST
        jsr     Z_SMARTPORT_CONTROL
        bcc     Z_RETURN_DEVICE_RESULT
Z_DEVICE_NOT_USABLE:  sec
        rts

; UniDisk path: set controller RAM address, download 65C02 code, execute.
Z_UNIDISK_PATH:  lda #$06
        ldx     #<Z_SET_ADDRESS_LIST
        ldy     #>Z_SET_ADDRESS_LIST
        jsr     Z_SMARTPORT_CONTROL
        bcs     Z_TRY_DISKII_FALLBACK
        lda     #$0C
        ldy     #$0A
        jsr     Z_PATCH_BYTE_READ_ADDRESS
        lda     #$07
        ldx     #<Z_DOWNLOAD_LIST
        ldy     #>Z_DOWNLOAD_LIST
        jsr     Z_SMARTPORT_CONTROL
        bcs     Z_DEVICE_NOT_USABLE
        lda     #$05
        ldx     #<Z_EXECUTE_LIST
        ldy     #>Z_EXECUTE_LIST
        jsr     Z_SMARTPORT_CONTROL
        bcs     Z_DEVICE_NOT_USABLE
        lda     #$05
        jsr     Z_SMARTPORT_STATUS
        bcs     Z_DEVICE_NOT_USABLE
Z_RETURN_DEVICE_RESULT:  lda     Z_RESULT_P
        pha
        lda     Z_RESULT_A
        ldx     Z_RESULT_X
        ldy     Z_RESULT_Y
        plp
        cli
        rts

; If SetAddress fails, recognize a specific ROM before using Disk II switches.
Z_TRY_DISKII_FALLBACK:  lda $FBB3
        cmp     #$06
        bne     Z_DEVICE_NOT_USABLE
        lda     $FBC0
        bne     Z_DEVICE_NOT_USABLE
        lda     $FBBF
        cmp     #$05
        bne     Z_DEVICE_NOT_USABLE
        jsr     Z_USE_DISKII_BYTE_PORT
        jsr     Z_CALCULATE_BLOCK_INDEX
        jsr     Z_SMARTPORT_READ_BLOCK
        sei
        sta     $C028
        jsr     Z_READ_DISKII_BYTE_AND_FLAGS
        pha
        jsr     Z_PREPARE_DISKII_PORTS
        jsr     Z_SCAN_DISKII_PROLOGUE
        bit     $C0E8
        pla
        and     #$1F
        bit     $C0ED
        sta     $C0EF
        jsr     Z_READ_DISKII_BYTE_AND_FLAGS
        jsr     Z_RESET_CONTROLLER_SWITCHES
        sta     $C028
        cli
        rts

Z_RESET_CONTROLLER_SWITCHES:  sta     $CC40
        sta     $CC80
        sta     $CCC0
        rts

; Inline bytes 1-2 are the block buffer, 3-4 the block index, and 5-6
; a NUL-terminated signature pointer. Compare it with the block at buffer+5.
Z_READ_AND_MATCH_SIGNATURE:  ldy #$01
        lda     ($E0),y
        sta     Z_READ_BUFFER_LO
        sta     $E6
        iny
        lda     ($E0),y
        sta     Z_READ_BUFFER_HI
        sta     $E7
        ldy     #$03
        lda     ($E0),y
        tax
        iny
        lda     ($E0),y
        tay
        jsr     Z_SMARTPORT_READ_BLOCK
        bcs     Z_SIGNATURE_MISMATCH
        ldy     #$05
        lda     ($E0),y
        sta     $EC
        iny
        lda     ($E0),y
        sta     $ED
        ldy     #$FF
        lda     $E6
        adc     #$05
        sta     $E6
        bcc     Z_COMPARE_SIGNATURE_BYTE
        inc     $E7
Z_COMPARE_SIGNATURE_BYTE:  iny
        lda     ($EC),y
        beq     Z_SIGNATURE_MATCHED
        cmp     ($E6),y
        beq     Z_COMPARE_SIGNATURE_BYTE
Z_SIGNATURE_MISMATCH:  sec
        rts

Z_SIGNATURE_MATCHED:  clc
        rts

; Convert inline fields 7-8 into the low/middle READ BLOCK index bytes.
; For field 7 in 0..79, let count(t) = 12 - floor(t/16). The result is
; 2*sum(count(t), t=0..field7-1), plus count(field7) if field8 is nonzero.
; Field8 selects the extra count(field7); its exact physical meaning is not
; established by the inactive caller. Values above 79 read past the table.
Z_CALCULATE_BLOCK_INDEX:  lda #$00
        sta     $E9
        ldx     Z_INLINE_FIELD_7
        ldy     Z_INLINE_FIELD_8
        beq     Z_STORE_BLOCK_INDEX_LOW
        jsr     Z_COUNT_FROM_HIGH_NIBBLE
Z_STORE_BLOCK_INDEX_LOW:  sta     $E8
Z_ACCUMULATE_BLOCK_INDEX:  dex
        bmi     Z_RETURN_BLOCK_INDEX
        jsr     Z_COUNT_FROM_HIGH_NIBBLE
        asl     a
        adc     $E8
        sta     $E8
        bcc     Z_ACCUMULATE_BLOCK_INDEX
        inc     $E9
        bcs     Z_ACCUMULATE_BLOCK_INDEX
Z_RETURN_BLOCK_INDEX:  ldx     $E8
        ldy     $E9
        rts

Z_COUNT_FROM_HIGH_NIBBLE:  txa
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tay
        lda     Z_HIGH_NIBBLE_COUNTS,y
        rts

; Lookup by the high nibble of X. The callback below uses 65816 opcodes.
Z_HIGH_NIBBLE_COUNTS:  .byte   $0C, $0B, $0A, $09, $08
Z_65816_CALLBACK:  .setcpu "65816"
        sei
        lda     f:Z_SCAN_MATCH_COUNT
        sta     $E5
        jsr     Z_SCAN_D5_AA_96
        phb
        php
        pha
        lda     #$00
        pha
        plb
        pla
        sta     Z_RESULT_A
        stx     Z_RESULT_X
        sty     Z_RESULT_Y
        pla
        sta     Z_RESULT_P
        plb
        clc
        rtl
        .setcpu "6502"
; Select the drive and prepare the Disk II I/O switches for the direct path.
Z_PREPARE_DISKII_PORTS:  bit $C0E8
        ldx     $E2
        dex
        dex
        bpl     Z_SELECT_OTHER_DISKII_DRIVE
        sta     $CC80
        sta     $CEA0
        sta     $CE60
        bit     $C0EB
        clc
        bcc     Z_WAIT_FOR_DISKII_DRIVE
Z_SELECT_OTHER_DISKII_DRIVE:  bit     $CCC0
        sta     $CE40
        lda     $C0EA,x
        sec
Z_WAIT_FOR_DISKII_DRIVE:  bit     $C0ED
        ldy     #$0F
        bpl     Z_POLL_DISKII_READY
Z_ENABLE_DISKII_WRITE:  sty     $C0EF
Z_POLL_DISKII_READY:  tya
        eor     $C0EE
        and     #$1F
        beq     Z_FINISH_DISKII_SETUP
        lda     $C0EE
        and     #$20
        beq     Z_ENABLE_DISKII_WRITE
        jsr     Z_RESET_CONTROLLER_SWITCHES
        bcs     Z_POLL_DISKII_READY
        sta     $CEA0
        sta     $CC80
        bcc     Z_POLL_DISKII_READY
Z_FINISH_DISKII_SETUP:  bit     $C0E9
        bit     $C0E4
        bit     $CE40
        bit     $C0E0
        bit     $C0E3
        jsr     Z_READ_DISKII_BYTE_AND_FLAGS
        bpl     Z_SELECT_DISKII_PHASE
        bit     $C0E7
        bit     $C0E6
        ldx     #$0D
        ldy     #$3F
Z_DISKII_SPIN_DELAY:  dex
        bne     Z_DISKII_SPIN_DELAY
        dey
        bne     Z_DISKII_SPIN_DELAY
Z_SELECT_DISKII_PHASE:  bit     $C0E5
Z_WAIT_FOR_DISKII_BYTE:  jsr     Z_READ_DISKII_BYTE_AND_FLAGS
        bpl     Z_WAIT_FOR_DISKII_BYTE
Z_DISABLE_DISKII_PHASES:  bit     $C0E0
        bit     $C0E2
        bit     $C0E6
        rts

; Read $C0EE, preserving the byte's condition codes across the $C0EC access.
Z_READ_DISKII_BYTE_AND_FLAGS:  bit $C0ED
        lda     $C0EE
        php
        bit     $C0EC
        plp
        rts

; Search for D5 AA 96, then a later $DE marker before handing off to the
; common scan routine. Return carry set after exhausting the attempt count.
Z_SCAN_DISKII_PROLOGUE:  ldx #$40
        bit     $CE60
        bit     $C0E5
        lda     Z_SCAN_MATCH_COUNT
        sta     $E5
Z_FIND_D5:  lda     #$D5
Z_POLL_D5:  cmp     $C0EE
        bne     Z_POLL_D5
        nop
Z_WAIT_FOR_AA:  lda     $C0EE
        bpl     Z_WAIT_FOR_AA
        cmp     #$AA
        bne     Z_FIND_D5
        nop
Z_WAIT_FOR_96:  lda     $C0EE
        bpl     Z_WAIT_FOR_96
        cmp     #$96
        bne     Z_FIND_D5
        nop
Z_WAIT_AFTER_PROLOGUE:  lda     $C0EE
        bpl     Z_WAIT_AFTER_PROLOGUE
        php
        plp
Z_WAIT_FOR_SECOND_96:  lda     $C0EE
        bpl     Z_WAIT_FOR_SECOND_96
        cmp     #$96
        bne     Z_PROLOGUE_ATTEMPT_FAILED
        ldy     #$04
Z_SKIP_TO_DE:  lda     $C0EE
        bpl     Z_SKIP_TO_DE
        dey
        bne     Z_SKIP_TO_DE
        cmp     #$DE
        beq     Z_SCAN_PROLOGUE_FOUND
Z_PROLOGUE_ATTEMPT_FAILED:  dex
        bne     Z_FIND_D5
        sec
        rts

Z_SCAN_PROLOGUE_FOUND:  jsr     Z_SCAN_D5_AA_96
        bit     $C0E4
        bit     $CE40
        jmp     Z_DISABLE_DISKII_PHASES

; Exchange scratch ZP and advance the caller return address by A bytes.
Z_SKIP_INLINE_BYTES:  sta     Z_INLINE_SKIP_COUNT
        jsr     Z_SWAP_ZP_E0_ED
        tsx
        clc
        lda     $0103,x
        sta     $E0
        adc     Z_INLINE_SKIP_COUNT
        sta     $0103,x
        lda     $0104,x
        sta     $E1
        adc     #$00
        sta     $0104,x
        rts

Z_SWAP_ZP_E0_ED:  ldx     #$0D
Z_SWAP_NEXT_ZP_BYTE:  lda     $E0,x
        ldy     Z_SAVED_ZP_E0_ED,x
        sta     Z_SAVED_ZP_E0_ED,x
        sty     $E0,x
        dex
        bpl     Z_SWAP_NEXT_ZP_BYTE
        rts

; STATUS: A is the status code; $E2 selects unit 0 or a drive.
Z_SMARTPORT_STATUS:  sta     Z_STATUS_CODE
        lda     $E2
        sta     Z_STATUS_UNIT
        jsr     Z_SMARTPORT_ENTRY_JUMP
        .byte   $00             ; inline command for slot firmware
        .word   Z_STATUS_PARAMS           ; parameter block
        rts

; READ BLOCK: X/Y supply the low and middle bytes of the block number.
Z_SMARTPORT_READ_BLOCK:  clc
        stx     Z_READ_BLOCK_LO
        sty     Z_READ_BLOCK_MID
        jsr     Z_SMARTPORT_ENTRY_JUMP
        .byte   $01             ; inline command for slot firmware
        .word   Z_READ_PARAMS           ; parameter block
        rts

; CONTROL: A is the control code; X/Y point to its device-specific list.
Z_SMARTPORT_CONTROL:  sta     Z_CONTROL_CODE
        stx     Z_CONTROL_LIST_LO
        sty     Z_CONTROL_LIST_HI
        jsr     Z_SMARTPORT_ENTRY_JUMP
        .byte   $04             ; inline command for slot firmware
        .word   Z_CONTROL_PARAMS           ; parameter block
        rts

Z_PROBE_SMARTPORT_ROM:  txa
        ldx     #$00
        ora     #$C0
        stx     $E2
        sta     $E3
        ldx     #$03
Z_CHECK_SMARTPORT_ID_BYTE:  ldy     Z_SMARTPORT_ID_OFFSETS,x
        lda     Z_SMARTPORT_ID_BYTES,x
        cmp     ($E2),y
        bne     Z_SMARTPORT_ROM_NOT_FOUND
        dex
        bpl     Z_CHECK_SMARTPORT_ID_BYTE
        ldy     #$FF
        lda     ($E2),y
        beq     Z_SMARTPORT_ROM_NOT_FOUND
        cmp     #$FF
        beq     Z_SMARTPORT_ROM_NOT_FOUND
        ldx     $E3
        adc     $E2
        adc     #$03
        sta     Z_SMARTPORT_ENTRY_JUMP_LO
        stx     Z_SMARTPORT_ENTRY_JUMP_HI
        clc
        rts

Z_SMARTPORT_ROM_NOT_FOUND:  sec
        rts

; SmartPort slot-ROM signature at offsets $01/$03/$05/$07.
; The final two stored entries are not examined by this probe.
Z_SMARTPORT_ID_OFFSETS:  .byte   $01, $03, $05, $07, $FF, $02
Z_SMARTPORT_ID_BYTES:  .byte   $20, $00, $03, $00, $FF, $02
; Reset the three self-modifying absolute reads to the Disk II data register.
Z_USE_DISKII_BYTE_PORT:  lda     #$EE
        ldy     #$C0
Z_PATCH_BYTE_READ_ADDRESS:  sta     Z_POLL_D5_OPERAND_LO
        sty     Z_POLL_D5_OPERAND_HI
        sta     Z_POLL_AA_OPERAND_LO
        sty     Z_POLL_AA_OPERAND_HI
        sta     Z_POLL_96_OPERAND_LO
        sty     Z_POLL_96_OPERAND_HI
        rts

; The slot ROM probe patches this JMP to the discovered firmware entry.
Z_SMARTPORT_ENTRY_JUMP:  jmp     $FFFF
Z_SMARTPORT_ENTRY_JUMP_LO   := Z_SMARTPORT_ENTRY_JUMP + 1
Z_SMARTPORT_ENTRY_JUMP_HI   := Z_SMARTPORT_ENTRY_JUMP + 2
; Saved zero-page $E0-$ED, exchanged with the caller by Z_SWAP_ZP_E0_ED.
Z_SAVED_ZP_E0_ED:  .res    14, $00
        .byte   $00
Z_INLINE_SKIP_COUNT: .byte $00

; Standard SmartPort parameter lists: READ BLOCK, CONTROL, and STATUS.
Z_READ_PARAMS:       .byte $03
Z_READ_UNIT:         .byte $01
Z_READ_BUFFER_LO:    .byte $00
Z_READ_BUFFER_HI:    .byte $20
Z_READ_BLOCK_LO:     .byte $00
Z_READ_BLOCK_MID:    .byte $00
Z_READ_BLOCK_HI:     .byte $00
Z_CONTROL_PARAMS:    .byte $03
Z_CONTROL_UNIT:      .byte $01
Z_CONTROL_LIST_LO:   .byte $FF
Z_CONTROL_LIST_HI:   .byte $FF
Z_CONTROL_CODE:      .byte $00
Z_STATUS_PARAMS:     .byte $03
Z_STATUS_UNIT:       .byte $01
        .word   Z_STATUS_BUFFER
Z_STATUS_CODE:       .byte $00
; STATUS $03 returns a DIB here. Controller callback results reuse bytes
; $4382-$4385 as A, X, Y, and P before returning to the caller.
Z_STATUS_BUFFER:     .res 3, $00
Z_DEVICE_COUNT := Z_STATUS_BUFFER ; STATUS unit 0, code 0
Z_DIB_FLAGS := Z_STATUS_BUFFER   ; STATUS device, code 3
Z_RESULT_A:          .byte $00
Z_RESULT_X:          .byte $00
Z_RESULT_Y:          .byte $00
Z_RESULT_P:          .res 15, $00
Z_DEVICE_TYPE:       .byte $00
Z_DEVICE_SUBTYPE:    .res 3, $00
; AppleDisk control $05 (SetHook): count, reference, and 24-bit callback.
; The stored reference $82 is outside the draft firmware manual's $01-$07
; list; the actual firmware interpretation has not been verified.
Z_APPLEDISK_SET_HOOK_LIST: .word $0004
        .byte $82
        .word Z_65816_CALLBACK
        .byte $00
; AppleDisk control $06 (ResetHook). Its stored count is four rather than
; the manual's one, and its payload overlaps the UniDisk Execute list below.
Z_APPLEDISK_RESET_HOOK_LIST:  .word $0004
        .byte $00
; UniDisk 3.5 Execute: six argument bytes after this 16-bit count.
Z_EXECUTE_LIST: .word $0006
Z_INLINE_FIELD_7:  .byte   $00 ; Execute A
Z_INLINE_FIELD_8:  .byte   $00 ; Execute X
Z_SCAN_MATCH_COUNT:  .byte   $00 ; Execute Y
Z_EXECUTE_P:       .byte $34 ; Execute processor status
Z_EXECUTE_PC:      .word $0500 ; controller entry address
; UniDisk SetAddress selects controller RAM $0500 for the subsequent download.
Z_SET_ADDRESS_LIST: .word $0002, $0500
; SetAddress's count covers the preceding two address bytes. DownLoad's
; pointer starts after this byte, so it is outside both control lists.
Z_UNREFERENCED_CONTROL_BYTE: .byte $38
; UniDisk DownLoad: 16-bit byte count followed by 65C02 controller code.
Z_DOWNLOAD_LIST: .word Z_CONTROLLER_CODE_END - Z_CONTROLLER_CODE
        .setcpu "65c02"
; Downloaded from host $43B0 to controller $0500 (101 bytes). Relative
; branches remain valid after relocation; the two JSRs call controller ROM.
; A supplies the expected value, X bit 1 becomes $16 bit 7, and Y supplies
; the number of matching prologues to consume. Carry in cannot affect bit 7
; after the two RORs and AND below.
Z_CONTROLLER_CODE:  sta     Z_CONTROLLER_EXPECTED_VALUE
        sty     Z_PENDING_PROLOGUES
        txa
        ror     a
        ror     a
        and     #$80
        sta     Z_CONTROLLER_SELECTOR_BIT
        jsr     Z_CONTROLLER_ROUTINE_7B
        bcs     Z_RETURN_STATUS_32
        lda     #$30
        sta     Z_CONTROLLER_READ_ATTEMPTS
; Pre-decrement gives at most 47 calls to firmware $72, not 48.
Z_RETRY_CONTROLLER_READ:  dec     Z_CONTROLLER_READ_ATTEMPTS
        beq     Z_RETURN_STATUS_31
        jsr     Z_CONTROLLER_ROUTINE_72
        bcs     Z_RETRY_CONTROLLER_READ
        lda     $29
        ror     a
        ror     a
        ror     a
        and     #$40
        ora     $2B
; Original $29 bit 1 is moved into bit 6, then merged with $2B.
        cmp     Z_CONTROLLER_EXPECTED_VALUE
        bne     Z_RETURN_STATUS_31
        lda     $2A
        bne     Z_RETRY_CONTROLLER_READ
; Poll the patched byte port for a D5 AA 96 prologue, $E5 times.
; A negative byte signals availability. Only mismatch paths increment X/Y.
; When both counters wrap, execution falls through to the AA poll without
; confirming D5; it does not branch to the retained status-$30 return.
Z_SCAN_D5_AA_96:  ldx     #$32
        ldy     #$00
; These three absolute reads are patched together by Z_PATCH_BYTE_READ_ADDRESS.
Z_POLL_CONTROLLER_D5:  lda     $C0EE
Z_POLL_D5_OPERAND_LO   := Z_POLL_CONTROLLER_D5 + 1
Z_POLL_D5_OPERAND_HI   := Z_POLL_CONTROLLER_D5 + 2
        bpl     Z_POLL_CONTROLLER_D5
        cmp     #$D5
        beq     Z_POLL_CONTROLLER_AA
Z_RETRY_CONTROLLER_PROLOGUE:  inx
        bne     Z_POLL_CONTROLLER_D5
        iny
        bne     Z_POLL_CONTROLLER_D5
Z_POLL_CONTROLLER_AA:  lda     $C0EE
Z_POLL_AA_OPERAND_LO   := Z_POLL_CONTROLLER_AA + 1
Z_POLL_AA_OPERAND_HI   := Z_POLL_CONTROLLER_AA + 2
        bpl     Z_POLL_CONTROLLER_AA
        cmp     #$AA
        bne     Z_RETRY_CONTROLLER_PROLOGUE
Z_POLL_CONTROLLER_96:  lda     $C0EE
Z_POLL_96_OPERAND_LO   := Z_POLL_CONTROLLER_96 + 1
Z_POLL_96_OPERAND_HI   := Z_POLL_CONTROLLER_96 + 2
        bpl     Z_POLL_CONTROLLER_96
        cmp     #$96
        bne     Z_RETRY_CONTROLLER_PROLOGUE
        dec     Z_PENDING_PROLOGUES
        bne     Z_POLL_CONTROLLER_D5
Z_RETURN_SUCCESS:  lda     #$00
        clc
        rts

; Each $2C BIT consumes the next two-byte LDA immediate as its operand.
; All three error returns set carry and place a status code in A.
Z_RETURN_STATUS_32:  lda     #$32 ; controller $7B returned carry set
        .byte   $2C
Z_RETURN_STATUS_31:  lda     #$31 ; retries exhausted or expected value mismatch
        .byte   $2C
Z_RETURN_STATUS_30:  lda     #$30 ; no identified branch enters this status
        sec
        rts
Z_CONTROLLER_CODE_END:
        .setcpu "6502"
