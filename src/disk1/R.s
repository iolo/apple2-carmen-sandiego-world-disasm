; disk1/R: $6000, 5094 bytes, sha256 7519dc80037293ffb3b6b0f0777a73617bdd7965d54112a87905eb5b29d52229
; Intro control flow, sound, HGR rectangles, and T frame pointers are partly
; annotated. Other instruction/data boundaries still need review.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

B_ENTER_GAME           := $9806
C_SKIP_NUL_STRINGS           := $D206
C_COPY_STRING           := $D209
C_COPY_PAGES_TO_AUX           := $D21B
D_FONT_PTR_LO                 := $B900
D_FONT_PTR_HI                 := $B970
R_S_BRODERBUND_LOGO := $7800
R_S_GLOBE           := $7BE0
R_S_TITLE_SCREEN    := $7FA0
R_S_ACME_STOREFRONT := $8760
R_TEXT_CASE_ANNOUNCEMENT := $00
R_TEXT_CASE_PROMPT       := $01
R_TEXT_VERSION_CREDIT    := $02
R_TEXT_RIGHTS_CREDIT     := $03
; Initialize intro sound and display state, then enter the replay loop.
R_INTRO_ENTRY:  lda     #$01
        sta     $18
        sta     $91
        sta     $92
        lda     #$02
        sta     $74
        ldx     #$00
        ldy     #$8A
        jsr     R_SET_HGR_BOUNDS_FROM_XY
        ldx     #$85
        ldy     #$0E
        lda     #$0F
        jsr     C_COPY_PAGES_TO_AUX
; Broderbund logo, then the moving figure sequence.
R_INTRO_LOOP:  jsr     R_CLEAR_NEXT_HGR_PAGE
        ldx     #<R_S_BRODERBUND_LOGO
        ldy     #>R_S_BRODERBUND_LOGO
        jsr     HGR_RLE_DRAW
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        ldy     #$10
        jsr     R_WAIT_INPUT_TICKS
        jsr     R_CLEAR_NEXT_HGR_PAGE
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        jsr     R_PLAY_NOISE_EFFECT
        lda     #$00
        sta     $AA
        sta     $B0
        sta     $B3
        lda     #$E4
        sta     $AC
        inc     $74
R_MOVING_GLYPH_LOOP:  jsr     R_DRAW_MOVING_GLYPHS
        jsr     R_FLASH_MOVING_GLYPH
        jsr     R_SHOW_FRAME_AND_POLL
        lda     $AA
        bne     R_MOVING_GLYPH_DECREMENT_FRAME
        lda     #$04
        sta     $AA
        bne     R_MOVING_GLYPH_SHIFT_LEFT
R_MOVING_GLYPH_DECREMENT_FRAME: dec $AA
R_MOVING_GLYPH_SHIFT_LEFT: sec
        lda     $AC
        sbc     #$04
        sta     $AC
        inc     $74
        jsr     R_DRAW_MOVING_GLYPHS
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     R_MOVING_GLYPH_SAVE_FRAME
        sbc     #$05
R_MOVING_GLYPH_SAVE_FRAME: sta $AA
        clc
        lda     $AC
        adc     #$08
        cmp     #$D0
        bcs     R_MOVING_GLYPH_CONTINUE
        cmp     #$96
        bcs     R_START_T_FRAME_SEQUENCE
R_MOVING_GLYPH_CONTINUE: sta $AC
        jmp     R_MOVING_GLYPH_LOOP

; Sound track 1 introduces the five-frame T animation.
R_START_T_FRAME_SEQUENCE:  lda     #$01
        jsr     R_PLAY_SOUND_TRACK
        lda     #$00
        sta     $AA
        lda     #$DC
        sta     $AC
R_T_FRAME_LOOP:  jsr     R_DRAW_T_FRAME
        jsr     R_SHOW_FRAME_AND_POLL
        lda     $AA
        beq     R_T_FRAME_TONE
        cmp     #$02
        bne     R_T_FRAME_SHIFT_LEFT
R_T_FRAME_TONE: ldy #$05
        lda     #$20
        jsr     R_PLAY_TONE_BURST
R_T_FRAME_SHIFT_LEFT: inc $74
        sec
        lda     $AC
        sbc     #$04
        sta     $AC
        lda     $AA
        bne     R_T_FRAME_DECREMENT_FRAME
        lda     #$04
        sta     $AA
        bne     R_T_FRAME_DRAW_NEXT
R_T_FRAME_DECREMENT_FRAME: dec $AA
R_T_FRAME_DRAW_NEXT: jsr R_DRAW_T_FRAME
        clc
        lda     $AC
        adc     #$08
        cmp     #$C0
        bcs     R_T_FRAME_ADVANCE_POSITION
        cmp     #$91
        bcs     R_SHOW_CASE_PROMPT
R_T_FRAME_ADVANCE_POSITION: sta $AC
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     R_T_FRAME_SAVE_FRAME
        sbc     #$05
R_T_FRAME_SAVE_FRAME: sta $AA
        jmp     R_T_FRAME_LOOP

; ACME storefront with the caper announcement and case prompt.
R_SHOW_CASE_PROMPT:  inc     $74
        jsr     R_CLEAR_NEXT_HGR_PAGE
        ldx     #<R_S_ACME_STOREFRONT
        ldy     #>R_S_ACME_STOREFRONT
        jsr     HGR_RLE_DRAW
        ldx     #$05
        ldy     #$0D
        lda     #R_TEXT_CASE_ANNOUNCEMENT
        jsr     R_DRAW_INTRO_STRING
        ldx     #$06
        ldy     #$A0
        lda     #R_TEXT_CASE_PROMPT
        jsr     R_DRAW_INTRO_STRING
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        ldy     #$20
        jsr     R_WAIT_INPUT_TICKS
        jsr     R_CLEAR_NEXT_HGR_PAGE
        ldx     #<R_S_GLOBE
        ldy     #>R_S_GLOBE
        jsr     HGR_RLE_DRAW
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        lda     #$8A
        sta     $AC
        lda     #$6C
        sta     $72
; Move the airplane glyph across the globe image.
R_GLOBE_ANIMATION_LOOP:  jsr     R_DRAW_GLOBE_AIRPLANE
        jsr     R_SHOW_FRAME_AND_POLL
        inc     $74
        clc
        lda     $AC
        tax
        cmp     #$8C
        bcc     R_GLOBE_CLAMP_CLEAR_START
        ldx     #$00
R_GLOBE_CLAMP_CLEAR_START: clc
        adc     #$4F
        tay
        cmp     #$8C
        bcc     R_GLOBE_CLEAR_TRAIL
        ldy     #$8B
R_GLOBE_CLEAR_TRAIL: clc
        lda     $72
        sta     $97
        adc     #$2A
        sta     $98
        jsr     R_HGR_CLEAR_RECT
        sec
        lda     $AC
        sbc     #$06
        sta     $AC
        cmp     #$B0
        bcs     R_GLOBE_CONTINUE
        cmp     #$8C
        bcs     R_SHOW_TITLE_CREDITS
R_GLOBE_CONTINUE: sec
        lda     $72
        sbc     #$02
        sta     $72
        jmp     R_GLOBE_ANIMATION_LOOP

; Title image with rights and version credits, followed by track 0.
R_SHOW_TITLE_CREDITS:  ldx     #<R_S_TITLE_SCREEN
        ldy     #>R_S_TITLE_SCREEN
        jsr     HGR_RLE_DRAW
        ldx     #$46
        ldy     #$74
        lda     #R_TEXT_RIGHTS_CREDIT
        jsr     R_CENTER_INTRO_STRING
        ldx     #$46
        ldy     #$80
        lda     #R_TEXT_VERSION_CREDIT
        jsr     R_CENTER_INTRO_STRING
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        lda     #$00
        jsr     R_PLAY_SOUND_TRACK
        ldy     #$30
        jsr     R_WAIT_INPUT_TICKS
        jsr     R_CLEAR_NEXT_HGR_PAGE
        jsr     R_PRESENT_AND_COPY_HGR_PAGE
        ldy     #$0A
        jsr     R_WAIT_INPUT_TICKS
        jmp     R_INTRO_LOOP

