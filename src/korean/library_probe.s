; RAM-only native library test. Both configurations decode all 710 IDs from
; A001 (so lead/trail pairs cross pages), fetch actual pixels and dump every
; row at 1100. The host compares all font bytes, not a lossy checksum.
.setcpu "6502"
.segment "CODE"
.include "native-probe-config.inc"

PROBE_ENTRY:
        jsr K_INIT
        lda #$00
        sta PROBE_ERROR
        lda #$01
        sta SOURCE_PTR
        lda #$A0
        sta SOURCE_PTR+1
        lda #$00
        sta $DA
        lda #$11
        sta $DB
        lda #<GLYPH_COUNT
        sta $D8
        lda #>GLYPH_COUNT
        sta $D9
PROBE_NEXT:
        ldx #$5A
        ldy #$A5
        lda $D8
        and #$01
        ora #$4C
        sta PROBE_EXPECTED_P
        lsr a
        bit PROBE_FLAG_BITS
        sed
        sei
        jsr K_READ
        sta PROBE_A
        php
        pla
        sta PROBE_P
        cld
        lda PROBE_P
        and #$4D
        cmp PROBE_EXPECTED_P
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda PROBE_A
        cmp #$7F
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda K_PENDING
        cmp #$01
        beq :+
        lda #$01
        sta PROBE_ERROR
:       txa
        cmp #$5A
        beq :+
        lda #$01
        sta PROBE_ERROR
:       tya
        cmp #$A5
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda PROBE_EXPECTED_P
        lsr a
        bit PROBE_FLAG_BITS
        sed
        sei
        lda #$36
        jsr K_FETCH
        sta PROBE_A
        php
        pla
        sta PROBE_P
        cld
        lda PROBE_A
        cmp #$36
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda PROBE_P
        and #$4D
        cmp PROBE_EXPECTED_P
        beq :+
        lda #$01
        sta PROBE_ERROR
:       txa
        cmp #$5A
        beq :+
        lda #$01
        sta PROBE_ERROR
:       tya
        cmp #$A5
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda K_PENDING
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda $97E0
        cmp #$07
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda $97E1
        cmp #$08
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda $C011
        bmi :+
        lda #$01
        sta PROBE_ERROR
:       lda $C013
        bpl :+
        lda #$01
        sta PROBE_ERROR
:       lda $C014
        bpl :+
        lda #$01
        sta PROBE_ERROR
:       ldy #$00
PROBE_COPY_ROW:
        lda $97E2,y
        sta ($DA),y
        iny
        cpy #$08
        bne PROBE_COPY_ROW
        clc
        lda $DA
        adc #$08
        sta $DA
        bcc :+
        inc $DB
:       inc SOURCE_PTR
        bne :+
        inc SOURCE_PTR+1
:       lda $D8
        bne :+
        dec $D9
:       dec $D8
        lda $D8
        ora $D9
        beq PROBE_TERMINATOR
        jmp PROBE_NEXT
PROBE_TERMINATOR:
        jsr K_READ
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda K_PENDING
        beq :+
        lda #$01
        sta PROBE_ERROR
:       lda K_ERROR
        beq PROBE_DONE
        lda #$01
        sta PROBE_ERROR
PROBE_DONE:
        jmp PROBE_DONE
PROBE_ERROR: .byte 0
PROBE_A: .byte 0
PROBE_P: .byte 0
PROBE_EXPECTED_P: .byte 0
PROBE_FLAG_BITS: .byte $40
        .assert * <= $9200, error, "Probe overlaps resident library"
