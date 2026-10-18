; K0 disposable RAM probe at $9200. This is not a translation patch.
; Existing N/R string routines render mixed English and two synthetic Hangul
; characters via temporarily redirected D glyph slots. All four pointer bytes
; are restored before PROBE_DONE. The harness restores CPU and zero page.
; Final multibyte encoding, >256 glyphs and complete font residency remain K4.
.segment "CODE"
.setcpu "6502"
.include "probe-config.inc"

PROBE_ENTRY:
        ; Page 1 is not initialized on the first intro frame. Clear it before
        ; the original XOR renderer draws, so every probe pixel is observable.
        lda #$20
        sta $C1
        lda #$00
        sta $C0
        tay
        ldx #$20
        lda #$80
CLEAR_PAGE_BYTE:
        sta ($C0),y
        iny
        bne CLEAR_PAGE_BYTE
        inc $C1
        dex
        bne CLEAR_PAGE_BYTE
        lda $B95E               ; D code $7E
        sta SAVED_LO_0
        lda $B9CE
        sta SAVED_HI_0
        lda $B95F               ; D code $7F
        sta SAVED_LO_1
        lda $B9CF
        sta SAVED_HI_1
        lda #<GLYPH_HAN
        sta $B95E
        lda #>GLYPH_HAN
        sta $B9CE
        lda #<GLYPH_GEUL
        sta $B95F
        lda #>GLYPH_GEUL
        sta $B9CF
        lda #$01
        sta $74                 ; renderer draws page 1
        lda $C054               ; show page 1
        lda #$08
        sta $72
        sta $91
        lda #$00
        sta $68
        ldx #<PROBE_TEXT
        ldy #>PROBE_TEXT
        lda #$08
        jsr DRAW_STRING
        lda SAVED_LO_0
        sta $B95E
        lda SAVED_HI_0
        sta $B9CE
        lda SAVED_LO_1
        sta $B95F
        lda SAVED_HI_1
        sta $B9CF
PROBE_DONE:
        jmp PROBE_DONE
SAVED_LO_0: .byte 0
SAVED_HI_0: .byte 0
SAVED_LO_1: .byte 0
SAVED_HI_1: .byte 0

; A long mixed line wraps; a forced break and a terminator are also exercised.
PROBE_TEXT:
        .byte "K0 ",$7E,$7F," ABC 123 ",$8D
        .repeat 14
            .byte $7E,$7F," Apple II "
        .endrepeat
        .byte 0
GLYPH_HAN:  .byte 7,8
        .include "probe-han.inc"
GLYPH_GEUL: .byte 7,8
        .include "probe-geul.inc"
        .assert * <= $9800, error, "K0 probe exceeds measured candidate gap"
