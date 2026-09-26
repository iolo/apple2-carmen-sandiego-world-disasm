; disk1/Q: $1F00, 252 bytes, sha256 d68f742f3df0c3bbc2b6ba5fc333152f3f7b9dbd1154981f3684e579116382b5
; Memory scrub and reset. It writes through selected main, auxiliary, and
; language-card ranges, restores the normal memory map, then jumps through
; the reset vector at $FFFC.
; The store operands below are modified to sweep successive 256-byte pages.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

RESET_VECTOR           := $FFFC
Q_ENTRY:  sei
        lda     $C082
        sta     $C008
        ldx     #$FF
        txs
        ldy     #$00
        sta     $C005
Q_COPY_SELF_TO_AUX_BYTE:  lda     Q_ENTRY,y
        sta     Q_ENTRY,y
        iny
        bne     Q_COPY_SELF_TO_AUX_BYTE
        sta     $C004
; Main-memory sweep. The BCS comparisons below stop after the first page
; of each low-memory range; the language-card pass runs through $FF00.
        lda     #$00
        sta     Q_MAIN_LOW_PAGE_HIGH
        ldx     #$02
        tay
Q_MAIN_LOW_PAGE_SWEEP:  sta     $0000,y        ; destination page changes below
Q_MAIN_LOW_PAGE_HIGH   = Q_MAIN_LOW_PAGE_SWEEP + 2          ; high byte of STA operand
        iny
        bne     Q_MAIN_LOW_PAGE_SWEEP
        cpx     Q_MAIN_LOW_PAGE_HIGH
        bcs     Q_MAIN_TEXT_PAGE_SETUP
        inc     Q_MAIN_LOW_PAGE_HIGH
        bne     Q_MAIN_LOW_PAGE_SWEEP
Q_MAIN_TEXT_PAGE_SETUP:  lda     #$04
        sta     Q_MAIN_TEXT_PAGE_HIGH
        lda     #$A0
        ldx     #$1E
Q_MAIN_TEXT_PAGE_SWEEP:  sta     $0400,y        ; destination page changes below
Q_MAIN_TEXT_PAGE_HIGH   = Q_MAIN_TEXT_PAGE_SWEEP + 2
        iny
        bne     Q_MAIN_TEXT_PAGE_SWEEP
        cpx     Q_MAIN_TEXT_PAGE_HIGH
        bcs     Q_MAIN_HGR_SETUP
        inc     Q_MAIN_TEXT_PAGE_HIGH
        bne     Q_MAIN_TEXT_PAGE_SWEEP
Q_MAIN_HGR_SETUP:  lda     #$20
        sta     Q_MAIN_HGR_PAGE_HIGH
        tya
        ldx     #$BF
Q_MAIN_HGR_SWEEP:  sta     $2000,y        ; destination page changes below
Q_MAIN_HGR_PAGE_HIGH   = Q_MAIN_HGR_SWEEP + 2
        iny
        bne     Q_MAIN_HGR_SWEEP
        cpx     Q_MAIN_HGR_PAGE_HIGH
        bcs     Q_MAIN_LANGUAGE_CARD_SETUP
        inc     Q_MAIN_HGR_PAGE_HIGH
        bne     Q_MAIN_HGR_SWEEP
Q_MAIN_LANGUAGE_CARD_SETUP:  lda     $C081
        lda     $C081
        lda     #$D0
        sta     Q_MAIN_LANGUAGE_CARD_HIGH
        tya
Q_MAIN_LANGUAGE_CARD_SWEEP:  sta     $D000,y        ; destination page changes below
Q_MAIN_LANGUAGE_CARD_HIGH   = Q_MAIN_LANGUAGE_CARD_SWEEP + 2
        iny
        bne     Q_MAIN_LANGUAGE_CARD_SWEEP
        inc     Q_MAIN_LANGUAGE_CARD_HIGH
        bne     Q_MAIN_LANGUAGE_CARD_SWEEP
        ldx     $C082
        sta     $C005
        sta     $C003
; Auxiliary-memory sweep. The BEQ comparisons cover $0400-$1EFF and
; $2000-$BFFF before the auxiliary language-card pass.
        lda     #$00
        sta     Q_AUX_LOW_PAGE_HIGH
        ldx     #$02
        tay
Q_AUX_LOW_PAGE_SWEEP:  sta     $0000,y        ; destination page changes below
Q_AUX_LOW_PAGE_HIGH   = Q_AUX_LOW_PAGE_SWEEP + 2
        iny
        bne     Q_AUX_LOW_PAGE_SWEEP
        cpx     Q_AUX_LOW_PAGE_HIGH
        bcs     Q_AUX_TEXT_SETUP
        inc     Q_AUX_LOW_PAGE_HIGH
        bne     Q_AUX_LOW_PAGE_SWEEP
Q_AUX_TEXT_SETUP:  lda     #$04
        sta     Q_AUX_TEXT_PAGE_HIGH
        lda     #$A0
        ldx     #$1E
Q_AUX_TEXT_SWEEP:  sta     $0400,y        ; destination page changes below
Q_AUX_TEXT_PAGE_HIGH   = Q_AUX_TEXT_SWEEP + 2
Q_AUX_TEXT_NEXT_BYTE:  iny
        bne     Q_AUX_TEXT_SWEEP
        cpx     Q_AUX_TEXT_PAGE_HIGH
        beq     Q_AUX_HGR_SETUP
        inc     Q_AUX_TEXT_PAGE_HIGH
        bne     Q_AUX_TEXT_SWEEP
Q_AUX_HGR_SETUP:  lda     #$20
        sta     Q_AUX_HGR_PAGE_HIGH
        tya
        ldx     #$BF
Q_AUX_HGR_SWEEP:  sta     $2000,y        ; destination page changes below
Q_AUX_HGR_PAGE_HIGH   = Q_AUX_HGR_SWEEP + 2
        iny
        bne     Q_AUX_HGR_SWEEP
        cpx     Q_AUX_HGR_PAGE_HIGH
        beq     Q_AUX_LANGUAGE_CARD_SETUP
        inc     Q_AUX_HGR_PAGE_HIGH
        bne     Q_AUX_HGR_SWEEP
Q_AUX_LANGUAGE_CARD_SETUP:  sta     $C009
        lda     $C081
        lda     $C081
        lda     #$D0
        sta     Q_AUX_LANGUAGE_CARD_HIGH
        tya
Q_AUX_LANGUAGE_CARD_SWEEP:  sta     $D000,y        ; destination page changes below
Q_AUX_LANGUAGE_CARD_HIGH   = Q_AUX_LANGUAGE_CARD_SWEEP + 2
        iny
        bne     Q_AUX_LANGUAGE_CARD_SWEEP
        inc     Q_AUX_LANGUAGE_CARD_HIGH
        bne     Q_AUX_LANGUAGE_CARD_SWEEP
        sta     $C008
        sta     $C004
        sta     $C002
        ldx     $C082
Q_CLEAR_PAGE3_AND_RESET:  sta     $0300,y
        iny
        bne     Q_CLEAR_PAGE3_AND_RESET
        jmp     (RESET_VECTOR)
