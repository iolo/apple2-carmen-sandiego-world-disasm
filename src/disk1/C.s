; disk1/C: $D200, 10105 bytes, sha256 d6c3d8fef74a9e282c919596bed43f0f8664612ee44d57aacee8e11197bf8528
; Public services, lookup tables, dictionary, UI text, and bitmap records are
; separated as code or data. Some service behavior still needs deeper review.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

; Public entry table at $D200. Callers in B, N, and R use these addresses.
; The tenth entry starts in the middle of the block-copy setup routine.
; Each entry is a three-byte JMP, so the addresses remain stable for overlays.
        jmp     C_COPY_PAGE_TO_AUX_9F00

        jmp     C_APPEND_6000_STRING

        jmp     C_SKIP_NUL_STRINGS

        jmp     C_COPY_STRING

        jmp     C_COPY_2200_TO_AUX_D400

        jmp     C_HGR_AUX_TO_MAIN

        jmp     C_HGR_MAIN_TO_AUX

        jmp     C_APPEND_5000_TEXT

        jmp     C_COPY_8000_TO_AUX_1100

        jmp     C_COPY_PAGES_TO_AUX

; Copy the page at main RAM $7000 + ($01 * $100) to auxiliary $9F00.
CASE_ROUTE_GRAPH := $01
C_COPY_PAGE_TO_AUX_9F00:  clc
        lda     CASE_ROUTE_GRAPH
        adc     #$70
        sta     $C5
        ldy     #$00
        sty     $C4
        sta     $C003
C_COPY_PAGE_FIRST_216: lda ($C4),y
        sta     $9F00,y
        iny
        cpy     #$D8
        bcc     C_COPY_PAGE_FIRST_216
        ldx     #$00
C_COPY_PAGE_LAST_40: lda ($C4),y
        sta     $9FD8,x
        inx
        iny
        bne     C_COPY_PAGE_LAST_40
        sta     $C002
        rts

; A selects a NUL-terminated string at $6000; append it using $DA/$DB and
; the destination cursor in $AC while auxiliary writes are enabled.
C_APPEND_6000_STRING:  ldx     #$00
        ldy     #$60
        sta     $C003
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        sta     $C002
        rts

; Input: X/Y points to a NUL-separated string list, A is the number to skip.
; Return: X/Y points to the selected string.
C_SKIP_NUL_STRINGS:  stx     $C2
        sty     $C3
        ldy     #$00
        tax
        beq     C_SKIP_DONE
C_SCAN_NUL_STRING: lda ($C2),y
        beq     C_SKIP_TERMINATOR
        inc     $C2
        bne     C_SCAN_NUL_STRING
        inc     $C3
        jmp     C_SCAN_NUL_STRING

C_SKIP_TERMINATOR: inc $C2
        bne     C_COUNT_SKIPPED
        inc     $C3
C_COUNT_SKIPPED: dex
        bne     C_SCAN_NUL_STRING
C_SKIP_DONE: ldx     $C2
        ldy     $C3
        rts

; Copy from X/Y to the pointer in $DA/$DB at offset $AC. Stop at NUL or $FF,
; and leave $AC at the terminator position for the next append.
C_COPY_STRING:  stx     $D8
        sty     $D9
        ldx     #$00
        ldy     $AC
C_COPY_STRING_BYTE: lda ($D8,x)
        sta     ($DA),y
        beq     C_COPY_STRING_DONE
        cmp     #$FF
        beq     C_COPY_STRING_DONE
        iny
        bne     C_COPY_STRING_ADVANCE_SOURCE
        inc     $DB
C_COPY_STRING_ADVANCE_SOURCE: inc $D8
        bne     C_COPY_STRING_BYTE
        inc     $D9
        bne     C_COPY_STRING_BYTE
C_COPY_STRING_DONE: sty $AC
        rts

