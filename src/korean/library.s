; Shared 6502 text/font services for the 128K unenhanced Apple //e.
; Immutable resident main $9200..$96FF, disposable glyph cache at $97E0;
; aux LC bank 1 $D000..$DFFF plus aux $A700. B's TEXT MODE disk-error prompt
; owns main $9700..$97FF while restoring firmware zero page. Each K_FETCH
; recreates the complete cache, so no persistent bytes may be placed there.
; The original game runs with ALTZP on, RAMRD/RAMWRT off, LC bank 2 RAM on.
; Preserve those mappings on return. Font fetch temporarily selects bank 1
; or executes a short bank-2 LC helper while auxiliary reads are enabled.
; Game glyph scratch is non-reentrant; the original game keeps IRQs disabled.
.setcpu "6502"
.segment "CODE"
.include "library-config.inc"

K_TRAIL_MAP = $D900
K_LEAD_OFFSET_LO = $DA00
K_LEAD_OFFSET_HI = $DA70
K_COPY_HELPER = $D100
K_CACHE = $97E0

; Stable public entries. Decoders emulate LDA ($C2/$C6),X for native X=0,
; returning ASCII/control unchanged or $7F with K_PENDING=1 for a glyph.
; They consume the lead byte only; the native caller consumes the trail.
        jmp K_INIT
        jmp K_READ_C2
        jmp K_READ_C6
        jmp K_FETCH
        jmp K_INSTALL_HELPER

K_READ_C2:
        lda #$C2
        bne K_READ_AT
K_READ_C6:
        lda #$C6
K_READ_AT:
        php
        cld
        stx K_SAVED_X
        sty K_SAVED_Y
        sta K_LOAD_FIRST+1
        sta K_LOAD_TRAIL+1
        sta K_ADVANCE_BYTE+1
        cmp #$C6
        bne K_POINTER_SELECTED
        lda $C6
        sta K_SCAN_FIRST_LO
        lda $C7
        sta K_SCAN_FIRST_HI
        lda #$C6
K_POINTER_SELECTED:
        clc
        adc #$01
        sta K_ADVANCE_HIGH+1
        ldy #$00
        sty K_PENDING
K_LOAD_FIRST:
        lda ($C2),y
        sta K_RESULT
        cmp #$90
        bcc K_READ_DONE
        cmp #$FF
        bcs K_BAD_GLYPH
        sec
        sbc #$90
        tax
        lda K_LEAD_OFFSET_HI,x
        cmp #$FF
        beq K_BAD_GLYPH
        jsr K_ADVANCE_SOURCE
K_LOAD_TRAIL:
        lda ($C2),y
        tay
        lda K_TRAIL_MAP,y
        cmp #$FF
        beq K_BAD_GLYPH
        ldy #$00
        sty K_OFFSET_HI
        asl a
        rol K_OFFSET_HI
        asl a
        rol K_OFFSET_HI
        asl a
        rol K_OFFSET_HI
        clc
        adc K_LEAD_OFFSET_LO,x
        sta K_OFFSET_LO
        lda K_OFFSET_HI
        adc K_LEAD_OFFSET_HI,x
        sta K_OFFSET_HI
        cmp #>K_FONT_BYTES
        bcc K_ACCEPT_GLYPH
        bne K_BAD_GLYPH
        lda K_OFFSET_LO
        cmp #<K_FONT_BYTES
        bcs K_BAD_GLYPH
K_ACCEPT_GLYPH:
        lda #$01
        sta K_PENDING
        lda #$7F
        sta K_RESULT
        bne K_READ_DONE
K_BAD_GLYPH:
        lda #$01
        sta K_ERROR
        lda #$00
        sta K_PENDING
        lda #$3F
        sta K_RESULT
K_READ_DONE:
        ldx K_SAVED_X
        ldy K_SAVED_Y
        plp
        lda K_RESULT
        rts

K_ADVANCE_SOURCE:
K_ADVANCE_BYTE:
        inc $C2
        bne K_ADVANCE_DONE
K_ADVANCE_HIGH:
        inc $C3
K_ADVANCE_DONE:
        rts