R_DRAW_GLOBE_AIRPLANE:  ldx     $AC
        ldy     $72
        lda     #$72
        jsr     R_DRAW_GLYPH_AT_XY
        rts

; Draw the T animation frame indexed by $AA at horizontal position $AC.
R_DRAW_T_FRAME:  ldx     $AC
        ldy     #$50
        stx     $73
        sty     $72
        jsr     R_SET_HGR_X_FROM_73
        ldy     $AA
        lda     R_T_FRAME_LO,y
        sta     $C8
        lda     R_T_FRAME_HI,y
        sta     $C9
        jsr     R_READ_GLYPH_SIZE
        jmp     R_DRAW_GLYPH_BITMAP

; T was copied from main $8500 into auxiliary $0E00. Its five 75x68 frames
; each occupy two dimension bytes plus 68 * ceil(75/7) = 750 bitmap bytes.
R_T_FRAME_BASE   = $0E00
R_T_FRAME_STRIDE = 750
R_T_FRAME_LO:
        .repeat 5, frame
            .byte <(R_T_FRAME_BASE + frame * R_T_FRAME_STRIDE)
        .endrepeat
R_T_FRAME_HI:
        .repeat 5, frame
            .byte >(R_T_FRAME_BASE + frame * R_T_FRAME_STRIDE)
        .endrepeat
R_DRAW_MOVING_GLYPHS:  ldx     $AC
        ldy     #$68
        lda     #$6B
        jsr     R_DRAW_GLYPH_AT_XY
        ldx     $AC
        ldy     #$90
        clc
        lda     $AA
        adc     #$6C
        jsr     R_DRAW_GLYPH_AT_XY
        rts

; Every second moving-glyph step draws a brief accent at one of two rows,
; alternating by $B3, then sounds a short burst if sound is enabled.
R_FLASH_MOVING_GLYPH: inc $B0
        lda     $B0
        cmp     #$02
        bcc     R_FLASH_DONE
        inc     $B3
        lda     $B3
        lsr     a
        bcc     R_FLASH_LOWER_ROW
        ldy     #$96
        jsr     R_DRAW_FLASH_GLYPH
        inc     $74
        ldy     #$96
R_FLASH_SECOND_PAGE: jsr R_DRAW_FLASH_GLYPH
        inc     $74
        lda     #$00
        sta     $B0
        jsr     R_PLAY_FLASH_TONE
R_FLASH_DONE: rts

R_FLASH_LOWER_ROW: ldy #$9A
        jsr     R_DRAW_FLASH_GLYPH
        inc     $74
        ldy     #$9A
        bne     R_FLASH_SECOND_PAGE
R_DRAW_FLASH_GLYPH: ldx $AC
        dex
        lda     #$71
        jsr     R_DRAW_GLYPH_AT_XY
        rts

R_PLAY_FLASH_TONE: ldy #$03
        lda     #$18
        jsr     R_PLAY_TONE_BURST
        rts

; Control-S toggles sound. Any other key or joystick button enters the game.
R_POLL_START_INPUT:  lda     $C000
        bpl     R_POLL_JOYSTICK
        bit     $C010
        cmp     #$93
        bne     R_START_GAME_FROM_INPUT
        lda     $18
        eor     #$01
        sta     $18
        jmp     R_POLL_START_INPUT

R_START_GAME_FROM_INPUT: lda $74
        lsr     a
        bcc     R_SHOW_PAGE2_AND_ENTER_GAME
        jsr     R_COPY_HGR_PAGE1_TO_PAGE2
        lda     #$02
        sta     $74
R_SHOW_PAGE2_AND_ENTER_GAME: lda $C055
        jmp     R_ENTER_GAME

R_POLL_JOYSTICK: lda $C061
        bmi     R_START_GAME_FROM_INPUT
        lda     $C062
        bmi     R_START_GAME_FROM_INPUT
        inc     $5A
        rts

R_ENTER_GAME:  jmp     B_ENTER_GAME

; Play one of two intro speaker sequences when sound is enabled.
R_PLAY_SOUND_TRACK:  ldx     $18
        beq     R_SOUND_TRACK_DONE
        asl     a
        tax
        lda     R_SOUND_TRACK_PTRS,x
        sta     $C2
        lda     R_SOUND_TRACK_PTRS+1,x
        sta     $C3
        lda     #$00
        sta     $88
R_SOUND_READ_COMMAND: ldy $88
        lda     ($C2),y
        cmp     #$FF
        beq     R_SOUND_TRACK_DONE
        bpl     R_SOUND_PLAY_PERIOD
        and     #$7F
        sta     R_SOUND_DURATION_IMMEDIATE
        inc     $88
        jmp     R_SOUND_READ_COMMAND

; A zero period redirects the speaker access to $0030 for a rest.
R_SOUND_PLAY_PERIOD: tax
        lda     R_SOUND_PERIODS,x
        bne     R_SOUND_SET_PERIOD
        sta     R_SOUND_SPEAKER_ADDRESS_HIGH
R_SOUND_SET_PERIOD: sta $83
        inc     $88
R_SOUND_DURATION_IMMEDIATE := * + 1
        lda     #$14
        sta     $BD
        ldx     #$00
        jsr     R_RUN_SPEAKER_OSCILLATOR
        lda     #$C0
        sta     R_SOUND_SPEAKER_ADDRESS_HIGH
        jmp     R_SOUND_READ_COMMAND

R_SOUND_TRACK_DONE: rts

; Two counters offset by one trigger a speaker access when either expires.
R_RUN_SPEAKER_OSCILLATOR: lda $83
        sta     $85
        sec
        sbc     #$01
        sta     $84
        sta     $86
R_SOUND_OSCILLATOR_TICK: lda #$01
        sta     $9B
        dec     $83
        bne     R_SOUND_DEC_SECOND_COUNTER
        lsr     $9B
        lda     $85
        sta     $83
R_SOUND_DEC_SECOND_COUNTER: dec $84
        bne     R_SOUND_MAY_TOGGLE_SPEAKER
        lsr     $9B
        lda     $86
        sta     $84
R_SOUND_MAY_TOGGLE_SPEAKER: lda $9B
        bne     R_SOUND_NEXT_TICK
R_SOUND_SPEAKER_ADDRESS_HIGH := * + 2
        lda     $C030
R_SOUND_NEXT_TICK: dex
        bne     R_SOUND_OSCILLATOR_TICK
        dec     $BD
        bne     R_SOUND_OSCILLATOR_TICK
        lda     #$60
        jsr     R_DELAY
        rts

        .include "../shared/r_sounds.inc"

; Advance the display-page state and clear the newly selected HGR page.
R_CLEAR_NEXT_HGR_PAGE:  inc     $74
        lda     $74
        lsr     a
        bcs     R_CLEAR_NEXT_PAGE1
        jsr     R_CLEAR_HGR_PAGE2
        rts

R_CLEAR_NEXT_PAGE1: jsr R_CLEAR_HGR_PAGE1
        rts

; Two groups of randomized speaker clicks, gated by the sound flag $18.
R_PLAY_NOISE_EFFECT:  lda     $18
        beq     R_NOISE_EFFECT_DONE
        lda     #$05
        sta     $88
R_NOISE_FIRST_GROUP: jsr R_PLAY_NOISE_BURST
        dec     $88
        bpl     R_NOISE_FIRST_GROUP
        lda     #$00
        jsr     R_DELAY
        lda     #$09
        sta     $88
R_NOISE_SECOND_GROUP: jsr R_PLAY_NOISE_BURST
        dec     $88
        bpl     R_NOISE_SECOND_GROUP
R_NOISE_EFFECT_DONE: rts

R_PLAY_NOISE_BURST:  ldy     #$55
R_NOISE_FIRST_CLICK: lda #$FF
        jsr     R_RANDOM_BELOW
        asl     a
        lda     #$20
        bcc     R_NOISE_FIRST_DELAY
        bit     $C030
        lda     #$1F
R_NOISE_FIRST_DELAY: tax
R_NOISE_FIRST_SHORT_WAIT: dex
        bne     R_NOISE_FIRST_SHORT_WAIT
        ldx     #$30
