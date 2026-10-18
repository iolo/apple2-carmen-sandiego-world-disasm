; Two-stage RAM fixture. Pause after native font installation, replace the
; staged font at $6000 with the patched N/R module, then enter PROBE_RENDER.
.setcpu "6502"
.segment "CODE"
.include "render-probe-config.inc"

PROBE_ENTRY:
        jsr K_INIT
PROBE_INITIALIZED:
        jmp PROBE_INITIALIZED
PROBE_RENDER:
        lda #$20
        sta $C1
        lda #$00
        sta $C0
        tay
        .if TYPEWRITER
        ldx #$40
        .else
        ldx #$20
        .endif
        lda #$80
PROBE_CLEAR:
        sta ($C0),y
        iny
        bne PROBE_CLEAR
        inc $C1
        dex
        bne PROBE_CLEAR
        lda #$00
        sta $68
        sta $BE
        sta $A2
        lda #$27
        sta $BF
        lda #$06
        sta $5F
        lda #$01
        sta $74
        lda $C054
        lda #$08
        sta $72
        sta $91
        .if TYPEWRITER
        lda #$03
        sta $70
        sta $71
        .endif
        ldx #$FC
        ldy #$A0
        lda #$08
        jsr DRAW_STRING
        lda $70
        sta PROBE_BODY_COLUMN
        lda $71
        sta PROBE_BODY_BIT
        lda $72
        sta PROBE_BODY_ROW
        lda $C2
        sta PROBE_BODY_PTR
        lda $C3
        sta PROBE_BODY_PTR+1
        .if !TYPEWRITER
        lda #$64
        sta $72
        lda #$46
        sta $93
        lda #$00
        sta $C2
        sta $C6
        sta $70
        sta $71
        sta $67
        lda #$A6
        sta $C3
        sta $C7
        ldx #$00
        jsr CENTER_LOOP
        .endif
PROBE_DONE:
        jmp PROBE_DONE
PROBE_BODY_COLUMN: .byte 0
PROBE_BODY_BIT: .byte 0
PROBE_BODY_ROW: .byte 0
PROBE_BODY_PTR: .word 0