; Fetch the selected eight scanlines. Return C8/C9 pointing to a native
; 7x8 glyph record. Preserve A/X/Y and carry/decimal/interrupt state.
K_FETCH:
        php
        cld
        pha
        txa
        pha
        tya
        pha
        lda #$00
        sta K_PENDING
        lda #$07
        sta K_CACHE
        lda #$08
        sta K_CACHE+1
        lda K_OFFSET_LO
        sta $C8
        lda K_OFFSET_HI
        cmp #$10
        bcs K_FETCH_AUX_NORMAL
        clc
        adc #$D0
        sta $C9
        lda $C08B
        lda $C08B
        ldy #$07
K_FETCH_LC_ROW:
        lda ($C8),y
        sta K_CACHE+2,y
        dey
        bpl K_FETCH_LC_ROW
        lda $C083
        lda $C083
        jmp K_FETCH_DONE
K_FETCH_AUX_NORMAL:
        sec
        sbc #$10
        clc
        adc #$A7
        sta $C9
        jsr K_COPY_HELPER
K_FETCH_DONE:
        lda #<K_CACHE
        sta $C8
        lda #>K_CACHE
        sta $C9
        pla
        tay
        pla
        tax
        pla
        plp
        rts

; This routine executes from auxiliary LC bank 2, whose mapping is independent
; of RAMRD. It can therefore read aux A700 while writing the main-RAM cache.
K_INSTALL_HELPER:
        ldx #K_HELPER_BYTES-1
K_INSTALL_HELPER_BYTE:
        lda K_HELPER_SOURCE,x
        sta K_COPY_HELPER,x
        dex
        bpl K_INSTALL_HELPER_BYTE
        rts
K_HELPER_SOURCE:
        sta $C003
        ldy #$07
K_HELPER_ROW:
        lda ($C8),y
        sta K_CACHE+2,y
        dey
        bpl K_HELPER_ROW
        sta $C002
        rts
K_HELPER_BYTES = * - K_HELPER_SOURCE
        .assert K_HELPER_BYTES <= 64, error, "LC helper exceeds measured reservation"

; Boot-only installation. The complete KF file is staged at main $6000.
; Install after C, before loading R, so neither overlay is overwritten.
K_INIT:
        php
        cld
        pha
        txa
        pha
        tya
        pha
        ldx #$03
K_PUSH_INIT_ZP:
        lda $C2,x
        pha
        dex
        bpl K_PUSH_INIT_ZP
        jsr K_INSTALL_HELPER
        lda #$00
        sta K_PENDING
        sta K_ERROR
        sta K_HARD_BREAK
        sta $C2
        sta $C4
        lda #$60
        sta $C3
        lda #$D0
        sta $C5
        lda $C08B
        lda $C08B
        ldx #$10
        jsr K_COPY_INIT_PAGES
        lda $C083
        lda $C083
        lda #$70
        sta $C3
        lda #$A7
        sta $C5
        sta $C005
        .if ((K_FONT_BYTES-$1000)/256) > 0
        ldx #((K_FONT_BYTES-$1000)/256)
        jsr K_COPY_INIT_PAGES
        .endif
        .if ((K_FONT_BYTES-$1000) .mod 256) > 0
        ldy #$00
K_COPY_INIT_TAIL:
        lda ($C2),y
        sta ($C4),y
        iny
        cpy #((K_FONT_BYTES-$1000) .mod 256)
        bne K_COPY_INIT_TAIL
        .endif
        sta $C004
        ldx #$00
K_POP_INIT_ZP:
        pla
        sta $C2,x
        inx
        cpx #$04
        bne K_POP_INIT_ZP
        pla
        tay
        pla
        tax
        pla
        plp
        rts
K_COPY_INIT_PAGES:
        ldy #$00
K_COPY_INIT_BYTE:
        lda ($C2),y
        sta ($C4),y
        iny
        bne K_COPY_INIT_BYTE
        inc $C3
        inc $C5
        dex
        bne K_COPY_INIT_BYTE
        rts

K_PENDING: .byte 0
K_ERROR: .byte 0
K_OFFSET_LO: .byte 0
K_OFFSET_HI: .byte 0
K_SCAN_FIRST_LO: .byte 0
K_SCAN_FIRST_HI: .byte 0
K_HARD_BREAK: .byte 0
K_SAVED_X: .byte 0
K_SAVED_Y: .byte 0
K_RESULT: .byte 0
K_PROGRAM_END:
        .assert K_PROGRAM_END <= $9700, error, "Library overlaps B disk-error zero-page staging buffer"