R_NOISE_FIRST_LONG_WAIT: dex
        bne     R_NOISE_FIRST_LONG_WAIT
        dey
        bne     R_NOISE_FIRST_CLICK
        ldy     #$88
R_NOISE_SECOND_CLICK: lda #$FF
        jsr     R_RANDOM_BELOW
        asl     a
        lda     #$33
        bcc     R_NOISE_SECOND_DELAY
        ldx     #$03
        bit     $C030
R_NOISE_DOUBLE_CLICK_WAIT: dex
        bpl     R_NOISE_DOUBLE_CLICK_WAIT
        bit     $C030
        lda     #$0A
R_NOISE_SECOND_DELAY: tax
R_NOISE_SECOND_WAIT: dex
        bne     R_NOISE_SECOND_WAIT
        dey
        bne     R_NOISE_SECOND_CLICK
        rts

R_SELECT_INTRO_STRING:  tya
        ldx     #<R_CASE_ANNOUNCEMENT
        ldy     #>R_CASE_ANNOUNCEMENT
        jmp     C_SKIP_NUL_STRINGS

; Retained $6395 helper: Y selects an intro string, then C copies it.
; No direct caller in the extracted game files has been identified.
R_COPY_SELECTED_INTRO_STRING:  jsr     R_SELECT_INTRO_STRING
        jmp     C_COPY_STRING

; Wait Y timing ticks, checking for a start key or joystick button each tick.
R_WAIT_INPUT_TICKS:  lda     #$00
R_WAIT_INPUT_TICK: jsr R_DELAY
        sty     $7F
        jsr     R_POLL_START_INPUT
        ldy     $7F
        dey
        bne     R_WAIT_INPUT_TICK
        rts

; Select the active HGR page from the low bit of $74.
R_SHOW_ACTIVE_HGR_PAGE:  lda     $74
        lsr     a
        bcs     R_SHOW_PAGE2
        lda     $C054
        rts

R_SHOW_PAGE2:  lda     $C055
        rts

; Default burst: ten speaker toggles with delay $50 when sound is enabled.
; No identified local caller; callers also enter R_PLAY_TONE_BURST directly.
R_DEFAULT_FEEDBACK_TONE:
        ldy     #$0A
        lda     #$50
R_PLAY_TONE_BURST:  sta     R_TONE_DELAY_VALUE
        sta     R_SILENT_TONE_DELAY_VALUE
        lda     $18
        beq     R_SILENT_TONE_DELAY_LOAD
R_TONE_BURST_NEXT_TICK:  lda     $C030
R_TONE_DELAY_LOAD:  lda     #$00
R_TONE_DELAY_VALUE   := R_TONE_DELAY_LOAD + 1
        jsr     R_DELAY
        dey
        bne     R_TONE_BURST_NEXT_TICK
        rts

R_SILENT_TONE_DELAY_LOAD:  lda     #$00
R_SILENT_TONE_DELAY_VALUE   := R_SILENT_TONE_DELAY_LOAD + 1
        jmp     R_DELAY

; The two entries clear HGR pages at $2000 and $4000, respectively.
R_CLEAR_HGR_PAGE1:  lda     #$20
        .byte   $2C             ; BIT absolute skips R_CLEAR_HGR_PAGE2's LDA #$40
R_CLEAR_HGR_PAGE2:  lda     #$40
        sta     $C1
        ldx     #$20
        ldy     #$00
        sty     $C0
        lda     #$80
R_CLEAR_HGR_NEXT_BYTE:  sta     ($C0),y
        iny
        bne     R_CLEAR_HGR_NEXT_BYTE
        inc     $C1
        dex
        bne     R_CLEAR_HGR_NEXT_BYTE
        rts

; Set $C0/$C1 to row Y on the active HGR page, plus byte column $70.
R_SET_HGR_ROW_PLUS_COLUMN: clc
        lda     $D600,y
        adc     $70
        sta     $C0
        lda     $D6C0,y
        sta     $C1
        lda     $74
        lsr     a
        bcs     R_HGR_ROW_PLUS_COLUMN_DONE
        lda     $C1
        adc     #$20
        sta     $C1
R_HGR_ROW_PLUS_COLUMN_DONE: ldy #$00
        rts

R_DRAW_GLYPH_INDEX:  jsr     R_LOOKUP_GLYPH_INDEX
        jmp     R_DRAW_GLYPH_BITMAP

R_DRAW_GLYPH:  jsr     R_LOOKUP_GLYPH
; $79 is pixel width and $7A is height. Count seven-pixel source bytes per
; row, draw the bitmap, then advance the destination byte/pixel column.
R_DRAW_GLYPH_BITMAP:  lda     #$01
        sta     $83
        lda     $79
R_COUNT_GLYPH_BYTE_COLUMNS:  cmp     #$08
        bcc     R_INIT_GLYPH_BITMAP_DRAW
        sbc     #$07
        inc     $83
        jmp     R_COUNT_GLYPH_BYTE_COLUMNS

R_INIT_GLYPH_BITMAP_DRAW:  inc     $79
        lda     $7A
        sta     $85
        lda     $72
        sta     $87
        lda     $C8
        sta     $CC
        lda     $C9
        sta     $CD
        ldx     #$00
        jsr     R_XOR_GLYPH_FORCE_PHASE
R_ADVANCE_GLYPH_COLUMN:  clc
        lda     $71
        adc     $79
R_NORMALIZE_ADVANCED_COLUMN:  cmp     #$07
        bcs     R_CARRY_ADVANCED_COLUMN
        sta     $71
        jmp     R_GLYPH_COLUMN_ADVANCED

R_CARRY_ADVANCED_COLUMN:  sbc     #$07
        inc     $70
        jmp     R_NORMALIZE_ADVANCED_COLUMN

R_GLYPH_COLUMN_ADVANCED:  rts

; Reverse the same byte/pixel column arithmetic. No local caller is known.
R_RETREAT_GLYPH_COLUMN:  sec
        lda     $71
        sbc     $79
        bcc     R_BORROW_RETREATED_COLUMN
        sta     $71
        jmp     R_GLYPH_COLUMN_RETREATED

R_BORROW_RETREATED_COLUMN:  clc
        adc     #$07
        sta     $71
        dec     $70
        cmp     #$07
        bcs     R_BORROW_RETREATED_COLUMN
R_GLYPH_COLUMN_RETREATED:  rts

; Character codes $20-$8A use D's font; $8B-$92 use R's extra glyphs.
; Return $C8/$C9 at the bitmap and $79/$7A as width and height.
R_LOOKUP_GLYPH:  sec
        sbc     #$20
R_LOOKUP_GLYPH_INDEX:  sta     $75
        tay
        cpy     #$6B
        bcc     R_USE_D_FONT_POINTER
        sbc     #$6B
        tay
        lda     R_GLYPH_PTR_LO,y
        sta     $C8
        lda     R_GLYPH_PTR_HI,y
        bne     R_GLYPH_POINTER_READY
R_USE_D_FONT_POINTER:  lda     D_FONT_PTR_LO,y
        sta     $C8
        lda     D_FONT_PTR_HI,y
R_GLYPH_POINTER_READY:  sta     $C9
R_READ_GLYPH_SIZE:  ldy     #$00
        lda     ($C8),y
        sta     $79
        inc     $C8
        bne     R_READ_GLYPH_HEIGHT
        inc     $C9
R_READ_GLYPH_HEIGHT:  lda     ($C8),y
        sta     $7A
        inc     $C8
        bne     R_GLYPH_SIZE_READY
        inc     $C9
R_GLYPH_SIZE_READY:  rts

; Direct string-pointer entry: X/Y point to NUL-terminated text, A selects
; the horizontal coordinate, and the caller has already set row $72.
R_DRAW_STRING_FROM_POINTER:  stx     $C2
        sty     $C3
        sta     $73
        jmp     R_BEGIN_STRING_DRAW

R_DRAW_INTRO_STRING:  stx     $73
        sty     $72
        tay
        jsr     R_SELECT_INTRO_STRING