; Fixed entry: copy 44 pages from main $2200-$4DFF to auxiliary $D400-$FFFF.
C_COPY_2200_TO_AUX_D400:  ldx     #$22
        ldy     #$D4
        lda     #$2C
; General entry: X = source page, Y = destination page, A = page count.
C_COPY_PAGES_TO_AUX:  stx     $C5
        sty     $C3
        tax
        ldy     #$00
        sty     $C4
        sty     $C2
        sta     $C003
C_COPY_AUX_PAGE_BYTE: lda ($C4),y
        sta     ($C2),y
        iny
        bne     C_COPY_AUX_PAGE_BYTE
        inc     $C5
        inc     $C3
        dex
        bne     C_COPY_AUX_PAGE_BYTE
        sta     $C002
        rts

; Four HGR spans: inclusive first row/column, exclusive end row/column,
; and the linear buffer address used to copy each span.
; The apparent PLP/RTI and branch in the mechanical listing were table bytes.
C_SPAN_FIRST_ROW: .byte $28, $40, $35, $68
C_SPAN_ROW_END:   .byte $67, $99, $6C, $BB
C_SPAN_FIRST_COL: .byte $02, $02, $05, $07
C_SPAN_COL_END:   .byte $13, $17, $22, $21
C_SPAN_BUFFER_LO: .byte $00, $00, $00, $00
C_SPAN_BUFFER_HI: .byte $A2, $10, $10, $10
C_LOAD_HGR_SPAN:  lda     C_SPAN_FIRST_ROW,y
        sta     $95
        sta     $87
        lda     C_SPAN_ROW_END,y
        sta     $96
        lda     C_SPAN_FIRST_COL,y
        sta     $97
        lda     C_SPAN_COL_END,y
        sta     $98
        lda     C_SPAN_BUFFER_LO,y
        sta     $C2
        lda     C_SPAN_BUFFER_HI,y
        sta     $C3
        rts

; Copy a selected graphics span with auxiliary reads enabled.
C_HGR_AUX_TO_MAIN:  jsr     C_LOAD_HGR_SPAN
        ldx     #$00
        stx     $70
        sta     $C005           ; auxiliary reads on
C_HGR_AUX_TO_MAIN_ROW: ldy $87
        jsr     C_SET_HGR_ROW_ADDRESS
        ldy     $97
C_HGR_AUX_TO_MAIN_BYTE: lda ($C0),y
        sta     ($C2,x)
        inc     $C2
        bne     C_HGR_AUX_TO_MAIN_NEXT_COL
        inc     $C3
C_HGR_AUX_TO_MAIN_NEXT_COL: iny
        cpy     $98
        bne     C_HGR_AUX_TO_MAIN_BYTE
        inc     $87
        lda     $87
        cmp     $96
        bne     C_HGR_AUX_TO_MAIN_ROW
        sta     $C004           ; auxiliary reads off
        rts

; Copy the same span in the opposite direction with auxiliary writes enabled.
C_HGR_MAIN_TO_AUX:  jsr     C_LOAD_HGR_SPAN
        ldx     #$00
        stx     $70
        sta     $C003           ; auxiliary writes on
C_HGR_MAIN_TO_AUX_ROW: ldy $87
        jsr     C_SET_HGR_ROW_ADDRESS
        ldy     $97
C_HGR_MAIN_TO_AUX_BYTE: lda ($C2,x)
        sta     ($C0),y
        inc     $C2
        bne     C_HGR_MAIN_TO_AUX_NEXT_COL
        inc     $C3
C_HGR_MAIN_TO_AUX_NEXT_COL: iny
        cpy     $98
        bne     C_HGR_MAIN_TO_AUX_BYTE
        inc     $87
        lda     $87
        cmp     $96
        bne     C_HGR_MAIN_TO_AUX_ROW
        sta     $C002           ; auxiliary writes off
        rts

