; Preserve the decompressor's exact returned registers/flags and zero page.
; Commands/strings below the wrapper belong to this overlay, not to S/O/P.
.setcpu "6502"
.segment "CODE"
.include "caption-hooks-config.inc"

K_IMAGE_HOOK:
.if MODE_N
        sty K_IMAGE_INDEX
.else
        stx K_IMAGE_LO
        sty K_IMAGE_HI
.endif
        jsr K_IMAGE_ORIGINAL
        php
        pha
        txa
        pha
        tya
        pha
.if MODE_N
        lda K_IMAGE_INDEX
        cmp #$04
        beq K_IMAGE_MONITOR
        cmp #$05
        bne K_IMAGE_RETURN
        ldx #<CAP_N5
        ldy #>CAP_N5
        jmp K_IMAGE_CAPTION
K_IMAGE_MONITOR:
        ldx #<CAP_N4
        ldy #>CAP_N4
.else
        lda K_IMAGE_HI
        cmp #$78
        bne K_IMAGE_TITLE
        lda K_IMAGE_LO
        cmp #$00
        bne K_IMAGE_RETURN
        ldx #<CAP_R0
        ldy #>CAP_R0
        jmp K_IMAGE_CAPTION
K_IMAGE_TITLE:
        cmp #$7F
        bne K_IMAGE_AGENCY
        lda K_IMAGE_LO
        cmp #$A0
        bne K_IMAGE_RETURN
        ldx #<CAP_R2
        ldy #>CAP_R2
        jmp K_IMAGE_CAPTION
K_IMAGE_AGENCY:
        cmp #$87
        bne K_IMAGE_RETURN
        lda K_IMAGE_LO
        cmp #$60
        bne K_IMAGE_RETURN
        ldx #<CAP_R3
        ldy #>CAP_R3
.endif
K_IMAGE_CAPTION:
        lda #1-MODE_N
        jsr K_CAPTION_DRAW
K_IMAGE_RETURN:
        pla
        tay
        pla
        tax
        pla
        plp
        rts
K_IMAGE_ORIGINAL:
.if MODE_N
        cpy #$00
        beq K_IMAGE_ZERO
        jmp N_TABLE_STRIDE
K_IMAGE_ZERO:
        jmp IMAGE_ENTRY+4
K_IMAGE_INDEX: .byte 0
.else
        stx $CC
        sty $CD
        jmp IMAGE_ENTRY+4
K_IMAGE_LO: .byte 0
K_IMAGE_HI: .byte 0
.endif
.include "caption-data.inc"
K_IMAGE_END:
