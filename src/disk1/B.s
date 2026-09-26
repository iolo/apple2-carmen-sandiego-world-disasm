; disk1/B: $9800, 1146 bytes, sha256 68864657be18ca2bae058fbe482f86747f7fc431d0b261c9f488991c1c158cf4
; Loader services at $9800. The first 24 bytes are an eight-entry jump table.
; WORLD.SYSTEM calls entry $9800 with Y selecting a module; later code uses
; other entries to load overlays and transfer control to $6000.
; ProDOS MLI calls at $BF00 carry inline function and parameter bytes.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

OVERLAY_ENTRY           := $6000
N_PROMPT_FOR_DISK       := $805B
PRODOS_MLI           := $BF00
C_COPY_2200_TO_AUX_D400           := $D20C
ROM_VTAB           := $FC22
ROM_HOME           := $FC58
ROM_COUT           := $FDED
; Entry $9800: load the module selected by Y.
B_LOAD_MODULE:
        jmp     B_LOAD_MODULE_IMPL

B_ENTER_INTRO:
        jmp     B_ENTER_INTRO_IMPL

B_ENTER_GAME:
        jmp     B_ENTER_GAME_IMPL

B_LOAD_S2_RECORD:
        jmp     B_LOAD_S2_RECORD_IMPL

B_LOAD_S2_TEXT:
        jmp     B_LOAD_S2_TEXT_IMPL

B_SAVE_F:
        jmp     B_SAVE_F_IMPL

B_SAVE_G:
        jmp     B_SAVE_G_IMPL

B_SAVE_H:
        jmp     B_SAVE_H_IMPL

; Runtime state, not executable BRK instructions.
B_ACTIVE_MODULE_INDEX: .byte $00
B_LAST_MLI_ERROR:     .byte $00
        .res 2, $00
; Look up file metadata, then issue ProDOS MLI calls to open/read the module.
B_LOAD_MODULE_IMPL:  sta     $C008
        lda     $C082
        lda     B_MODULE_PATH_LO,y
        sta     B_OPEN_PATH_LO
        lda     B_MODULE_PATH_HI,y
        sta     B_OPEN_PATH_HI
        lda     B_MODULE_BUFFER_PAGE,y
        sta     $C5
        sty     B_ACTIVE_MODULE_INDEX
        jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   B_OPEN_PARAMS ; parameter block
        beq     B_MODULE_OPENED
B_MODULE_LOAD_FAILED:  sec
        sta     B_LAST_MLI_ERROR
        jmp     B_RESTORE_MEMORY_MAPPING

B_MODULE_OPENED:  lda     B_OPEN_REF
        sta     B_READ_REF
B_READ_MODULE_PAGE:  lda     $C5
        sta     B_READ_DEST_PAGE
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_READ_PARAMS ; parameter block
        beq     B_ADVANCE_MODULE_PAGE
        sta     B_LAST_MLI_ERROR
        lda     B_OPEN_REF
        jsr     B_CLOSE_FILE
        bne     B_MODULE_LOAD_FAILED
        lda     B_LAST_MLI_ERROR
        cmp     #$4C
        bne     B_MODULE_LOAD_FAILED
        clc
        jmp     B_RESTORE_MEMORY_MAPPING

B_ADVANCE_MODULE_PAGE:  clc
        lda     $C5
        adc     #$01
        sta     $C5
        jmp     B_READ_MODULE_PAGE

B_RESTORE_MEMORY_MAPPING:  sta     $C009
        ldx     $C083
        ldx     $C083
        rts

B_REPORT_SAVE_ERROR:  sta     B_LAST_MLI_ERROR
        sta     $C009
        ldx     $C083
        ldx     $C083
        ldx     #$01
        jsr     N_PROMPT_FOR_DISK
        sta     $C008
        lda     $C082
        rts

; Copy A whole pages from page X to page Y (A=0 copies 256 pages).
; Uses the caller's memory mapping; no identified local caller.
B_COPY_WHOLE_PAGES:
        stx     $C5
        sty     $CF
        tax
        ldy     #$00
        sty     $C4
        sty     $CE
