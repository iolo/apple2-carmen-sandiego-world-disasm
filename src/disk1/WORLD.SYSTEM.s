; disk1/WORLD.SYSTEM: $2000, 1217 bytes, sha256 c1b476648350bc2352bb63574aae31ca213378603b58763e956344e8e5431842
; ProDOS SYS entry at $2000. This loader prepares main/auxiliary RAM,
; checks available memory and /RAM, loads game modules, then jumps into B.
; ProDOS MLI calls use inline function/parameter bytes after JSR $BF00.
; Remaining mechanical instruction boundaries and tables need review.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

ZERO_PAGE_BASE           := $0000
B_LOAD_MODULE           := $9800
B_ENTER_INTRO           := $9803
PRODOS_MLI           := $BF00
C_COPY_2200_TO_AUX_D400           := $D20C
ROM_VTAB           := $FC22
ROM_HOME           := $FC58
ROM_PRBYTE           := $FDDA
ROM_COUT           := $FDED
RESET_VECTOR           := $FFFC
; Disable interrupts and establish the memory/video mapping expected by the loader.
BOOT_ENTRY:  sei
        cld
        ldx     #$FF
        txs
        sta     $C000
        sta     $C00C
        sta     $C008
        sta     $C004
        lda     $C082
        lda     $C054
        lda     $C051
        stx     CURRENT_FILE_INDEX
        jsr     ROM_HOME
        ldy     #$00
; Stage zero page at $4000 before copying it to $1D00 and language-card RAM.
BOOT_BACKUP_ZERO_PAGE:  lda     ZERO_PAGE_BASE,y
        sta     $4000,y
        iny
        bne     BOOT_BACKUP_ZERO_PAGE
        sta     $C009
        lda     $C081
        lda     $C081
BOOT_COPY_ZERO_PAGE_TO_LC:  lda     $4000,y
        sta     $1D00,y
        sta     $D000,y
        iny
        bne     BOOT_COPY_ZERO_PAGE_TO_LC
        sta     $C008
        lda     $C082
        lda     #$00
        sta     $BFFC
        sta     $BFFD
        sta     $03F4
        sta     $C009
        lda     #$BC
        sta     $0101
        sta     $C008
        lda     #$FF
        sta     $0101
        sta     $C009
; The saved $BC value must survive the alternate-memory write probe.
BOOT_VERIFY_AUX_MEMORY:  lda     $0101
        sta     $C008
        cmp     #$BC
        beq     BOOT_CHECK_RAM_DISK
        jsr     ROM_HOME
        lda     #$0A
        ldx     #<BOOT_TITLE_MESSAGE
        ldy     #>BOOT_TITLE_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        lda     #$0C
        ldx     #<BOOT_MEMORY_MESSAGE
        ldy     #>BOOT_MEMORY_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        jsr     READ_KEY
        jmp     BOOT_EXIT_TO_PRODOS

; Probe the RAM disk and prepare the ProDOS file I/O path.
BOOT_CHECK_RAM_DISK:  jsr     CHECK_RAM_DISK
        bcc     BOOT_SET_PREFIX
        jmp     WARN_RAM_DISK

BOOT_SET_PREFIX:  jsr     PRODOS_MLI
        .byte   $C6             ; SET_PREFIX
        .word   BOOT_SET_PREFIX_PARAMS ; parameter list
        bcc     BOOT_LOAD_SPLASH_AND_B
BOOT_GOTO_LOAD_ERROR:  jmp     BOOT_REPORT_LOAD_ERROR

BOOT_LOAD_SPLASH_AND_B:  jsr     LOAD_SPLASH_A
        bcs     BOOT_GOTO_LOAD_ERROR
        jsr     SELECT_HGR_PAGE2
        jsr     LOAD_RESIDENT_B
        bcs     BOOT_GOTO_LOAD_ERROR
        sta     $C009
        lda     $C083
        lda     $C083
        ldy     #$0E
        jsr     B_LOAD_MODULE
        bcs     BOOT_GOTO_LOAD_ERROR
        sta     $C008
        lda     $C083
        lda     $C083
        lda     #$00
        sta     $03F2
        sta     $FFFA
        sta     RESET_VECTOR
        sta     $FFFE
        lda     #$1F
        sta     $03F3
        eor     #$A5
        sta     $03F4
        sta     $FFFB
        sta     $FFFD
        sta     $FFFF
        sta     $C009
        lda     $C083
        lda     $C083
        lda     #$00
        sta     $03F2
        sta     $FFFA
        sta     RESET_VECTOR
        sta     $FFFE
        lda     #$1F
        sta     $03F3
        eor     #$A5
        sta     $03F4
        sta     $FFFB
        sta     $FFFD
        sta     $FFFF
        lda     #$02
        sta     $74
        lda     #$01
        sta     $6B
        lda     #$04
        sta     CURRENT_FILE_INDEX