; Scan ahead to measure a line before drawing it. At the right edge, back up
; to a space so the next line begins with the following word.
R_BEGIN_STRING_DRAW:  jsr     R_SET_HGR_X_FROM_73
R_RESET_STRING_SCAN:  lda     $C2
        sta     $C6
        lda     $C3
        sta     $C7
        ldx     #$00
R_SCAN_STRING_LINE:  lda     $70
        sta     $80
        lda     $71
        sta     $81
R_SCAN_STRING_CHAR:  lda     ($C6,x)
        bne     R_MEASURE_STRING_CHAR
        lda     $C2
        cmp     $C6
        bne     R_DRAW_MEASURED_LINE
        lda     $C3
        cmp     $C7
        bne     R_DRAW_MEASURED_LINE
        jmp     R_STRING_DRAW_DONE

R_MEASURE_STRING_CHAR:  cmp     #$8D
        bcs     R_CHECK_LINE_CONTROL
        jsr     R_LOOKUP_GLYPH
        inc     $79
        jsr     R_ADVANCE_GLYPH_COLUMN
        lda     $70
        cmp     #$27
        bcs     R_BACKTRACK_TO_WORD_BREAK
        inc     $C6
        bne     R_SCAN_STRING_CHAR
        inc     $C7
        jmp     R_SCAN_STRING_CHAR

R_CHECK_LINE_CONTROL:  lda     $C3
        cmp     $C7
        bne     R_DRAW_MEASURED_LINE
        lda     $C2
        cmp     $C6
        bne     R_DRAW_MEASURED_LINE
        jmp     R_HANDLE_STRING_LINE_BREAK

R_BACKTRACK_TO_WORD_BREAK:  lda     ($C6,x)
        cmp     #$20
        beq     R_DRAW_MEASURED_LINE
        lda     $C6
        bne     R_BACKTRACK_ONE_CHAR
        dec     $C7
R_BACKTRACK_ONE_CHAR:  dec     $C6
        jmp     R_BACKTRACK_TO_WORD_BREAK

R_DRAW_MEASURED_LINE:  lda     $80
        sta     $70
        lda     $81
        sta     $71
R_DRAW_NEXT_LINE_CHAR:  lda     ($C2,x)
        jsr     R_DRAW_GLYPH
        inc     $C2
        bne     R_CHECK_DRAWN_LINE_END
        inc     $C3
R_CHECK_DRAWN_LINE_END:  lda     $C3
        cmp     $C7
        bne     R_DRAW_NEXT_LINE_CHAR
        lda     $C2
        cmp     $C6
        bne     R_DRAW_NEXT_LINE_CHAR
        lda     ($C6,x)
        beq     R_STRING_DRAW_DONE
; A control byte at or above $8D resets the horizontal position from $91;
; $8F additionally resets it from $92 before advancing ten HGR rows.
R_HANDLE_STRING_LINE_BREAK:  ldy     $91
        jsr     R_SET_HGR_X_FROM_Y
        lda     ($C6,x)
        cmp     #$8F
        bne     R_SKIP_LINE_SEPARATOR
        ldy     $92
        jsr     R_SET_HGR_X_FROM_Y
R_SKIP_LINE_SEPARATOR:  inc     $C6
        bne     R_BEGIN_NEXT_STRING_LINE
        inc     $C7
R_BEGIN_NEXT_STRING_LINE:  lda     ($C6,x)
        cmp     #$20
        beq     R_SKIP_LINE_SEPARATOR
        lda     $C6
        sta     $C2
        lda     $C7
        sta     $C3
        jsr     R_ADVANCE_STRING_ROW_10
        jmp     R_SCAN_STRING_LINE

R_STRING_DRAW_DONE:  rts

R_ADVANCE_STRING_ROW_10:  clc
        lda     $72
        adc     #$0A
        sta     $72
R_STRING_ROW_ADVANCED:  rts

; X selects the requested horizontal position through C's $D400/$D500
; quotient/remainder tables; Y is the HGR row, A the intro string index.
; Measure the string in seven-pixel columns, subtract half its width, then
; pass the saved pointer to the ordinary string drawing loop.
R_CENTER_INTRO_STRING:  stx     $93
        sty     $72
        tay
R_GET_CENTERED_STRING_POINTER:  jsr     R_SELECT_INTRO_STRING
        stx     $C6
        stx     $C2
        sty     $C7
        sty     $C3
        ldx     #$00
        stx     $70
        stx     $71
        stx     $67
R_MEASURE_CENTERED_STRING:  lda     ($C2,x)
        beq     R_HALVE_STRING_WIDTH
        jsr     R_LOOKUP_GLYPH
        inc     $79
        jsr     R_ADVANCE_GLYPH_COLUMN
        inc     $C2
        bne     R_MEASURE_CENTERED_STRING
        inc     $C3
        jmp     R_MEASURE_CENTERED_STRING

; $70 counts whole seven-pixel columns and $71 is the remaining pixels.
; $67 records an odd whole-column count for the half-width correction.
R_HALVE_STRING_WIDTH:  lda     $70
        lsr     a
        sta     $70
        bcc     R_SUBTRACT_HALF_WIDTH_FROM_X
        inc     $67
R_SUBTRACT_HALF_WIDTH_FROM_X:  ldy     $93
        sec
        lda     $D400,y
        sbc     $70
        sta     $70
        lda     $71
        lsr     a
        sta     $71
        sec
        lda     $D500,y
        sbc     $71
        bcs     R_ADJUST_ODD_BYTE_HALF_WIDTH
        adc     #$07
        dec     $70
R_ADJUST_ODD_BYTE_HALF_WIDTH:  sta     $71
        lda     $67
        beq     R_RESTORE_CENTERED_STRING_POINTER
        sec
        lda     $71
        sbc     #$04
        bcs     R_CENTER_REMAINDER_READY
        adc     #$07
        dec     $70
R_CENTER_REMAINDER_READY:  sta     $71
R_RESTORE_CENTERED_STRING_POINTER:  lda     $C6
        sta     $C2
        lda     $C7
        sta     $C3
        lda     $68
        beq     R_DRAW_CENTERED_STRING
        lda     $70
        sta     $7D
        sec
        lda     $71
        sbc     #$02
        bcs     R_STORE_CENTERED_POSITION
        adc     #$07
        dec     $7D
; When $68 is set, retain a derived horizontal position in $9E70+$94.
; No local reader of this stored value has been identified.
R_STORE_CENTERED_POSITION:  ldy     $94
        lsr     a
        sta     $5E
        lda     $7D
        sta     $87
        asl     $87
        lsr     a
        clc
        adc     $7D
        adc     $87
        adc     $5E
        sta     $9E70,y
R_DRAW_CENTERED_STRING:  jmp     R_RESET_STRING_SCAN

; Wait for a keyboard byte. Return its 7-bit value in A and uppercase
; ASCII form in $77; consume the dispatch control key and read again.
R_READ_KEY:  bit     $C010
R_WAIT_FOR_KEY_BYTE:  lda     $C000
        bmi     R_PROCESS_KEY_BYTE
        inc     $5A
        jmp     R_WAIT_FOR_KEY_BYTE

R_PROCESS_KEY_BYTE:  sta     $75
        and     #$7F
        sta     $77
        sta     $76
        bit     $C010
        jsr     R_DISPATCH_CONTROL_KEY
        bcs     R_WAIT_FOR_KEY_BYTE
        jsr     R_UPPERCASE_ASCII
        sta     $77
        lda     $76
        rts

R_UPPERCASE_ASCII:  cmp     #$61
        bcc     R_UPPERCASE_DONE
        cmp     #$7B
        bcs     R_UPPERCASE_DONE
        sec
        sbc     #$20
R_UPPERCASE_DONE:  rts

; Copy $85 rows of $83 bytes from X/Y into consecutive HGR columns.
; This entry has no identified local caller.
R_COPY_BITMAP_ROWS:  stx     $CC
        sty     $CD
R_COPY_BITMAP_NEXT_ROW:  ldy     $87
        jsr     R_SET_HGR_ROW_PLUS_COLUMN
        ldx     #$00
        lda     $83
        sta     $84
