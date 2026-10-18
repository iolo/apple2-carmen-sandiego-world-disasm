; Shared post-decompression caption interpreter. Main RAM after base KL,
; below $9700. Caller saves A/X/Y/P; all 256 auxiliary zero-page bytes are
; backed up here and restored before returning. The original game has IRQs
; disabled and neither native text path recursively decompresses a picture.
.setcpu "6502"
.segment "CODE"
.include "caption-engine-config.inc"

; A=0 for N, 1 for R; X/Y points to overlay-owned caption commands.
K_CAPTION_DRAW:
        cld
        sta K_CAPTION_MODE
        stx K_CAPTION_READ+1
        sty K_CAPTION_READ+2
        ldx #$00
K_CAPTION_SAVE_ZP:
        lda $00,x
        sta K_CAPTION_ZP,x
        inx
        bne K_CAPTION_SAVE_ZP
        ldx K_CAPTION_MODE
        lda K_CAPTION_CLEAR_LO,x
        sta K_CAPTION_CLEAR_CALL+1
        lda K_CAPTION_CLEAR_HI,x
        sta K_CAPTION_CLEAR_CALL+2
        lda K_CAPTION_FILL_LO,x
        sta K_CAPTION_FILL_CALL+1
        lda K_CAPTION_FILL_HI,x
        sta K_CAPTION_FILL_CALL+2
        lda K_CAPTION_CENTER_LO,x
        sta K_CAPTION_CENTER_CALL+1
        lda K_CAPTION_CENTER_HI,x
        sta K_CAPTION_CENTER_CALL+2
        lda #$00
        sta $68
        sta $BE
        sta $A2
        lda #$27
        sta $BF
        lda #$06
        sta $5F
K_CAPTION_NEXT_COMMAND:
        jsr K_CAPTION_NEXT
        cmp #$FF
        beq K_CAPTION_RESTORE
        cmp #$02
        beq K_CAPTION_TEXT
        sta K_CAPTION_COLOR
        jsr K_CAPTION_NEXT
        tax
        jsr K_CAPTION_NEXT
        tay
        jsr K_CAPTION_NEXT
        sta $97
        jsr K_CAPTION_NEXT
        sta $98
        lda K_CAPTION_COLOR
        beq K_CAPTION_BLACK
K_CAPTION_FILL_CALL:
        jsr $FFFF
        jmp K_CAPTION_NEXT_COMMAND
K_CAPTION_BLACK:
K_CAPTION_CLEAR_CALL:
        jsr $FFFF
        jmp K_CAPTION_NEXT_COMMAND
K_CAPTION_TEXT:
        jsr K_CAPTION_NEXT
        sta $93
        jsr K_CAPTION_NEXT
        sta $72
        jsr K_CAPTION_NEXT
        tax
        jsr K_CAPTION_NEXT
        tay
        stx $C2
        stx $C6
        sty $C3
        sty $C7
        ldx #$00
        stx $70
        stx $71
        stx $67
K_CAPTION_CENTER_CALL:
        jsr $FFFF
        jmp K_CAPTION_NEXT_COMMAND
K_CAPTION_RESTORE:
        ldx #$00
K_CAPTION_RESTORE_ZP:
        lda K_CAPTION_ZP,x
        sta $00,x
        inx
        bne K_CAPTION_RESTORE_ZP
        rts
K_CAPTION_NEXT:
K_CAPTION_READ:
        lda $FFFF
        inc K_CAPTION_READ+1
        bne K_CAPTION_BYTE_DONE
        inc K_CAPTION_READ+2
K_CAPTION_BYTE_DONE:
        rts
K_CAPTION_CLEAR_LO: .byte <N_CLEAR, <R_CLEAR
K_CAPTION_CLEAR_HI: .byte >N_CLEAR, >R_CLEAR
K_CAPTION_FILL_LO: .byte <N_FILL, <R_FILL
K_CAPTION_FILL_HI: .byte >N_FILL, >R_FILL
K_CAPTION_CENTER_LO: .byte <N_CENTER, <R_CENTER
K_CAPTION_CENTER_HI: .byte >N_CENTER, >R_CENTER
K_CAPTION_MUTABLE:
K_CAPTION_MODE: .byte 0
K_CAPTION_COLOR: .byte 0
K_CAPTION_ZP: .res 256, 0
K_CAPTION_END:
        .assert K_CAPTION_END <= $9700, error, "Captions overlap B disk-error scratch page"