; Load the first group of modules through B's $9800 file loader.
BOOT_LOAD_BASE_MODULES:  ldy     CURRENT_FILE_INDEX
        jsr     B_LOAD_MODULE
        bcc     BOOT_BASE_MODULE_LOADED
        jmp     BOOT_REPORT_LOAD_ERROR

BOOT_BASE_MODULE_LOADED:  dec     CURRENT_FILE_INDEX
        bpl     BOOT_LOAD_BASE_MODULES
        lda     #$0B
        sta     CURRENT_FILE_INDEX
; Load the second module group; one module is moved into language-card RAM.
BOOT_LOAD_AUX_MODULES:  ldy     CURRENT_FILE_INDEX
        jsr     B_LOAD_MODULE
        bcc     BOOT_AUX_MODULE_LOADED
        jmp     BOOT_REPORT_LOAD_ERROR

BOOT_AUX_MODULE_LOADED:  sec
        lda     CURRENT_FILE_INDEX
        sbc     #$05
        pha
        cmp     #$01
        bne     BOOT_COPY_SELECTED_AUX_MODULE
        lda     #$00
        sta     $8DFA
        sta     $8DFC
        sta     $8DFE
        lda     #$1F
        eor     #$A5
        sta     $8DFB
        sta     $8DFD
        sta     $8DFF
        pla
        pha
BOOT_COPY_SELECTED_AUX_MODULE:  tay
        sta     $C005
        jsr     COPY_MODULE_TO_AUX
        sta     $C004
        pla
        cmp     #$01
        bne     BOOT_ADVANCE_AUX_MODULE
        ldy     #$00
; Install the resident C service entry pages at $D200-$D3FF.
BOOT_COPY_RESIDENT_C_BYTE:  lda     $6000,y
        sta     $D200,y
        lda     $6100,y
        sta     $D300,y
        iny
        bne     BOOT_COPY_RESIDENT_C_BYTE
BOOT_ADVANCE_AUX_MODULE:  dec     CURRENT_FILE_INDEX
        lda     CURRENT_FILE_INDEX
        cmp     #$05
        bcs     BOOT_LOAD_AUX_MODULES
        jsr     INIT_GAME_STATE
        jsr     C_COPY_2200_TO_AUX_D400
        jmp     B_ENTER_INTRO

; Restore the normal memory map and report a load error.
BOOT_REPORT_LOAD_ERROR:  sta     ERROR_CODE
        sta     $C000
        sta     $C00C
        sta     $C008
        sta     $C004
        lda     $C082
        lda     $C054
        lda     $C051
        ldy     #$00
; Restore zero page before using firmware text output for the error report.
BOOT_RESTORE_ZERO_PAGE:  lda     $1D00,y
        sta     ZERO_PAGE_BASE,y
        iny
        bne     BOOT_RESTORE_ZERO_PAGE
        lda     #$00
        sta     $20
        sta     $22
        lda     #$28
        sta     $21
        lda     #$18
        sta     $23
        jsr     ROM_HOME
        lda     #$05
        sta     $24
        lda     #$0A
        ldx     #<BOOT_ERROR_MESSAGE
        ldy     #>BOOT_ERROR_MESSAGE
        jsr     PRINT_MESSAGE
        lda     ERROR_CODE
        jsr     ROM_PRBYTE
        lda     #$0A
        ldx     #<BOOT_ERROR_FILE_MESSAGE
        ldy     #>BOOT_ERROR_FILE_MESSAGE
        jsr     PRINT_MESSAGE
        lda     CURRENT_FILE_INDEX
        jsr     ROM_PRBYTE
        jsr     READ_KEY
BOOT_EXIT_TO_PRODOS:  lda     $C082
        jmp     (RESET_VECTOR)