B_COPY_PAGES_LOOP:  lda     ($C4),y
        sta     ($CE),y
        iny
        bne     B_COPY_PAGES_LOOP
        inc     $C5
        inc     $CF
        dex
        bne     B_COPY_PAGES_LOOP
        rts

B_ENTER_INTRO_IMPL:  ldy     #$0F
        jsr     B_LOAD_MODULE_IMPL
        bcs     B_RETRY_ENTER_INTRO
        ldy     #$10
        jsr     B_LOAD_MODULE_IMPL
        bcs     B_RETRY_ENTER_INTRO
        jmp     OVERLAY_ENTRY

B_RETRY_ENTER_INTRO:  jsr     B_PROMPT_FOR_DISK
        jmp     B_ENTER_INTRO_IMPL

B_ENTER_GAME_IMPL:  jsr     C_COPY_2200_TO_AUX_D400
        ldy     #$0C
        jsr     B_LOAD_MODULE_IMPL
        bcc     B_START_GAME_OVERLAY
        jsr     B_PROMPT_FOR_DISK
        jmp     B_ENTER_GAME_IMPL

B_START_GAME_OVERLAY:  jmp     OVERLAY_ENTRY

B_ACTIVE_S2_RECORD: .byte $00
B_LOAD_S2_RECORD_IMPL:  sta     B_ACTIVE_S2_RECORD
        sta     $C008
        lda     $C082
B_RETRY_S2_RECORD:  lda     B_ACTIVE_S2_RECORD
        jsr     B_SEEK_AND_READ_S2_HEADER
        sec
        txa
        sbc     #$02
        sta     B_S2_TEXT_LENGTH_LO
        bcs     B_READ_S2_TEXT
        dey
B_READ_S2_TEXT:  sty     B_S2_TEXT_LENGTH_HI
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_S2_TEXT_READ_PARAMS ; parameter block
        bcc     B_READ_S2_IMAGE
B_RETRY_S2_AFTER_ERROR:  jsr     B_REPORT_S2_READ_ERROR
        jmp     B_RETRY_S2_RECORD

; Index entries are three-byte file offsets. Subtract the current entry
; from the next, then subtract the text/image boundary at $1DC0 to get the
; compressed image length for the second READ.
B_READ_S2_IMAGE:  clc
        lda     B_ACTIVE_S2_RECORD
        sta     $5E
        asl     a
        adc     $5E
        tax
        adc     #$03
        tay
        sec
        lda     $1D00,y
        sbc     $1D00,x
        sta     B_S2_IMAGE_LENGTH_LO
        iny
        inx
        lda     $1D00,y
        sbc     $1D00,x
        sta     B_S2_IMAGE_LENGTH_HI
        sec
        lda     B_S2_IMAGE_LENGTH_LO
        sbc     $1DC0
        sta     B_S2_IMAGE_LENGTH_LO
        lda     B_S2_IMAGE_LENGTH_HI
        sbc     $1DC1
        sta     B_S2_IMAGE_LENGTH_HI
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_S2_IMAGE_READ_PARAMS ; parameter block
        bcs     B_RETRY_S2_AFTER_ERROR
        lda     #$00
        jsr     B_CLOSE_FILE
        bcs     B_RETRY_S2_AFTER_ERROR
        clc
        lda     #$00
        adc     B_S2_IMAGE_TRANSFERRED_LO
        sta     $C4
        lda     #$11
        adc     B_S2_IMAGE_TRANSFERRED_HI
        sta     $C5
        lda     #$00
        tay
        sta     ($C4),y
        jmp     B_RESTORE_MEMORY_MAPPING

B_LOAD_S2_TEXT_IMPL:  sta     B_ACTIVE_S2_RECORD
        sta     $C008
        ldx     $C082
B_RETRY_S2_TEXT_ONLY:  lda     B_ACTIVE_S2_RECORD
        jsr     B_SEEK_AND_READ_S2_HEADER
        sec
        txa
        sbc     #$02
        sta     B_S2_TEXT_LENGTH_LO
        bcs     B_READ_S2_TEXT_ONLY
        dey
B_READ_S2_TEXT_ONLY:  sty     B_S2_TEXT_LENGTH_HI
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_S2_TEXT_READ_PARAMS ; parameter block
        bcc     B_CLOSE_S2_TEXT_ONLY
        jsr     B_REPORT_S2_READ_ERROR
        jmp     B_RETRY_S2_TEXT_ONLY

B_CLOSE_S2_TEXT_ONLY:  lda     #$00
        jsr     B_CLOSE_FILE
        jmp     B_RESTORE_MEMORY_MAPPING

B_REPORT_S2_READ_ERROR:  sta     B_LAST_MLI_ERROR
        lda     #$00
        jsr     B_CLOSE_FILE
        sta     $C009
        ldx     $C083
        ldx     $C083
        ldx     $BB
        jsr     N_PROMPT_FOR_DISK
        sta     $C008
        lda     $C082
        rts

B_SEEK_S2_RECORD: .byte $00
; Seek to one S2 record and read its two-byte text/image boundary and
; tokenized text. Return that boundary in X/Y.
B_SEEK_AND_READ_S2_HEADER:  sta     B_SEEK_S2_RECORD
B_RETRY_S2_SEEK:  lda     B_SEEK_S2_RECORD
        jsr     B_OPEN_S2_AND_READ_INDEX
        bcc     B_SET_S2_RECORD_MARK
B_RETRY_S2_SEEK_AFTER_ERROR:  jsr     B_REPORT_S2_READ_ERROR
        jmp     B_RETRY_S2_SEEK

B_SET_S2_RECORD_MARK:  ldx     #$00
        lda     B_SEEK_S2_RECORD
        sta     $5E
        clc
        asl     a
        adc     $5E
        tay
B_COPY_S2_INDEX_OFFSET:  lda     $1D00,y
        sta     B_S2_SET_MARK_OFFSET,x
        iny
        inx
        cpx     #$03
        bcc     B_COPY_S2_INDEX_OFFSET
        jsr     PRODOS_MLI
        .byte   $CE             ; SET_MARK
        .word   B_S2_SET_MARK_PARAMS          ; parameter block
        bcs     B_RETRY_S2_SEEK_AFTER_ERROR
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_S2_BOUNDARY_READ_PARAMS ; parameter block
        bcs     B_RETRY_S2_SEEK_AFTER_ERROR
        ldx     $1DC0
        ldy     $1DC1
        rts

; OPEN the S2 file and read its 192-byte, 24-bit record index into $1D00.
B_OPEN_S2_AND_READ_INDEX:  sta     $C009
        ldx     #$02
        stx     $BB
        sta     $C008
        ldx     #<B_S2_PATH
        ldy     #>B_S2_PATH
        stx     B_S2_OPEN_PATH_LO
        sty     B_S2_OPEN_PATH_HI
        jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   B_S2_OPEN_PARAMS ; parameter block
        bcs     B_RETRY_S2_SEEK_AFTER_ERROR
        lda     B_S2_OPEN_REF
        sta     B_S2_INDEX_READ_REF
        sta     B_S2_BOUNDARY_READ_REF
        sta     B_S2_TEXT_READ_REF
        sta     B_S2_IMAGE_READ_REF
        sta     B_S2_SET_MARK_REF
        jsr     PRODOS_MLI
        .byte   $CA             ; READ
        .word   B_S2_INDEX_READ_PARAMS ; parameter block
        bcc     B_S2_INDEX_READ_COMPLETE
        jmp     B_RETRY_S2_SEEK_AFTER_ERROR

B_S2_INDEX_READ_COMPLETE:  rts

; S2 reads: 192-byte record index, two-byte text/image boundary,
; text at $A000, then the compressed image at $1100.
B_S2_INDEX_READ_PARAMS:  .byte   $04             ; READ index: parameter count
B_S2_INDEX_READ_REF:  .byte   $00             ; reference number
        .word   $1D00          ; destination
        .word   $00C0          ; requested bytes
        .word   $0000          ; transferred bytes
B_S2_BOUNDARY_READ_PARAMS:  .byte   $04             ; READ record boundary
B_S2_BOUNDARY_READ_REF:  .byte   $00             ; reference number
        .word   $1DC0
        .word   $0002
        .word   $0000