; Calculate the HGR byte address for the selected scanline and page.
C_SET_HGR_ROW_ADDRESS: clc
        lda     C_HGR_ROW_LO,y
        adc     $70
        sta     $C0
        lda     C_HGR_ROW_HI,y
        sta     $C1
        lda     $74
        lsr     a
        bcs     C_HGR_ROW_ADDRESS_DONE
        lda     $C1
        adc     #$20
        sta     $C1
C_HGR_ROW_ADDRESS_DONE: ldy #$00
        rts

; X selects a NUL-terminated string in the $5000 text buffer. Append it to
; auxiliary $A000 at cursor $AC; replace each '#' with a pronoun selected by
; the value at $00.
C_APPEND_5000_TEXT:  lda     #$00
        sta     $CE
        lda     #$50
        sta     $CF
        sta     $C003
        cpx     #$00
        beq     C_APPEND_5000_COPY
        ldy     #$00
C_APPEND_5000_SCAN: lda ($CE),y
        beq     C_APPEND_5000_COUNT_STRING
C_APPEND_5000_ADVANCE: inc $CE
        bne     C_APPEND_5000_SCAN
        inc     $CF
        bne     C_APPEND_5000_SCAN
C_APPEND_5000_COUNT_STRING: dex
        bne     C_APPEND_5000_ADVANCE
        inc     $CE
        bne     C_APPEND_5000_COPY
        inc     $CF
C_APPEND_5000_COPY: ldy $AC
C_APPEND_5000_BYTE: lda ($CE,x)
        cmp     #$23
        beq     C_APPEND_5000_PRONOUN
        sta     $A000,y
        cmp     #$00
        beq     C_APPEND_5000_DONE
        iny
C_APPEND_5000_NEXT_BYTE: inc $CE
        bne     C_APPEND_5000_BYTE
        inc     $CF
        bne     C_APPEND_5000_BYTE
C_APPEND_5000_PRONOUN: sty $AC
        lda     $00
        cmp     #$05
        bcs     C_APPEND_5000_HE
        ldx     #<C_PRONOUN_SHE
        ldy     #>C_PRONOUN_SHE
        jmp     C_APPEND_5000_COPY_PRONOUN

C_APPEND_5000_HE: ldx #<C_PRONOUN_HE
        ldy     #>C_PRONOUN_HE
C_APPEND_5000_COPY_PRONOUN: jsr C_COPY_STRING
        ldx     #$00
        jmp     C_APPEND_5000_NEXT_BYTE

C_APPEND_5000_DONE: sta $C002
        rts

C_PRONOUN_SHE: .asciiz "she"
C_PRONOUN_HE:  .asciiz "he"
; Fixed entry: copy nine pages from main $8000-$88FF to auxiliary $1100-$19FF.
C_COPY_8000_TO_AUX_1100:  ldx     #$80
        ldy     #$11
        lda     #$09
        jmp     C_COPY_PAGES_TO_AUX

; Unused alignment space before the page-aligned lookup tables.
        .res 37, $00
; HGR horizontal coordinate lookup for 140 logical columns.
; Coordinates 140-255 represent signed values -116 through -1.
; The first page is floor(2*x/7), the byte-column displacement.
C_X_BYTE_OFFSET:
        .repeat 256, coord
            .if coord < 140
                .byte (coord * 2) / 7
            .else
                .byte 256 - (((256 - coord) * 2 + 6) / 7)
            .endif
        .endrepeat
; The second page is (2*x) modulo 7, the bit position within a byte.
C_X_BIT_OFFSET:
        .repeat 256, coord
            .if coord < 140
                .byte (coord * 2) - 7 * ((coord * 2) / 7)
            .else
                .byte 7 * (((256 - coord) * 2 + 6) / 7) - ((256 - coord) * 2)
            .endif
        .endrepeat
; Apple II HGR scanline addresses for rows 0-191 on page 1 ($2000).
; Each table supplies one byte of the address to C_SET_HGR_ROW_ADDRESS.
C_HGR_ROW_LO:
        .repeat 192, row
            .byte <($2000 + ((row & 7) * $400) + (((row >> 3) & 7) * $80) + ((row >> 6) * 40))
        .endrepeat
