; Appended, address-preserving hooks for N or R. The generator validates every
; replaced instruction span against the original binary before writing it.
.setcpu "6502"
.segment "CODE"
.include "render-config.inc"

HOOK_SCAN:
        jsr K_READ_C6
        bne :+
        jmp SCAN_SITE+4
:       jmp SCAN_NONZERO
HOOK_CENTER:
        jsr K_READ_C2
        bne :+
        jmp CENTER_ZERO
:       jmp CENTER_SITE+4
HOOK_DRAW:
        jsr K_READ_C2
        jmp DRAW_GLYPH
HOOK_CHAR:
        pha
        cmp #$7F
        bne HOOK_ASCII
        lda K_PENDING
        beq HOOK_ASCII
        pla
        lda #$5F
        sta $75
        jsr K_FETCH
        .if MODE_N
        lda #$97
        .endif
        jmp CHAR_HEADER
HOOK_ASCII:
        lda #$00
        sta K_PENDING
        pla
        sec
        sbc #$20
        jmp CHAR_INDEX

; A raw reverse scan is safe because no glyph trail can equal ASCII space.
; Stop at the beginning of this run, and retain the last measured glyph's
; leading-byte address if the word has no space. The next line must not skip it.
HOOK_BACKTRACK:
        lda $C6
        cmp $C2
        bne HOOK_CHECK_SPACE
        lda $C7
        cmp $C3
        beq HOOK_HARD_BREAK
HOOK_CHECK_SPACE:
        lda ($C6,x)
        cmp #$20
        beq HOOK_RUN_READY
        lda $C6
        bne :+
        dec $C7
:       dec $C6
        jmp HOOK_BACKTRACK
HOOK_HARD_BREAK:
        lda K_SCAN_FIRST_LO
        sta $C6
        lda K_SCAN_FIRST_HI
        sta $C7
        lda #$01
        sta K_HARD_BREAK
HOOK_RUN_READY:
        jmp BACKTRACK_READY
HOOK_SEPARATOR:
        lda K_HARD_BREAK
        beq HOOK_INCREMENT_SEPARATOR
        lda #$00
        sta K_HARD_BREAK
        jmp SEPARATOR_NEXT
HOOK_INCREMENT_SEPARATOR:
        inc $C6
        bne :+
        inc $C7
:       jmp SEPARATOR_NEXT

        .if MODE_N
HOOK_TW_SCAN:
        jsr K_READ_C6
        bne :+
        jmp TW_SCAN_SITE+4
:       jmp TW_SCAN_NONZERO
HOOK_TW_BACKTRACK:
        lda $C6
        cmp $C2
        bne HOOK_TW_CHECK_SPACE
        lda $C7
        cmp $C3
        beq HOOK_TW_HARD_BREAK
HOOK_TW_CHECK_SPACE:
        lda ($C6,x)
        cmp #$20
        beq HOOK_TW_RUN_READY
        lda $C6
        bne :+
        dec $C7
:       dec $C6
        jmp HOOK_TW_BACKTRACK
HOOK_TW_HARD_BREAK:
        lda K_SCAN_FIRST_LO
        sta $C6
        lda K_SCAN_FIRST_HI
        sta $C7
        lda #$01
        sta K_HARD_BREAK
HOOK_TW_RUN_READY:
        jmp TW_BACKTRACK_READY
HOOK_TW_SEPARATOR:
        lda K_HARD_BREAK
        beq HOOK_TW_INCREMENT_SEPARATOR
        lda #$00
        sta K_HARD_BREAK
        jmp TW_SEPARATOR_NEXT
HOOK_TW_INCREMENT_SEPARATOR:
        inc $C6
        bne :+
        inc $C7
:       jmp TW_SEPARATOR_NEXT
        .endif