B_S2_TEXT_READ_PARAMS:  .byte   $04             ; READ tokenized text
B_S2_TEXT_READ_REF:  .byte   $00             ; reference number
        .word   $A000
B_S2_TEXT_LENGTH_LO:  .byte   $00             ; requested byte count, low
B_S2_TEXT_LENGTH_HI:  .byte   $00             ; requested byte count, high
        .word   $0000          ; transferred bytes
B_S2_IMAGE_READ_PARAMS:  .byte   $04             ; READ city image
B_S2_IMAGE_READ_REF:  .byte   $00             ; reference number
        .word   $1100
B_S2_IMAGE_LENGTH_LO:  .byte   $00             ; requested byte count, low
B_S2_IMAGE_LENGTH_HI:  .byte   $00             ; requested byte count, high
B_S2_IMAGE_TRANSFERRED_LO:  .byte   $00             ; transferred byte count, low
B_S2_IMAGE_TRANSFERRED_HI:  .byte   $00             ; transferred byte count, high
B_S2_OPEN_PARAMS:  .byte   $03             ; OPEN parameter count
B_S2_OPEN_PATH_LO:  .byte   $00             ; pathname pointer, low
B_S2_OPEN_PATH_HI:  .byte   $00             ; pathname pointer, high
        .word   $0800          ; I/O buffer
B_S2_OPEN_REF:  .byte   $00             ; returned reference number
B_S2_SET_MARK_PARAMS:  .byte   $02             ; SET_MARK parameter count
B_S2_SET_MARK_REF:  .byte   $00             ; reference number
B_S2_SET_MARK_OFFSET:  .byte   $00,$00,$00    ; 24-bit file position
B_S2_PATH:  .byte   24
        .byte   "/carmen.world.s2/data.s2",$00
B_SAVE_G_IMPL:  ldx     #<B_FILE_G
        ldy     #>B_FILE_G
        stx     B_SAVE_FG_PATH_LO
        sty     B_SAVE_FG_PATH_HI
        ldy     #$0D
        bne     B_SAVE_FG_SELECTED
B_SAVE_F_IMPL:  ldx     #<B_FILE_F
        ldy     #>B_FILE_F
        stx     B_SAVE_FG_PATH_LO
        sty     B_SAVE_FG_PATH_HI
        ldy     #$0C
B_SAVE_FG_SELECTED:  sty     B_SAVE_FG_BUFFER_PAGE
        sta     $C008
        lda     $C082
B_RETRY_SAVE_FG:  jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   B_SAVE_FG_OPEN_PARAMS ; parameter block
        bcc     B_WRITE_FG
        jsr     B_REPORT_SAVE_ERROR
        jmp     B_RETRY_SAVE_FG

B_WRITE_FG:  lda     B_SAVE_FG_OPEN_REF
        sta     B_SAVE_FG_WRITE_REF
        jsr     PRODOS_MLI
        .byte   $CB             ; WRITE
        .word   B_SAVE_FG_WRITE_PARAMS ; parameter block
        php
        pha
        lda     #$00
        jsr     B_CLOSE_FILE
        pla
        plp
        bcc     B_SAVE_FG_DONE
        jsr     B_REPORT_SAVE_ERROR
        jmp     B_RETRY_SAVE_FG

B_SAVE_FG_DONE:  jmp     B_RESTORE_MEMORY_MAPPING

; OPEN F or G, then WRITE one page from $0C00 or $0D00.
B_SAVE_FG_OPEN_PARAMS:  .byte   $03             ; OPEN parameter count
B_SAVE_FG_PATH_LO:  .byte   $00             ; pathname pointer, low
B_SAVE_FG_PATH_HI:  .byte   $00             ; pathname pointer, high
        .word   $0800
B_SAVE_FG_OPEN_REF:  .byte   $00             ; returned reference number
B_SAVE_FG_WRITE_PARAMS:  .byte   $04             ; WRITE parameter count
B_SAVE_FG_WRITE_REF:  .byte   $00             ; reference number
        .byte   $00             ; buffer address low
B_SAVE_FG_BUFFER_PAGE:  .byte   $00             ; buffer page, selected by caller
        .word   $0100          ; requested bytes
        .word   $0000          ; transferred bytes