; Copy whole 256-byte pages from $6000 into auxiliary RAM. The destination
; high byte and page count come from the tables at $2212 and $2219.
COPY_MODULE_TO_AUX:  lda     #$60
        sta     $C5
        lda     BOOT_AUX_DEST_PAGES,y
        sta     $CF
        ldx     BOOT_AUX_PAGE_COUNTS,y
        ldy     #$00
        sty     $C4
        sty     $CE
BOOT_COPY_AUX_BYTE:  lda     ($C4),y
        sta     ($CE),y
        iny
        bne     BOOT_COPY_AUX_BYTE
        inc     $C5
        inc     $CF
        dex
        bne     BOOT_COPY_AUX_BYTE
        rts

; Destination high bytes and page counts indexed by module number.
BOOT_AUX_DEST_PAGES:  .byte   $70, $20, $50, $60, $80, $85, $94
BOOT_AUX_PAGE_COUNTS:  .byte   $08, $2E, $10, $10, $05, $0F, $0E
WARN_RAM_DISK:  jsr     ROM_HOME
        lda     #$08
        ldx     #<BOOT_RAM_WARNING_MESSAGE
        ldy     #>BOOT_RAM_WARNING_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        lda     #$09
        ldx     #<BOOT_RAM_DAMAGE_MESSAGE
        ldy     #>BOOT_RAM_DAMAGE_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        lda     #$0C
        ldx     #<BOOT_CONTINUE_MESSAGE
        ldy     #>BOOT_CONTINUE_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        lda     #$0D
        ldx     #<BOOT_QUIT_MESSAGE
        ldy     #>BOOT_QUIT_MESSAGE
        jsr     PRINT_CENTERED_MESSAGE
        jsr     READ_KEY
        cmp     #$1B
        bne     BOOT_CONTINUE_AFTER_RAM_WARNING
        jsr     PRODOS_MLI
        .byte   $65             ; QUIT
        .word   BOOT_QUIT_PARAMS ; parameter list
        jmp     BOOT_EXIT_TO_PRODOS

BOOT_CONTINUE_AFTER_RAM_WARNING:  lda     BOOT_RAM_OPEN_REF
        jsr     CLOSE_FILE
        bne     BOOT_RAM_WARNING_CLOSE_FAILED
        jmp     BOOT_SET_PREFIX

BOOT_RAM_WARNING_CLOSE_FAILED:  jmp     BOOT_REPORT_LOAD_ERROR

; An absent /ram/ ($44) or two zero bytes at I/O buffer offsets $25/$26
; lets startup proceed. Other results request the overwrite warning.
CHECK_RAM_DISK:  jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   BOOT_RAM_OPEN_PARAMS ; parameter list
        bne     BOOT_RAM_OPEN_ERROR
        ldy     #$25
        lda     $0800,y
        bne     BOOT_RAM_DISK_NOT_EMPTY
        iny
        lda     $0800,y
        bne     BOOT_RAM_DISK_NOT_EMPTY
        lda     BOOT_RAM_OPEN_REF
        jsr     CLOSE_FILE
        bcc     BOOT_RAM_DISK_OK
        jmp     BOOT_REPORT_LOAD_ERROR

BOOT_RAM_DISK_OK:  clc
        rts

BOOT_RAM_OPEN_ERROR:  cmp     #$44
        beq     BOOT_RAM_DISK_OK
BOOT_RAM_DISK_NOT_EMPTY:  sec
        rts

; OPEN B and READ it at $9800. A successful READ or status $4C proceeds to
; CLOSE; every other failure returns with carry set.
LOAD_RESIDENT_B:  jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   BOOT_B_OPEN_PARAMS ; parameter list
        beq     BOOT_B_OPEN_SUCCEEDED
BOOT_B_LOAD_FAILED:  sec
        rts

BOOT_B_OPEN_SUCCEEDED:  lda     BOOT_B_OPEN_REF
        sta     BOOT_B_READ_REF
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   BOOT_B_READ_PARAMS ; parameter list
        bcc     BOOT_B_CLOSE_AFTER_READ
        cmp     #$4C
        bne     BOOT_B_LOAD_FAILED
BOOT_B_CLOSE_AFTER_READ:  lda     #$00
        jsr     CLOSE_FILE
        bcs     BOOT_B_LOAD_FAILED
        rts

; ProDOS OPEN and READ parameter blocks for the B loader at $9800.
BOOT_B_OPEN_PARAMS:  .byte   $03             ; OPEN: three parameters
        .word   BOOT_B_PATH          ; pathname
        .word   $0800          ; I/O buffer
