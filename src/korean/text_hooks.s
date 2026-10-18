; Address-preserving N reader fixes. Main RAM, original ALTZP/LC mapping.
; $DA/$DB is C's append page, $DC/$DD is N's literal-copy page; $AC/Y
; is the byte cursor within that page. Both paths must agree across $xxFF.
.setcpu "6502"
.segment "CODE"
.include "text-config.inc"

K_APPEND_CHOSEN_PRONOUN:
        lda $DD
        sta $DB
        jsr N_APPEND_UI_TEXT
        lda $DB
        sta $DD
        rts

K_TEXT_EXPANSION_DONE:
        lda $DD
        sta $DB
        sty $AC
        rts

; Y points at the current NUL. A final raw quote suppresses the period.
; The encoding never puts $22 inside a multibyte glyph.
K_END_TEXT_SENTENCE:
        cpy #$00
        bne K_SENTENCE_PREVIOUS
        dec $DB
K_SENTENCE_PREVIOUS:
        dey
        lda ($DA),y
        cmp #$22
        beq K_SENTENCE_NUL
        iny
        bne K_SENTENCE_PERIOD
        inc $DB
K_SENTENCE_PERIOD:
        lda #$2E
        sta ($DA),y
K_SENTENCE_NUL:
        iny
        bne K_SENTENCE_STORE_NUL
        inc $DB
K_SENTENCE_STORE_NUL:
        lda #$00
        sta ($DA),y
        sty $AC
        rts