C_HGR_ROW_HI:
        .repeat 192, row
            .byte >($2000 + ((row & 7) * $400) + (((row >> 3) & 7) * $80) + ((row >> 6) * 40))
        .endrepeat
; Two 24-entry lookup arrays convert a 0-23 hour to the tens and ones
; character codes of a 12-hour clock. The caller adds $20 before printing.
C_CLOCK_HOUR_TENS:
        .byte $11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11
        .byte $11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11
C_CLOCK_HOUR_ONES:
        .byte $12,$11,$12,$13,$14,$15,$16,$17,$18,$19,$10,$11
        .byte $12,$11,$12,$13,$14,$15,$16,$17,$18,$19,$10,$11
; Thirteen 19-byte detective slots in F / the $0C00 roster buffer.
C_DETECTIVE_OFFSETS:
        .repeat 13, slot
            .byte slot * 19
        .endrepeat
; $80-$FF token dictionary for S2 text; code $80 starts at the first word.
C_WORD_DICTIONARY:
        .asciiz "a" ; $80
        .asciiz "about" ; $81
        .asciiz "address" ; $82
        .asciiz "an" ; $83
        .asciiz "ancestors" ; $84
        .asciiz "and" ; $85
        .asciiz "article" ; $86
        .asciiz "at" ; $87
        .asciiz "bag" ; $88
        .asciiz "been" ; $89
        .asciiz "between" ; $8A
        .asciiz "biography" ; $8B
        .asciiz "black" ; $8C
        .asciiz "blue" ; $8D
        .asciiz "book" ; $8E
        .asciiz "briefcase" ; $8F
        .asciiz "business" ; $90
        .asciiz "by" ; $91
        .asciiz "car" ; $92
        .asciiz "catch" ; $93
        .asciiz "character" ; $94
        .asciiz "Communist" ; $95
        .asciiz "compartment" ; $96
        .asciiz "containing" ; $97
        .asciiz "country" ; $98
        .asciiz "countries" ; $99
        .asciiz "cross" ; $9A
        .asciiz "discover" ; $9B
        .asciiz "Europe" ; $9C
        .asciiz "family" ; $9D
        .asciiz "find" ; $9E
        .asciiz "flag" ; $9F
        .asciiz "for" ; $A0
        .asciiz "found" ; $A1
        .asciiz "from" ; $A2
        .asciiz "genealogist" ; $A3
        .asciiz "German" ; $A4
        .asciiz "going" ; $A5
        .asciiz "government" ; $A6
        .asciiz "guide" ; $A7
        .asciiz "had" ; $A8
        .asciiz "has" ; $A9
        .asciiz "heading" ; $AA
        .asciiz "head" ; $AB
        .asciiz "hear" ; $AC
        .asciiz "heard" ; $AD
        .asciiz "hide" ; $AE
        .asciiz "I" ; $AF
        .asciiz "if" ; $B0
        .asciiz "in" ; $B1
        .asciiz "industries" ; $B2
        .asciiz "inside" ; $B3
        .asciiz "intercepted" ; $B4
        .asciiz "is" ; $B5
        .asciiz "island" ; $B6
        .asciiz "islands" ; $B7
        .asciiz "it" ; $B8
        .asciiz "job" ; $B9
        .asciiz "largest" ; $BA
        .asciiz "language" ; $BB
        .asciiz "languages" ; $BC
        .asciiz "learned" ; $BD
        .asciiz "letter" ; $BE
        .asciiz "low" ; $BF
        .asciiz "map" ; $C0
        .asciiz "me" ; $C1
        .asciiz "Mediterranean" ; $C2
        .asciiz "membership" ; $C3
        .asciiz "music" ; $C4
        .asciiz "nation" ; $C5
        .asciiz "newspaper" ; $C6
        .asciiz "night" ; $C7
        .asciiz "north" ; $C8
        .asciiz "Norwegian" ; $C9
        .asciiz "notebook" ; $CA
        .asciiz "notice" ; $CB
        .asciiz "noticed" ; $CC
        .asciiz "of" ; $CD
        .asciiz "on" ; $CE
        .asciiz "one" ; $CF
        .asciiz "out" ; $D0
        .asciiz "overdue" ; $D1
        .asciiz "paintings" ; $D2
        .asciiz "party" ; $D3
        .asciiz "person" ; $D4
        .asciiz "planned" ; $D5
        .asciiz "planning" ; $D6
        .asciiz "plans" ; $D7
        .asciiz "postage" ; $D8
        .asciiz "postcard" ; $D9
        .asciiz "red" ; $DA
        .asciiz "reading" ; $DB
        .asciiz "said" ; $DC
        .asciiz "say" ; $DD
        .asciiz "Sea" ; $DE
        .asciiz "search" ; $DF
        .asciiz "seen" ; $E0
        .asciiz "ski" ; $E1
        .asciiz "smallest" ; $E2
        .asciiz "some" ; $E3
        .asciiz "someone" ; $E4
        .asciiz "suitcase" ; $E5
        .asciiz "suspect" ; $E6
        .asciiz "suspicious" ; $E7
        .asciiz "Switzerland" ; $E8
        .asciiz "taking" ; $E9
        .asciiz "tape" ; $EA
        .asciiz "that" ; $EB
        .asciiz "the" ; $EC
        .asciiz "there" ; $ED
        .asciiz "thief" ; $EE
        .asciiz "ticket" ; $EF
        .asciiz "to" ; $F0
        .asciiz "told" ; $F1
        .asciiz "travel" ; $F2
        .asciiz "traveling" ; $F3
        .asciiz "understand" ; $F4
        .asciiz "wallet" ; $F5
        .asciiz "wanted" ; $F6
        .asciiz "was" ; $F7
        .asciiz "wearing" ; $F8
        .asciiz "white" ; $F9
        .asciiz "with" ; $FA
        .asciiz "word" ; $FB
        .asciiz "world" ; $FC
        .asciiz "written" ; $FD
        .asciiz "you" ; $FE
        .asciiz "your" ; $FF