R_COPY_BITMAP_NEXT_BYTE:  lda     ($CC,x)
        sta     ($C0),y
        inc     $CC
        bne     R_COPY_BITMAP_ADVANCE_BYTE
        inc     $CD
R_COPY_BITMAP_ADVANCE_BYTE:  iny
        dec     $84
        bne     R_COPY_BITMAP_NEXT_BYTE
        inc     $87
        dec     $85
        bne     R_COPY_BITMAP_NEXT_ROW
        rts

; Related byte copier gated by row $04 <= $87 < $A3. Its local caller
; has not been identified.
R_COPY_BITMAP_ROWS_IN_WINDOW:  stx     $CC
        sty     $CD
R_COPY_CLIPPED_BITMAP_NEXT_ROW:  lda     $83
        sta     $84
        ldy     $87
        jsr     R_SET_HGR_ROW_PLUS_COLUMN
R_COPY_CLIPPED_BITMAP_NEXT_BYTE:  lda     $87
        cmp     #$04
        bcc     R_COPY_CLIPPED_BITMAP_ADVANCE_SOURCE
        cmp     $A3
        bcs     R_COPY_CLIPPED_BITMAP_ADVANCE_SOURCE
        lda     ($CC),y
        sta     ($C0),y
R_COPY_CLIPPED_BITMAP_ADVANCE_SOURCE:  inc     $CC
        bne     R_COPY_CLIPPED_BITMAP_ADVANCE_COLUMN
        inc     $CD
R_COPY_CLIPPED_BITMAP_ADVANCE_COLUMN:  inc     $C0
        dec     $84
        bne     R_COPY_CLIPPED_BITMAP_NEXT_BYTE
        inc     $87
        dec     $85
        bne     R_COPY_CLIPPED_BITMAP_NEXT_ROW
        rts

; Convert X and Y positions through C's HGR quotient/remainder tables.
R_SET_HGR_BOUNDS_FROM_XY:  lda     $D400,x
        sta     $BE
        lda     $D500,x
        sta     $A2
        lda     $D400,y
        sta     $BF
        lda     $D500,y
        sta     $5F
        rts

; Draw source glyph bytes through the shift tables at $B2xx, preserving
; pixels outside the left/right clipping bounds $BE/$BF.
R_COPY_GLYPH_WITH_CLIPPING:  stx     $CC
        sty     $CD
        ldx     #$00
        stx     $A1
        jsr     R_SET_HGR_X_FROM_73
        lda     ($CC,x)
        bpl     R_COPY_GLYPH_PHASE_READY
        lda     #$80
        sta     $A1
R_COPY_GLYPH_PHASE_READY:  clc
        lda     $71
        adc     #$B2
        sta     $CB
R_COPY_GLYPH_NEXT_ROW:  lda     $83
        sta     $84
        lda     $70
        sta     $80
        lda     #$00
        sta     $A0
        ldy     $87
        jsr     R_SET_HGR_ROW_ADDRESS
R_COPY_GLYPH_NEXT_SOURCE_BYTE:  lda     #$00
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        ora     $A0
        ldy     $80
        cpy     $BE
        bcc     R_PREPARE_COPY_GLYPH_OVERFLOW
        bne     R_COPY_GLYPH_CHECK_RIGHT_EDGE
        ldx     $A2
        and     R_GLYPH_START_MASK,x
R_MERGE_COPY_GLYPH_EDGE:  ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     R_PREPARE_COPY_GLYPH_OVERFLOW

R_COPY_GLYPH_CHECK_RIGHT_EDGE:  cpy     $BF
        beq     R_MASK_COPY_GLYPH_RIGHT_EDGE
        bcs     R_PREPARE_COPY_GLYPH_OVERFLOW
        ora     $A1
        sta     ($C0),y
        jmp     R_PREPARE_COPY_GLYPH_OVERFLOW

R_MASK_COPY_GLYPH_RIGHT_EDGE:  ldx     $5F
        and     R_GLYPH_END_MASK,x
        jmp     R_MERGE_COPY_GLYPH_EDGE

R_PREPARE_COPY_GLYPH_OVERFLOW:  lda     #$80
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        sta     $A0
        inc     $80
        inc     $CC
        bne     R_FINISH_COPY_GLYPH_SOURCE_BYTE
        inc     $CD
R_FINISH_COPY_GLYPH_SOURCE_BYTE:  dec     $84
        bne     R_COPY_GLYPH_NEXT_SOURCE_BYTE
        ldy     $80
        cpy     $BE
        bcc     R_COPY_GLYPH_ADVANCE_ROW
        bne     R_COPY_GLYPH_CHECK_OVERFLOW_RIGHT
        ldx     $A2
        and     R_GLYPH_START_MASK,x
R_MERGE_COPY_GLYPH_OVERFLOW:  ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     R_COPY_GLYPH_ADVANCE_ROW

R_COPY_GLYPH_CHECK_OVERFLOW_RIGHT:  cpy     $BF
        beq     R_MASK_COPY_GLYPH_OVERFLOW_EDGE
        bcs     R_COPY_GLYPH_ADVANCE_ROW
        ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     R_COPY_GLYPH_ADVANCE_ROW

R_MASK_COPY_GLYPH_OVERFLOW_EDGE:  ldx     $5F
        and     R_GLYPH_END_MASK,x
        jmp     R_MERGE_COPY_GLYPH_OVERFLOW

R_COPY_GLYPH_ADVANCE_ROW:  dec     $85
        beq     R_COPY_GLYPH_DONE
        inc     $87
        jmp     R_COPY_GLYPH_NEXT_ROW

R_COPY_GLYPH_DONE:  rts

; Set horizontal position from X and HGR row from Y, then draw glyph index A.
R_DRAW_GLYPH_AT_XY:  stx     $73
        sty     $72
        pha
        jsr     R_SET_HGR_X_FROM_73
        pla
        jmp     R_DRAW_GLYPH_INDEX

; XOR version of the clipped glyph renderer. Animated glyphs enter at
; R_XOR_GLYPH_FORCE_PHASE after setting $CC/$CD and X themselves.
R_XOR_GLYPH_WITH_CLIPPING:  stx     $CC
        sty     $CD
        ldx     #$00
        stx     $A1
        jsr     R_SET_HGR_X_FROM_73
        lda     ($CC,x)
        bpl     R_XOR_GLYPH_PHASE_READY
R_XOR_GLYPH_FORCE_PHASE:  lda     #$80
        sta     $A1
R_XOR_GLYPH_PHASE_READY:  clc
        lda     $71
        adc     #$B2
        sta     $CB
R_XOR_GLYPH_NEXT_ROW:  lda     $83
        sta     $84
        lda     $70
        sta     $80
        lda     #$00
        sta     $A0
        ldy     $87
        jsr     R_SET_HGR_ROW_ADDRESS
R_XOR_GLYPH_NEXT_SOURCE_BYTE:  lda     #$00
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        ora     $A0
        ldy     $80
        cpy     $BE
        bcc     R_XOR_GLYPH_PREPARE_OVERFLOW
        bne     R_XOR_GLYPH_CHECK_RIGHT_EDGE
        ldx     $A2
        and     R_GLYPH_START_MASK,x
R_XOR_GLYPH_LEFT_EDGE:  eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     R_XOR_GLYPH_PREPARE_OVERFLOW

R_XOR_GLYPH_CHECK_RIGHT_EDGE:  cpy     $BF
        beq     R_XOR_GLYPH_MASK_RIGHT_EDGE
        bcs     R_XOR_GLYPH_PREPARE_OVERFLOW
        eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     R_XOR_GLYPH_PREPARE_OVERFLOW

R_XOR_GLYPH_MASK_RIGHT_EDGE:  ldx     $5F
        and     R_GLYPH_END_MASK,x
        jmp     R_XOR_GLYPH_LEFT_EDGE

R_XOR_GLYPH_PREPARE_OVERFLOW:  lda     #$80
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        sta     $A0
        inc     $80
        inc     $CC
        bne     R_XOR_GLYPH_SOURCE_BYTE_DONE
        inc     $CD