B_SAVE_H_IMPL:  sta     $C008
        lda     $C082
B_RETRY_SAVE_H:  jsr     PRODOS_MLI
        .byte   $C8             ; OPEN
        .word   B_SAVE_H_OPEN_PARAMS ; parameter block
        bcc     B_WRITE_H
        jsr     B_REPORT_SAVE_ERROR
        jmp     B_RETRY_SAVE_H

B_RETRY_SAVE_H_AFTER_WRITE_ERROR:  lda     #$00
        jsr     B_CLOSE_FILE
        jsr     B_REPORT_SAVE_ERROR
        jmp     B_RETRY_SAVE_H

B_WRITE_H:  lda     B_SAVE_H_OPEN_REF
        sta     B_SAVE_H_WRITE_REF
        jsr     PRODOS_MLI
        .byte   $CB             ; WRITE
        .word   B_SAVE_H_WRITE_PARAMS ; parameter block
        bcs     B_RETRY_SAVE_H_AFTER_WRITE_ERROR
        lda     #$00
        jsr     B_CLOSE_FILE
        jmp     B_RESTORE_MEMORY_MAPPING

; OPEN H, then WRITE its thirteen $1100-$1DFF case-state pages.
B_SAVE_H_OPEN_PARAMS:  .byte   $03             ; OPEN parameter count
        .word   B_FILE_H          ; pathname for H
        .word   $0800
B_SAVE_H_OPEN_REF:  .byte   $00             ; returned reference number
B_SAVE_H_WRITE_PARAMS:  .byte   $04             ; WRITE parameter count
B_SAVE_H_WRITE_REF:  .byte   $00             ; reference number
        .word   $1100          ; source buffer
        .word   $0D00          ; requested bytes
        .word   $0000          ; transferred bytes
B_PROMPT_FOR_DISK:  ldy     #$00
B_COPY_LANGUAGE_CARD_PAGE:  lda     $D000,y
        sta     $9700,y
        iny
        bne     B_COPY_LANGUAGE_CARD_PAGE
        sta     $C008
        sta     $C004
        lda     $C082
        lda     $C054
        lda     $C051
B_RESTORE_ZERO_PAGE:  lda     $9700,y
        sta     $00,y
        iny
        bne     B_RESTORE_ZERO_PAGE
        jsr     ROM_HOME
        ldy     #$00
        sty     $AC
B_DRAW_PROMPT_LINE:  ldx     B_PROMPT_TEXT_LO,y
        lda     B_PROMPT_TEXT_HI,y
        tay
        clc
        lda     $AC
        asl     a
        adc     #$06
        jsr     B_CENTER_PROMPT_STRING
        inc     $AC
        ldy     $AC
        cpy     #$04
        bcc     B_DRAW_PROMPT_LINE
B_WAIT_FOR_DISK_KEY:  lda     $C000
        bpl     B_WAIT_FOR_DISK_KEY
        bit     $C010
        lda     $C050
        lda     $C052
        lda     $C055
        lda     $C057
        sta     $C009
        lda     $C083
        lda     $C083
        rts

; Four NUL-terminated strings printed by the disk-insertion prompt.
B_PROMPT_TEXT_LO:  .byte   <PROMPT_INSERT,<PROMPT_TITLE,<PROMPT_GAME,<PROMPT_RETURN
B_PROMPT_TEXT_HI:  .byte   >PROMPT_INSERT,>PROMPT_TITLE,>PROMPT_GAME,>PROMPT_RETURN
        stx     $C2
        sty     $C3
        sta     $25
B_PRINT_PROMPT_STRING:  jsr     ROM_VTAB
        ldy     #$00
B_PRINT_PROMPT_CHAR:  lda     ($C2),y
        beq     B_PROMPT_STRING_DONE
        ora     #$80
        jsr     ROM_COUT
        iny
        bne     B_PRINT_PROMPT_CHAR
B_PROMPT_STRING_DONE:  rts

B_CENTER_PROMPT_STRING:  sta     $25
        stx     $C2
        sty     $C3
        ldy     #$00