BOOT_B_OPEN_REF:  .byte   $00             ; returned reference number
BOOT_B_READ_PARAMS:  .byte   $04             ; READ: four parameters
BOOT_B_READ_REF:  .byte   $00             ; reference number
        .word   $9800          ; destination
        .word   $0600          ; requested byte count
        .word   $0000          ; transferred byte count
BOOT_B_PATH:  .byte   $01, 'b', $00  ; length-prefixed pathname plus pad
; OPEN A and request up to 8 KiB of splash data at $4000.
LOAD_SPLASH_A:  jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   BOOT_A_OPEN_PARAMS ; parameter list
        bcc     BOOT_A_OPEN_SUCCEEDED
BOOT_A_LOAD_FAILED:  sec
        rts

BOOT_A_OPEN_SUCCEEDED:  lda     BOOT_A_OPEN_REF
        sta     BOOT_A_READ_REF
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   BOOT_A_READ_PARAMS ; parameter list
        bcc     BOOT_A_CLOSE_AFTER_READ
        cmp     #$4C
        bne     BOOT_A_LOAD_FAILED
BOOT_A_CLOSE_AFTER_READ:
        lda     #$00
        jsr     CLOSE_FILE
        bcs     BOOT_A_LOAD_FAILED
        rts

; OPEN and READ parameter blocks for the A splash page at $4000.
BOOT_A_OPEN_PARAMS:  .byte   $03
        .word   BOOT_A_PATH          ; pathname
        .word   $0800          ; I/O buffer
BOOT_A_OPEN_REF:  .byte   $00             ; returned reference number
BOOT_A_READ_PARAMS:  .byte   $04
BOOT_A_READ_REF:  .byte   $00             ; reference number
        .word   $4000          ; destination
        .word   $2000          ; requested byte count
        .word   $0000          ; transferred byte count
BOOT_A_PATH:  .byte   $01, 'a', $00
BOOT_SET_PREFIX_PARAMS:  .byte   $01             ; SET_PREFIX parameter count
        .word   BOOT_PREFIX_PATH
; Set bit A in the table at $BF58. No local caller has been identified.
BOOT_SET_BF58_BIT:  tax
        lsr     a
        lsr     a
        lsr     a
        tay
        txa
        and     #$07
        tax
        lda     #$80
BOOT_SHIFT_BF58_BIT:  dex
        bmi     BOOT_STORE_BF58_BIT
        lsr     a
        jmp     BOOT_SHIFT_BF58_BIT

BOOT_STORE_BF58_BIT:  ora     $BF58,y
        sta     $BF58,y
        rts

; A is the text row; X/Y point to a NUL-terminated ASCII message. Print it
; with the high bit set for Apple II text output.
PRINT_MESSAGE:  stx     $C2
        sty     $C3
        sta     $25
BOOT_PRINT_FROM_POINTER:  jsr     ROM_VTAB
        ldy     #$00
BOOT_PRINT_NEXT_CHARACTER:  lda     ($C2),y
        beq     BOOT_PRINT_DONE
        ora     #$80
        jsr     ROM_COUT
        iny
        bne     BOOT_PRINT_NEXT_CHARACTER
BOOT_PRINT_DONE:  rts

; Retained alternate entry with a fixed text row of ten.
PRINT_CENTERED_MESSAGE_ROW_10:  lda     #$0A
; Count the message and set column $24 to 19 minus half its length.
PRINT_CENTERED_MESSAGE:  sta     $25
        stx     $C2
        sty     $C3
        ldy     #$00
BOOT_COUNT_MESSAGE_CHARACTERS:  lda     ($C2),y
        beq     BOOT_SET_CENTERED_COLUMN
        iny
        bne     BOOT_COUNT_MESSAGE_CHARACTERS
BOOT_SET_CENTERED_COLUMN:  tya
        lsr     a
        sta     $5E
        sec
        lda     #$13
        sbc     $5E
        sta     $24
        jmp     BOOT_PRINT_FROM_POINTER

; Two entry points for clearing either 8 KiB HGR page. The $2C BIT opcode
; consumes the following LDA immediate when entering page 1.
BOOT_CLEAR_HGR_PAGE1:  lda     #$20
        .byte   $2C