R_XOR_GLYPH_SOURCE_BYTE_DONE:  dec     $84
        bne     R_XOR_GLYPH_NEXT_SOURCE_BYTE
        ldy     $80
        cpy     $BE
        bcc     R_XOR_GLYPH_ADVANCE_ROW
        bne     R_XOR_GLYPH_OVERFLOW_RIGHT
        ldx     $A2
        and     R_GLYPH_START_MASK,x
R_XOR_GLYPH_OVERFLOW_LEFT:  eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     R_XOR_GLYPH_ADVANCE_ROW

R_XOR_GLYPH_OVERFLOW_RIGHT:  cpy     $BF
        beq     R_XOR_GLYPH_MASK_OVERFLOW_RIGHT
        bcs     R_XOR_GLYPH_ADVANCE_ROW
        eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     R_XOR_GLYPH_ADVANCE_ROW

R_XOR_GLYPH_MASK_OVERFLOW_RIGHT:  ldx     $5F
        and     R_GLYPH_END_MASK,x
        jmp     R_XOR_GLYPH_OVERFLOW_LEFT

R_XOR_GLYPH_ADVANCE_ROW:  dec     $85
        beq     R_XOR_GLYPH_DONE
        inc     $87
        jmp     R_XOR_GLYPH_NEXT_ROW

R_XOR_GLYPH_DONE:  rts

; Fill a seven-bit HGR rectangle using horizontal endpoints X/Y and
; first/last scanlines $97/$98.
R_HGR_FILL_RECT:  sty     $5E
        lda     $D400,x
        sta     $95
        sta     $70
        ldy     $D500,x
        sty     $7C
        lda     R_HGR_FILL_START_MASK,y
        sta     $83
        ldy     $5E
        lda     $D400,y
        sta     $96
        ldx     $D500,y
        stx     $7E
        lda     R_HGR_FILL_END_MASK,x
        sta     $85
        lda     $97
        sta     $87
R_FILL_RECT_NEXT_ROW:  ldy     $87
        jsr     R_SET_HGR_ROW_PLUS_COLUMN
        ldx     $95
        lda     $83
        cpx     $96
        bne     R_FILL_RECT_WRITE_START
        and     $85
R_FILL_RECT_WRITE_START:  ora     ($C0),y
        sta     ($C0),y
        cpx     $96
        beq     R_FILL_RECT_FINISH_ROW
        lda     $7C
        jsr     R_FILL_NEXT_BYTE_BIT0_IF_NEEDED
        lda     #$FF
R_FILL_RECT_ADVANCE_COLUMN:  iny
        inx
        cpx     $96
        bcs     R_FILL_RECT_WRITE_END
R_FILL_RECT_WRITE_MIDDLE:  sta     ($C0),y
        jmp     R_FILL_RECT_ADVANCE_COLUMN

R_FILL_RECT_WRITE_END:  lda     $85
        ora     ($C0),y
        sta     ($C0),y
R_FILL_RECT_FINISH_ROW:  lda     $7E
        jsr     R_FILL_NEXT_BYTE_BIT0_IF_NEEDED
        lda     $87
        cmp     $98
        bcs     R_FILL_RECT_DONE
        inc     $87
        bne     R_FILL_RECT_NEXT_ROW
R_FILL_RECT_DONE:  rts

; Pixel position 6 spills one bit into the following HGR byte.
R_FILL_NEXT_BYTE_BIT0_IF_NEEDED:  cmp     #$06
        bcc     R_FILL_NEXT_BYTE_DONE
        iny
        lda     ($C0),y
        ora     #$01
        sta     ($C0),y
        dey
R_FILL_NEXT_BYTE_DONE:  rts

R_HGR_FILL_START_MASK:
        .byte   $FF,$FE,$FC,$F8,$F0,$E0,$C0
R_HGR_FILL_END_MASK:
        .byte   $83,$87,$8F,$9F,$BF,$FF,$FF
; Clear a rectangle with the same coordinate convention.
R_HGR_CLEAR_RECT:  sty     $5E
        lda     $D400,x
        sta     $95
        sta     $70
        ldy     $D500,x
        sty     $7C
        lda     R_HGR_CLEAR_START_MASK,y
        sta     $83
        ldy     $5E
        lda     $D400,y
        sta     $96
        ldx     $D500,y
        stx     $7E
        lda     R_HGR_CLEAR_END_MASK,x
        sta     $85
        lda     $97
        sta     $87
R_CLEAR_RECT_NEXT_ROW:  ldy     $87
        jsr     R_SET_HGR_ROW_PLUS_COLUMN
        ldx     $95
        lda     $83
        cpx     $96
        bne     R_CLEAR_RECT_WRITE_START
        ora     $85
R_CLEAR_RECT_WRITE_START:  and     ($C0),y
        sta     ($C0),y
        cpx     $96
        beq     R_CLEAR_RECT_FINISH_ROW
        lda     $7C
        jsr     R_CLEAR_NEXT_BYTE_BIT0_IF_NEEDED
        lda     #$80
R_CLEAR_RECT_ADVANCE_COLUMN:  iny
        inx
        cpx     $96
        bcs     R_CLEAR_RECT_WRITE_END
        sta     ($C0),y
        jmp     R_CLEAR_RECT_ADVANCE_COLUMN

R_CLEAR_RECT_WRITE_END:  lda     $85
        and     ($C0),y
        sta     ($C0),y
R_CLEAR_RECT_FINISH_ROW:  lda     $7E
        jsr     R_CLEAR_NEXT_BYTE_BIT0_IF_NEEDED
        lda     $87
        cmp     $98
        bcs     R_CLEAR_RECT_DONE
        inc     $87
        bne     R_CLEAR_RECT_NEXT_ROW
R_CLEAR_RECT_DONE:  rts

; Mirror the fill helper for the spilled pixel at position 6.
R_CLEAR_NEXT_BYTE_BIT0_IF_NEEDED:  cmp     #$06
        bcc     R_CLEAR_NEXT_BYTE_DONE
        iny
        lda     ($C0),y
        and     #$FE
        sta     ($C0),y
        dey
R_CLEAR_NEXT_BYTE_DONE:  rts

R_HGR_CLEAR_START_MASK:
        .byte   $80,$81,$83,$87,$8F,$9F,$BF
R_HGR_CLEAR_END_MASK:
        .byte   $FC,$F8,$F0,$E0,$C0,$80,$80
; Y selects one of the six rectangle parameter rows. Fill the outer shape,
; clear an inset region, then clear the remaining edge sections. The selected
; coordinates patch immediate operands in the drawing calls below.
R_DRAW_RECT_FRAME:  clc
        lda     R_RECT_TOP,y
        sta     $97
        adc     #$02
        sta     R_FRAME_INNER_TOP_VALUE
        lda     R_RECT_LEFT,y
        tax
        adc     #$02
        sta     R_FRAME_INNER_LEFT_VALUE
        lda     R_RECT_BOTTOM,y
        sec
        sta     $98
        sta     R_FRAME_OUTER_BOTTOM_VALUE
        sbc     #$02
        sta     R_FRAME_INNER_BOTTOM_VALUE
        lda     R_RECT_RIGHT,y
        tay
        sta     R_FRAME_OUTER_RIGHT_VALUE
        sbc     #$02
        sta     R_FRAME_INNER_RIGHT_VALUE
        jsr     R_HGR_FILL_RECT
; The rectangle table above patches the immediate operands below.
R_FRAME_INNER_TOP_LOAD:  lda     #$00
R_FRAME_INNER_TOP_VALUE   := R_FRAME_INNER_TOP_LOAD + 1
        sta     $97
R_FRAME_INNER_BOTTOM_LOAD:  lda     #$00
R_FRAME_INNER_BOTTOM_VALUE   := R_FRAME_INNER_BOTTOM_LOAD + 1
        sta     $98
R_FRAME_INNER_LEFT_LOAD:  ldx     #$00
R_FRAME_INNER_LEFT_VALUE   := R_FRAME_INNER_LEFT_LOAD + 1
R_FRAME_INNER_RIGHT_LOAD:  ldy     #$00
R_FRAME_INNER_RIGHT_VALUE   := R_FRAME_INNER_RIGHT_LOAD + 1
        jsr     R_HGR_CLEAR_RECT