; Named game tables immediately after the S2 token dictionary.
C_CITY_NAMES:
        .asciiz "Athens"
        .asciiz "Baghdad"
        .asciiz "Bamako"
        .asciiz "Bangkok"
        .asciiz "Budapest"
        .asciiz "Buenos Aires"
        .asciiz "Cairo"
        .asciiz "Colombo"
        .asciiz "Istanbul"
        .asciiz "Kathmandu"
        .asciiz "Kigali"
        .asciiz "Lima"
        .asciiz "London"
        .asciiz "Mexico City"
        .asciiz "Montreal"
        .asciiz "Moroni"
        .asciiz "Moscow"
        .asciiz "New Delhi"
        .asciiz "New York"
        .asciiz "Oslo"
        .asciiz "Paris"
        .asciiz "Beijing"
        .asciiz "Port Moresby"
        .asciiz "Reykjavik"
        .asciiz "Rio de Janeiro"
        .asciiz "Rome"
        .asciiz "San Marino"
        .asciiz "Singapore"
        .asciiz "Sydney"
        .asciiz "Tokyo"

C_SUSPECT_NAMES:
        .asciiz "Carmen Sandiego"
        .asciiz "Merey LaRoc"
        .asciiz "Dazzle Annie"
        .asciiz "Lady Agatha"
        .asciiz "Katherine Drib"
        .asciiz "Len Bulk"
        .asciiz "Scar Graynolt"
        .asciiz "Nick Brunch"
        .asciiz "Fast Eddie B"
        .asciiz "Ihor Ihorovitch"

C_DETECTIVE_RANKS:
        .asciiz "Rookie"
        .asciiz "Sleuth"
        .asciiz "Private Eye"
        .asciiz "Investigator"
        .asciiz "Ace Detective"
        .asciiz "Super Sleuth"