B_COUNT_PROMPT_CHARS:  lda     ($C2),y
        beq     B_PROMPT_LENGTH_READY
        iny
        bne     B_COUNT_PROMPT_CHARS
B_PROMPT_LENGTH_READY:  tya
        lsr     a
        sta     $5E
        sec
        lda     #$13
        sbc     $5E
        sta     $24
        jmp     B_PRINT_PROMPT_STRING

        ; Disk insertion prompt
PROMPT_INSERT: .asciiz "Please insert"
PROMPT_TITLE:  .asciiz "WHERE IN THE WORLD"
PROMPT_GAME:   .asciiz "IS CARMEN SANDIEGO?"
PROMPT_RETURN: .asciiz "and press <RETURN>"
B_CLOSE_FILE:  sta     B_CLOSE_REF
        jsr     PRODOS_MLI
        .byte   $CC             ; CLOSE
        .word   B_CLOSE_PARAMS          ; parameter block
        rts

; Shared CLOSE, OPEN, and READ parameter blocks.
B_CLOSE_PARAMS:  .byte   $01             ; CLOSE parameter count
B_CLOSE_REF:  .byte   $00             ; reference number
B_OPEN_PARAMS:  .byte   $03             ; OPEN parameter count
B_OPEN_PATH_LO:  .byte   $00             ; pathname pointer low byte, set by loader
B_OPEN_PATH_HI:  .byte   $00             ; pathname pointer high byte
        .word   $0800          ; I/O buffer
B_OPEN_REF:  .byte   $00             ; returned reference number
B_READ_PARAMS:  .byte   $04             ; READ parameter count
B_READ_REF:  .byte   $00             ; reference number
        .byte   $00             ; destination low byte
B_READ_DEST_PAGE:  .byte   $00             ; destination high byte, advanced by loader
        .word   $0100          ; requested byte count
        .word   $0000          ; transferred byte count
; Filename pointers by module number. Each filename below is a
; one-character Pascal string followed by a pad byte.
B_MODULE_PATH_LO:  .byte   <B_FILE_E, <B_FILE_D, <B_FILE_F, <B_FILE_G, <B_FILE_O, <B_FILE_J, <B_FILE_C, <B_FILE_K, <B_FILE_I, <B_FILE_P, <B_FILE_T, <B_FILE_U
B_MODULE_PATH_LO_TAIL:  .byte   <B_FILE_N, <B_FILE_H, <B_FILE_Q, <B_FILE_R, <B_FILE_S
B_MODULE_PATH_HI:  .byte   >B_FILE_E, >B_FILE_D, >B_FILE_F, >B_FILE_G, >B_FILE_O, >B_FILE_J, >B_FILE_C, >B_FILE_K, >B_FILE_I, >B_FILE_P, >B_FILE_T, >B_FILE_U, >B_FILE_N, >B_FILE_H, >B_FILE_Q, >B_FILE_R, >B_FILE_S
; High byte of the first buffer used for each module.
B_MODULE_BUFFER_PAGE:  .byte   $B2, $B9, $0C, $0D, $A7, $60, $60, $60, $60, $60, $60, $60, $60, $11, $1F, $60, $78
; Module index order: E, D, F, G, O, J, C, K, I, P, T, U, N, H, Q, R, S
B_FILE_C:  .byte   $01, 'c', $00
B_FILE_D:  .byte   $01, 'd', $00
B_FILE_E:  .byte   $01, 'e', $00
B_FILE_F:  .byte   $01, 'f', $00
B_FILE_G:  .byte   $01, 'g', $00
B_FILE_H:  .byte   $01, 'h', $00
B_FILE_I:  .byte   $01, 'i', $00
B_FILE_J:  .byte   $01, 'j', $00
B_FILE_K:  .byte   $01, 'k', $00
B_FILE_N:  .byte   $01, 'n', $00
B_FILE_O:  .byte   $01, 'o', $00
B_FILE_P:  .byte   $01, 'p', $00
B_FILE_Q:  .byte   $01, 'q', $00
B_FILE_R:  .byte   $01, 'r', $00
B_FILE_S:  .byte   $01, 's', $00
B_FILE_T:  .byte   $01, 't', $00
B_FILE_U:  .byte   $01, 'u', $00