R_FRAME_OUTER_BOTTOM_LOAD:  lda     #$00
R_FRAME_OUTER_BOTTOM_VALUE   := R_FRAME_OUTER_BOTTOM_LOAD + 1
        sta     $98
R_FRAME_OUTER_RIGHT_LOAD:  ldx     #$00
R_FRAME_OUTER_RIGHT_VALUE   := R_FRAME_OUTER_RIGHT_LOAD + 1
        inx
        txa
        tay
        iny
        sty     R_FRAME_BOTTOM_EDGE_VALUE
        jsr     R_HGR_CLEAR_RECT
        inc     $98
        lda     $98
        sta     $97
        inc     $98
        ldx     R_FRAME_INNER_LEFT_VALUE
R_FRAME_BOTTOM_EDGE_LOAD:  ldy     #$00
R_FRAME_BOTTOM_EDGE_VALUE   := R_FRAME_BOTTOM_EDGE_LOAD + 1
        jsr     R_HGR_CLEAR_RECT
        rts

; Delay loop; A selects its outer count (zero wraps through 256).
R_DELAY:  sec
R_DELAY_OUTER_LOOP:  pha
R_DELAY_INNER_LOOP:  sbc     #$01
        bne     R_DELAY_INNER_LOOP
        pla
        sbc     #$01
        bne     R_DELAY_OUTER_LOOP
        rts

; Copy the full 8 KiB displayed page to the other HGR page.
R_COPY_HGR_PAGE1_TO_PAGE2:  ldx     #$20
        ldy     #$40
        bne     R_COPY_HGR_PAGES_SETUP
R_COPY_HGR_PAGE2_TO_PAGE1:  ldx     #$40
        ldy     #$20
R_COPY_HGR_PAGES_SETUP:  stx     $C1
        sty     $CF
        ldy     #$00
        sty     $C0
        sty     $CE
        ldx     #$20
R_COPY_HGR_PAGE_BYTE:  lda     ($C0),y
        sta     ($CE),y
        iny
        bne     R_COPY_HGR_PAGE_BYTE
        inc     $CF
        inc     $C1
        dex
        bne     R_COPY_HGR_PAGE_BYTE
        rts

; Draw a compressed HGR image. X/Y point to its six-byte header: first/last
; byte column, first/last scanline, repeat marker, and scanline stride.
; It writes columns to the active HGR page; stride two uses separate row passes.
HGR_RLE_DRAW:  stx     $CC
        sty     $CD
        ldy     #$00
R_RLE_READ_GEOMETRY: lda ($CC),y
        sta     $95,y
        iny
        cpy     #$04
        bcc     R_RLE_READ_GEOMETRY
        lda     ($CC),y
        sta     $AF
        iny
        lda     ($CC),y
        sta     $90
        clc
        lda     $CC
        adc     #$06
        sta     $CC
        jsr     R_RLE_DRAW_PASS
        lda     $90
        cmp     #$02
        bne     R_RLE_DONE
        inc     $97
        jsr     R_RLE_DRAW_PASS
R_RLE_DONE: rts

; One pass starts at the first column and scanline. The stream cursor in
; $CC/$CD survives the return and is reused by a second pass when needed.
R_RLE_DRAW_PASS: lda $95
        sta     $70
        lda     $97
        sta     $72
        ldx     #$00
R_RLE_NEXT_COMMAND: ldy $72
        jsr     R_SET_HGR_ROW_ADDRESS
        ldy     $70
        lda     ($CC,x)
        cmp     $AF
        beq     R_RLE_REPEAT_COMMAND
        sta     ($C0),y
R_RLE_ADVANCE_STREAM: inc $CC
        bne     R_RLE_NEXT_POSITION
        inc     $CD
R_RLE_NEXT_POSITION: jsr R_RLE_ADVANCE_POSITION
        jmp     R_RLE_NEXT_COMMAND

R_RLE_REPEAT_COMMAND: inc $CC
        bne     R_RLE_READ_REPEAT_VALUE
        inc     $CD
R_RLE_READ_REPEAT_VALUE: lda ($CC,x)
        sta     $B1
        inc     $CC
        bne     R_RLE_READ_REPEAT_COUNT
        inc     $CD
R_RLE_READ_REPEAT_COUNT: lda ($CC,x)
        sta     $B2
; A zero count wraps through 256 copies via DEC below.
R_RLE_REPEAT_BYTE: lda $B1
        sta     ($C0),y
        dec     $B2
        beq     R_RLE_ADVANCE_STREAM
        jsr     R_RLE_ADVANCE_POSITION
        ldy     $72
        jsr     R_SET_HGR_ROW_ADDRESS
        ldy     $70
        jmp     R_RLE_REPEAT_BYTE

; Advance scanline by the stride, then move to the next column when past the
; last scanline. At the final column, discard our own return address so the
; caller returns from R_RLE_DRAW_PASS to HGR_RLE_DRAW.
R_RLE_ADVANCE_POSITION: clc
        lda     $72
        adc     $90
        sta     $72
        cmp     $98
        bcc     R_RLE_POSITION_DONE
        beq     R_RLE_POSITION_DONE
        lda     $70
        cmp     $96
        beq     R_RLE_PASS_DONE
        inc     $70
        lda     $97
        sta     $72
R_RLE_POSITION_DONE: rts

R_RLE_PASS_DONE: pla
        pla
        rts

; Disk prompt service retained in R; no local caller has been identified.
; X selects the requested disk side and $E0 supplies the status code. Its
; string indexes include $61 and $75, beyond R's four declared intro strings;
; the intended text source for those indexes remains unresolved.
R_PROMPT_FOR_DISK: stx $BB
        jsr     R_SAVE_DISPLAY_STATE
        lda     $6B
        beq     R_DISK_PROMPT_OUTER
        jmp     R_DISK_PROMPT_NESTED

R_DISK_PROMPT_OUTER:  lda     #$01
        sta     $6B
        inc     $74
        lda     $74
        lsr     a
        bcs     R_DISK_PROMPT_FROM_PAGE2
        jsr     R_COPY_HGR_PAGE1_TO_PAGE2
        jsr     R_WAIT_ON_DISK_PROMPT
        jsr     R_COPY_HGR_PAGE1_TO_PAGE2
R_DISK_PROMPT_RESTORE:  inc     $74
        jsr     R_RESTORE_DISPLAY_STATE
        lda     #$00
        sta     $6B
        rts

R_DISK_PROMPT_FROM_PAGE2:  jsr     R_COPY_HGR_PAGE2_TO_PAGE1
        jsr     R_WAIT_ON_DISK_PROMPT
        jsr     R_COPY_HGR_PAGE2_TO_PAGE1
        jmp     R_DISK_PROMPT_RESTORE

R_DISK_PROMPT_NESTED:  jsr     R_DRAW_DISK_PROMPT
        jsr     R_WAIT_KEY_OR_BUTTON
        jsr     R_RESTORE_DISPLAY_STATE
        rts

R_WAIT_ON_DISK_PROMPT:  jsr     R_DRAW_DISK_PROMPT
        jsr     R_SHOW_FRAME_AND_POLL
        jsr     R_WAIT_KEY_OR_BUTTON
        inc     $74
        jsr     R_SHOW_FRAME_AND_POLL
        inc     $74
        rts

; Preserve the HGR text position and two source-pointer bytes in $F0-$F4.
R_SAVE_DISPLAY_STATE:  lda     $70
        sta     $F0
        lda     $71
        sta     $F1
        lda     $72
        sta     $F2
        lda     $C4
        sta     $F3
        lda     $C5
        sta     $F4
        rts

R_RESTORE_DISPLAY_STATE:  lda     $F0
        sta     $70
        lda     $F1
        sta     $71
        lda     $F2
        sta     $72
        lda     $F3
        sta     $C4
        lda     $F4
        sta     $C5
        rts

; Set $C0/$C1 to row Y on the active HGR page.
R_SET_HGR_ROW_ADDRESS: lda $D600,y
        sta     $C0
        lda     $D6C0,y
        sta     $C1
        lda     $74
        lsr     a
        bcs     R_HGR_ROW_ADDRESS_DONE
        lda     $C1
        adc     #$20
        sta     $C1