C_WEEKDAYS:
        .asciiz "Mon"
        .asciiz "Tues"
        .asciiz "Wed"
        .asciiz "Thur"
        .asciiz "Fri"
        .asciiz "Sat"
        .asciiz "Sun"
; Seven parallel suffixes complete full weekday names before "day" is appended.
C_WEEKDAY_SUFFIXES:
        .asciiz ""      ; Monday
        .asciiz ""      ; Tuesday
        .asciiz "nes"   ; Wednesday
        .asciiz "s"     ; Thursday
        .asciiz ""      ; Friday
        .asciiz "ur"    ; Saturday
        .asciiz ""      ; Sunday
; Thirty split pointers select the packed bitmaps at $EC00-$F945.
C_ICON_PTR_LO:
        .byte <C_ICON_00,<C_ICON_01,<C_ICON_02,<C_ICON_03,<C_ICON_04
        .byte <C_ICON_05,<C_ICON_06,<C_ICON_07,<C_ICON_08,<C_ICON_09
        .byte <C_ICON_10,<C_ICON_11,<C_ICON_12,<C_ICON_13,<C_ICON_14
        .byte <C_ICON_15,<C_ICON_16,<C_ICON_17,<C_ICON_18,<C_ICON_19
        .byte <C_ICON_20,<C_ICON_21,<C_ICON_22,<C_ICON_23,<C_ICON_24
        .byte <C_ICON_25,<C_ICON_26,<C_ICON_27,<C_ICON_28,<C_ICON_29
; Five T frames, then all 26 U sprites in table order, then a zero entry.
C_ANIMATION_PTR_LO:
        .include "c_animation_ptr_lo.inc"
C_ICON_PTR_HI:
        .byte >C_ICON_00,>C_ICON_01,>C_ICON_02,>C_ICON_03,>C_ICON_04
        .byte >C_ICON_05,>C_ICON_06,>C_ICON_07,>C_ICON_08,>C_ICON_09
        .byte >C_ICON_10,>C_ICON_11,>C_ICON_12,>C_ICON_13,>C_ICON_14
        .byte >C_ICON_15,>C_ICON_16,>C_ICON_17,>C_ICON_18,>C_ICON_19
        .byte >C_ICON_20,>C_ICON_21,>C_ICON_22,>C_ICON_23,>C_ICON_24
        .byte >C_ICON_25,>C_ICON_26,>C_ICON_27,>C_ICON_28,>C_ICON_29
C_ANIMATION_PTR_HI:
        .include "c_animation_ptr_hi.inc"
; Suspect clue categories, each stored as NUL-terminated display text.
C_SEX_LABELS:
        .asciiz "Male"
        .asciiz "Female"

C_HOBBY_LABELS:
        .asciiz "Tennis"
        .asciiz "Music"
        .asciiz "Mt.Climbing"
        .asciiz "Skydiving"
        .asciiz "Swimming"
        .asciiz "Croquet"

C_HAIR_LABELS:
        .asciiz "Brown"
        .asciiz "Blond"
        .asciiz "Red"
        .asciiz "Black"

C_FEATURE_LABELS:
        .asciiz "Limps"
        .asciiz "Ring"
        .asciiz "Tattoo"
        .asciiz "Scar"
        .asciiz "Jewelry"

C_VEHICLE_LABELS:
        .asciiz "Convertible"
        .asciiz "Limousine"
        .asciiz "Racecar"
        .asciiz "Motorcycle"

C_FOOD_LABELS:
        .asciiz "Mexican"
        .asciiz "Seafood"
; Zero padding through the next page boundary at $E000.
        .res 470, $00
; Interface strings occupy $E000-$EB3A; zero padding ends at $EC00.
        .include "c_ui_text.inc"
; Thirty packed bitmaps occupy $EC00-$F978.
        .include "c_icons.inc"