BOOT_CLEAR_HGR_PAGE2:  lda     #$40
        sta     $C3
        ldx     #$20
        ldy     #$00
        sty     $C2
        lda     #$80
BOOT_CLEAR_HGR_NEXT_BYTE:  sta     ($C2),y
        iny
        bne     BOOT_CLEAR_HGR_NEXT_BYTE
        inc     $C3
        dex
        bne     BOOT_CLEAR_HGR_NEXT_BYTE
        rts

; Wait for a key and return its low seven bits.
READ_KEY:  bit     $C010
BOOT_WAIT_FOR_KEY:  lda     $C000
        bpl     BOOT_WAIT_FOR_KEY
        bit     $C010
        and     #$7F
        rts

CLOSE_FILE:  sta     BOOT_CLOSE_REF
        jsr     PRODOS_MLI
        .byte   $CC             ; CLOSE
        .word   BOOT_CLOSE_PARAMS          ; parameter list
        rts

; CLOSE, QUIT, and OPEN(/ram/) parameter blocks.
BOOT_CLOSE_PARAMS:  .byte   $01             ; CLOSE parameter count
BOOT_CLOSE_REF:  .byte   $00             ; reference number, set by caller
BOOT_QUIT_PARAMS:  .byte   $04, $00, $00, $00, $00, $00, $00
BOOT_RAM_OPEN_PARAMS:  .byte   $03             ; OPEN parameter count
        .word   BOOT_RAM_PATH
        .word   $0800          ; I/O buffer
BOOT_RAM_OPEN_REF:  ; ProDOS parameter bytes and NUL terminated loader messages
        .byte   $00
BOOT_RAM_PATH: .byte $04
        ; $238C
        .asciiz "/ram/"
        ; $2392
BOOT_RAM_WARNING_MESSAGE: .asciiz "Warning:  volume /RAM is not empty"
        ; $23B5
BOOT_RAM_DAMAGE_MESSAGE: .asciiz "and will be damaged if you proceed."
        ; $23D9
BOOT_CONTINUE_MESSAGE: .asciiz "Press <SPACE> to continue"
        ; $23F3
BOOT_QUIT_MESSAGE: .asciiz "or <ESC> to quit"
        ; $2404
BOOT_ERROR_MESSAGE: .asciiz "Error "
        ; $240B
BOOT_ERROR_FILE_MESSAGE: .asciiz " on file "
BOOT_PREFIX_PATH: .byte $0D
        ; $2416
        .asciiz "/CARMEN.WORLD"
        ; $2424
BOOT_TITLE_MESSAGE: .asciiz "WHERE IN THE WORLD IS CARMEN SANDIEGO?"
        ; $244B
BOOT_MEMORY_MESSAGE: .asciiz "REQUIRES 128K OF MEMORY TO EXECUTE"
CURRENT_FILE_INDEX:  .byte $00
ERROR_CODE:          .byte $00
SELECT_HGR_PAGE2:  lda     $C050
        lda     $C052
        lda     $C055
        lda     $C057
        rts

INIT_GAME_STATE:  lda     $5A
        sta     $59
        lda     #$00
        sta     $60
        sta     $BE
        sta     $A2
        sta     $6B
        lda     #$01
        sta     $18
        sta     $99
        sta     $BB
        lda     #$02
        sta     $1A
        lda     #$27
        sta     $BF
        sta     $18
        lda     #$FF
        sta     $01
        rts

; Retained speaker tone helper. Its delay immediate is patched from A;
; no local caller has been identified.
BOOT_PLAY_TONE_BURST:  ldy     #$0A
        lda     #$50
        sta     BOOT_TONE_DELAY_VALUE
BOOT_TONE_NEXT_TICK:  lda     $C030
; The delay-loop immediate operand is patched at $24AD above.
BOOT_TONE_DELAY_LOAD:  lda     #$00
BOOT_TONE_DELAY_VALUE   := BOOT_TONE_DELAY_LOAD + 1
        jsr     DELAY_LOOP
        dey
        bne     BOOT_TONE_NEXT_TICK
        rts

DELAY_LOOP:  sec
BOOT_DELAY_OUTER_LOOP:  pha
BOOT_DELAY_INNER_LOOP:  sbc     #$01
        bne     BOOT_DELAY_INNER_LOOP
        pla
        sbc     #$01
        bne     BOOT_DELAY_OUTER_LOOP
        rts