R_HGR_ROW_ADDRESS_DONE: rts

R_SET_HGR_X_FROM_73:  ldy     $73
R_SET_HGR_X_FROM_Y:  lda     $D400,y
        sta     $70
        lda     $D500,y
        sta     $71
        rts

R_IGNORE_CONTROL_KEY: rts

; Recognize control-S ($13); carry set means the caller should read again.
R_DISPATCH_CONTROL_KEY:  lda     $76
        ldy     #$00
R_SCAN_CONTROL_KEY:  cmp     R_DISPATCH_KEY,y
        beq     R_DISPATCH_MATCHED_CONTROL_KEY
        dey
        bpl     R_SCAN_CONTROL_KEY
        clc
        rts

R_DISPATCH_MATCHED_CONTROL_KEY:  lda     R_DISPATCH_TARGET_LO,y
        sta     R_DISPATCH_CALL+1
        lda     R_DISPATCH_TARGET_HI,y
        sta     R_DISPATCH_CALL+2
R_DISPATCH_CALL: jsr $0000     ; target patched from the tables above
        sec
        rts

R_TOGGLE_SOUND:  lda     $18
        eor     #$01
        sta     $18
        rts

; Show the current HGR page, copy it to the other page, then poll input.
R_PRESENT_AND_COPY_HGR_PAGE:  lda     $74
        lsr     a
        bcc     R_PRESENT_PAGE2_AND_COPY
        lda     $C054
        jsr     R_COPY_HGR_PAGE1_TO_PAGE2
R_POLL_AFTER_PRESENT:  jsr     R_POLL_START_INPUT
        rts

R_PRESENT_PAGE2_AND_COPY:  lda     $C055
        jsr     R_COPY_HGR_PAGE2_TO_PAGE1
        jmp     R_POLL_AFTER_PRESENT

; X is the low byte of an RLE stream pointer in zero page.
; No identified local caller.
R_DRAW_ZERO_PAGE_RLE_IMAGE:
        ldy     #$00
        jsr     HGR_RLE_DRAW
        rts

R_SHOW_FRAME_AND_POLL:  lda     $74
        lsr     a
        bcc     R_SHOW_FRAME_PAGE2
        lda     $C054
R_POLL_AFTER_FRAME:  jsr     R_POLL_START_INPUT
        rts

R_SHOW_FRAME_PAGE2:  lda     $C055
        jmp     R_POLL_AFTER_FRAME

; Return a pseudorandom value below the A-register bound (zero if A=0).
R_RANDOM_BELOW:  ora     #$00
        beq     R_RANDOM_DONE
        sta     $5E
        lda     $5A
        ror     a
        ror     a
        lda     $59
        rol     $59
        eor     $59
        ror     $59
        inc     $5A
        adc     $5A
        bvc     R_RANDOM_STORE_STATE
        inc     $5A
R_RANDOM_STORE_STATE:  sta     $59
        dec     $59
R_REDUCE_RANDOM_TO_BOUND:  cmp     $5E
        bcc     R_RANDOM_DONE
        sbc     $5E
        bcs     R_REDUCE_RANDOM_TO_BOUND
R_RANDOM_DONE:  rts

; Wait until a non-dispatched key or either joystick button is pressed.
R_WAIT_KEY_OR_BUTTON:  bit     $C010
R_WAIT_KEY_OR_BUTTON_LOOP:  lda     $C000
        bmi     R_ACCEPT_WAIT_KEY
        lda     $C061
        bmi     R_WAIT_KEY_OR_BUTTON_DONE
        lda     $C062
        bmi     R_WAIT_KEY_OR_BUTTON_DONE
        jmp     R_WAIT_KEY_OR_BUTTON_LOOP

R_ACCEPT_WAIT_KEY:  bit     $C010
        and     #$7F
        sta     $76
        jsr     R_DISPATCH_CONTROL_KEY
        bcs     R_WAIT_KEY_OR_BUTTON_LOOP
R_WAIT_KEY_OR_BUTTON_DONE:  rts

; $2B requests the write-protection warning. Other statuses show the
; "Please insert" prompt with Side A/B selected by $BB.
R_DRAW_DISK_PROMPT:  lda     $E0
        cmp     #$2B
        bne     R_DRAW_INSERT_DISK_PROMPT
        ldy     #$05
        jsr     R_DRAW_RECT_FRAME
        ldy     #$48
        lda     #$61
        ldx     #$44
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldy     $72
        lda     #$75
        ldx     #$44
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldy     $72
        lda     #$08
        bne     R_DRAW_DISK_PROMPT_LAST_LINE
R_DRAW_INSERT_DISK_PROMPT:  ldy     #$00
        jsr     R_DRAW_RECT_FRAME
        ldx     #$44
        ldy     #$34
        lda     #$03
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldx     #$44
        ldy     $72
        lda     #$04
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldx     #$44
        ldy     $72
        lda     #$05
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldy     $72
        ldx     $BB
        dex
        lda     R_DISK_SIDE_TEXT_IDS,x
        ldx     #$44
        jsr     R_CENTER_INTRO_STRING
        jsr     R_ADVANCE_STRING_ROW_10
        ldy     $72
        lda     #$08
R_DRAW_DISK_PROMPT_LAST_LINE:  ldx     #$44
        jsr     R_CENTER_INTRO_STRING
        rts

R_DISK_SIDE_TEXT_IDS:  .byte   $06, $07       ; stored disk-side string indexes
; Six HGR rectangles: top/bottom scanlines and left/right byte columns.
R_RECT_TOP:    .byte $30, $40, $28, $42, $35, $3F
R_RECT_BOTTOM: .byte $68, $50, $00, $96, $68, $6C
R_RECT_LEFT:   .byte $1F, $27, $0A, $07, $12, $22
R_RECT_RIGHT:  .byte $67, $63, $3F, $4C, $74, $64

; Retained fragment with no identified local caller; its indexes $28/$29
; likewise run beyond R's four declared intro strings.
R_UNREFERENCED_PROMPT_FRAGMENT:  ldx     #$45
        ldy     #$39
        lda     #$28
        jsr     R_CENTER_INTRO_STRING
        lda     $72
        clc
        adc     #$0F
        tay
        ldx     #$17
        stx     $91
        lda     #$29
        jsr     R_DRAW_INTRO_STRING
        rts

; Eight extra bitmap glyphs for character codes $8B-$92. Each record has
; width and height bytes followed by packed seven-pixel bitmap rows.
R_GLYPH_PTR_LO:
        .byte <R_GLYPH_0,<R_GLYPH_1,<R_GLYPH_2,<R_GLYPH_3
        .byte <R_GLYPH_4,<R_GLYPH_5,<R_GLYPH_6,<R_GLYPH_7
R_GLYPH_PTR_HI:
        .byte >R_GLYPH_0,>R_GLYPH_1,>R_GLYPH_2,>R_GLYPH_3
        .byte >R_GLYPH_4,>R_GLYPH_5,>R_GLYPH_6,>R_GLYPH_7
; Seven bit positions, with high bit set to retain Apple II HGR color phase.
R_GLYPH_START_MASK: .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0
R_GLYPH_END_MASK:   .byte $81,$83,$87,$8F,$9F,$BF,$FF
R_GLYPH_AUX_MASK:   .byte $81,$82,$84,$88,$90,$A0,$C0
; The keyboard dispatcher tests one key and patches a JSR operand.
R_DISPATCH_KEY:       .byte $13
R_DISPATCH_TARGET_LO: .byte <R_IGNORE_CONTROL_KEY,<R_TOGGLE_SOUND
R_DISPATCH_TARGET_HI: .byte >R_IGNORE_CONTROL_KEY,>R_TOGGLE_SOUND
R_CASE_ANNOUNCEMENT: .asciiz "Carmen's gang has pulled another caper!"
R_CASE_PROMPT:       .asciiz "And it's up to you to solve the case..."
R_VERSION_CREDIT:    .asciiz "PRODOS VERSION BY KEN BULL"
R_RIGHTS_CREDIT:     .asciiz "All rights reserved"
        .include "r_glyphs.inc"
