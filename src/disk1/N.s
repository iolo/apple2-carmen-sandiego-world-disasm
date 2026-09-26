; disk1/N: $6000, 11996 bytes, sha256 293137de334e724d69bb6437dc7925da628dbb0187e683100d8d04c0fc6f8389
; Main game entry at $6000. It initializes case state and calls services in
; the resident $D200 and $9800 modules. Remaining code/data boundaries need
; review; the exact byte match does not establish a complete control flow map.
; This file is verified to assemble to exactly the source file bytes.
.segment "CODE"

        .setcpu "6502"

RAM_QUIT_TRAMPOLINE           := $0100
B_LOAD_MODULE           := $9800
B_LOAD_S2_RECORD           := $9809
B_LOAD_S2_TEXT           := $980C
B_SAVE_F           := $980F
B_SAVE_G           := $9812
B_SAVE_H           := $9815
PRODOS_MLI           := $BF00
C_COPY_PAGE_TO_AUX_9F00           := $D200
C_APPEND_6000_STRING           := $D203
C_SKIP_NUL_STRINGS           := $D206
C_COPY_STRING           := $D209
C_HGR_AUX_TO_MAIN           := $D20F
C_HGR_MAIN_TO_AUX           := $D212
C_APPEND_5000_TEXT           := $D215
C_COPY_PAGES_TO_AUX           := $D21B
C_DETECTIVE_OFFSETS := $D7B0
C_WORD_DICTIONARY   := $D7BD
C_CLOCK_HOUR_TENS   := $D780
C_CLOCK_HOUR_ONES   := $D798
C_ICON_PTR_LO      := $DD00
C_ICON_PTR_HI      := $DD3E
N_ANIMATION_GLYPH_BASE := $89 ; $6B font glyphs + $1E embedded C icons
N_ARREST_MARKER_GLYPH_INDEX := N_ANIMATION_GLYPH_BASE + 29 ; U sprite 24
C_WEEKDAYS         := $DCD5
C_WEEKDAY_SUFFIXES := $DCF3
C_CITY_NAMES := $DB11
C_SUSPECT_NAMES := $DC0F
C_DETECTIVE_RANKS := $DC93
G_HALL_OF_FAME := $0D00
F_DETECTIVE_ROSTER := $0C00
WARRANT_SUSPECT := $0017
J_ROUTE_DESTS        := $9F00
J_ROUTE_OFFSETS      := $9FD8
CITY_PLACE_STATE     := $9E5A ; three slots: $FF or packed trait/category
MENU_LEFT_PIXEL      := $9E70 ; selection rectangle endpoints by menu row
MENU_RIGHT_PIXEL     := $9E80
D_FONT_PTR_LO      := $B900
D_FONT_PTR_HI      := $B970
CASE_SUSPECT        := $0000
CASE_ROUTE_GRAPH           := $0001
CASE_INVESTIGATION_COUNT   := $0016
CASE_TREASURE_TEXT         := $0019
CASE_CITY_MENU_SELECTION   := $001A
CASE_ROUTE_INDEX    := $0002
CASE_ROUTE          := $0003
CASE_HIDEOUT_CITY     := $0010
CASE_CURRENT_CITY   := $0011
CASE_DAY            := $0012
CASE_HOUR           := $0013
CASE_DEADLINE_DAY   := $0014
CASE_DEADLINE_HOUR  := $0015
SOUND_ENABLED       := $0018
SUSPECT_TRAIT_FILTERS := $001B ; six selected values, $FF means unset
JOYSTICK_ENABLED    := $0099
JOYSTICK_DIRECTION_BITS := $0066
DETECTIVE_RANK      := $005B
CASES_SOLVED        := $005C
SAVED_CASE          := $006D
; Aliases for route-line scratch storage; other routines reuse these bytes.
N_ROUTE_X           := $B4 ; two-pixel units
N_ROUTE_END_X       := $B5
N_ROUTE_Y           := $B6 ; HGR scanlines
N_ROUTE_END_Y       := $B7
N_ROUTE_ERROR       := $B8
N_ROUTE_DELTA_X     := $B9
N_ROUTE_DELTA_Y     := $BA
N_ROUTE_DELAY       := $78
N_ROUTE_POINT_COUNT := $A7
.include "../shared/n_ui_text_ids.inc"
ROM_RETURN_ENTRY_FF65           := $FF65
; Initialize stack, memory-bank service, and case state.
N_MAIN_ENTRY:  ldx     #$FF
        txs
        lda     #$08
        jsr     N_RANDOM_BELOW
        sta     CASE_ROUTE_GRAPH
        jsr     C_COPY_PAGE_TO_AUX_9F00
        lda     #$00
        sta     $68
        sta     $64
        sta     $6A
        sta     $6B
        sta     $65
        sta     $8F
        lda     #$01
        sta     $89
        sta     $63
        sta     CASE_ROUTE_INDEX
        lda     #$10
        sta     $92
        lda     #$30
        sta     $AB
        lda     #$FF
        sta     WARRANT_SUSPECT
        ldy     #$05
N_CLEAR_SUSPECT_TRAIT_FILTERS:  sta     SUSPECT_TRAIT_FILTERS,y
        dey
        bpl     N_CLEAR_SUSPECT_TRAIT_FILTERS
        lda     #$07
        jsr     N_RANDOM_BELOW
        sta     CASE_DAY
        sta     CASE_DEADLINE_DAY
        dec     CASE_DEADLINE_DAY
        bpl     N_RANDOMIZE_START_HOUR
        lda     #$06
        sta     CASE_DEADLINE_DAY
N_RANDOMIZE_START_HOUR:  lda     #$0A
        jsr     N_RANDOM_BELOW
        adc     #$08
        sta     CASE_HOUR
        sta     CASE_DEADLINE_HOUR
        lda     $60
        beq     N_REGISTER_DETECTIVE
        jsr     N_DRAW_CLOCK_HOUR
        jsr     N_DRAW_CLOCK_WEEKDAY
        jsr     N_DRAW_CLOCK_AM_PM
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$04
        sta     $70
        lda     #$03
        sta     $71
        jmp     N_BEGIN_CASE

; New detective: draw registration prompt and read up to 15 characters into
; $9E60, with one byte left for the terminator/sentinel. Printable ASCII
; $20-$7E is accepted; Delete/$08 backs up, and Return needs a nonempty
; name whose first character is not a space.
N_REGISTER_DETECTIVE:  jsr     N_PREPARE_REPORT_SCREEN
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        bit     $C010
N_SHOW_IDENTIFY_PROMPT:  ldy     #N_UI_IDENTIFY_PROMPT
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
N_RESET_NAME_INPUT:  ldy     #$0F
        lda     #$FF
N_CLEAR_NAME_BUFFER:  sta     $9E60,y
        dey
        bpl     N_CLEAR_NAME_BUFFER
        lda     #$03
        sta     $70
        sta     $71
        lda     #$99
        sta     $72
        lda     #$00
        sta     $9D
        bit     $C010
N_READ_NAME_KEY:  jsr     N_READ_GAME_KEY
        cmp     #$20
        bcc     N_HANDLE_NAME_CONTROL_KEY
        cmp     #$7F
        bcs     N_HANDLE_NAME_CONTROL_KEY
        ldy     $70
        cpy     #$10
        bcs     N_REJECT_NAME_KEY
        ldy     $9D
        cpy     #$0F
        bcs     N_REJECT_NAME_KEY
        sta     $9E60,y
        jsr     N_TOGGLE_TEXT_CURSOR
        ldy     $9D
        lda     $9E60,y
        jsr     N_DRAW_GLYPH_CHAR
        jsr     N_TOGGLE_TEXT_CURSOR
        inc     $9D
        jmp     N_READ_NAME_KEY

N_HANDLE_NAME_CONTROL_KEY:  cmp     #$0D
        bne     N_HANDLE_NAME_DELETE_KEY
        lda     $9D
        bne     N_CHECK_LEADING_SPACE
N_REJECT_EMPTY_NAME:  jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_READ_NAME_KEY

N_CHECK_LEADING_SPACE:  lda     $9E60
        cmp     #$20
        beq     N_REJECT_EMPTY_NAME
        jmp     N_CHECK_RESERVED_NAME

N_HANDLE_NAME_DELETE_KEY:  cmp     #$7F
        bne     N_CHECK_BACKSPACE
N_DELETE_LAST_NAME_CHAR:  jsr     N_TOGGLE_TEXT_CURSOR
        jsr     N_DELETE_LAST_NAME_CHARACTER
        jsr     N_TOGGLE_TEXT_CURSOR
        jmp     N_READ_NAME_KEY

N_CHECK_BACKSPACE:  cmp     #$08
        beq     N_DELETE_LAST_NAME_CHAR
N_REJECT_NAME_KEY:  jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_READ_NAME_KEY

; Reject any of 15 strings starting at C_SUSPECT_NAMES. The range includes
; ten suspect names and the first five detective-rank names.
N_CHECK_RESERVED_NAME:  lda #$00
        sta     $A6
N_CHECK_NEXT_RESERVED_NAME:  lda     $A6
        ldx     #<C_SUSPECT_NAMES
        ldy     #>C_SUSPECT_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     N_COMPARE_INPUT_NAME
        bcc     N_REJECT_RESERVED_NAME
        inc     $A6
        lda     $A6
        cmp     #$0F
        bne     N_CHECK_NEXT_RESERVED_NAME
        jmp     N_CHECK_HALL_OF_FAME_NAME

N_REJECT_RESERVED_NAME:  ldy     #N_UI_CRIMINAL_DENIAL
        jsr     N_DRAW_UI_TEXT
        jmp     N_SHOW_IDENTIFY_PROMPT

; The sixteen 16-byte G slots retain names of former Super Sleuths.
N_CHECK_HALL_OF_FAME_NAME:  lda #<G_HALL_OF_FAME
        sta     $C4
        lda     #>G_HALL_OF_FAME
        sta     $C5
        lda     #$00
        sta     $AC
N_CHECK_NEXT_HALL_NAME:  ldx     $C4
        ldy     $C5
        jsr     N_COMPARE_INPUT_NAME
        bcc     N_REJECT_HALL_NAME
        clc
        lda     $C4
        adc     #$10
        sta     $C4
        inc     $AC
        lda     $AC
        cmp     #$10
        bcc     N_CHECK_NEXT_HALL_NAME
        jmp     N_SEARCH_DETECTIVE_ROSTER

N_REJECT_HALL_NAME:  ldy     #N_UI_FAMOUS_SLEUTH_ALIAS
        jsr     N_DRAW_UI_TEXT
        jsr     N_SHOW_WARRANT_FOLLOWUP
        ldy     #$27
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        jmp     N_SHOW_IDENTIFY_PROMPT

; Compare the entered name against the 13 records in the F roster at $0C00.
; An existing record supplies rank, solved-case count, and saved-case flag.
N_SEARCH_DETECTIVE_ROSTER:  lda     #$00
        sta     $C4
        lda     #$0C
        sta     $C5
        lda     #$00
        sta     $AC
N_CHECK_NEXT_ROSTER_NAME:  ldx     $C4
        ldy     $C5
        jsr     N_COMPARE_INPUT_NAME
        bcs     N_ADVANCE_ROSTER_SLOT
        ldy     #$10
        lda     ($C4),y
        sta     DETECTIVE_RANK
        iny
        lda     ($C4),y
        sta     CASES_SOLVED
        iny
        lda     ($C4),y
        sta     SAVED_CASE
        lda     $AC
        sta     $5D
        jmp     N_BEGIN_CASE

N_ADVANCE_ROSTER_SLOT:  inc     $AC
        lda     $AC
        cmp     #$0D
        beq     N_ASK_CREATE_RECORD
        tay
        lda     C_DETECTIVE_OFFSETS,y
        sta     $C4
        jmp     N_CHECK_NEXT_ROSTER_NAME

N_ASK_CREATE_RECORD:  ldy     #N_UI_NO_NAME_RECORD
        jsr     N_DRAW_UI_TEXT
        jsr     N_READ_YES_NO_RESPONSE
        cmp     #$59
        beq     N_CREATE_DETECTIVE_RECORD
        ldy     #N_UI_TYPE_NAME_PROMPT
        jsr     N_DRAW_UI_TEXT
        jmp     N_RESET_NAME_INPUT

; Find a record whose first byte is $FF, then store the new name and clear its
; three status bytes before asking the B loader to save the roster. All 13
; slots are checked before reporting that the roster is full.
N_CREATE_DETECTIVE_RECORD:  ldx     #$00
        stx     $AC
        lda     #$0C
        sta     $C5
N_FIND_EMPTY_ROSTER_SLOT:  ldy     $AC
        lda     C_DETECTIVE_OFFSETS,y
        sta     $C4
        lda     ($C4,x)
        cmp     #$FF
        beq     N_COPY_NAME_TO_ROSTER
        inc     $AC
        lda     $AC
        cmp     #$0D
        bne     N_FIND_EMPTY_ROSTER_SLOT
        ldy     #N_UI_ROSTER_FULL
        jsr     N_DRAW_UI_TEXT
        jmp     N_SHOW_IDENTIFY_PROMPT

N_COPY_NAME_TO_ROSTER:  ldy     #$0F
N_COPY_NAME_BYTE:  lda     $9E60,y
        sta     ($C4),y
        dey
        bpl     N_COPY_NAME_BYTE
        ldy     #$10
        lda     #$00
        sta     ($C4),y
        sta     DETECTIVE_RANK
        iny
        sta     ($C4),y
        sta     CASES_SOLVED
        iny
        sta     ($C4),y
        sta     SAVED_CASE
        lda     $AC
        sta     $5D
        jsr     B_SAVE_F
N_BEGIN_CASE:  ldx     DETECTIVE_RANK
        cpx     #$04
        bcc     N_PICK_NON_CARMEN_SUSPECT
        lda     CASES_SOLVED
        cmp     #$1D
        bcc     N_PICK_NON_CARMEN_SUSPECT
        lda     #$00
        jmp     N_SET_CASE_SUSPECT

N_PICK_NON_CARMEN_SUSPECT:  lda     #$0A
        jsr     N_RANDOM_BELOW
        cmp     CASE_SUSPECT
        beq     N_PICK_NON_CARMEN_SUSPECT
        cmp     #$00
        beq     N_PICK_NON_CARMEN_SUSPECT
N_SET_CASE_SUSPECT:  sta     CASE_SUSPECT
; Choose the final hideout first; build the route backward from that city.
        lda     #$1E
        jsr     N_RANDOM_BELOW
        sta     CASE_HIDEOUT_CITY
        sta     CASE_CURRENT_CITY
        clc
        lda     DETECTIVE_RANK
        adc     #$03
        sta     $AC
        sta     $83
        tay
        lda     CASE_HIDEOUT_CITY
        sta     CASE_ROUTE,y
        dec     $AC
; Follow one randomly selected outgoing J edge. Reject a destination
; already used later in this route; store accepted cities back toward slot 0.
N_GENERATE_ROUTE_STEP:  jsr     N_CITY_ROUTE_COUNT
        txa
        bne     N_PICK_ROUTE_DESTINATION
; No outgoing route remains. Ring the bell three times and restart setup.
N_ROUTE_DEAD_END: jsr     N_DEFAULT_FEEDBACK_TONE
        jsr     N_DEFAULT_FEEDBACK_TONE
        jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_MAIN_ENTRY

N_PICK_ROUTE_DESTINATION:  jsr     N_RANDOM_BELOW
        ldx     CASE_CURRENT_CITY
        adc     J_ROUTE_OFFSETS,x
        tay
        lda     J_ROUTE_DESTS,y
        ldx     $83
N_CHECK_ROUTE_CITY:  cmp     CASE_ROUTE,x
        beq     N_GENERATE_ROUTE_STEP
        dex
        cpx     $AC
        bne     N_CHECK_ROUTE_CITY
        sta     CASE_ROUTE,x
        sta     CASE_CURRENT_CITY
        dec     $AC
        bpl     N_GENERATE_ROUTE_STEP
; The reversed route is complete. Welcome the detective and announce the case.
N_SHOW_CASE_WELCOME:
        jsr     N_RESET_TEXT_BUFFER_A000
        ldy     #N_UI_WELCOME_PREFIX
        jsr     N_APPEND_UI_TEXT
        ldx     #$60
        ldy     #$9E
        jsr     C_COPY_STRING
        ldy     #N_UI_RANK_SUFFIX
        jsr     N_APPEND_UI_TEXT
        ldx     #$00
        ldy     #$A0
        jsr     N_DRAW_TEXT_XY
        lda     #$00
        sta     $AC
        lda     DETECTIVE_RANK
        ldx     #<C_DETECTIVE_RANKS
        ldy     #>C_DETECTIVE_RANKS
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        ldy     #N_UI_SENTENCE_PERIOD
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     SAVED_CASE
        beq     N_SET_ANNOUNCEMENT_POSITION
        jsr     N_PROMPT_TO_RESUME_CASE
        clc
        lda     #$99
        sta     $97
        adc     #$09
        sta     $98
        ldx     #$0A
        ldy     #$18
        jsr     HGR_FILL_RECT
        ldy     #$0C
        jsr     N_SET_HGR_X_FROM_Y
        jsr     N_TOGGLE_TEXT_CURSOR
        jmp     N_ANNOUNCE_NEWS_FLASH

N_SET_ANNOUNCEMENT_POSITION:  lda     #$03
        sta     $70
        sta     $71
N_ANNOUNCE_NEWS_FLASH:  lda     #$00
        sta     $AC
        ldy     #N_UI_NEWS_FLASH_PREFIX
        jsr     N_APPEND_UI_TEXT
        lda     CASE_ROUTE
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        jsr     N_END_TEXT_SENTENCE
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_TREASURE_IDENTIFIED
        jsr     N_APPEND_UI_TEXT
        lda     CASE_CURRENT_CITY
        sta     $87
        asl     a
        clc
        adc     $87
        sta     $87
        lda     #$03
        jsr     N_RANDOM_BELOW
        adc     $87
        sta     CASE_TREASURE_TEXT
        jsr     C_APPEND_6000_STRING
        jsr     N_END_TEXT_SENTENCE
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_SELECT_MALE_SUSPECT_WORD
        ldy     #N_UI_FEMALE
        jmp     N_ANNOUNCE_SUSPECT

N_SELECT_MALE_SUSPECT_WORD:  ldy     #N_UI_MALE
N_ANNOUNCE_SUSPECT:  jsr     N_APPEND_UI_TEXT
        ldy     #N_UI_SUSPECT_REPORTED
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_TRACK_THIEF_FROM
        jsr     N_APPEND_UI_TEXT
        lda     CASE_ROUTE
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        lda     #$20
        sta     ($DA),y
        inc     $AC
        ldy     #N_UI_TO
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_SELECT_HIS_POSSESSIVE
        ldy     #N_UI_HER_POSSESSIVE
        jmp     N_APPEND_TRACKING_POSSESSIVE

N_SELECT_HIS_POSSESSIVE:  ldy     #N_UI_HIS_POSSESSIVE
N_APPEND_TRACKING_POSSESSIVE:  jsr     N_APPEND_UI_TEXT
        ldy     #N_UI_HIDEOUT_AND_ARREST
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_SELECT_HIM_OBJECT
        ldy     #N_UI_HER_OBJECT
        jmp     N_APPEND_ARREST_OBJECT

N_SELECT_HIM_OBJECT:  ldy     #N_UI_HIM_OBJECT
N_APPEND_ARREST_OBJECT:  jsr     N_APPEND_UI_TEXT
        lda     #$8D
        sta     ($DA),y
        iny
        lda     #$00
        sta     ($DA),y
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_DEADLINE_PREFIX
        jsr     N_APPEND_UI_TEXT
        lda     CASE_DEADLINE_DAY
        ldx     #<C_WEEKDAYS
        ldy     #>C_WEEKDAYS
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        lda     CASE_DEADLINE_DAY
        ldx     #<C_WEEKDAY_SUFFIXES
        ldy     #>C_WEEKDAY_SUFFIXES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        ldy     #N_UI_DAY_SUFFIX
        jsr     N_APPEND_UI_TEXT
        ldx     CASE_DEADLINE_HOUR
        cpx     #$0A
        bcc     N_APPEND_DEADLINE_HOUR_ONES
        cpx     #$16
        bcs     N_APPEND_DEADLINE_HOUR_TENS
        cpx     #$0D
        bcs     N_APPEND_DEADLINE_HOUR_ONES
N_APPEND_DEADLINE_HOUR_TENS:  lda     C_CLOCK_HOUR_TENS,x
        clc
        adc     #$20
        sta     ($DA),y
        iny
        inc     $AC
N_APPEND_DEADLINE_HOUR_ONES:  lda     C_CLOCK_HOUR_ONES,x
        clc
        adc     #$20
        sta     ($DA),y
        inc     $AC
        cpx     #$0C
        bcs     N_SELECT_DEADLINE_PM
        ldy     #N_UI_AM
        jmp     N_APPEND_DEADLINE_MERIDIEM

N_SELECT_DEADLINE_PM:  ldy     #N_UI_PM
N_APPEND_DEADLINE_MERIDIEM:  jsr     N_APPEND_UI_TEXT
        ldy     #N_UI_GOOD_LUCK
        jsr     N_APPEND_UI_TEXT
        ldx     #$60
        ldy     #$9E
        jsr     C_COPY_STRING
        ldy     #N_UI_CHIEF_SIGNOFF
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
; Reset the three city option slots, prepare clues, and present the city menu.
N_PREPARE_CITY_MENU:  ldy     #$02
        lda     #$FF
N_CLEAR_CITY_OPTIONS:  sta     CITY_PLACE_STATE,y
        dey
        bpl     N_CLEAR_CITY_OPTIONS
        lda     #$00
        sta     CASE_INVESTIGATION_COUNT
        jsr     N_ROUTE_COMPLETE
        bcc     N_SELECT_CITY_OPTION
        jsr     N_ASSIGN_CITY_PLACE_CLUES
        jmp     N_PREPARE_CITY_SCREEN

N_SELECT_CITY_OPTION:  lda     #$03
        jsr     N_RANDOM_BELOW
        tay
        lda     #$01
        sta     CITY_PLACE_STATE,y
N_PREPARE_CITY_SCREEN:  jsr     N_PREPARE_CITY_CLUES
N_SHOW_CITY_SCREEN:  jsr     N_DRAW_CITY_SCREEN
N_WAIT_CITY_INPUT:  bit     $C010
        lda     #$01
        sta     $65
        jsr     N_WAIT_MENU_SELECTION
        lda     #$00
        sta     $65
        ldx     #$04
        ldy     #$87
        jsr     N_SET_HGR_HORIZONTAL_CLIP
        lda     $76
        cmp     #$1B
        bne     N_DISPATCH_CITY_SELECTION
        jsr     N_DEFAULT_FEEDBACK_TONE
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        inc     $74
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        inc     $74
        jmp     N_WAIT_CITY_INPUT

; The menu selection in $6C dispatches city information, travel, investigation,
; or the remaining command modes below.
N_DISPATCH_CITY_SELECTION:  lda     $6C
        sta     CASE_CITY_MENU_SELECTION
        bne     N_CHECK_TRAVEL_SELECTION
        lda     $9E
        bne     N_HIDE_CONNECTIONS
        inc     $74
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        jsr     N_DRAW_TRAVEL_DESTINATION_LIST
        jsr     N_CLEAR_MENU_TOP_STRIP
        ldy     #N_UI_HIDE_CONNECTIONS
        jsr     N_DRAW_CONNECTION_TOGGLE_OPTION
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jmp     N_WAIT_CITY_INPUT

N_HIDE_CONNECTIONS:  inc     $74
        ldy     #$00
        jsr     C_HGR_MAIN_TO_AUX
        jsr     N_CLEAR_MENU_TOP_STRIP
        ldy     #N_UI_SEE_CONNECTIONS
        jsr     N_DRAW_CONNECTION_TOGGLE_OPTION
        lda     #$00
        sta     $9E
        sta     $89
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jmp     N_WAIT_CITY_INPUT

N_CHECK_TRAVEL_SELECTION:  cmp     #$01
        beq     N_SHOW_TRAVEL_MENU
        jmp     N_CHECK_INVESTIGATION_SELECTION

; Show destinations reachable from the current city and read the selection.
N_SHOW_TRAVEL_MENU:  inc     $74
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        lda     #$01
        sta     $68
        lda     #$00
        sta     $94
        jsr     N_DRAW_TRAVEL_DESTINATION_LIST
        dec     $68
        lda     #$25
        sta     $D0
        lda     #$8D
        sta     $D1
        lda     #$00
        sta     $6C
        jsr     N_CITY_ROUTE_COUNT
        dex
        stx     $6F
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        ldy     #$03
        jsr     C_HGR_AUX_TO_MAIN
        ldy     #$03
        jsr     HGR_RLE_DRAW_N
        lda     #$B9
        sta     $97
        lda     #$BA
        sta     $98
        ldx     #$1A
        ldy     #$76
        jsr     HGR_CLEAR_RECT
        jsr     N_CLEAR_CURRENT_CITY_MAP_MARKER
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     $AB
        sta     $A9
        lda     #$00
        sta     $69
        lda     #$01
        sta     $64
        bit     $C010
        jsr     N_WAIT_MENU_SELECTION
        lda     #$00
        sta     $64
        sta     $89
        lda     $69
        bne     N_HANDLE_TRAVEL_INPUT
        jsr     N_GET_SELECTED_ROUTE_DESTINATION
        jsr     N_DRAW_ROUTE_DESTINATION_MARKER
N_HANDLE_TRAVEL_INPUT:  lda     $76
        cmp     #$1B
        bne     N_TRAVEL_TO_SELECTED_CITY
        inc     $74
        ldy     #$00
        jsr     C_HGR_MAIN_TO_AUX
        ldy     #$03
        jsr     C_HGR_MAIN_TO_AUX
        lda     #$00
        sta     $9E
        jsr     N_DRAW_MAIN_CITY_MENU
        lda     #$01
        sta     $6C
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jmp     N_WAIT_CITY_INPUT

; Animate the move and advance the planned route index only when the selected
; destination is the next route city and is not the final hideout.
N_TRAVEL_TO_SELECTED_CITY:  lda     $72
        pha
        ldx     CASE_CURRENT_CITY
        jsr     N_STORE_CURRENT_CITY_MAP_POSITION
        pla
        sta     $72
        jsr     N_GET_SELECTED_ROUTE_DESTINATION
        jsr     N_GET_CITY_MAP_POSITION_AND_ROW
        sta     N_ROUTE_END_X
        sty     N_ROUTE_END_Y
        jsr     N_DRAW_TRAVEL_ROUTE_LINE
; Count includes both endpoints; charge 1 + floor(point_count / 4) hours.
        lda     N_ROUTE_POINT_COUNT
        lsr     a
        lsr     a
        clc
        adc     #$01
        tax
        jsr     N_ADVANCE_CASE_HOURS
        lda     #$00
        sta     $62
        jsr     N_GET_SELECTED_ROUTE_DESTINATION
        txa
        ldy     CASE_ROUTE_INDEX
        cmp     CASE_ROUTE,y
        bne     N_FINISH_TRAVEL
        cmp     CASE_HIDEOUT_CITY
        beq     N_FINISH_TRAVEL
        inc     CASE_ROUTE_INDEX
        inc     $62
N_FINISH_TRAVEL:  stx     CASE_CURRENT_CITY
        lda     #$02
        sta     CASE_CITY_MENU_SELECTION
        jmp     N_PREPARE_CITY_MENU

N_CHECK_INVESTIGATION_SELECTION:  cmp     #$02
        beq     N_SHOW_INVESTIGATION_MENU
        jmp     N_SHOW_COMPUTER_SAVE_MENU

; Present three location choices and then resolve the selected clue or arrest.
N_SHOW_INVESTIGATION_MENU:  inc     $74
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        lda     #$01
        sta     $89
        ldy     #$01
        jsr     C_HGR_AUX_TO_MAIN
        ldy     #$03
        jsr     N_DRAW_FRAMED_MENU_RECT
        jsr     N_DRAW_INVESTIGATION_CHOICES
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_DRAW_INVESTIGATION_TITLES
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        bit     $C010
        jsr     N_WAIT_MENU_SELECTION
        lda     $76
        cmp     #$1B
        beq     N_AFTER_INVESTIGATION_INPUT
        jsr     N_ANIMATE_INVESTIGATION_SELECTION
N_AFTER_INVESTIGATION_INPUT:  inc     $74
        ldy     #$01
        jsr     C_HGR_MAIN_TO_AUX
        lda     $76
        cmp     #$1B
        bne     N_RESOLVE_INVESTIGATION_CHOICE
        jmp     N_RETURN_TO_CITY_SCREEN

; At the final city, one of the three place slots starts marked 1. The first
; visit to that slot can move the mark to a different slot (FF becomes 0).
; Later visits to a marked slot enter the arrest sequence.
N_RESOLVE_INVESTIGATION_CHOICE:  jsr     N_ROUTE_COMPLETE
        bcs     N_INVESTIGATE_DURING_ROUTE
        jsr     N_CLEAR_PICTURE_PANEL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        inc     $74
        ldx     $6C
        lda     CITY_PLACE_STATE,x
        beq     N_START_ARREST_FROM_PLACE
        bmi     N_PLAY_PLACE_EVENT
        lda     CASE_INVESTIGATION_COUNT
        bne     N_START_ARREST_FROM_PLACE
        lda     #$FF
        sta     CITY_PLACE_STATE,x
N_PICK_NEW_SUSPECT_PLACE:  lda     #$03
        jsr     N_RANDOM_BELOW
        cmp     $6C
        beq     N_PICK_NEW_SUSPECT_PLACE
        tax
        inc     CITY_PLACE_STATE,x
        jmp     N_PLAY_PLACE_EVENT

N_START_ARREST_FROM_PLACE:  jmp     N_RESOLVE_ARREST

N_PLAY_PLACE_EVENT:  lda     #$03
        jsr     N_RANDOM_BELOW
        tay
        lda     N_RANDOM_ANIMATION_ENTRY_LO,y
        sta     N_RANDOM_PLACE_CALL_LO
        lda     N_RANDOM_ANIMATION_ENTRY_HI,y
        sta     N_RANDOM_PLACE_CALL_HI
; The selected address from the two tables below patches this JSR operand.
N_CALL_RANDOM_PLACE_ANIMATION:  jsr     $0000
N_RANDOM_PLACE_CALL_LO   := N_CALL_RANDOM_PLACE_ANIMATION + 1
N_RANDOM_PLACE_CALL_HI   := N_CALL_RANDOM_PLACE_ANIMATION + 2
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$05
        jsr     N_PLAY_SOUND_TRACK
        inc     $74
        jsr     N_RESET_INVESTIGATION_TEXT_CURSOR
        lda     #$04
        jsr     N_RANDOM_BELOW
        adc     #$04
        tax
        jsr     C_APPEND_5000_TEXT
        jmp     N_SHOW_INVESTIGATION_RESULT

N_INVESTIGATE_DURING_ROUTE:  dey
        lda     CASE_CURRENT_CITY
        cmp     CASE_ROUTE,y
        beq     N_INVESTIGATE_PLANNED_CITY
        jsr     N_CLEAR_INVESTIGATION_TEXT_PANEL
        lda     #$04
        jsr     N_RANDOM_BELOW
        adc     #$00
        tax
        jsr     C_APPEND_5000_TEXT
        jmp     N_SHOW_INVESTIGATION_RESULT

N_INVESTIGATE_PLANNED_CITY:  lda     $62
        bne     N_PLAY_ROUTE_CITY_EVENT
N_SHOW_STANDARD_PLACE_CLUE:  jmp     N_BUILD_PLACE_CLUE

N_PLAY_ROUTE_CITY_EVENT:  lda     CASE_ROUTE_INDEX
        cmp     #$01
        beq     N_SHOW_STANDARD_PLACE_CLUE
        jsr     N_CLEAR_PICTURE_PANEL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        clc
        lda     #$03
        jsr     N_RANDOM_BELOW
        adc     #$02
        jsr     N_PLAY_SOUND_TRACK
        lda     #$02
        jsr     N_RANDOM_BELOW
        cmp     #$01
        beq     N_PLAY_ALTERNATE_ROUTE_ANIMATION
        jsr     N_ANIMATE_PRIMARY_ROUTE_EVENT
        jmp     N_FINISH_ROUTE_CITY_EVENT

N_PLAY_ALTERNATE_ROUTE_ANIMATION:  jsr     N_ANIMATE_ALTERNATE_ROUTE_EVENT
N_FINISH_ROUTE_CITY_EVENT:  lda     #$00
        sta     $62
        jsr     N_CLEAR_PICTURE_PANEL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        inc     $74
        lda     $63
        beq     N_FINISH_OPTIONAL_ROUTE_MESSAGE
        ldx     #$68
        stx     $93
        ldy     #$40
        lda     #$2A
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        lda     #$2B
        ldx     $93
        ldy     $72
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     $93
        ldy     $72
        lda     #$2C
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$01
        jsr     N_PLAY_SOUND_TRACK
        lda     #$00
        sta     $63
        ldy     #$10
        jsr     N_DELAY_WITH_ZERO_ACCUMULATOR
        inc     $74
        jsr     N_CLEAR_PICTURE_PANEL
N_FINISH_OPTIONAL_ROUTE_MESSAGE:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        inc     $74
; Build the place description, then select one clue text from the location's
; packed trait/category value. FF means no additional clue.
N_BUILD_PLACE_CLUE:  jsr     N_CLEAR_INVESTIGATION_TEXT_PANEL
        jsr     N_APPEND_SUSPECT_SUBJECT_PRONOUN
        lda     $6C
        ldx     #$00
        ldy     #$0F
        jsr     C_SKIP_NUL_STRINGS
        stx     $C4
        sty     $C5
        jsr     N_EXPAND_TOKENIZED_TEXT
        jsr     N_END_TEXT_SENTENCE
        sty     $AC
        ldy     $6C
        lda     CITY_PLACE_STATE,y
        cmp     #$FF
        bne     N_APPEND_CHOSEN_PLACE_CLUE
        jmp     N_SHOW_INVESTIGATION_RESULT

; Low nibble selects one of five offset lists; high nibble is the culprit's
; value for that trait and selects a group within the chosen list.
N_APPEND_CHOSEN_PLACE_CLUE:  ldy     #$38
        jsr     N_APPEND_UI_TEXT
        jsr     N_APPEND_SUSPECT_SUBJECT_PRONOUN
        ldy     $6C
        lda     CITY_PLACE_STATE,y
        pha
        and     #$0F
        tax
        pla
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     $9C
        tay
        lda     N_CLUE_OFFSET_PTR_LO,x
        sta     $C2
        lda     N_CLUE_OFFSET_PTR_HI,x
        sta     $C3
        lda     ($C2),y
        jsr     N_RANDOM_BELOW
        adc     #$08
        adc     N_CLUE_TEXT_BASE,x
        ldy     #$00
N_SUM_PRIOR_CLUE_GROUPS:  cpy     $9C
        bcs     N_APPEND_SELECTED_CLUE_TEXT
        adc     ($C2),y
        iny
        bne     N_SUM_PRIOR_CLUE_GROUPS
N_APPEND_SELECTED_CLUE_TEXT:  tax
        jsr     C_APPEND_5000_TEXT
        jsr     N_END_TEXT_SENTENCE
N_SHOW_INVESTIGATION_RESULT:  ldx     #$00
        ldy     #$A0
        lda     #$4A
        jsr     N_DRAW_TEXT_POINTER_AT_X
        ldx     #$04
        ldy     #$87
        jsr     N_SET_HGR_HORIZONTAL_CLIP
N_RETURN_TO_CITY_SCREEN:  jsr     N_DRAW_MAIN_CITY_MENU
        lda     #$02
        sta     $6C
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        lda     $76
        cmp     #$1B
        beq     N_WAIT_FOR_NEXT_CITY_ACTION
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        inc     CASE_INVESTIGATION_COUNT
        ldx     CASE_INVESTIGATION_COUNT
        cpx     #$04
        bcc     N_ADVANCE_INVESTIGATION_TIME
        ldx     #$03
N_ADVANCE_INVESTIGATION_TIME:  jsr     N_ADVANCE_CASE_HOURS
N_WAIT_FOR_NEXT_CITY_ACTION:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$00
        sta     $89
        jmp     N_WAIT_CITY_INPUT

; City action menu: Use Computer or Save Case. Return from the save prompt
; writes H and F only when the player confirms with Return.
N_SHOW_COMPUTER_SAVE_MENU:  inc     $74
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        lda     #$01
        sta     $89
        jsr     N_CLEAR_LOWER_MENU_PANEL
        lda     #$02
        sta     $94
        lda     #$01
        sta     $68
        ldx     #$02
        stx     $6F
        ldy     N_MAIN_MENU_ROWS,x
        ldx     #$68
        lda     #N_UI_SAVE_CASE
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        lda     #$01
        sta     $94
        sta     $6E
        sta     $6C
        tax
        ldy     N_MAIN_MENU_ROWS,x
        ldx     $93
        lda     #N_UI_USE_COMPUTER
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        dec     $68
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        bit     $C010
        jsr     N_WAIT_MENU_SELECTION
        lda     $76
        cmp     #$1B
        bne     N_HANDLE_COMPUTER_SAVE_CHOICE
        inc     $74
        jsr     N_DRAW_MAIN_CITY_MENU
        lda     #$03
        sta     $6C
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$00
        sta     $89
        jmp     N_WAIT_CITY_INPUT

N_HANDLE_COMPUTER_SAVE_CHOICE:  lda     $6C
        cmp     #$02
        bne     N_OPEN_COMPUTER
        inc     $74
        ldy     #$02
        jsr     C_HGR_AUX_TO_MAIN
        ldy     #$04
        jsr     N_DRAW_FRAMED_MENU_RECT
        jsr     N_DRAW_SAVE_CASE_PROMPT
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jsr     N_READ_GAME_KEY
        inc     $74
        ldy     #$02
        jsr     C_HGR_MAIN_TO_AUX
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     $76
        cmp     #$0D
        bne     N_RESHOW_COMPUTER_SAVE_MENU
        jmp     N_SAVE_CURRENT_CASE

N_RESHOW_COMPUTER_SAVE_MENU:  jmp     N_SHOW_COMPUTER_SAVE_MENU

; Six computer rows correspond to the six suspect traits. Row six evaluates
; the current filters and may issue a warrant if exactly one suspect remains.
N_OPEN_COMPUTER:  jsr     N_CLEAR_NEXT_MODAL_HGR_PAGE
        jsr     N_DRAW_COMMON_SCREEN_BACKGROUND
        jsr     N_DRAW_CURRENT_CITY_NAME
        ldy     #$02
        jsr     HGR_RLE_DRAW_N
        ldy     #$0C
        jsr     N_SET_HGR_X_FROM_Y
        lda     #$99
        sta     $72
        lda     #$5F
        jsr     N_DRAW_GLYPH_INDEX
        ldy     #$04
        jsr     HGR_RLE_DRAW_N
        lda     #$32
        sta     $D0
        lda     #$8D
        sta     $D1
        lda     #$00
        sta     $A8
        sta     $6E
        sta     $6C
        lda     #$06
        sta     $6F
N_DRAW_NEXT_COMPUTER_TRAIT:  ldy     $A8
        jsr     N_DRAW_TRAIT_VALUE
        inc     $A8
        lda     $A8
        cmp     #$06
        bne     N_DRAW_NEXT_COMPUTER_TRAIT
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        ldy     #N_UI_READY
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
N_WAIT_COMPUTER_SELECTION:  lda     #$01
        sta     $6A
        bit     $C010
        jsr     N_WAIT_MENU_SELECTION
        dec     $6A
        lda     $76
        cmp     #$1B
        bne     N_HANDLE_COMPUTER_SELECTION
N_LEAVE_COMPUTER:  lda     #$00
        sta     $89
        jmp     N_SHOW_CITY_SCREEN

N_HANDLE_COMPUTER_SELECTION:  lda     $6C
        cmp     #$06
        beq     N_EVALUATE_WARRANT
        jsr     N_CLEAR_PREVIOUS_TRAIT
        ldx     $6C
        lda     SUSPECT_TRAIT_FILTERS,x
        cmp     #$FF
        beq     N_SELECT_NEXT_TRAIT_VALUE
        cmp     N_CLUE_CATEGORY_LIMIT,x
        bcc     N_SELECT_NEXT_TRAIT_VALUE
        lda     #$FF
        sta     SUSPECT_TRAIT_FILTERS,x
        jmp     N_WAIT_COMPUTER_SELECTION

N_SELECT_NEXT_TRAIT_VALUE:  inc     SUSPECT_TRAIT_FILTERS,x
        ldy     $6C
        jsr     N_DRAW_TRAIT_VALUE
        jmp     N_WAIT_COMPUTER_SELECTION

N_EVALUATE_WARRANT:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jsr     N_FIND_WARRANT_MATCHES
        jsr     N_SHOW_WARRANT_MATCHES
        jsr     N_DRAW_MENU_ROW_MARKER
        lda     #$01
        sta     $6A
        ldx     #$02
        jsr     N_ADVANCE_CASE_HOURS
        dec     $6A
        jsr     N_SHOW_WARRANT_FOLLOWUP
N_FINISH_WARRANT_SCREEN:  jmp     N_LEAVE_COMPUTER

N_DRAW_TRAIT_VALUE:  lda     SUSPECT_TRAIT_FILTERS,y
        cmp     #$FF
        beq     N_TRAIT_VALUE_DRAWN
        lda     #$1C
        sta     $70
        lda     #$00
        sta     $71
        lda     CLUE_TEXT_ROW,y
        sta     $72
        lda     SUSPECT_TRAIT_FILTERS,y
        pha
        ldx     N_CLUE_STRING_PTR_LO,y
        lda     N_CLUE_STRING_PTR_HI,y
        tay
        pla
        jsr     C_SKIP_NUL_STRINGS
        stx     $C2
        sty     $C3
        jsr     N_PREPARE_TEXT_SCAN
N_TRAIT_VALUE_DRAWN:  rts

; The case deadline expired; report the suspect's escape before the next case.
N_REPORT_CASE_TIMEOUT:  jsr     N_PREPARE_REPORT_SCREEN
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jsr     N_RESET_TEXT_BUFFER_A000
        ldy     #N_UI_INTERPOL_HERE
        jsr     N_APPEND_UI_TEXT
        ldy     #N_UI_BAD_NEWS
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        ldy     #$5C
        jmp     N_APPEND_CASE_FEEDBACK

; Compare the warrant target with the actual culprit after the arrest scene.
; $FF means there was no warrant.
N_RESOLVE_ARREST:  jsr     N_CLEAR_PICTURE_PANEL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        ldx     #$94
        ldy     #$0E
        lda     #$03
        jsr     C_COPY_PAGES_TO_AUX
        lda     #$06
        jsr     N_PLAY_SOUND_TRACK
        jsr     N_ANIMATE_ARREST_FIRST_STAGE
        ldx     #$68
        stx     $93
        ldy     #$50
        lda     #$2D
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     $93
        ldy     $72
        lda     #$2E
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     #$08
        jsr     N_PLAY_SOUND_TRACK
        ldx     #$85
        ldy     #$0E
        lda     #$0F
        jsr     C_COPY_PAGES_TO_AUX
        ldy     #$06
        jsr     N_DELAY_WITH_ZERO_ACCUMULATOR
        inc     $74
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     #$09
        jsr     N_PLAY_SOUND_TRACK
        jsr     N_ANIMATE_ARREST_SECOND_STAGE
        ldx     #$94
        ldy     #$0E
        lda     #$0E
        jsr     C_COPY_PAGES_TO_AUX
        lda     CASE_SUSPECT
        cmp     WARRANT_SUSPECT
        bne     N_ARREST_WITH_WRONG_WARRANT
        ora     #$80
        sta     $8E
        lda     #$0A
        jsr     N_PLAY_SOUND_TRACK
        jsr     N_ANIMATE_CORRECT_WARRANT
        jmp     N_CONTINUE_ARREST_ANIMATION

N_ARREST_WITH_WRONG_WARRANT:  lda     WARRANT_SUSPECT
        sta     $8E
        lda     #$0B
        jsr     N_PLAY_SOUND_TRACK
        jsr     N_ANIMATE_WRONG_WARRANT
N_CONTINUE_ARREST_ANIMATION:  inc     $74
        ldx     #$80
        ldy     #$11
        lda     #$05
        jsr     C_COPY_PAGES_TO_AUX
        jsr     N_DRAW_ARREST_SCENE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     WARRANT_SUSPECT
        cmp     CASE_SUSPECT
        bne     N_SHOW_ARREST_RESULT
        lda     #$00
        jsr     N_PLAY_SOUND_TRACK
        inc     $74
        lda     #$A7
        jsr     N_DRAW_ARREST_SYMBOL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
N_SHOW_ARREST_RESULT:  jsr     N_PREPARE_REPORT_SCREEN
        jsr     N_DRAW_ARREST_SCENE
        lda     WARRANT_SUSPECT
        cmp     CASE_SUSPECT
        bne     N_FINISH_ARREST_ANIMATION
        lda     #$A7
        jsr     N_DRAW_ARREST_SYMBOL
N_FINISH_ARREST_ANIMATION:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        lda     WARRANT_SUSPECT
        cmp     CASE_SUSPECT
        beq     N_HANDLE_CORRECT_ARREST
        jsr     N_BEGIN_FAILED_CASE_REPORT
        lda     WARRANT_SUSPECT
        cmp     #$FF
        bne     N_REPORT_WRONG_WARRANT
        ldy     #N_UI_CAUGHT_UP
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        jsr     N_END_TEXT_SENTENCE
        ldy     #N_UI_NO_WARRANT
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_GANG_ESCAPED
        jmp     N_APPEND_CASE_FEEDBACK

N_REPORT_WRONG_WARRANT:  ldy     #N_UI_TRAILED_SUSPECT
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        ldy     #N_UI_TRAILED_CORRECTLY
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_WRONG_WARRANT
        jsr     N_APPEND_UI_TEXT
        lda     WARRANT_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        jsr     N_END_TEXT_SENTENCE
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_FALSE_ARREST_WARNING
        jmp     N_APPEND_CASE_FEEDBACK

; Capturing Carmen (suspect zero) retires the detective; other arrests count
; toward the promotion thresholds.
N_HANDLE_CORRECT_ARREST:  jsr     N_RESET_TEXT_BUFFER_A000
        lda     CASE_SUSPECT
        bne     N_COUNT_SOLVED_CASE
        inc     DETECTIVE_RANK
        inc     CASES_SOLVED
        jsr     N_SAVE_DETECTIVE_PROGRESS
        ldy     #N_UI_CAUGHT_CARMEN
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        jsr     N_SHOW_WARRANT_FOLLOWUP
        ldy     #N_UI_SUPER_SLEUTH_RETIRED
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        jmp     N_RETIRE_TO_HALL_OF_FAME

N_COUNT_SOLVED_CASE:  inc     CASES_SOLVED
        ldy     DETECTIVE_RANK
        lda     CASES_SOLVED
        cmp     RANK_PROMOTION_CASES,y
        bcc     N_REPORT_SUCCESS_WITHOUT_PROMOTION
        inc     DETECTIVE_RANK
        ldy     #N_UI_PROMOTION
        jmp     N_REPORT_SOLVED_CASE

N_REPORT_SUCCESS_WITHOUT_PROMOTION:  ldy     #N_UI_SUCCESS_RECORDED
        jmp     N_REPORT_SOLVED_CASE

; Store the retired detective in G, using its final slot if all sixteen are
; occupied, then clear the corresponding 19-byte F roster record.
N_RETIRE_TO_HALL_OF_FAME:  ldy     #<G_HALL_OF_FAME
        sty     $C4
        lda     #>G_HALL_OF_FAME
        sta     $C5
N_FIND_FREE_HALL_SLOT:  lda     ($C4),y
        cmp     #$FF
        beq     N_COPY_NAME_TO_HALL
        lda     $C4
        clc
        adc     #$10
        sta     $C4
        bcc     N_FIND_FREE_HALL_SLOT
        lda     #$F0
        sta     $C4
N_COPY_NAME_TO_HALL:  lda     $9E60,y
        sta     ($C4),y
        cmp     #$FF
        beq     N_SAVE_HALL_AND_REMOVE_ROSTER
        iny
        bne     N_COPY_NAME_TO_HALL
N_SAVE_HALL_AND_REMOVE_ROSTER:  jsr     B_SAVE_G
        ldx     $5D
        lda     C_DETECTIVE_OFFSETS,x
        sta     $C4
        lda     #$0C
        sta     $C5
        lda     #$FF
        ldy     #$12
N_CLEAR_RETIRED_ROSTER_SLOT:  sta     ($C4),y
        dey
        bpl     N_CLEAR_RETIRED_ROSTER_SLOT
        jsr     B_SAVE_F
        ldy     #N_UI_CHIEF_SERVICE
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        jsr     N_SHOW_WARRANT_FOLLOWUP
        jsr     N_SHOW_HALL_OF_FAME
        lda     #$00
        sta     $60
        jmp     N_MAIN_ENTRY

; Y selects either the recorded-success message or the promotion message.
N_REPORT_SOLVED_CASE:  sty     $8E
        jsr     N_SAVE_DETECTIVE_PROGRESS
        ldy     #N_UI_THANKS_TO_YOU
        jsr     N_APPEND_UI_TEXT
        lda     CASE_HIDEOUT_CITY
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        ldy     #N_UI_POLICE_APPREHENDED
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        jsr     N_END_TEXT_SENTENCE
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_EMPTY
        jsr     N_APPEND_UI_TEXT
        lda     CASE_SUSPECT
        jsr     N_APPEND_SUSPECT_NAME
        ldy     #N_UI_HAD_LOOT
        jsr     N_APPEND_UI_TEXT
        lda     CASE_TREASURE_TEXT
        jsr     C_APPEND_6000_STRING
        ldy     #N_UI_LOOT_RETURNED
        jsr     N_APPEND_UI_TEXT
        lda     CASE_ROUTE
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        jsr     N_END_TEXT_SENTENCE
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     #N_UI_INTERPOL_THANKS
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        lda     #$00
        sta     $AC
        ldy     $8E
        cpy     #N_UI_SUCCESS_RECORDED
        bne     N_CHECK_PROMOTION_REPORT
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
N_REPORT_CASES_UNTIL_PROMOTION:  lda     #$00
        sta     $AC
        ldy     #N_UI_EMPTY
        jsr     N_APPEND_UI_TEXT
        ldx     DETECTIVE_RANK
        sec
        lda     RANK_PROGRESS_CASES,x
        sbc     CASES_SOLVED
        pha
        clc
        adc     #$6B
        tay
        dey
        jsr     N_APPEND_UI_TEXT
        ldy     #N_UI_MORE_CASES
        jsr     N_APPEND_UI_TEXT
        pla
        cmp     #$01
        beq     N_APPEND_UNTIL_PROMOTION
        ldy     $AC
        lda     #$73
        sta     $A000,y
        inc     $AC
N_APPEND_UNTIL_PROMOTION:  ldy     #N_UI_UNTIL_PROMOTION
        jsr     N_APPEND_UI_TEXT
        jsr     N_DRAW_TEXT_BUFFER_LEFT_MARGIN
        jmp     N_ASK_FOR_NEXT_CASE

N_APPEND_CASE_FEEDBACK:  jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
N_ASK_FOR_NEXT_CASE:  lda     #$00
        sta     $AC
        ldy     #N_UI_NEXT_CASE_PROMPT
        jsr     N_APPEND_UI_TEXT
        ldx     #$60
        ldy     #$9E
        jsr     C_COPY_STRING
        ldy     #N_UI_YES_NO_SUFFIX
        jsr     N_APPEND_UI_TEXT
        jsr     N_DRAW_TEXT_BUFFER_LEFT_MARGIN
        jsr     N_READ_YES_NO_RESPONSE
        cmp     #$59
        beq     N_ACCEPT_NEXT_CASE
        lda     #$00
        jmp     N_STORE_NEXT_CASE_CHOICE

N_ACCEPT_NEXT_CASE:  lda     #$01
N_STORE_NEXT_CASE_CHOICE:  sta     $60
        jmp     N_MAIN_ENTRY

N_CHECK_PROMOTION_REPORT:  cpy     #N_UI_PROMOTION
        bne     N_SKIP_PROMOTION_PROGRESS
        ldy     #N_UI_PROMOTION
        jsr     N_APPEND_UI_TEXT
        lda     DETECTIVE_RANK
        ldx     #<C_DETECTIVE_RANKS
        ldy     #>C_DETECTIVE_RANKS
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        ldy     #$3A
        jsr     N_APPEND_UI_TEXT
        jsr     N_SHOW_TEXT_BUFFER_A000
        jmp     N_REPORT_CASES_UNTIL_PROMOTION

N_SKIP_PROMOTION_PROGRESS:  jmp     N_APPEND_CASE_FEEDBACK

N_BEGIN_FAILED_CASE_REPORT:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jsr     N_RESET_TEXT_BUFFER_A000
        ldy     #N_UI_ATTENTION_PREFIX
        jsr     N_APPEND_UI_TEXT
        ldx     #$60
        ldy     #$9E
        jsr     C_COPY_STRING
        jsr     N_END_TEXT_SENTENCE
        ldy     #$38
        jsr     N_APPEND_UI_TEXT
        rts

; A selects a suspect name to append to the current $A000 report.
N_APPEND_SUSPECT_NAME:  ldx     #<C_SUSPECT_NAMES
        ldy     #>C_SUSPECT_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        rts

N_DRAW_ARREST_SCENE:  ldy     #$05
        jsr     HGR_RLE_DRAW_N
        lda     $8E
        bpl     N_ARREST_SCENE_DONE
        cmp     #$FF
        beq     N_ARREST_SCENE_DONE
        lda     #N_ARREST_MARKER_GLYPH_INDEX
N_DRAW_ARREST_SYMBOL:  ldx     #$4D
        stx     $72
        ldx     #$19
        stx     $70
        jsr     N_PREPARE_GLYPH_INDEX
        ldx     $CC
        ldy     $CD
        jsr     N_COPY_BITMAP_ROWS_TO_HGR
N_ARREST_SCENE_DONE:  rts

; Persist rank and solved-case count in the active F roster slot.
N_SAVE_DETECTIVE_PROGRESS:  ldy     $5D
        lda     C_DETECTIVE_OFFSETS,y
        clc
        adc     #$10
        tay
        lda     DETECTIVE_RANK
        sta     F_DETECTIVE_ROSTER,y
        iny
        lda     CASES_SOLVED
        sta     F_DETECTIVE_ROSTER,y
        jsr     B_SAVE_F
        rts

; Draw the current $A000 report at the default left margin.
N_DRAW_TEXT_BUFFER_LEFT_MARGIN:  lda     #$0C
        sta     $73
        jsr     N_SET_HGR_X_FROM_73
        ldx     #$00
        ldy     #$A0
        jsr     N_DRAW_TEXT_XY
        rts

; Carry clear when the planned next city and current city are both the
; final hideout. Otherwise carry set.
N_ROUTE_COMPLETE:  ldy     CASE_ROUTE_INDEX
        lda     CASE_ROUTE,y
        cmp     CASE_HIDEOUT_CITY
        bne     N_ROUTE_NOT_COMPLETE
        lda     CASE_CURRENT_CITY
        cmp     CASE_HIDEOUT_CITY
        bne     N_ROUTE_NOT_COMPLETE
        clc
        rts

N_ROUTE_NOT_COMPLETE:  sec
        rts

N_QUIT_TO_PRODOS:  lda     $C082
        lda     $C051
        lda     $C054
        sta     $C008
        sta     $C00C
        jsr     PRODOS_MLI
        .byte   $65             ; ProDOS MLI QUIT
        .word   N_QUIT_PARAMS
        jmp     N_QUIT_TO_PRODOS

N_QUIT_PARAMS:
        .byte   $04, $00, $00, $00, $00, $00, $00
; Y selects one of C's NUL-separated interface strings at $E000.
; Return its address in X/Y; the append entry copies it to $DA/$DB + $AC.
N_SELECT_UI_TEXT:  tya
        ldx     #$00
        ldy     #$E0
        jmp     C_SKIP_NUL_STRINGS

N_APPEND_UI_TEXT:  jsr     N_SELECT_UI_TEXT
        jmp     C_COPY_STRING

N_STORE_CURRENT_CITY_MAP_POSITION:  ldx     CASE_CURRENT_CITY
        jsr     N_GET_CITY_MAP_POSITION_AND_ROW
        sta     N_ROUTE_X
        sty     N_ROUTE_Y
        rts

; Return the route line's X coordinate in two-pixel units in A and HGR row in Y.
N_GET_CITY_MAP_POSITION_AND_ROW:  lda     N_CITY_ROUTE_X,x
        pha
        jsr     N_LOAD_CITY_MAP_POSITION
        ldy     $72
        pla
        rts

N_DELAY_WITH_ZERO_ACCUMULATOR:  lda     #$00
N_DELAY_Y_COUNTS:  jsr     N_DELAY_NESTED_A_Y
        dey
        bne     N_DELAY_Y_COUNTS
        rts

; Clear this detective's H page, copy zero-page case state $00-$20 into it,
; save H, and mark the third byte of the detective's F roster record.
N_SAVE_CURRENT_CASE:  jsr     N_LOAD_DETECTIVE_SAVE_PAGE
        ldy     #$00
        tya
N_CLEAR_SAVED_CASE_PAGE:  sta     ($C4),y
        iny
        bne     N_CLEAR_SAVED_CASE_PAGE
        ldy     #$20
N_COPY_CASE_STATE_TO_SAVE_PAGE:  lda     $00,y
        sta     ($C4),y
        dey
        bpl     N_COPY_CASE_STATE_TO_SAVE_PAGE
        jsr     B_SAVE_H
        ldy     $5D
        lda     C_DETECTIVE_OFFSETS,y
        clc
        adc     #$12
        tay
        lda     #$01
        sta     $0C00,y
        jsr     B_SAVE_F
        lda     #$00
        sta     $60
        jmp     N_MAIN_ENTRY

N_PROMPT_TO_RESUME_CASE:  ldy     #N_UI_RESUME_CASE_PROMPT
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        jsr     N_READ_YES_NO_RESPONSE
        cmp     #$59
        beq     N_RESTORE_SAVED_CASE
        jsr     N_CLEAR_SAVED_CASE_FLAG
        rts

N_RESTORE_SAVED_CASE:  jsr     N_LOAD_DETECTIVE_SAVE_PAGE
        ldy     #$20
N_COPY_SAVED_PAGE_TO_CASE_STATE:  lda     ($C4),y
        sta     $00,y
        dey
        bpl     N_COPY_SAVED_PAGE_TO_CASE_STATE
        lda     #$02
        sta     CASE_CITY_MENU_SELECTION
        jsr     N_CLEAR_SAVED_CASE_FLAG
        jsr     C_COPY_PAGE_TO_AUX_9F00
        jmp     N_PREPARE_CITY_MENU

; Clear the saved-case flag when the saved case is resumed or discarded.
N_CLEAR_SAVED_CASE_FLAG:  ldy     $5D
        lda     C_DETECTIVE_OFFSETS,y
        clc
        adc     #$12
        tay
        lda     #$00
        sta     $0C00,y
        sta     SAVED_CASE
        jsr     B_SAVE_F
        rts

; H is module 13. Its thirteen pages are loaded at $1100, one per detective.
N_LOAD_DETECTIVE_SAVE_PAGE:  ldy     #$0D
        jsr     B_LOAD_MODULE
        bcc     N_POINT_TO_DETECTIVE_SAVE_PAGE
        ldx     #$01
        jsr     N_PROMPT_FOR_DISK
        jmp     N_LOAD_DETECTIVE_SAVE_PAGE

N_POINT_TO_DETECTIVE_SAVE_PAGE:  lda     $5D
        clc
        adc     #$11
        sta     $C5             ; page $11 + detective slot
        lda     #$00
        sta     $C4
        rts

; Advance up to X hours, stopping early when a transition reports carry.
N_ADVANCE_CASE_HOURS:  stx     $88
N_ADVANCE_NEXT_CASE_HOUR:  jsr     N_ADVANCE_CASE_HOUR
        bcs     N_CASE_HOURS_ADVANCED
        dec     $88
        bne     N_ADVANCE_NEXT_CASE_HOUR
N_CASE_HOURS_ADVANCED:  rts

; Y points at the current terminator. Keep a trailing quote, or add a period,
; then write NUL and update the text-buffer cursor $AC.
N_END_TEXT_SENTENCE:  dey
        lda     ($DA),y
        cmp     #$22
        beq     N_WRITE_SENTENCE_TERMINATOR
        iny
        lda     #$2E
        sta     ($DA),y
N_WRITE_SENTENCE_TERMINATOR:  iny
        lda     #$00
        sta     ($DA),y
        sty     $AC
        rts

N_APPEND_SUSPECT_SUBJECT_PRONOUN:  lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_SELECT_HE_SUBJECT
        ldy     #N_UI_SHE_SUBJECT
        jmp     N_APPEND_SELECTED_SUBJECT_PRONOUN

N_SELECT_HE_SUBJECT:  ldy     #N_UI_HE_SUBJECT
N_APPEND_SELECTED_SUBJECT_PRONOUN:  jsr     N_APPEND_UI_TEXT
        rts

; Erase the previous glyph, move the input cursor back, and restore $FF in
; the vacated name slot. An empty name is left unchanged.
N_DELETE_LAST_NAME_CHARACTER: ldy $9D
        beq     N_NAME_DELETE_DONE
        dey
        lda     $9E60,y
        pha
        jsr     N_MOVE_LEFT_BY_GLYPH_WIDTH
        pla
        pha
        jsr     N_DRAW_GLYPH_CHAR
        pla
        jsr     N_MOVE_LEFT_BY_GLYPH_WIDTH
        dec     $9D
        ldy     $9D
        lda     #$FF
        sta     $9E60,y
N_NAME_DELETE_DONE:  rts

N_MOVE_LEFT_BY_GLYPH_WIDTH:  jsr     N_PREPARE_GLYPH_CHAR
        jsr     N_REWIND_GLYPH_CURSOR
        rts

N_CLEAR_INVESTIGATION_TEXT_PANEL:  jsr     N_CLEAR_PICTURE_PANEL
N_RESET_INVESTIGATION_TEXT_CURSOR:  lda     #$4A
        sta     $91
        lda     #$1A
        sta     $72
        jsr     N_RESET_TEXT_BUFFER_A000
        rts

; For each place, sometimes select one of the culprit's five non-sex traits.
; The chosen trait must have a nonzero offset list entry. Pack its value in
; the high nibble and category 0-4 in the low nibble of CITY_PLACE_STATE.
N_ASSIGN_CITY_PLACE_CLUES:  ldx     #$02
N_TRY_NEXT_CITY_PLACE:  lda     #$02
        jsr     N_RANDOM_BELOW
        cmp     #$01
        bne     N_ADVANCE_CITY_PLACE_SLOT
N_PICK_CULPRIT_TRAIT_CLUE:  lda     #$05
        jsr     N_RANDOM_BELOW
        sta     $5E
        clc
        lda     CASE_SUSPECT
        asl     a
        sta     $9C
        asl     a
        adc     $9C
        adc     #$01
        adc     $5E
        tay
        lda     SUSPECT_TRAIT_MATRIX,y
        sta     $9C
        ldy     $5E
        lda     N_CLUE_OFFSET_PTR_LO,y
        sta     $C2
        lda     N_CLUE_OFFSET_PTR_HI,y
        sta     $C3
        ldy     $9C
        lda     ($C2),y
        beq     N_PICK_CULPRIT_TRAIT_CLUE
        tya
        asl     a
        asl     a
        asl     a
        asl     a
        ora     $5E
        sta     CITY_PLACE_STATE,x
N_ADVANCE_CITY_PLACE_SLOT:  dex
        bpl     N_TRY_NEXT_CITY_PLACE
        rts

; Remove a four-row, two-byte marker at the current city's map position
; before the travel menu redraws that part of the screen.
N_CLEAR_CURRENT_CITY_MAP_MARKER:  ldx     CASE_CURRENT_CITY
        jsr     N_LOAD_CITY_MAP_POSITION
        lda     $71
        sec
        sbc     #$01
        bcs     N_SET_MAP_MARKER_PIXEL_COLUMN
        dec     $70
        adc     #$07
N_SET_MAP_MARKER_PIXEL_COLUMN:  sta     $71
        lda     $72
        sec
        sbc     #$01
        sta     $72
        lda     #$04
        sta     $85
        ldx     $71
N_CLEAR_NEXT_MAP_MARKER_ROW:  ldy     $72
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        lda     ($C0),y
        and     N_HGR_CLEAR_MASK_A,x
        sta     ($C0),y
        iny
        lda     ($C0),y
        and     N_HGR_CLEAR_MASK_B,x
        sta     ($C0),y
        inc     $72
        dec     $85
        bne     N_CLEAR_NEXT_MAP_MARKER_ROW
        rts

; Advance the day/hour clock, check the deadline, and redraw it. At 22:00
; the game advances internally to 07:00 and returns carry set to its caller.
N_ADVANCE_CASE_HOUR:  inc     CASE_HOUR
        lda     CASE_DAY
        cmp     CASE_DEADLINE_DAY
        bne     N_CHECK_CLOCK_TRANSITIONS
        lda     CASE_HOUR
        cmp     CASE_DEADLINE_HOUR
        bne     N_CHECK_CLOCK_TRANSITIONS
        jmp     N_REPORT_CASE_TIMEOUT

N_CHECK_CLOCK_TRANSITIONS:  lda     CASE_HOUR
        cmp     #$0C
        bne     N_CHECK_DAY_ROLLOVER
        jsr     N_DRAW_CLOCK_AM_PM
        jmp     N_SHOW_CLOCK_TICK

N_CHECK_DAY_ROLLOVER:  cmp     #$18
        bne     N_REDRAW_DAY_ON_CLOCK
        lda     #$00
        sta     CASE_HOUR
        jsr     N_DRAW_CLOCK_AM_PM
        inc     CASE_DAY
        lda     CASE_DAY
        cmp     #$07
        bcc     N_REDRAW_DAY_ON_CLOCK
        lda     #$00
        sta     CASE_DAY
N_REDRAW_DAY_ON_CLOCK:  jsr     N_DRAW_CLOCK_WEEKDAY
N_SHOW_CLOCK_TICK:  jsr     N_DRAW_CLOCK_HOUR
        ldy     #$0A
        lda     #$03
        jsr     N_PLAY_FEEDBACK_TONE
        lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        lda     CASE_HOUR
        cmp     #$16
        beq     N_BEGIN_OVERNIGHT_SKIP
        clc
        rts

N_BEGIN_OVERNIGHT_SKIP:  jsr     N_CLEAR_CLOCK_PANEL
        lda     #$01
        ldy     #$0E
        ldx     #$1C
        jsr     N_DRAW_CENTERED_UI_TEXT
N_SKIP_NEXT_NIGHT_HOUR:  lda     CASE_HOUR
        cmp     #$07
        beq     N_FINISH_OVERNIGHT_SKIP
        jsr     N_ADVANCE_CASE_HOUR
        jmp     N_SKIP_NEXT_NIGHT_HOUR

N_FINISH_OVERNIGHT_SKIP:  jsr     N_CLEAR_CLOCK_PANEL
        jsr     N_DRAW_CURRENT_CITY_NAME
        sec
        rts

; Load the current city's S2 record and the planned route city's text, then
; use that route city's twelve category counts to select three distinct
; displayed clues. The first three S2 strings precede the selectable clues.
N_PREPARE_CITY_CLUES:  lda     CASE_CURRENT_CITY
        jsr     B_LOAD_S2_RECORD
        lda     #$03
        jsr     N_RANDOM_BELOW
        ldx     #$00
        ldy     #$A0
        jsr     C_SKIP_NUL_STRINGS
        stx     $C4
        sty     $C5
        ldy     #$00
N_COPY_SELECTED_CITY_STRING_BYTE:  lda     ($C4),y
        sta     $0E00,y
        beq     N_LOAD_ROUTE_CITY_TEXT
        iny
        bne     N_COPY_SELECTED_CITY_STRING_BYTE
N_LOAD_ROUTE_CITY_TEXT:  ldy     CASE_ROUTE_INDEX
        lda     CASE_ROUTE,y
        pha
        jsr     B_LOAD_S2_TEXT
        pla
        jsr     N_POINT_TO_CITY_CLUE_COUNTS
        clc
        ldy     #$0B
        lda     #$00
N_SUM_CITY_CLUE_COUNTS:  adc     ($C4),y
        dey
        bpl     N_SUM_CITY_CLUE_COUNTS
        sta     $8B
        lda     #$00
        sta     $DA
        sta     $AC
        sta     $85
        lda     #$0F
        sta     $DB
; Pick one text offset uniformly from the row total; cumulative counts map
; that offset to a category in X. Reject a category already in $9E57-$9E59.
N_PICK_WEIGHTED_CLUE:  lda     $8B
        jsr     N_RANDOM_BELOW
        sta     $9C
        inc     $9C
        lda     #$00
        tax
        tay
        clc
N_ACCUMULATE_CLUE_COUNTS:  adc     ($C4),y
        cmp     $9C
        bcs     N_CHECK_CLUE_DUPLICATE
        inx
        iny
        bne     N_ACCUMULATE_CLUE_COUNTS
N_CHECK_CLUE_DUPLICATE:  txa
        ldy     #$02
N_COMPARE_CHOSEN_CLUE:  cmp     $9E57,y
        beq     N_PICK_WEIGHTED_CLUE
        dey
        bpl     N_COMPARE_CHOSEN_CLUE
        ldy     $85
        sta     $9E57,y
        dec     $9C
        clc
; The corresponding text starts after the three city-description strings.
        lda     $9C
        adc     #$03
        ldx     #$00
        ldy     #$A0
        jsr     C_SKIP_NUL_STRINGS
        jsr     C_COPY_STRING
        inc     $AC
        inc     $85
        lda     $85
        cmp     #$03
        bcc     N_PICK_WEIGHTED_CLUE
        rts

; A is a city index. Set $C4/$C5 to its twelve-byte clue-count row.
N_POINT_TO_CITY_CLUE_COUNTS: ldx #$00
        stx     $9C
        asl     a
        rol     $9C
        asl     a
        rol     $9C
        sta     $5E
        ldy     $9C
        asl     a
        rol     $9C
        clc
        adc     $5E
        tax
        tya
        adc     $9C
        tay
        clc
        txa
        adc     #<N_CITY_CLUE_COUNTS
        sta     $C4
        tya
        adc     #>N_CITY_CLUE_COUNTS
        sta     $C5
        rts

; In this entry, an odd $74 selects page 2 and an even $74 selects page 1.
N_SHOW_PAGE2_WHEN_74_ODD:  lda     $74
        lsr     a
        bcs     N_SHOW_ODD_74_PAGE2
        lda     $C054
        rts

N_SHOW_ODD_74_PAGE2:  lda     $C055
        rts

; Draw the city name, background, and command choices for the main screen.
N_DRAW_CITY_SCREEN:  jsr     N_CLEAR_NEXT_MODAL_HGR_PAGE
        jsr     N_DRAW_COMMON_SCREEN_BACKGROUND
        jsr     N_DRAW_CURRENT_CITY_NAME
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        jsr     N_DRAW_CITY_DESCRIPTION
        lda     #$00
        sta     $9E
        jsr     N_DRAW_MAIN_CITY_MENU
        lda     CASE_CITY_MENU_SELECTION
        sta     $6C
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        rts

; Draw the selected city's name from C's NUL-delimited city list.
N_DRAW_CURRENT_CITY_NAME:  lda     CASE_CURRENT_CITY
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        lda     #$1C
        sta     $93
        lda     #$0E
        sta     $72
        jsr     N_MEASURE_CENTERED_TEXT
        rts

N_CLEAR_CLOCK_PANEL:  lda     #$08
        sta     $87
        lda     #$01
        sta     $70
N_CLEAR_NEXT_CLOCK_ROW:  ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        lda     ($C0),y
        and     #$8F
        sta     ($C0),y
        tya
N_CLEAR_CLOCK_MIDDLE_BYTES:  iny
        sta     ($C0),y
        cpy     #$0C
        bne     N_CLEAR_CLOCK_MIDDLE_BYTES
        iny
        lda     ($C0),y
        and     #$FC
        sta     ($C0),y
        inc     $87
        lda     $87
        cmp     #$1C
        bne     N_CLEAR_NEXT_CLOCK_ROW
        rts

; Step from (N_ROUTE_X,N_ROUTE_Y) to (N_ROUTE_END_X,N_ROUTE_END_Y).
; The larger absolute delta selects the major axis;
; the four INC opcodes below are patched to DEC when that axis runs backward.
; Each step clears a short stroke on two HGR rows, revealing a route line.
N_DRAW_TRAVEL_ROUTE_LINE:  lda     #$70
        sta     N_ROUTE_DELAY
        lda     #$00
        sta     N_ROUTE_POINT_COUNT
        lda     #$C6
        sta     N_ROUTE_X_STEP_X_MAJOR_OPCODE
        sta     N_ROUTE_X_STEP_Y_MAJOR_OPCODE
        lda     N_ROUTE_X
        sec
        sbc     N_ROUTE_END_X
        bcs     N_STORE_ROUTE_DELTA_X
        lda     #$E6
        sta     N_ROUTE_X_STEP_X_MAJOR_OPCODE
        sta     N_ROUTE_X_STEP_Y_MAJOR_OPCODE
        lda     N_ROUTE_END_X
        sec
        sbc     N_ROUTE_X
N_STORE_ROUTE_DELTA_X:  sta     N_ROUTE_DELTA_X
        lda     #$C6
        sta     N_ROUTE_Y_STEP_X_MAJOR_OPCODE
        sta     N_ROUTE_Y_STEP_Y_MAJOR_OPCODE
        lda     N_ROUTE_Y
        sec
        sbc     N_ROUTE_END_Y
        bcs     N_CHOOSE_ROUTE_MAJOR_AXIS
        lda     #$E6
        sta     N_ROUTE_Y_STEP_X_MAJOR_OPCODE
        sta     N_ROUTE_Y_STEP_Y_MAJOR_OPCODE
        lda     N_ROUTE_END_Y
        sec
        sbc     N_ROUTE_Y
N_CHOOSE_ROUTE_MAJOR_AXIS:  sta     N_ROUTE_DELTA_Y
        cmp     N_ROUTE_DELTA_X
        bcc     N_DRAW_X_MAJOR_ROUTE
        jmp     N_DRAW_Y_MAJOR_ROUTE

N_DRAW_X_MAJOR_ROUTE:  lda     N_ROUTE_DELTA_X
; Seed the error at half the major delta. Each major step adds the minor
; delta; crossing the major delta advances the other axis and subtracts it.
        lsr     a
        sta     N_ROUTE_ERROR
        ldx     #$00
N_DRAW_NEXT_X_MAJOR_STEP:  jsr     N_DRAW_ROUTE_POINT
        lda     N_ROUTE_DELAY
        jsr     N_DELAY_NESTED_A_Y
        lda     N_ROUTE_X
        cmp     N_ROUTE_END_X
        beq     N_ROUTE_LINE_DONE
N_ROUTE_X_STEP_X_MAJOR_OPCODE:  inc     N_ROUTE_X
        lda     N_ROUTE_ERROR
        clc
        adc     N_ROUTE_DELTA_Y
        sta     N_ROUTE_ERROR
        cmp     N_ROUTE_DELTA_X
        bcc     N_DRAW_NEXT_X_MAJOR_STEP
        sbc     N_ROUTE_DELTA_X
        sta     N_ROUTE_ERROR
N_ROUTE_Y_STEP_X_MAJOR_OPCODE:  inc     N_ROUTE_Y
        jmp     N_DRAW_NEXT_X_MAJOR_STEP

N_ROUTE_LINE_DONE:  rts

N_DRAW_Y_MAJOR_ROUTE:  lda     N_ROUTE_DELTA_Y
        lsr     a
        sta     N_ROUTE_ERROR
        ldx     #$00
N_DRAW_NEXT_Y_MAJOR_STEP:  jsr     N_DRAW_ROUTE_POINT
        lda     N_ROUTE_DELAY
        jsr     N_DELAY_NESTED_A_Y
        lda     N_ROUTE_Y
        cmp     N_ROUTE_END_Y
        beq     N_ROUTE_LINE_DONE
N_ROUTE_Y_STEP_Y_MAJOR_OPCODE:  inc     N_ROUTE_Y
        lda     N_ROUTE_ERROR
        clc
        adc     N_ROUTE_DELTA_X
        sta     N_ROUTE_ERROR
        cmp     N_ROUTE_DELTA_Y
        bcc     N_DRAW_NEXT_Y_MAJOR_STEP
        sbc     N_ROUTE_DELTA_Y
        sta     N_ROUTE_ERROR
N_ROUTE_X_STEP_Y_MAJOR_OPCODE:  inc     N_ROUTE_X
        jmp     N_DRAW_NEXT_Y_MAJOR_STEP

N_DRAW_ROUTE_POINT:  ldy     N_ROUTE_X
        jsr     N_SET_HGR_X_FROM_Y
        ldy     N_ROUTE_Y
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        jsr     N_CLEAR_ROUTE_STROKE_PIXEL
        ldy     N_ROUTE_Y
        iny
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        jsr     N_CLEAR_ROUTE_STROKE_PIXEL
        inc     N_ROUTE_POINT_COUNT
        rts

N_CLEAR_ROUTE_STROKE_PIXEL:  ldy     $71
        lda     ($C0,x)
        and     HGR_STROKE_MASK_FIRST,y
        sta     ($C0,x)
        inc     $C0
        lda     ($C0,x)
        and     HGR_STROKE_MASK_SECOND,y
        sta     ($C0,x)
        rts

N_DRAW_TRAVEL_DESTINATION_LIST:  jsr     N_CITY_ROUTE_COUNT
        stx     $A4
        lda     $9E
        bne     N_INIT_TRAVEL_DESTINATION_LIST
        ldy     #$00
        jsr     C_HGR_AUX_TO_MAIN
N_INIT_TRAVEL_DESTINATION_LIST:  ldy     #$02
        jsr     N_DRAW_FRAMED_MENU_RECT
        ldx     CASE_CURRENT_CITY
        lda     J_ROUTE_OFFSETS,x
        sta     $A5
        lda     #$25
        sta     $93
        lda     #$2C
        sta     $72
N_DRAW_NEXT_TRAVEL_DESTINATION:  ldy     $A5
        lda     J_ROUTE_DESTS,y
        ldx     #<C_CITY_NAMES
        ldy     #>C_CITY_NAMES
        jsr     C_SKIP_NUL_STRINGS
        jsr     N_MEASURE_CENTERED_TEXT
        lda     $68
        beq     N_ADVANCE_TRAVEL_DESTINATION
        jsr     N_RECORD_MENU_RIGHT_EDGE
        inc     $94
N_ADVANCE_TRAVEL_DESTINATION:  inc     $A5
        jsr     N_ADVANCE_ROW_11
        dec     $A4
        bne     N_DRAW_NEXT_TRAVEL_DESTINATION
        lda     #$01
        sta     $9E
        sta     $89
        rts

; Draw See/Hide Connections (text index in Y) and record its selection edge.
N_DRAW_CONNECTION_TOGGLE_OPTION:  lda     #$00
        sta     $94
        lda     #$01
        sta     $68
        tya
        ldx     #$68
        ldy     N_MAIN_MENU_ROWS
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        lda     #$00
        sta     $68
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        rts

; Draw the three place choices for this city, advancing the text row by 11.
N_DRAW_INVESTIGATION_CHOICES:  lda     #$00
        sta     $94
        lda     #$01
        sta     $68
        lda     #$2B
        sta     $D0
        lda     #$8D
        sta     $D1
        lda     N_INVESTIGATION_CHOICE_ROWS
        sta     $72
        ldy     #$00
        sty     $AC
N_DRAW_NEXT_INVESTIGATION_CHOICE:  clc
        lda     $9E57,y
        adc     #$76
        ldx     #$2A
        ldy     $72
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        inc     $94
        jsr     N_ADVANCE_ROW_11
        inc     $AC
        ldy     $AC
        cpy     #$03
        bcc     N_DRAW_NEXT_INVESTIGATION_CHOICE
        lda     #$00
        sta     $68
        sta     $6C
        sta     $6E
        lda     #$02
        sta     $6F
        rts

; Center the three place titles using their measured glyph widths.
N_DRAW_INVESTIGATION_TITLES:  lda     #$02
        sta     $AA
N_DRAW_NEXT_INVESTIGATION_TITLE:  clc
        ldy     $AA
        lda     $9E57,y
        adc     #$7D
        pha
        jsr     N_PREPARE_GLYPH_INDEX
        sec
        lda     #$5C
        sbc     $7A
        pha
        clc
        lda     $79
        lsr     a
        lsr     a
        sta     $5E
        sec
        ldy     $AA
        lda     N_TEXT_CENTER_OFFSETS,y
        sbc     $5E
        tax
        pla
        tay
        pla
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        dec     $AA
        bpl     N_DRAW_NEXT_INVESTIGATION_TITLE
        rts

; Paint six short strokes for the chosen place. Mode 1 alternates the two
; three-byte patterns; the other modes use their fixed pattern pointers.
N_ANIMATE_INVESTIGATION_SELECTION:  lda     #$71
        sta     $72
        ldx     $6C
        lda     N_STEP_PTR_LO,x
        sta     $C2
        lda     N_STEP_PTR_HI,x
        sta     $C3
        lda     N_PATTERN_START,x
        sta     $73
        lda     #$00
        sta     $AA
N_DRAW_NEXT_SELECTION_STEP:  jsr     N_PREPARE_SELECTION_STROKE
        jsr     N_MASKED_BITMAP_TO_HGR
        jsr     N_BEEP_SELECTION_STEP
        inc     $AA
        lda     $AA
        cmp     #$06
        bcc     N_DRAW_NEXT_SELECTION_STEP
        rts

N_PREPARE_SELECTION_STROKE:  ldy     $AA
        clc
        lda     ($C2),y
        adc     $73
        sta     $73
        sec
        lda     $72
        sbc     #$03
        sta     $72
        sta     $87
        lda     #$01
        sta     $83
        ldx     $6C
        lda     N_PATTERN_SIZE,x
        sta     $85
        cpx     #$01
        bne     N_USE_MODE_SELECTION_PATTERN
        lda     $AA
        lsr     a
        bcs     N_USE_SELECTION_PATTERN_B
        ldx     #<N_PATTERN_C
        ldy     #>N_PATTERN_C
        bne     N_SELECTION_PATTERN_READY
N_USE_SELECTION_PATTERN_B:  ldx     #<N_PATTERN_B
        ldy     #>N_PATTERN_B
        bne     N_SELECTION_PATTERN_READY
N_USE_MODE_SELECTION_PATTERN:  ldy     N_PATTERN_PTR_HI,x
        lda     N_PATTERN_PTR_LO,x
        tax
N_SELECTION_PATTERN_READY:  rts

N_BEEP_SELECTION_STEP:  jsr     N_SHORT_FEEDBACK_TONE
        lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        rts

; Draw See Connections, Depart by Plane, Investigate, and Visit Interpol.
N_DRAW_MAIN_CITY_MENU:  lda     #$2E
        sta     $D0
        lda     #$8D
        sta     $D1
        jsr     N_CLEAR_LOWER_MENU_PANEL
        lda     #$01
        sta     $68
        lda     #$00
        sta     $94
        lda     #N_UI_SEE_CONNECTIONS
        ldy     N_MAIN_MENU_ROWS
        sty     $72
        ldx     #$68
        stx     $93
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        jsr     N_ADVANCE_ROW_11
        inc     $94
        lda     #N_UI_DEPART_BY_PLANE
        ldx     $93
        ldy     $72
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        jsr     N_ADVANCE_ROW_11
        inc     $94
        ldx     $93
        ldy     $72
        lda     #N_UI_INVESTIGATE
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        jsr     N_ADVANCE_ROW_11
        inc     $94
        lda     #N_UI_VISIT_INTERPOL
        ldx     $93
        ldy     $72
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_RECORD_MENU_RIGHT_EDGE
        lda     #$00
        sta     $68
        sta     $9E
        sta     $6E
        lda     #$03
        sta     $6F
        rts

; Convert the HGR byte/pixel cursor after a text draw to the menu's pixel X.
; N_INVERT_MENU_SELECTION_RECTANGLE uses this stored endpoint for the selection rectangle.
N_RECORD_MENU_RIGHT_EDGE:  lda     $70
        sta     $7D
        clc
        lda     $71
        adc     #$02
        cmp     #$07
        bcc     N_STORE_MENU_RIGHT_EDGE
        sbc     #$07
        inc     $7D
N_STORE_MENU_RIGHT_EDGE:  ldy     $94
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
        sta     MENU_RIGHT_PIXEL,y
        rts

; Expand the current city's selected description from $0E00 into $A000,
; finish the sentence, and draw it on the HGR page.
N_DRAW_CITY_DESCRIPTION:  jsr     N_RESET_TEXT_BUFFER_A000
        ldx     #$00
        ldy     #$0E
        stx     $C4
        sty     $C5
        jsr     N_EXPAND_TOKENIZED_TEXT
        jsr     N_END_TEXT_SENTENCE
        lda     #$4A
        sta     $91
        lda     #$06
        sta     $72
        ldx     #$00
        ldy     #$A0
        lda     #$4E
        jsr     N_DRAW_TEXT_POINTER_AT_X
        rts

; Source pointer $C4/$C5, destination $A000+$AC. High-bit bytes index C's
; word dictionary; #, @, and ^ select subject, possessive, and object words.
; Dictionary words receive a space unless punctuation or NUL follows.
N_EXPAND_TOKENIZED_TEXT:  ldx     #$00
        ldy     $AC
        lda     #$00
        sta     $DC
        lda     #$A0
        sta     $DD
N_READ_NEXT_TEXT_TOKEN:  lda     ($C4,x)
        bmi     N_EXPAND_DICTIONARY_TOKEN
        cmp     #$23
        beq     N_APPEND_SUBJECT_PRONOUN
        cmp     #$40
        beq     N_APPEND_POSSESSIVE_PRONOUN
        cmp     #$5E
        beq     N_APPEND_OBJECT_PRONOUN
        sta     ($DC),y
        cmp     #$00
        bne     N_ADVANCE_TEXT_OUTPUT
        jmp     N_TEXT_EXPANSION_DONE

N_ADVANCE_TEXT_OUTPUT:  iny
        bne     N_ADVANCE_TEXT_SOURCE
        inc     $DD
N_ADVANCE_TEXT_SOURCE:  inc     $C4
        bne     N_READ_NEXT_TEXT_TOKEN
        inc     $C5
        bne     N_READ_NEXT_TEXT_TOKEN
N_APPEND_SUBJECT_PRONOUN:  sty     $AC
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_USE_HE_PRONOUN
        ldy     #N_UI_SHE_WORD
        jmp     N_APPEND_CHOSEN_PRONOUN

N_USE_HE_PRONOUN:  ldy     #N_UI_HE_WORD
N_APPEND_CHOSEN_PRONOUN:  jsr     N_APPEND_UI_TEXT
        ldx     #$00
        jmp     N_ADVANCE_TEXT_SOURCE

N_APPEND_POSSESSIVE_PRONOUN:  sty     $AC
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_USE_HIS_POSSESSIVE
        ldy     #N_UI_HER_WORD
        bne     N_APPEND_CHOSEN_PRONOUN
N_USE_HIS_POSSESSIVE:  ldy     #N_UI_HIS_WORD
        bne     N_APPEND_CHOSEN_PRONOUN
N_APPEND_OBJECT_PRONOUN:  sty     $AC
        lda     CASE_SUSPECT
        cmp     #$05
        bcs     N_USE_HIM_PRONOUN
        ldy     #N_UI_HER_WORD
        bne     N_APPEND_CHOSEN_PRONOUN
N_USE_HIM_PRONOUN:  ldy     #N_UI_HIM_WORD
        bne     N_APPEND_CHOSEN_PRONOUN
N_EXPAND_DICTIONARY_TOKEN:  and     #$7F
        sty     $AC
        ldx     #<C_WORD_DICTIONARY
        ldy     #>C_WORD_DICTIONARY
        jsr     C_SKIP_NUL_STRINGS
        lda     $DD
        sta     $DB
        jsr     C_COPY_STRING
        ldx     #$00
        inc     $C4
        bne     N_CHECK_AFTER_DICTIONARY_WORD
        inc     $C5
N_CHECK_AFTER_DICTIONARY_WORD:  lda     ($C4,x)
        beq     N_CONTINUE_TOKEN_EXPANSION
        cmp     #$21
        beq     N_CONTINUE_TOKEN_EXPANSION
        cmp     #$2C
        beq     N_CONTINUE_TOKEN_EXPANSION
        cmp     #$2E
        beq     N_CONTINUE_TOKEN_EXPANSION
        cmp     #$3A
        beq     N_CONTINUE_TOKEN_EXPANSION
        lda     #$20
        sta     ($DC),y
        inc     $AC
        iny
        bne     N_CONTINUE_TOKEN_EXPANSION
        inc     $DD
N_CONTINUE_TOKEN_EXPANSION:  jmp     N_READ_NEXT_TEXT_TOKEN

N_TEXT_EXPANSION_DONE:  rts

N_SHOW_WARRANT_MATCHES:  lda     $A7
        bne     N_SHOW_NONEMPTY_WARRANT_MATCHES
        ldy     #N_UI_NO_SUSPECT_MATCH
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        rts

N_SHOW_NONEMPTY_WARRANT_MATCHES:  lda     #$00
        sta     $A6
        jsr     N_RESET_TEXT_BUFFER_A000
        lda     $A7
        cmp     #$01
        bne     N_SHOW_MULTIPLE_WARRANT_MATCHES
        ldy     #N_UI_WARRANT_ISSUED
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
        lda     $9EB0
        sta     WARRANT_SUSPECT
        jmp     N_APPEND_NEXT_MATCHED_SUSPECT

N_SHOW_MULTIPLE_WARRANT_MATCHES:  ldy     #N_UI_SUSPECTS_FOLLOW
        jsr     N_DRAW_UI_TEXT_AT_LEFT_MARGIN
N_APPEND_NEXT_MATCHED_SUSPECT:  ldy     $A6
        lda     $9EB0,y
        ldx     #<C_SUSPECT_NAMES
        ldy     #>C_SUSPECT_NAMES
        jsr     C_SKIP_NUL_STRINGS
        lda     #$00
        sta     $AC
        jsr     C_COPY_STRING
        lda     $A7
        cmp     #$01
        bne     N_USE_COMMA_BETWEEN_SUSPECTS
        ldy     #$3A
        jmp     N_APPEND_SUSPECT_SEPARATOR

N_USE_COMMA_BETWEEN_SUSPECTS:  ldy     #$39
N_APPEND_SUSPECT_SEPARATOR:  jsr     N_APPEND_UI_TEXT
        ldx     #$00
        ldy     #$A0
        jsr     N_DRAW_TEXT_XY
        inc     $A6
        dec     $A7
        bne     N_APPEND_NEXT_MATCHED_SUSPECT
        rts

; Compare each suspect's six trait bytes with the selected $1B-$20 filters.
; FF is an unset filter. $9EB0 holds matching suspect indexes; $A7 is count.
N_FIND_WARRANT_MATCHES:  lda     #$00
        sta     $A7
        sta     $A6
        lda     #$FF
        sta     WARRANT_SUSPECT
N_TEST_NEXT_SUSPECT:  ldy     $A6
        tya
        asl     a
        sta     $88
        asl     a
        clc
        adc     $88
        tay
        ldx     #$00
N_TEST_NEXT_TRAIT:  lda     SUSPECT_TRAIT_FILTERS,x
        cmp     #$FF
        beq     N_TRAIT_MATCHED_OR_UNSET
        cmp     SUSPECT_TRAIT_MATRIX,y
        bne     N_ADVANCE_SUSPECT
N_TRAIT_MATCHED_OR_UNSET:  iny
        inx
        cpx     #$06
        bcs     N_RECORD_MATCHED_SUSPECT
        jmp     N_TEST_NEXT_TRAIT

N_ADVANCE_SUSPECT:  lda     $A6
        cmp     #$09
        beq     N_WARRANT_MATCH_SCAN_DONE
        inc     $A6
        jmp     N_TEST_NEXT_SUSPECT

N_RECORD_MATCHED_SUSPECT:  ldy     $A7
        lda     $A6
        sta     $9EB0,y
        inc     $A7
        jmp     N_ADVANCE_SUSPECT

N_WARRANT_MATCH_SCAN_DONE:  rts

N_CLEAR_PREVIOUS_TRAIT:  lda     #$1C
        sta     $95
        lda     #$26
        sta     $96
        lda     #$00
        sta     $7E
        ldy     $6C
        lda     ($D0),y
        sta     $87
        lda     #$09
        sta     $85
N_CLEAR_NEXT_TRAIT_ROW:  lda     $95
        sta     $70
        ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        jsr     N_FILL_TRAIT_ROW_SPAN
        inc     $87
        dec     $85
        bne     N_CLEAR_NEXT_TRAIT_ROW
        rts

N_FILL_TRAIT_ROW_SPAN:  lda     #$FF
        sta     ($C0),y
        inc     $70
        inc     $C0
        lda     $70
        cmp     $96
        bne     N_FILL_TRAIT_ROW_SPAN
        ldx     $7E
        lda     ($C0),y
        ora     HGR_LOW_BIT_MASK,x
        sta     ($C0),y
        rts

; The two warrant outcomes use different sets of glyph indexes. Both move
; paired glyphs across alternating HGR pages; $AA cycles the frame phase.
N_ANIMATE_WRONG_WARRANT:  lda     #$8B
        sta     $B0
        lda     #$00
        sta     $AA
N_WRONG_WARRANT_FRAME:  jsr     N_DRAW_WRONG_WARRANT_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     #$A0
        jsr     N_DELAY_NESTED_A_Y
        lda     $AA
        bne     N_WRONG_WARRANT_DECREMENT_PHASE
        ldy     #$05
        lda     #$20
        jsr     N_PLAY_FEEDBACK_TONE
        lda     #$04
        sta     $AA
        bne     N_WRONG_WARRANT_ADVANCE_X
N_WRONG_WARRANT_DECREMENT_PHASE:  dec     $AA
N_WRONG_WARRANT_ADVANCE_X:  clc
        lda     $B0
        adc     #$02
        sta     $B0
        cmp     #$32
        bcc     N_WRONG_WARRANT_DONE
        inc     $74
        jsr     N_DRAW_WRONG_WARRANT_FRAME
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     N_WRONG_WARRANT_STORE_PHASE
        sbc     #$05
N_WRONG_WARRANT_STORE_PHASE:  sta     $AA
        sec
        lda     $B0
        sbc     #$04
        sta     $B0
        jmp     N_WRONG_WARRANT_FRAME

N_WRONG_WARRANT_DONE:  rts

N_DRAW_WRONG_WARRANT_FRAME:  ldx     $B0
        ldy     #$4A
        lda     #$A0
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        ldx     $B0
        ldy     #$6B
        clc
        lda     $AA
        adc     #$A1
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_ANIMATE_CORRECT_WARRANT:  lda     #$8B
        sta     $B0
        lda     #$A4
        sta     $B3
        lda     #$00
        sta     $AA
N_CORRECT_WARRANT_FRAME:  jsr     N_DRAW_CORRECT_WARRANT_LEFT
        jsr     N_DRAW_CORRECT_WARRANT_RIGHT
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $AA
        bne     N_CORRECT_WARRANT_DECREMENT_PHASE
        ldy     #$05
        lda     #$20
        jsr     N_PLAY_FEEDBACK_TONE
        lda     #$04
        sta     $AA
        bne     N_CORRECT_WARRANT_ADVANCE_X
N_CORRECT_WARRANT_DECREMENT_PHASE:  dec     $AA
N_CORRECT_WARRANT_ADVANCE_X:  clc
        lda     $B0
        adc     #$02
        sta     $B0
        cmp     #$0E
        bcc     N_CORRECT_WARRANT_DONE
        clc
        lda     $B3
        adc     #$02
        sta     $B3
        inc     $74
        jsr     N_DRAW_CORRECT_WARRANT_LEFT
        jsr     N_DRAW_CORRECT_WARRANT_RIGHT
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     N_CORRECT_WARRANT_STORE_PHASE
        sbc     #$05
N_CORRECT_WARRANT_STORE_PHASE:  sta     $AA
        sec
        lda     $B0
        sbc     #$04
        sta     $B0
        sec
        lda     $B3
        sbc     #$04
        sta     $B3
        jmp     N_CORRECT_WARRANT_FRAME

N_CORRECT_WARRANT_DONE:  rts

N_DRAW_CORRECT_WARRANT_LEFT:  ldx     $B0
        ldy     #$42
        lda     #$94
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        ldx     $B0
        ldy     #$72
        clc
        lda     $AA
        adc     #$95
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_DRAW_CORRECT_WARRANT_RIGHT:  ldx     $B3
        ldy     #$4A
        lda     #$9A
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        clc
        lda     $B3
        adc     #$0B
        tax
        ldy     #$6E
        clc
        lda     $AA
        adc     #$9B
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

; These two moving-glyph stages run before the warrant comparison. $AC is
; the horizontal position and $AA selects one of five glyph frames.
N_ANIMATE_ARREST_SECOND_STAGE:  lda     #$00
        sta     $AA
        lda     #$22
        sta     $AC
        inc     $74
N_ARREST_SECOND_STAGE_FRAME:  jsr     N_DRAW_ARREST_SECOND_STAGE_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $AA
        beq     N_ARREST_SECOND_STAGE_PAUSE
        cmp     #$02
        bne     N_ARREST_SECOND_STAGE_ADVANCE
N_ARREST_SECOND_STAGE_PAUSE:  ldy     #$05
        lda     #$20
        jsr     N_PLAY_FEEDBACK_TONE
N_ARREST_SECOND_STAGE_ADVANCE:  inc     $74
        sec
        lda     $AC
        sbc     #$04
        sta     $AC
        lda     $AA
        bne     N_ARREST_SECOND_STAGE_DECREMENT_PHASE
        lda     #$04
        sta     $AA
        bne     N_ARREST_SECOND_STAGE_DRAW_NEXT
N_ARREST_SECOND_STAGE_DECREMENT_PHASE:  dec     $AA
N_ARREST_SECOND_STAGE_DRAW_NEXT:  jsr     N_DRAW_ARREST_SECOND_STAGE_FRAME
        clc
        lda     $AC
        adc     #$08
        cmp     #$C0
        bcs     N_ARREST_SECOND_STAGE_WRAP_POSITION
        cmp     #$91
        bcs     N_ARREST_SECOND_STAGE_DONE
N_ARREST_SECOND_STAGE_WRAP_POSITION:  sta     $AC
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     N_ARREST_SECOND_STAGE_STORE_PHASE
        sbc     #$05
N_ARREST_SECOND_STAGE_STORE_PHASE:  sta     $AA
        jmp     N_ARREST_SECOND_STAGE_FRAME

N_ARREST_SECOND_STAGE_DONE:  rts

N_DRAW_ARREST_SECOND_STAGE_FRAME:  ldx     $AC
        ldy     #$40
        clc
        lda     $AA
        adc     #$89
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_ANIMATE_ARREST_FIRST_STAGE:  lda     #$00
        sta     $AA
        lda     #$2E
        sta     $AC
        inc     $74
N_ARREST_FIRST_STAGE_FRAME:  jsr     N_DRAW_ARREST_FIRST_STAGE_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $AA
        bne     N_ARREST_FIRST_STAGE_DECREMENT_PHASE
        lda     #$04
        sta     $AA
        bne     N_ARREST_FIRST_STAGE_ADVANCE
N_ARREST_FIRST_STAGE_DECREMENT_PHASE:  dec     $AA
N_ARREST_FIRST_STAGE_ADVANCE:  sec
        lda     $AC
        sbc     #$04
        sta     $AC
        inc     $74
        jsr     N_DRAW_ARREST_FIRST_STAGE_FRAME
        clc
        lda     $AA
        adc     #$02
        cmp     #$05
        bcc     N_ARREST_FIRST_STAGE_STORE_PHASE
        sbc     #$05
N_ARREST_FIRST_STAGE_STORE_PHASE:  sta     $AA
        clc
        lda     $AC
        adc     #$08
        cmp     #$D0
        bcs     N_ARREST_FIRST_STAGE_WRAP_POSITION
        cmp     #$8C
        bcs     N_ARREST_FIRST_STAGE_DONE
N_ARREST_FIRST_STAGE_WRAP_POSITION:  sta     $AC
        jmp     N_ARREST_FIRST_STAGE_FRAME

N_ARREST_FIRST_STAGE_DONE:  rts

N_DRAW_ARREST_FIRST_STAGE_FRAME:  ldx     $AC
        ldy     #$50
        lda     #$8E
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        ldx     $AC
        ldy     #$7A
        clc
        lda     $AA
        adc     #$8F
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

; The three entrypoints below are selected by the patched JSR in the place
; visit path. Their numbers match N_RANDOM_ANIMATION_ENTRY_LO/HI.
N_ANIMATE_PLACE_EVENT_ONE:  lda     #$8B
        sta     $73
        lda     #$00
        sta     $AA
N_PLACE_EVENT_ONE_FRAME:  jsr     N_DRAW_PLACE_EVENT_ONE_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $AA
        bne     N_PLACE_EVENT_ONE_DECREMENT_PHASE
        lda     #$03
        sta     $AA
        bne     N_PLACE_EVENT_ONE_ADVANCE_X
N_PLACE_EVENT_ONE_DECREMENT_PHASE:  dec     $AA
N_PLACE_EVENT_ONE_ADVANCE_X:  clc
        lda     $73
        adc     #$04
        sta     $73
        cmp     #$4F
        bcc     N_PLACE_EVENT_ONE_DONE
        inc     $74
        jsr     N_DRAW_PLACE_EVENT_ONE_FRAME
        clc
        lda     $AA
        adc     #$02
        cmp     #$04
        bcc     N_PLACE_EVENT_ONE_STORE_PHASE
        sbc     #$04
N_PLACE_EVENT_ONE_STORE_PHASE:  sta     $AA
        sec
        lda     $73
        sbc     #$08
        sta     $73
        bne     N_PLACE_EVENT_ONE_FRAME
N_PLACE_EVENT_ONE_DONE:  rts

N_DRAW_PLACE_EVENT_ONE_FRAME:  ldx     $73
        ldy     #$50
        clc
        lda     $AA
        adc     #$79
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_ANIMATE_PLACE_EVENT_ZERO:  lda     #$30
        sta     $73
        inc     $74
N_PLACE_EVENT_ZERO_OPENING_FRAME:  jsr     N_DRAW_PLACE_EVENT_ZERO_FIRST_GLYPH
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $73
        cmp     #$49
        bcs     N_PLACE_EVENT_ZERO_SECOND_HALF
        inc     $74
        dec     $73
        jsr     N_DRAW_PLACE_EVENT_ZERO_FIRST_GLYPH
        clc
        lda     $73
        adc     #$02
        sta     $73
        bne     N_PLACE_EVENT_ZERO_OPENING_FRAME
N_PLACE_EVENT_ZERO_SECOND_HALF:  jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        ldy     #$03
        jsr     N_DELAY_WITH_ZERO_ACCUMULATOR
        inc     $74
        jsr     N_CLEAR_PICTURE_PANEL
        lda     #$77
        ldx     #$49
        jsr     N_DRAW_PLACE_EVENT_GLYPH_AT_Y58
        lda     #$60
        sta     $B0
        jsr     N_DRAW_PLACE_EVENT_ZERO_SECOND_GLYPH
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        inc     $74
        jsr     N_CLEAR_PICTURE_PANEL
N_PLACE_EVENT_ZERO_NEXT_FRAME:  ldx     #$49
        lda     $B0
        cmp     #$6E
        bcs     N_PLACE_EVENT_ZERO_OTHER_GLYPH
        lda     #$78
        bne     N_PLACE_EVENT_ZERO_DRAW_FRAME
N_PLACE_EVENT_ZERO_OTHER_GLYPH:  lda     #$76
N_PLACE_EVENT_ZERO_DRAW_FRAME:  jsr     N_DRAW_PLACE_EVENT_GLYPH_AT_Y58
        jsr     N_DRAW_PLACE_EVENT_ZERO_SECOND_GLYPH
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        inc     $74
        jsr     N_CLEAR_PICTURE_PANEL
        clc
        lda     $B0
        adc     #$08
        sta     $B0
        cmp     #$8C
        bcc     N_PLACE_EVENT_ZERO_NEXT_FRAME
        rts

N_DRAW_PLACE_EVENT_ZERO_SECOND_GLYPH:  ldy     $B0
        jsr     N_SET_HGR_X_FROM_Y
        lda     #$57
        sta     $72
        lda     #$2D
        jsr     N_DRAW_GLYPH_CHAR
        rts

N_DRAW_PLACE_EVENT_ZERO_FIRST_GLYPH:  lda     #$76
        ldx     $73
N_DRAW_PLACE_EVENT_GLYPH_AT_Y58:  ldy     #$58
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_ANIMATE_PLACE_EVENT_TWO:  lda     #$8C
        sta     $73
N_PLACE_EVENT_TWO_FRAME:  jsr     N_DRAW_PLACE_EVENT_TWO_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        clc
        lda     $73
        adc     #$03
        sta     $73
        cmp     #$4A
        bcc     N_PLACE_EVENT_TWO_DONE
        inc     $74
        jsr     N_DRAW_PLACE_EVENT_TWO_FRAME
        sec
        lda     $73
        sbc     #$06
        sta     $73
        bne     N_PLACE_EVENT_TWO_FRAME
N_PLACE_EVENT_TWO_DONE:  rts

N_DRAW_PLACE_EVENT_TWO_FRAME:  ldx     $73
        ldy     #$6A
        lda     #$75
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_ANIMATE_PRIMARY_ROUTE_EVENT:  lda     #$89
        sta     $7F
        sta     $A3
        inc     $74
N_PRIMARY_ROUTE_EVENT_FRAME:  jsr     N_DRAW_PRIMARY_ROUTE_EVENT_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        inc     $74
        jsr     N_CLEAR_PICTURE_PANEL
        dec     $7F
        lda     $7F
        cmp     #$75
        bcs     N_PRIMARY_ROUTE_EVENT_FRAME
        ldx     #$64
        ldy     #$74
        lda     #$74
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        ldy     #$0A
        jsr     N_DELAY_WITH_ZERO_ACCUMULATOR
        inc     $74
        rts

N_DRAW_PRIMARY_ROUTE_EVENT_FRAME:  lda     #$1C
        sta     $70
        lda     $7F
        sta     $72
        lda     #$6B
        jsr     N_PREPARE_GLYPH_INDEX
        ldx     $CC
        ldy     $CD
        jsr     N_COPY_BITMAP_WITH_ROW_CLIP
        rts

N_ANIMATE_ALTERNATE_ROUTE_EVENT:  lda     #$00
        sta     $AA
        lda     #$32
        sta     $AC
        inc     $74
N_ALTERNATE_ROUTE_EVENT_FRAME:  jsr     N_DRAW_ALTERNATE_ROUTE_EVENT_FRAME
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        lda     $AA
        bne     N_ALTERNATE_ROUTE_DECREMENT_PHASE
        lda     #$07
        sta     $AA
        bne     N_ALTERNATE_ROUTE_ADVANCE_X
N_ALTERNATE_ROUTE_DECREMENT_PHASE:  dec     $AA
N_ALTERNATE_ROUTE_ADVANCE_X:  sec
        lda     $AC
        sbc     #$02
        sta     $AC
        inc     $74
        jsr     N_DRAW_ALTERNATE_ROUTE_EVENT_FRAME
        clc
        lda     $AA
        adc     #$02
        cmp     #$08
        bcc     N_ALTERNATE_ROUTE_STORE_PHASE
        sbc     #$08
N_ALTERNATE_ROUTE_STORE_PHASE:  sta     $AA
        clc
        lda     $AC
        adc     #$04
        cmp     #$8C
        bcs     N_ALTERNATE_ROUTE_EVENT_DONE
        sta     $AC
        jmp     N_ALTERNATE_ROUTE_EVENT_FRAME

N_ALTERNATE_ROUTE_EVENT_DONE:  rts

N_DRAW_ALTERNATE_ROUTE_EVENT_FRAME:  ldx     $AC
        ldy     #$50
        lda     #$6B
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        ldx     $AC
        ldy     #$71
        clc
        lda     $AA
        adc     #$6C
        jsr     N_DRAW_GLYPH_INDEX_AT_XY
        rts

N_EXIT_TO_PRODOS: sta     $C004
        sta     $C002
        jmp     N_QUIT_TO_PRODOS

; A is a patched delay value and Y is the number of speaker toggles. When
; sound is off, consume the delay once without touching the speaker switch.
N_DEFAULT_FEEDBACK_TONE:  ldy     #$0A
        lda     #$50
N_PLAY_FEEDBACK_TONE:  sta     N_TONE_LOOP_DELAY
        sta     N_SILENT_TONE_DELAY
        lda     SOUND_ENABLED
        beq     N_DELAY_WITHOUT_TONE
N_TOGGLE_SPEAKER_FOR_TONE:  lda     $C030
        lda     #$00
N_TONE_LOOP_DELAY  := * - 1
        jsr     N_DELAY_NESTED_A_Y
        dey
        bne     N_TOGGLE_SPEAKER_FOR_TONE
        rts

N_DELAY_WITHOUT_TONE:  lda     #$00
N_SILENT_TONE_DELAY  := * - 1
        jmp     N_DELAY_NESTED_A_Y

N_CLEAR_HGR_PAGE1:  lda     #$20
        .byte   $2C             ; BIT skips the following LDA immediate
N_CLEAR_HGR_PAGE2:  lda     #$40
        sta     $C1
        ldx     #$20
        ldy     #$00
        sty     $C0
        lda     #$80
N_CLEAR_HGR_PAGE_BYTE:  sta     ($C0),y
        iny
        bne     N_CLEAR_HGR_PAGE_BYTE
        inc     $C1
        dex
        bne     N_CLEAR_HGR_PAGE_BYTE
        rts

; Set $C0/$C1 to scanline Y and byte column $70 on the active HGR page;
; return Y=0 so callers can use ($C0),Y directly.
N_SET_HGR_ROW_PLUS_COLUMN:  clc
        lda     $D600,y
        adc     $70
        sta     $C0
        lda     $D6C0,y
        sta     $C1
        lda     $74
        lsr     a
        bcs     N_HGR_ROW_PLUS_COLUMN_DONE
        lda     $C1
        adc     #$20
        sta     $C1
N_HGR_ROW_PLUS_COLUMN_DONE:  ldy     #$00
        rts

; X is horizontal HGR position, Y is scanline, and A is a glyph index.
; The character entry instead accepts ASCII in A at the current position.
N_DRAW_GLYPH_INDEX_AT_XY:  stx     $73
        sty     $72
        pha
        jsr     N_SET_HGR_X_FROM_73
        pla
N_DRAW_GLYPH_INDEX:  jsr     N_PREPARE_GLYPH_INDEX
        jmp     N_DRAW_PREPARED_GLYPH

N_DRAW_GLYPH_CHAR:  jsr     N_PREPARE_GLYPH_CHAR
N_DRAW_PREPARED_GLYPH:  ldx     #$00
        jsr     N_XOR_PREPARED_BITMAP_TO_HGR
N_ADVANCE_GLYPH_CURSOR:  clc
        lda     $71
        adc     $79
N_NORMALIZE_GLYPH_CURSOR_BIT:  cmp     #$07
        bcs     N_ADVANCE_GLYPH_CURSOR_BYTE
        sta     $71
        jmp     N_GLYPH_CURSOR_ADVANCED

N_ADVANCE_GLYPH_CURSOR_BYTE:  sbc     #$07
        inc     $70
        jmp     N_NORMALIZE_GLYPH_CURSOR_BIT

N_GLYPH_CURSOR_ADVANCED:  rts

; Backspace by the prepared glyph width, borrowing a byte column as needed.
N_REWIND_GLYPH_CURSOR:  sec
        lda     $71
        sbc     $79
        bcc     N_REWIND_GLYPH_CURSOR_BYTE
        sta     $71
        jmp     N_GLYPH_CURSOR_REWOUND

N_REWIND_GLYPH_CURSOR_BYTE:  clc
        adc     #$07
        sta     $71
        dec     $70
        cmp     #$07
        bcs     N_REWIND_GLYPH_CURSOR_BYTE
N_GLYPH_CURSOR_REWOUND:  rts

; Character codes $20-$8A use D; $8B-$A8 use the 30 C bitmaps.
; Direct glyph indexes $89-$A7 continue into the adjacent T/U pointer table:
; five T frames and 26 U sprites. Index $A8 reaches its zero terminator.
; Return packed rows at $CC/$CD, width plus one in $79, and height in $85.
N_PREPARE_GLYPH_CHAR:  sec
        sbc     #$20
N_PREPARE_GLYPH_INDEX:  sta     $75
        tay
        cpy     #$6B
        bcc     N_GET_FONT_GLYPH_POINTER
        sbc     #$6B
        tay
        lda     C_ICON_PTR_LO,y
        sta     $C8
        lda     C_ICON_PTR_HI,y
        bne     N_READ_GLYPH_HEADER
N_GET_FONT_GLYPH_POINTER:  lda     D_FONT_PTR_LO,y
        sta     $C8
        lda     D_FONT_PTR_HI,y
N_READ_GLYPH_HEADER:  sta     $C9
        ldy     #$00
        lda     ($C8),y
        sta     $79
        inc     $C8
        bne     N_READ_GLYPH_HEIGHT
        inc     $C9
N_READ_GLYPH_HEIGHT:  lda     ($C8),y
        sta     $7A
        inc     $C8
        bne     N_COUNT_GLYPH_ROW_BYTES
        inc     $C9
N_COUNT_GLYPH_ROW_BYTES:  lda     #$01
        sta     $83
        lda     $79
N_COUNT_NEXT_GLYPH_ROW_BYTE:  cmp     #$08
        bcc     N_FINISH_GLYPH_PREPARATION
        sbc     #$07
        inc     $83
        jmp     N_COUNT_NEXT_GLYPH_ROW_BYTE

N_FINISH_GLYPH_PREPARATION:  inc     $79
        lda     $7A
        sta     $85
        lda     $72
        sta     $87
        lda     $C8
        sta     $CC
        lda     $C9
        sta     $CD
        rts

; Draw a NUL-terminated string from X/Y at horizontal index A and current
; scanline $72. The scanner measures ahead, wraps at a preceding space when
; byte column 39 is reached, and draws only the measured run.
N_DRAW_TEXT_POINTER_AT_X:  stx     $C2
        sty     $C3
        sta     $73
        jmp     N_SET_TEXT_START_X

N_DRAW_UI_TEXT_AT_XY:  stx     $73
        sty     $72
        tay
        jsr     N_SELECT_UI_TEXT
N_SET_TEXT_START_X:  jsr     N_SET_HGR_X_FROM_73
N_PREPARE_TEXT_SCAN:  lda     $C2
        sta     $C6
        lda     $C3
        sta     $C7
        ldx     #$00
N_MEASURE_NEXT_TEXT_RUN:  lda     $70
        sta     $80
        lda     $71
        sta     $81
N_SCAN_NEXT_TEXT_CHAR:  lda     ($C6,x)
        bne     N_MEASURE_PRINTABLE_CHAR
        lda     $C2
        cmp     $C6
        bne     N_RESTORE_TEXT_RUN_START
        lda     $C3
        cmp     $C7
        bne     N_RESTORE_TEXT_RUN_START
        jmp     N_TEXT_DRAW_DONE

N_MEASURE_PRINTABLE_CHAR:  cmp     #$8D
        bcs     N_HANDLE_TEXT_BREAK_MARKER
        jsr     N_PREPARE_GLYPH_CHAR
        jsr     N_ADVANCE_GLYPH_CURSOR
        lda     $70
        cmp     #$27
        bcs     N_BACKTRACK_TO_WORD_SPACE
        inc     $C6
        bne     N_SCAN_NEXT_TEXT_CHAR
        inc     $C7
        jmp     N_SCAN_NEXT_TEXT_CHAR

N_HANDLE_TEXT_BREAK_MARKER:  lda     $C3
        cmp     $C7
        bne     N_RESTORE_TEXT_RUN_START
        lda     $C2
        cmp     $C6
        bne     N_RESTORE_TEXT_RUN_START
        jmp     N_BEGIN_NEXT_TEXT_LINE

N_BACKTRACK_TO_WORD_SPACE:  lda     ($C6,x)
        cmp     #$20
        beq     N_RESTORE_TEXT_RUN_START
        lda     $C6
        bne     N_BACKTRACK_TEXT_POINTER
        dec     $C7
N_BACKTRACK_TEXT_POINTER:  dec     $C6
        jmp     N_BACKTRACK_TO_WORD_SPACE

N_RESTORE_TEXT_RUN_START:  lda     $80
        sta     $70
        lda     $81
        sta     $71
N_DRAW_NEXT_TEXT_CHAR:  lda     ($C2,x)
        jsr     N_DRAW_GLYPH_CHAR
        inc     $C2
        bne     N_CHECK_TEXT_RUN_END
        inc     $C3
N_CHECK_TEXT_RUN_END:  lda     $C3
        cmp     $C7
        bne     N_DRAW_NEXT_TEXT_CHAR
        lda     $C2
        cmp     $C6
        bne     N_DRAW_NEXT_TEXT_CHAR
        lda     ($C6,x)
        beq     N_TEXT_DRAW_DONE
N_BEGIN_NEXT_TEXT_LINE:  ldy     $91
        jsr     N_SET_HGR_X_FROM_Y
        lda     ($C6,x)
        cmp     #$8F
        bne     N_SKIP_TEXT_SEPARATOR
        ldy     $92
        jsr     N_SET_HGR_X_FROM_Y
N_SKIP_TEXT_SEPARATOR:  inc     $C6
        bne     N_CHECK_NEXT_TEXT_SPACE
        inc     $C7
N_CHECK_NEXT_TEXT_SPACE:  lda     ($C6,x)
        cmp     #$20
        beq     N_SKIP_TEXT_SEPARATOR
        lda     $C6
        sta     $C2
        lda     $C7
        sta     $C3
        jsr     N_ADVANCE_ROW_10
        jmp     N_MEASURE_NEXT_TEXT_RUN

N_TEXT_DRAW_DONE:  rts

; Center C interface string A around horizontal index X at scanline Y.
; Optional menu mode ($68) also records the computed left pixel edge.
N_DRAW_CENTERED_UI_TEXT:  stx     $93
        sty     $72
        tay
        jsr     N_SELECT_UI_TEXT
N_MEASURE_CENTERED_TEXT:  stx     $C6
        stx     $C2
        sty     $C7
        sty     $C3
        ldx     #$00
        stx     $70
        stx     $71
        stx     $67
N_MEASURE_CENTERED_NEXT_CHAR:  lda     ($C2,x)
        beq     N_HALVE_CENTERED_TEXT_WIDTH
        jsr     N_PREPARE_GLYPH_CHAR
        jsr     N_ADVANCE_GLYPH_CURSOR
        inc     $C2
        bne     N_MEASURE_CENTERED_NEXT_CHAR
        inc     $C3
        jmp     N_MEASURE_CENTERED_NEXT_CHAR

N_HALVE_CENTERED_TEXT_WIDTH:  lda     $70
        lsr     a
        sta     $70
        bcc     N_SUBTRACT_CENTERED_TEXT_WIDTH
        inc     $67
N_SUBTRACT_CENTERED_TEXT_WIDTH:  ldy     $93
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
        bcs     N_ADJUST_CENTERED_HALF_PIXEL
        adc     #$07
        dec     $70
N_ADJUST_CENTERED_HALF_PIXEL:  sta     $71
        lda     $67
        beq     N_RESET_CENTERED_TEXT_POINTER
        sec
        lda     $71
        sbc     #$04
        bcs     N_STORE_CENTERED_BIT_OFFSET
        adc     #$07
        dec     $70
N_STORE_CENTERED_BIT_OFFSET:  sta     $71
N_RESET_CENTERED_TEXT_POINTER:  lda     $C6
        sta     $C2
        lda     $C7
        sta     $C3
        lda     $68
        beq     N_DRAW_MEASURED_CENTERED_TEXT
        lda     $70
        sta     $7D
        sec
        lda     $71
        sbc     #$02
        bcs     N_RECORD_MENU_TEXT_LEFT_EDGE
        adc     #$07
        dec     $7D
N_RECORD_MENU_TEXT_LEFT_EDGE:  ldy     $94
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
        sta     MENU_LEFT_PIXEL,y
N_DRAW_MEASURED_CENTERED_TEXT:  jmp     N_PREPARE_TEXT_SCAN

N_READ_GAME_KEY:  bit     $C010
N_POLL_GAME_KEYBOARD:  lda     $C000
        bmi     N_FILTER_CONTROL_KEY
        inc     $5A
        jmp     N_POLL_GAME_KEYBOARD

N_FILTER_CONTROL_KEY:  sta     $75
        and     #$7F
        sta     $77
        sta     $76
        bit     $C010
        jsr     N_DISPATCH_CONTROL_KEY
        bcs     N_POLL_GAME_KEYBOARD
        jsr     N_UPPERCASE_NAME_CHAR
        sta     $77
        lda     $76
        rts

; Copy $83 bytes on each of $85 HGR rows from the source pointer in X/Y.
N_COPY_BITMAP_ROWS_TO_HGR:  stx     $CC
        sty     $CD
N_COPY_NEXT_BITMAP_ROW:  ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        ldx     #$00
        lda     $83
        sta     $84
N_COPY_NEXT_BITMAP_BYTE:  lda     ($CC,x)
        sta     ($C0),y
        inc     $CC
        bne     N_ADVANCE_COPIED_BITMAP_BYTE
        inc     $CD
N_ADVANCE_COPIED_BITMAP_BYTE:  iny
        dec     $84
        bne     N_COPY_NEXT_BITMAP_BYTE
        inc     $87
        dec     $85
        bne     N_COPY_NEXT_BITMAP_ROW
        rts

N_COPY_BITMAP_WITH_ROW_CLIP:  stx     $CC
        sty     $CD
N_COPY_CLIPPED_NEXT_ROW:  lda     $83
        sta     $84
        ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
N_CHECK_BITMAP_ROW_CLIP:  lda     $87
        cmp     #$04
        bcc     N_ADVANCE_CLIPPED_SOURCE_BYTE
        cmp     $A3
        bcs     N_ADVANCE_CLIPPED_SOURCE_BYTE
        lda     ($CC),y
        sta     ($C0),y
N_ADVANCE_CLIPPED_SOURCE_BYTE:  inc     $CC
        bne     N_ADVANCE_CLIPPED_DEST_BYTE
        inc     $CD
N_ADVANCE_CLIPPED_DEST_BYTE:  inc     $C0
        dec     $84
        bne     N_CHECK_BITMAP_ROW_CLIP
        inc     $87
        dec     $85
        bne     N_COPY_CLIPPED_NEXT_ROW
        rts

; Convert two horizontal indexes to byte columns and bit masks used by the
; clipped copy and XOR bitmap writers below.
N_SET_HGR_HORIZONTAL_CLIP:  lda     $D400,x
        sta     $BE
        lda     $D500,x
        sta     $A2
        lda     $D400,y
        sta     $BF
        lda     $D500,y
        sta     $5F
        rts

; Shift source bytes to the current HGR bit offset, replace complete interior
; bytes, and merge edge bits without changing pixels outside the clip.
N_MASKED_BITMAP_TO_HGR:  stx     $CC
        sty     $CD
        ldx     #$00
        stx     $A1
        jsr     N_SET_HGR_X_FROM_73
        lda     ($CC,x)
        bpl     N_MASKED_BITMAP_PREPARE_SHIFT
        lda     #$80
        sta     $A1
N_MASKED_BITMAP_PREPARE_SHIFT:  clc
        lda     $71
        adc     #$B2
        sta     $CB
N_MASKED_BITMAP_NEXT_ROW:  lda     $83
        sta     $84
        lda     $70
        sta     $80
        lda     #$00
        sta     $A0
        ldy     $87
        jsr     N_SET_HGR_ROW_ADDRESS
N_MASKED_BITMAP_NEXT_BYTE:  lda     #$00
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        ora     $A0
        ldy     $80
        cpy     $BE
        bcc     N_MASKED_BITMAP_SHIFT_REMAINDER
        bne     N_MASKED_BITMAP_CHECK_RIGHT_EDGE
        ldx     $A2
        and     N_OR_START_MASK,x
N_MASKED_BITMAP_MERGE_BOUNDARY:  ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     N_MASKED_BITMAP_SHIFT_REMAINDER

N_MASKED_BITMAP_CHECK_RIGHT_EDGE:  cpy     $BF
        beq     N_MASKED_BITMAP_MASK_RIGHT_EDGE
        bcs     N_MASKED_BITMAP_SHIFT_REMAINDER
        ora     $A1
        sta     ($C0),y
        jmp     N_MASKED_BITMAP_SHIFT_REMAINDER

N_MASKED_BITMAP_MASK_RIGHT_EDGE:  ldx     $5F
        and     N_OR_END_MASK,x
        jmp     N_MASKED_BITMAP_MERGE_BOUNDARY

N_MASKED_BITMAP_SHIFT_REMAINDER:  lda     #$80
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        sta     $A0
        inc     $80
        inc     $CC
        bne     N_MASKED_BITMAP_FINISH_ROW_BYTES
        inc     $CD
N_MASKED_BITMAP_FINISH_ROW_BYTES:  dec     $84
        bne     N_MASKED_BITMAP_NEXT_BYTE
        ldy     $80
        cpy     $BE
        bcc     N_MASKED_BITMAP_ADVANCE_ROW
        bne     N_MASKED_BITMAP_CHECK_REMAINDER_RIGHT_EDGE
        ldx     $A2
        and     N_OR_START_MASK,x
N_MASKED_BITMAP_MERGE_REMAINDER:  ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     N_MASKED_BITMAP_ADVANCE_ROW

N_MASKED_BITMAP_CHECK_REMAINDER_RIGHT_EDGE:  cpy     $BF
        beq     N_MASKED_BITMAP_MASK_REMAINDER_RIGHT_EDGE
        bcs     N_MASKED_BITMAP_ADVANCE_ROW
        ora     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     N_MASKED_BITMAP_ADVANCE_ROW

N_MASKED_BITMAP_MASK_REMAINDER_RIGHT_EDGE:  ldx     $5F
        and     N_OR_END_MASK,x
        jmp     N_MASKED_BITMAP_MERGE_REMAINDER

N_MASKED_BITMAP_ADVANCE_ROW:  dec     $85
        beq     N_MASKED_BITMAP_DONE
        inc     $87
        jmp     N_MASKED_BITMAP_NEXT_ROW

N_MASKED_BITMAP_DONE:  rts

; Alternate entry initializes the source pointer and HGR position. The glyph
; renderer enters at N_XOR_PREPARED_BITMAP_TO_HGR after those are prepared.
N_XOR_BITMAP_TO_HGR:  stx     $CC
        sty     $CD
        ldx     #$00
        stx     $A1
        jsr     N_SET_HGR_X_FROM_73
        lda     ($CC,x)
        bpl     N_XOR_BITMAP_PREPARE_SHIFT
N_XOR_PREPARED_BITMAP_TO_HGR:  lda     #$80
        sta     $A1
N_XOR_BITMAP_PREPARE_SHIFT:  clc
        lda     $71
        adc     #$B2
        sta     $CB
N_XOR_BITMAP_NEXT_ROW:  lda     $83
        sta     $84
        lda     $70
        sta     $80
        lda     #$00
        sta     $A0
        ldy     $87
        jsr     N_SET_HGR_ROW_ADDRESS
N_XOR_BITMAP_NEXT_BYTE:  lda     #$00
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        ora     $A0
        ldy     $80
        cpy     $BE
        bcc     N_XOR_BITMAP_SHIFT_REMAINDER
        bne     N_XOR_BITMAP_CHECK_RIGHT_EDGE
        ldx     $A2
        and     N_OR_START_MASK,x
N_XOR_BITMAP_MERGE_BOUNDARY:  eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     N_XOR_BITMAP_SHIFT_REMAINDER

N_XOR_BITMAP_CHECK_RIGHT_EDGE:  cpy     $BF
        beq     N_XOR_BITMAP_MASK_RIGHT_EDGE
        bcs     N_XOR_BITMAP_SHIFT_REMAINDER
        eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     N_XOR_BITMAP_SHIFT_REMAINDER

N_XOR_BITMAP_MASK_RIGHT_EDGE:  ldx     $5F
        and     N_OR_END_MASK,x
        jmp     N_XOR_BITMAP_MERGE_BOUNDARY

N_XOR_BITMAP_SHIFT_REMAINDER:  lda     #$80
        sta     $CA
        lda     ($CC,x)
        and     #$7F
        tay
        lda     ($CA),y
        sta     $A0
        inc     $80
        inc     $CC
        bne     N_XOR_BITMAP_FINISH_ROW_BYTES
        inc     $CD
N_XOR_BITMAP_FINISH_ROW_BYTES:  dec     $84
        bne     N_XOR_BITMAP_NEXT_BYTE
        ldy     $80
        cpy     $BE
        bcc     N_XOR_BITMAP_ADVANCE_ROW
        bne     N_XOR_BITMAP_CHECK_REMAINDER_RIGHT_EDGE
        ldx     $A2
        and     N_OR_START_MASK,x
N_XOR_BITMAP_MERGE_REMAINDER:  eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        ldx     #$00
        jmp     N_XOR_BITMAP_ADVANCE_ROW

N_XOR_BITMAP_CHECK_REMAINDER_RIGHT_EDGE:  cpy     $BF
        beq     N_XOR_BITMAP_MASK_REMAINDER_RIGHT_EDGE
        bcs     N_XOR_BITMAP_ADVANCE_ROW
        eor     ($C0),y
        and     #$7F
        ora     $A1
        sta     ($C0),y
        jmp     N_XOR_BITMAP_ADVANCE_ROW

N_XOR_BITMAP_MASK_REMAINDER_RIGHT_EDGE:  ldx     $5F
        and     N_OR_END_MASK,x
        jmp     N_XOR_BITMAP_MERGE_REMAINDER

N_XOR_BITMAP_ADVANCE_ROW:  dec     $85
        beq     N_XOR_BITMAP_DONE
        inc     $87
        jmp     N_XOR_BITMAP_NEXT_ROW

N_XOR_BITMAP_DONE:  rts

; Fill an HGR rectangle. X and Y supply the horizontal endpoints;
; $97 and $98 are the first and last scanlines. The first and last byte use
; masks; interior bytes are written whole. A boundary bit offset of six also
; updates bit zero of the adjacent byte.
HGR_FILL_RECT:  sty     $5E
        lda     $D400,x
        sta     $95
        sta     $70
        ldy     $D500,x
        sty     $7C
        lda     HGR_START_MASK,y
        sta     $83
        ldy     $5E
        lda     $D400,y
        sta     $96
        ldx     $D500,y
        stx     $7E
        lda     HGR_END_MASK,x
        sta     $85
        lda     $97
        sta     $87
N_FILL_RECT_NEXT_ROW:  ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        ldx     $95
        lda     $83
        cpx     $96
        bne     N_FILL_RECT_FIRST_BYTE
        and     $85
N_FILL_RECT_FIRST_BYTE:  ora     ($C0),y
        sta     ($C0),y
        cpx     $96
        beq     N_FILL_RECT_ROW_DONE
        lda     $7C
        jsr     N_FILL_ADJACENT_BIT0_IF_NEEDED
        lda     #$FF
N_FILL_RECT_INTERIOR_BYTE:  iny
        inx
        cpx     $96
        bcs     N_FILL_RECT_LAST_BYTE
        sta     ($C0),y
        jmp     N_FILL_RECT_INTERIOR_BYTE

N_FILL_RECT_LAST_BYTE:  lda     $85
        ora     ($C0),y
        sta     ($C0),y
N_FILL_RECT_ROW_DONE:  lda     $7E
        jsr     N_FILL_ADJACENT_BIT0_IF_NEEDED
        lda     $87
        cmp     $98
        bcs     N_FILL_RECT_DONE
        inc     $87
        bne     N_FILL_RECT_NEXT_ROW
N_FILL_RECT_DONE:  rts

N_FILL_ADJACENT_BIT0_IF_NEEDED:  cmp     #$06
        bcc     N_FILL_ADJACENT_DONE
        iny
        lda     ($C0),y
        ora     #$01
        sta     ($C0),y
        dey
N_FILL_ADJACENT_DONE:  rts

; Seven-bit HGR masks used to fill the first and last byte of a span.
; The high bit is set for the pixel phase in the ending masks.
HGR_START_MASK:
        .byte   $FF,$FE,$FC,$F8,$F0,$E0,$C0
HGR_END_MASK:
        .byte   $83,$87,$8F,$9F,$BF,$FF,$FF
; Clear an HGR rectangle with the same coordinate convention.
HGR_CLEAR_RECT:  sty     $5E
        lda     $D400,x
        sta     $95
        sta     $70
        ldy     $D500,x
        sty     $7C
        lda     HGR_CLEAR_START_MASK,y
        sta     $83
        ldy     $5E
        lda     $D400,y
        sta     $96
        ldx     $D500,y
        stx     $7E
        lda     HGR_CLEAR_END_MASK,x
        sta     $85
        lda     $97
        sta     $87
N_CLEAR_RECT_NEXT_ROW:  ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        ldx     $95
        lda     $83
        cpx     $96
        bne     N_CLEAR_RECT_FIRST_BYTE
        ora     $85
N_CLEAR_RECT_FIRST_BYTE:  and     ($C0),y
        sta     ($C0),y
        cpx     $96
        beq     N_CLEAR_RECT_ROW_DONE
        lda     $7C
        jsr     N_CLEAR_ADJACENT_BIT0_IF_NEEDED
        lda     #$80
N_CLEAR_RECT_INTERIOR_BYTE:  iny
        inx
        cpx     $96
        bcs     N_CLEAR_RECT_LAST_BYTE
        sta     ($C0),y
        jmp     N_CLEAR_RECT_INTERIOR_BYTE

N_CLEAR_RECT_LAST_BYTE:  lda     $85
        and     ($C0),y
        sta     ($C0),y
N_CLEAR_RECT_ROW_DONE:  lda     $7E
        jsr     N_CLEAR_ADJACENT_BIT0_IF_NEEDED
        lda     $87
        cmp     $98
        bcs     N_CLEAR_RECT_DONE
        inc     $87
        bne     N_CLEAR_RECT_NEXT_ROW
N_CLEAR_RECT_DONE:  rts

N_CLEAR_ADJACENT_BIT0_IF_NEEDED:  cmp     #$06
        bcc     N_CLEAR_ADJACENT_DONE
        iny
        lda     ($C0),y
        and     #$FE
        sta     ($C0),y
        dey
N_CLEAR_ADJACENT_DONE:  rts

; Complementary masks for clearing a seven-bit HGR span.
HGR_CLEAR_START_MASK:
        .byte   $80,$81,$83,$87,$8F,$9F,$BF
HGR_CLEAR_END_MASK:
        .byte   $FC,$F8,$F0,$E0,$C0,$80,$80
; Clear the main picture rectangle (scanlines $06-$89), then refresh its
; horizontal clipping endpoints for subsequent bitmap draws.
N_CLEAR_PICTURE_PANEL:  jsr     N_DRAW_COMMON_PANEL_GLYPHS
        lda     #$06
        sta     $97
        lda     #$89
        sta     $98
        ldx     #$49
        ldy     #$87
        jsr     HGR_CLEAR_RECT
        jsr     N_DRAW_COMMON_PANEL_GLYPHS
        ldx     #$49
        ldy     #$87
        jsr     N_SET_HGR_HORIZONTAL_CLIP
        rts

N_CLEAR_LOWER_MENU_PANEL:  lda     #$90
        sta     $97
        lda     #$BA
        sta     $98
        ldx     #$4D
        ldy     #$83
        jsr     HGR_CLEAR_RECT
        rts

N_CLEAR_MENU_TOP_STRIP:  lda     #$90
        sta     $97
        lda     #$99
        sta     $98
        ldx     #$49
        ldy     #$87
        jsr     HGR_CLEAR_RECT
        rts

; Y selects one of six rectangle geometries. Fill the outer area, clear the
; inset, then clear the two remaining border strips. The travel rectangle
; derives its bottom edge from the current city's connection count.
N_DRAW_FRAMED_MENU_RECT:  clc
        lda     N_RECT_PARAM_97,y
        sta     $97
        adc     #$02
        sta     N_FRAME_INNER_TOP_IMMEDIATE
        lda     N_RECT_PARAM_X,y
        tax
        adc     #$02
        sta     N_FRAME_INNER_LEFT_IMMEDIATE
        cpy     #$02
        bne     N_FRAME_USE_TABLE_BOTTOM
        stx     N_FRAME_RESTORE_LEFT_IMMEDIATE
        sty     N_FRAME_RESTORE_PARAM_IMMEDIATE
        jsr     N_CITY_ROUTE_COUNT
        clc
        lda     N_TRAVEL_RECT_BOTTOM_BY_ROUTE_COUNT,x
        adc     #$01
        ldx     #$00
N_FRAME_RESTORE_LEFT_IMMEDIATE  := * - 1             ; patched X immediate
        ldy     #$00
N_FRAME_RESTORE_PARAM_IMMEDIATE  := * - 1             ; patched Y immediate
        jmp     N_FRAME_SET_BOTTOM

N_FRAME_USE_TABLE_BOTTOM:  lda     N_RECT_PARAM_98,y
N_FRAME_SET_BOTTOM:  sec
        sta     $98
        sta     N_FRAME_OUTER_BOTTOM_IMMEDIATE
        sbc     #$02
        sta     N_FRAME_INNER_BOTTOM_IMMEDIATE
        lda     N_RECT_PARAM_Y,y
        tay
        sta     N_FRAME_OUTER_RIGHT_IMMEDIATE
        sbc     #$02
        sta     N_FRAME_INNER_RIGHT_IMMEDIATE
        jsr     HGR_FILL_RECT
        lda     #$00
N_FRAME_INNER_TOP_IMMEDIATE  := * - 1
        sta     $97
        lda     #$00
N_FRAME_INNER_BOTTOM_IMMEDIATE  := * - 1
        sta     $98
        ldx     #$00
N_FRAME_INNER_LEFT_IMMEDIATE  := * - 1
        ldy     #$00
N_FRAME_INNER_RIGHT_IMMEDIATE  := * - 1
        jsr     HGR_CLEAR_RECT
        lda     #$00
N_FRAME_OUTER_BOTTOM_IMMEDIATE  := * - 1
        sta     $98
        ldx     #$00
N_FRAME_OUTER_RIGHT_IMMEDIATE  := * - 1
        inx
        txa
        tay
        iny
        sty     N_FRAME_RIGHT_BORDER_IMMEDIATE
        jsr     HGR_CLEAR_RECT
        inc     $98
        lda     $98
        sta     $97
        inc     $98
        ldx     N_FRAME_INNER_LEFT_IMMEDIATE
        ldy     #$00
N_FRAME_RIGHT_BORDER_IMMEDIATE  := * - 1
        jsr     HGR_CLEAR_RECT
        rts

; Convert the selected option's stored pixel endpoints and row, then invert
; the seven visible HGR bits across eleven rows. Edge masks preserve pixels
; outside the selected text's horizontal span.
N_INVERT_MENU_SELECTION_RECTANGLE:  ldy     $6C
        ldx     MENU_LEFT_PIXEL,y
        lda     $D400,x
        sta     $95
        lda     $D500,x
        sta     $7C
        ldx     MENU_RIGHT_PIXEL,y
        lda     $D400,x
        sta     $96
        lda     $D500,x
        sta     $7E
        lda     ($D0),y
        sta     $87
        dec     $87
        lda     #$0B
        sta     $85
N_INVERT_MENU_NEXT_ROW:  lda     $95
        sta     $70
        ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        jsr     N_INVERT_MENU_ROW
        inc     $87
        dec     $85
        bne     N_INVERT_MENU_NEXT_ROW
        rts

N_INVERT_MENU_ROW:  ldx     $7C
        lda     ($C0),y
        pha
        and     N_AND_START_MASK,x
        sta     $5E
        pla
        eor     #$7F
        and     N_OR_START_MASK,x
        ora     $5E
        sta     ($C0),y
        inc     $C0
        inc     $70
N_INVERT_MENU_INTERIOR_BYTE:  lda     ($C0),y
        eor     #$7F
        sta     ($C0),y
        inc     $70
        inc     $C0
        lda     $70
        cmp     $96
        bcc     N_INVERT_MENU_INTERIOR_BYTE
        ldx     $7E
        lda     ($C0),y
        pha
        and     N_AND_END_MASK,x
        sta     $5E
        pla
        eor     #$7F
        and     N_OR_END_MASK,x
        ora     $5E
        sta     ($C0),y
        rts

N_ADVANCE_ROW_10:  lda     #$0A
        .byte   $2C             ; BIT skips the following LDA immediate
N_ADVANCE_ROW_11:  lda     #$0B
        sta     N_ROW_ADVANCE_IMMEDIATE
        clc
        lda     $72
        adc     #$00
N_ROW_ADVANCE_IMMEDIATE  := * - 1             ; patched by N_ADVANCE_ROW_10/N_ADVANCE_ROW_11
        sta     $72
        rts

N_DELAY_NESTED_A_Y:  sec
N_DELAY_OUTER_LOOP:  pha
N_DELAY_INNER_LOOP:  sbc     #$01
        bne     N_DELAY_INNER_LOOP
        pla
        sbc     #$01
        bne     N_DELAY_OUTER_LOOP
        rts

; Copy the complete 8 KiB HGR page between page 1 and page 2.
N_COPY_HGR_PAGE1_TO_PAGE2:  ldx     #$20
        ldy     #$40
        bne     N_COPY_HGR_PAGE_SETUP
N_COPY_HGR_PAGE2_TO_PAGE1:  ldx     #$40
        ldy     #$20
N_COPY_HGR_PAGE_SETUP:  stx     $C1
        sty     $CF
        ldy     #$00
        sty     $C0
        sty     $CE
        ldx     #$20
N_COPY_HGR_PAGE_BYTE:  lda     ($C0),y
        sta     ($CE),y
        iny
        bne     N_COPY_HGR_PAGE_BYTE
        inc     $CF
        inc     $C1
        dex
        bne     N_COPY_HGR_PAGE_BYTE
        rts

N_DRAW_MENU_ROW_MARKER:  lda     #$15
        sta     $70
        lda     #$00
        sta     $71
        lda     #$63
        ldx     $6C
        ldy     CLUE_TEXT_ROW,x
        dey
        sty     $72
        cpx     #$06
        bne     N_DRAW_SELECTED_ROW_GLYPH
        lda     #$17
        sta     $70
        lda     #$64
N_DRAW_SELECTED_ROW_GLYPH:  jsr     N_DRAW_GLYPH_INDEX
        rts

; Return when Return, Escape, or a joystick button selects/cancels the menu.
; $08/$0B move to the previous row; $15/$0A move to the next row. Other
; control keys pass through the global command dispatcher.
N_WAIT_MENU_SELECTION:  lda     $64
        beq     N_POLL_MENU_KEYBOARD
        dec     $A9
        bne     N_POLL_MENU_KEYBOARD
        lda     $69
        eor     #$01
        sta     $69
        jsr     N_GET_SELECTED_ROUTE_DESTINATION
        jsr     N_DRAW_ROUTE_DESTINATION_MARKER
        lda     $AB
        sta     $A9
N_POLL_MENU_KEYBOARD:  lda     $C000
        bmi     N_HANDLE_MENU_KEY
        inc     $5A
        jmp     N_CHECK_JOYSTICK_CONFIRM_BUTTON

N_HANDLE_MENU_KEY:  bit     $C010
        and     #$7F
        sta     $76
        cmp     #$08
        bne     N_CHECK_NEXT_MENU_KEY
N_SELECT_PREVIOUS_MENU_ROW:  jsr     N_CLEAR_OLD_MENU_HIGHLIGHT
        lda     $6C
        cmp     $6E
        beq     N_WRAP_TO_LAST_MENU_ROW
        dec     $6C
N_REDRAW_MENU_SELECTION:  lda     $6A
        beq     N_INVERT_NEW_MENU_SELECTION
        jsr     N_DRAW_MENU_ROW_MARKER
        jmp     N_WAIT_MENU_SELECTION

N_INVERT_NEW_MENU_SELECTION:  jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        lda     $6B
        bne     N_CONTINUE_MENU_INPUT
        lda     $64
        beq     N_INVERT_SECOND_PAGE_SELECTION
        jsr     N_CLEAR_TRAVEL_DEST_MARKER
        jmp     N_WAIT_MENU_SELECTION

N_INVERT_SECOND_PAGE_SELECTION:  inc     $74
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        inc     $74
N_CONTINUE_MENU_INPUT:  jmp     N_WAIT_MENU_SELECTION

N_WRAP_TO_LAST_MENU_ROW:  lda     $6F
        sta     $6C
        bne     N_REDRAW_MENU_SELECTION
N_CHECK_NEXT_MENU_KEY:  cmp     #$15
        bne     N_CHECK_UP_ARROW
N_SELECT_NEXT_MENU_ROW:  jsr     N_CLEAR_OLD_MENU_HIGHLIGHT
        lda     $6C
        cmp     $6F
        beq     N_WRAP_TO_FIRST_MENU_ROW
        inc     $6C
        jmp     N_REDRAW_MENU_SELECTION

N_WRAP_TO_FIRST_MENU_ROW:  lda     $6E
        sta     $6C
        jmp     N_REDRAW_MENU_SELECTION

N_CHECK_UP_ARROW:  cmp     #$0B
        bne     N_CHECK_DOWN_ARROW
        jmp     N_SELECT_PREVIOUS_MENU_ROW

N_CHECK_DOWN_ARROW:  cmp     #$0A
        bne     N_CHECK_MENU_CONFIRM
        jmp     N_SELECT_NEXT_MENU_ROW

N_CHECK_MENU_CONFIRM:  cmp     #$0D
        bne     N_CHECK_MENU_CANCEL
N_FINISH_MENU_SELECTION:  lda     $6A
        bne     N_MENU_SELECTION_DONE
N_CLEAR_MENU_SELECTION:  jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        lda     $6B
        bne     N_MENU_SELECTION_DONE
        lda     $64
        bne     N_MENU_SELECTION_DONE
        inc     $74
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        inc     $74
N_MENU_SELECTION_DONE:  rts

N_CHECK_MENU_CANCEL:  cmp     #$1B
        bne     N_DISPATCH_MENU_CONTROL_KEY
        lda     $6A
        beq     N_CLEAR_MENU_SELECTION
        jsr     N_DRAW_MENU_ROW_MARKER
        rts

N_DISPATCH_MENU_CONTROL_KEY:  jsr     N_DISPATCH_CONTROL_KEY
        bcc     N_REJECT_MENU_KEY
        jmp     N_WAIT_MENU_SELECTION

N_REJECT_MENU_KEY:  jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_WAIT_MENU_SELECTION

N_CHECK_JOYSTICK_CONFIRM_BUTTON:  lda     $C061
        bpl     N_CHECK_JOYSTICK_CANCEL_BUTTON
        lda     #$0D
        sta     $76
        lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        jmp     N_FINISH_MENU_SELECTION

N_CHECK_JOYSTICK_CANCEL_BUTTON:  lda     $C062
        bpl     N_POLL_JOYSTICK_DIRECTION
        lda     #$1B
        sta     $76
        lda     $6A
        bne     N_CANCEL_MARKED_MENU_ROW
        jmp     N_CLEAR_MENU_SELECTION

N_CANCEL_MARKED_MENU_ROW:  jsr     N_DRAW_MENU_ROW_MARKER
        rts

N_POLL_JOYSTICK_DIRECTION:  jsr     N_SAMPLE_JOYSTICK_PADDLES
        bcs     N_MENU_NO_JOYSTICK_ACTION
        lda     JOYSTICK_ENABLED
        beq     N_MENU_NO_JOYSTICK_ACTION
        lda     JOYSTICK_DIRECTION_BITS
        beq     N_MENU_NO_JOYSTICK_ACTION
        lda     #$80
        jsr     N_DELAY_NESTED_A_Y
        lda     JOYSTICK_DIRECTION_BITS
        bit     N_CONTROL_BIT_10
        bne     N_PADDLE1_MOVE_PREVIOUS
        bit     N_CONTROL_BIT_20
        bne     N_PADDLE1_MOVE_NEXT
        bit     N_CONTROL_BIT_80
        bne     N_PADDLE0_MOVE_PREVIOUS
        bit     N_CONTROL_BIT_40
        bne     N_PADDLE0_MOVE_NEXT
N_MENU_NO_JOYSTICK_ACTION:  jmp     N_WAIT_MENU_SELECTION

N_PADDLE0_MOVE_PREVIOUS:  lda     #$08
        sta     $76
        lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        jmp     N_SELECT_PREVIOUS_MENU_ROW

N_PADDLE0_MOVE_NEXT:  lda     #$15
        sta     $76
        lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        jmp     N_SELECT_NEXT_MENU_ROW

N_PADDLE1_MOVE_PREVIOUS:  lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        jmp     N_SELECT_PREVIOUS_MENU_ROW

N_PADDLE1_MOVE_NEXT:  lda     #$00
        jsr     N_DELAY_NESTED_A_Y
        jmp     N_SELECT_NEXT_MENU_ROW

; Strobe the two paddle timers. X counts until each $C064/$C065 signal
; drops; values below $18 or at least $A8 set one of four direction bits.
N_SAMPLE_JOYSTICK_PADDLES:  ldx     #$00
        stx     JOYSTICK_DIRECTION_BITS
        bit     $C070
N_WAIT_BOTH_PADDLES:  lda     $C064
        bpl     N_CAPTURE_PADDLE0_FIRST
        lda     $C065
        bpl     N_CAPTURE_PADDLE1_FIRST
        inx
        bne     N_WAIT_BOTH_PADDLES
        sec
        rts

N_CAPTURE_PADDLE0_FIRST:  stx     $9C
N_WAIT_PADDLE1:  lda     $C065
        bpl     N_CAPTURE_PADDLE1_AFTER_0
        lda     $C064
        nop
        inx
        bne     N_WAIT_PADDLE1
N_PADDLE_SAMPLE_TIMED_OUT:  sec
        rts

N_CAPTURE_PADDLE1_AFTER_0:  stx     $9A
        jmp     N_CLASSIFY_PADDLE0

N_CAPTURE_PADDLE1_FIRST:  stx     $9A
N_WAIT_PADDLE0:  lda     $C064
        bpl     N_CAPTURE_PADDLE0_AFTER_1
        lda     $C065
        nop
        inx
        bne     N_WAIT_PADDLE0
        jmp     N_PADDLE_SAMPLE_TIMED_OUT

N_CAPTURE_PADDLE0_AFTER_1:  stx     $9C
N_CLASSIFY_PADDLE0:  lda     $9C
        cmp     #$A8
        bcs     N_PADDLE0_HIGH
        cmp     #$18
        bcs     N_CLASSIFY_PADDLE1
        lda     #$80
        sta     JOYSTICK_DIRECTION_BITS
        bne     N_CLASSIFY_PADDLE1
N_PADDLE0_HIGH:  lda     #$40
        sta     JOYSTICK_DIRECTION_BITS
N_CLASSIFY_PADDLE1:  lda     $9A
        cmp     #$A8
        bcs     N_PADDLE1_HIGH
        cmp     #$18
        bcs     N_JOYSTICK_SAMPLE_DONE
        lda     #$10
        bne     N_STORE_PADDLE1_DIRECTION
N_PADDLE1_HIGH:  lda     #$20
N_STORE_PADDLE1_DIRECTION:  ora     JOYSTICK_DIRECTION_BITS
        sta     JOYSTICK_DIRECTION_BITS
N_JOYSTICK_SAMPLE_DONE:  lda     #$1A
        jsr     N_DELAY_NESTED_A_Y
        clc
        rts

N_CONTROL_BIT_80: .byte $80
N_CONTROL_BIT_40: .byte $40
N_CONTROL_BIT_20: .byte $20
N_CONTROL_BIT_10: .byte $10
N_CLEAR_OLD_MENU_HIGHLIGHT:  lda     $6A
        beq     N_INVERT_OLD_MENU_HIGHLIGHT
        jsr     N_DRAW_MENU_ROW_MARKER
N_HIGHLIGHT_CLEAR_DONE:  rts

N_INVERT_OLD_MENU_HIGHLIGHT:  jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        lda     $6B
        bne     N_HIGHLIGHT_CLEAR_DONE
        lda     $64
        beq     N_CLEAR_SECOND_PAGE_HIGHLIGHT
        jsr     N_CLEAR_TRAVEL_DEST_MARKER
        rts

N_CLEAR_SECOND_PAGE_HIGHLIGHT:  inc     $74
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        inc     $74
        rts

N_CLEAR_TRAVEL_DEST_MARKER:  lda     $69
        beq     N_RESET_TRAVEL_BLINK_TIMER
        jsr     N_GET_SELECTED_ROUTE_DESTINATION
        jsr     N_DRAW_ROUTE_DESTINATION_MARKER
        lda     #$00
        sta     $69
N_RESET_TRAVEL_BLINK_TIMER:  lda     $AB
        sta     $A9
        rts

; $6C is the selected row in the current city's J route list. Return that
; destination city in X; the map-position helper then loads its HGR column
; and scanline from N_POSITION_TRIPLES.
N_GET_SELECTED_ROUTE_DESTINATION:  ldy     CASE_CURRENT_CITY
        clc
        lda     J_ROUTE_OFFSETS,y
        adc     $6C
        tay
        ldx     J_ROUTE_DESTS,y
        rts

N_LOAD_CITY_MAP_POSITION:  txa
        sta     $87
        asl     a
        clc
        adc     $87
        tay
        lda     N_POSITION_TRIPLES,y
        sta     $70
        iny
        lda     N_POSITION_TRIPLES,y
        sta     $71
        iny
        lda     N_POSITION_TRIPLES,y
        sta     $72
        rts

N_DRAW_ROUTE_DESTINATION_MARKER:  jsr     N_LOAD_CITY_MAP_POSITION
        sec
        lda     $71
        sbc     #$02
        bcs     N_SET_DESTINATION_MARKER_COLUMN
        dec     $70
        adc     #$07
N_SET_DESTINATION_MARKER_COLUMN:  sta     $71
        sec
        lda     $72
        sbc     #$02
        sta     $72
        lda     #$60
        jsr     N_DRAW_GLYPH_INDEX
        rts

; Return the current city's route count in X from J's offset table.
N_CITY_ROUTE_COUNT:  ldy     CASE_CURRENT_CITY
        iny
        lda     J_ROUTE_OFFSETS,y
        dey
        sec
        sbc     J_ROUTE_OFFSETS,y
        tax
        rts

; Draw one of six compressed pictures using the metadata tables below.
; Geometry and source pointer come from N's parallel tables. Picture 0 takes
; its scanline stride from $1100 when that byte is nonzero; the first byte at
; the selected source pointer is the repeat marker.
HGR_RLE_DRAW_N:  cpy     #$00
        bne     N_RLE_USE_TABLE_STRIDE
        lda     $1100
        bne     N_RLE_LOAD_METADATA
N_RLE_USE_TABLE_STRIDE:  lda     N_IMAGE_STRIDE,y
N_RLE_LOAD_METADATA:  sta     $90
        lda     N_IMAGE_PTR_LO,y
        sta     $CC
        lda     N_IMAGE_PTR_HI,y
        sta     $CD
        lda     N_IMAGE_Y_START,y
        sta     $97
        lda     N_IMAGE_Y_END,y
        sta     $98
        lda     N_IMAGE_X_START,y
        sta     $95
        lda     N_IMAGE_X_END,y
        sta     $96
        ldx     #$00
        lda     ($CC,x)
        sta     $AF
        inc     $CC
        bne     N_RLE_START_PASS
        inc     $CD
N_RLE_START_PASS:  jsr     N_RLE_DRAW_PASS
        lda     $90
        cmp     #$01
        beq     N_RLE_DONE
        inc     $97
        jsr     N_RLE_DRAW_PASS
N_RLE_DONE:  rts

; Draw columns from first to last, visiting rows by the selected stride.
; The compressed stream pointer persists into the optional second row pass.
N_RLE_DRAW_PASS:  lda     $97
        sta     $72
        lda     $95
        sta     $70
N_RLE_NEXT_COMMAND:  ldy     $72
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        lda     ($CC,x)
        cmp     $AF
        beq     N_RLE_REPEAT_COMMAND
        sta     ($C0),y
N_RLE_ADVANCE_STREAM:  inc     $CC
        bne     N_RLE_NEXT_POSITION
        inc     $CD
N_RLE_NEXT_POSITION:  jsr     N_RLE_ADVANCE_POSITION
        jmp     N_RLE_NEXT_COMMAND

N_RLE_REPEAT_COMMAND:  inc     $CC
        bne     N_RLE_READ_REPEAT_VALUE
        inc     $CD
N_RLE_READ_REPEAT_VALUE:  lda     ($CC,x)
        sta     $B1
        inc     $CC
        bne     N_RLE_READ_REPEAT_COUNT
        inc     $CD
N_RLE_READ_REPEAT_COUNT:  lda     ($CC,x)
        sta     $B2
; A zero repeat count wraps through 256 copies via DEC below.
N_RLE_REPEAT_BYTE:  ldy     $72
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        lda     $B1
        sta     ($C0),y
        dec     $B2
        beq     N_RLE_REPEAT_FINISHED
        jsr     N_RLE_ADVANCE_POSITION
        jmp     N_RLE_REPEAT_BYTE

N_RLE_REPEAT_FINISHED:  jmp     N_RLE_ADVANCE_STREAM

; At the final column, remove our caller's return address so RTS exits the
; current pass instead of resuming its command loop.
N_RLE_ADVANCE_POSITION:  lda     $72
        clc
        adc     $90
        sta     $72
        cmp     $98
        bcc     N_RLE_POSITION_DONE
        beq     N_RLE_POSITION_DONE
        lda     $70
        cmp     $96
        bne     N_RLE_NEXT_COLUMN
        pla
        pla
        rts

N_RLE_NEXT_COLUMN:  inc     $70
        lda     $97
        sta     $72
N_RLE_POSITION_DONE:  rts

; Called after a module-load failure. A is the status code; X selects the
; requested disk side. Save drawing state while showing the prompt, then
; restore it before retrying the load.
N_PROMPT_FOR_DISK:  sta     $E0
        stx     $BB
        jsr     N_SAVE_DISPLAY_STATE
        lda     $6B
        beq     N_DISK_PROMPT_OUTER
        jmp     N_DISK_PROMPT_NESTED

N_DISK_PROMPT_OUTER:  lda     #$01
        sta     $6B
        inc     $74
        lda     $74
        lsr     a
        bcs     N_DISK_PROMPT_FROM_PAGE2
        jsr     N_COPY_HGR_PAGE1_TO_PAGE2
        jsr     N_WAIT_ON_DISK_PROMPT
        jsr     N_COPY_HGR_PAGE1_TO_PAGE2
N_DISK_PROMPT_RESTORE:  inc     $74
        jsr     N_RESTORE_DISPLAY_STATE
        lda     #$00
        sta     $6B
        rts

N_DISK_PROMPT_FROM_PAGE2:  jsr     N_COPY_HGR_PAGE2_TO_PAGE1
        jsr     N_WAIT_ON_DISK_PROMPT
        jsr     N_COPY_HGR_PAGE2_TO_PAGE1
        jmp     N_DISK_PROMPT_RESTORE

N_DISK_PROMPT_NESTED:  jsr     N_DRAW_DISK_PROMPT
        jsr     N_WAIT_KEY_OR_BUTTON
        jsr     N_RESTORE_DISPLAY_STATE
        rts

N_WAIT_ON_DISK_PROMPT:  jsr     N_DRAW_DISK_PROMPT
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        jsr     N_WAIT_KEY_OR_BUTTON
        inc     $74
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        inc     $74
        rts

; Preserve the HGR text position and two source-pointer bytes in $F0-$F4.
N_SAVE_DISPLAY_STATE:  lda     $70
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

N_RESTORE_DISPLAY_STATE:  lda     $F0
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

N_SET_HGR_ROW_ADDRESS:  lda     $D600,y
        sta     $C0
        lda     $D6C0,y
        sta     $C1
        lda     $74
        lsr     a
        bcs     N_HGR_ROW_ADDRESS_DONE
        lda     $C1
        adc     #$20
        sta     $C1
N_HGR_ROW_ADDRESS_DONE:  rts

; Convert an HGR horizontal index through C's quotient/remainder tables.
; The second entry accepts the index directly in Y.
N_SET_HGR_X_FROM_73:  ldy     $73
N_SET_HGR_X_FROM_Y:  lda     $D400,y
        sta     $70
        lda     $D500,y
        sta     $71
        rts

; Copy the 13-byte bank/display restore stub to $0100 and execute it there.
; No direct call to this entry has yet been identified.
N_INSTALL_QUIT_RAM_TRAMPOLINE: ldx #$0C
N_COPY_QUIT_TRAMPOLINE_BYTE:  lda     N_QUIT_RAM_TRAMPOLINE_SOURCE,x
        sta     RAM_QUIT_TRAMPOLINE,x
        dex
        bpl     N_COPY_QUIT_TRAMPOLINE_BYTE
        jmp     RAM_QUIT_TRAMPOLINE

N_QUIT_RAM_TRAMPOLINE_SOURCE:  lda     $C082
        lda     $C051
        lda     $C054
        jmp     ROM_RETURN_ENTRY_FF65

        nop
N_SHORT_FEEDBACK_TONE:  ldy     #$04
        lda     #$1E
        jmp     N_PLAY_FEEDBACK_TONE

N_RESTART_DETECTIVE_SESSION: lda #$00
        sta     $60
        jmp     N_MAIN_ENTRY

; Accept Y or N, echo the choice, then accept Return or backspace to edit it.
; Return the selected uppercase Y/N in A.
N_READ_YES_NO_RESPONSE:  jsr     N_READ_GAME_KEY
        lda     $77
        sta     N_YES_NO_RESULT_IMMEDIATE
        cmp     #$59
        beq     N_ECHO_YES_NO_RESPONSE
        cmp     #$4E
        beq     N_ECHO_YES_NO_RESPONSE
        jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_READ_YES_NO_RESPONSE

N_ECHO_YES_NO_RESPONSE:  jsr     N_TOGGLE_TEXT_CURSOR
        lda     $76
        sta     N_YES_NO_ECHO_CHAR_IMMEDIATE
        jsr     N_DRAW_GLYPH_CHAR
        jsr     N_TOGGLE_TEXT_CURSOR
N_WAIT_YES_NO_RETURN:  jsr     N_READ_GAME_KEY
        cmp     #$0D
        beq     N_RETURN_YES_NO_CHAR
        cmp     #$08
        bne     N_CHECK_YES_NO_DELETE
N_ERASE_YES_NO_RESPONSE:  jsr     N_TOGGLE_TEXT_CURSOR
        lda     #$00
N_YES_NO_ECHO_CHAR_IMMEDIATE  := * - 1
        jsr     N_MOVE_LEFT_BY_GLYPH_WIDTH
        lda     N_YES_NO_ECHO_CHAR_IMMEDIATE
        jsr     N_DRAW_GLYPH_CHAR
        jsr     N_REWIND_GLYPH_CURSOR
        jsr     N_TOGGLE_TEXT_CURSOR
        jmp     N_READ_YES_NO_RESPONSE

N_CHECK_YES_NO_DELETE:  cmp     #$7F
        beq     N_ERASE_YES_NO_RESPONSE
        jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_WAIT_YES_NO_RETURN

N_RETURN_YES_NO_CHAR:  lda     #$00
N_YES_NO_RESULT_IMMEDIATE  := * - 1
        rts

N_REFRESH_CITY_PICTURE:  inc     $74
        jsr     N_DRAW_CITY_LANDMARK_IMAGE
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        rts

N_DISPATCH_CONTROL_KEY:  lda     $76
        ldy     #$07
N_SCAN_CONTROL_KEY_TABLE:  cmp     N_KEY_DISPATCH_CODES,y
        beq     N_PATCH_CONTROL_KEY_CALL
        dey
        bpl     N_SCAN_CONTROL_KEY_TABLE
        clc
        rts

N_PATCH_CONTROL_KEY_CALL:  lda     N_KEY_DISPATCH_LO,y
        sta     N_KEY_JSR_LO
        lda     N_KEY_DISPATCH_HI,y
        sta     N_KEY_JSR_HI
N_KEY_JSR:
        jsr     $0000            ; target supplied by the tables above
N_KEY_JSR_LO := N_KEY_JSR + 1
N_KEY_JSR_HI := N_KEY_JSR + 2
        sec
        rts

N_TOGGLE_SOUND: lda     SOUND_ENABLED
        eor     #$01
        sta     SOUND_ENABLED
        rts

N_TOGGLE_JOYSTICK: lda JOYSTICK_ENABLED
        eor     #$01
        sta     JOYSTICK_ENABLED
        rts

; $74 odd selects page 1; $74 even selects page 2. Present that page and
; mirror its 8 KiB image into the other page for the next animation frame.
N_PRESENT_AND_MIRROR_HGR_PAGE:  lda     $74
        lsr     a
        bcc     N_PRESENT_HGR_PAGE2_AND_MIRROR
        lda     $C054
        jsr     N_COPY_HGR_PAGE1_TO_PAGE2
        rts

N_PRESENT_HGR_PAGE2_AND_MIRROR:  lda     $C055
        jsr     N_COPY_HGR_PAGE2_TO_PAGE1
        rts

N_DRAW_CITY_LANDMARK_IMAGE:  ldy     #$00
        jsr     HGR_RLE_DRAW_N
        rts

; Select the HGR page indicated by the low bit of $74.
N_SHOW_ACTIVE_HGR_PAGE:  lda     $74
        lsr     a
        bcc     N_SHOW_HGR_PAGE2
        lda     $C054
        rts

N_SHOW_HGR_PAGE2:  lda     $C055
        rts

; Draw the assembled text at $A000, then present it and wait for input.
N_SHOW_TEXT_BUFFER_A000:  lda     #$0C
        sta     $73
        jsr     N_SET_HGR_X_FROM_73
        ldx     #$00
        ldy     #$A0
        jsr     N_DRAW_TEXT_XY
        jsr     N_SHOW_WARRANT_FOLLOWUP
        rts

; Reset the C string-copy destination to $A000 and its append offset to zero.
N_RESET_TEXT_BUFFER_A000:  lda     #$00
        sta     $AC
        lda     #$00
        sta     $DA
        lda     #$A0
        sta     $DB
        rts

; Compare the X/Y string with the input at $9E60, ignoring ASCII case.
; Both strings may end with $FF; carry clear means equal, set means different.
N_COMPARE_INPUT_NAME:  stx     $C2
        sty     $C3
        ldy     #$00
N_COMPARE_NEXT_NAME_CHAR:  lda     ($C2),y
        beq     N_COMPARE_NAME_TERMINATOR
        cmp     #$FF
        beq     N_COMPARE_NAME_TERMINATOR
        jsr     N_UPPERCASE_NAME_CHAR
        sta     $87
        lda     $9E60,y
        jsr     N_UPPERCASE_NAME_CHAR
        cmp     $87
        bne     N_NAME_DIFFERENT
        iny
        bne     N_COMPARE_NEXT_NAME_CHAR
N_NAME_DIFFERENT:  sec
        rts

N_COMPARE_NAME_TERMINATOR:  lda     $9E60,y
        cmp     #$FF
        bne     N_NAME_DIFFERENT
        clc
        rts

N_UPPERCASE_NAME_CHAR:  cmp     #$61
        bcc     N_UPPERCASE_CHAR_DONE
        cmp     #$7B
        bcs     N_UPPERCASE_CHAR_DONE
        sec
        sbc     #$20
N_UPPERCASE_CHAR_DONE:  rts

; The clock is drawn as weekday, two hour digits, and AM/PM glyphs so each
; part can be refreshed independently when a case hour advances.
N_DRAW_CLOCK_WEEKDAY:  lda     #$3C
        sta     $93
        lda     #$09
        sta     $72
        sta     $97
        lda     #$10
        sta     $98
        ldx     #$35
        ldy     #$42
        jsr     HGR_FILL_RECT
        lda     CASE_DAY
        ldx     #<C_WEEKDAYS
        ldy     #>C_WEEKDAYS
        jsr     C_SKIP_NUL_STRINGS
        jsr     N_MEASURE_CENTERED_TEXT
        rts

N_DRAW_CLOCK_HOUR:  lda     #$15
        sta     $97
        sta     $72
        lda     #$1B
        sta     $98
        ldx     #$35
        ldy     #$3D
        jsr     HGR_FILL_RECT
        lda     #$0F
        sta     $70
        lda     #$03
        sta     $71
        ldy     CASE_HOUR
        lda     C_CLOCK_HOUR_TENS,y
        jsr     N_DRAW_GLYPH_INDEX
        ldy     CASE_HOUR
        lda     C_CLOCK_HOUR_ONES,y
        jsr     N_DRAW_GLYPH_INDEX
        rts

N_DRAW_CLOCK_AM_PM:  lda     #$18
        sta     $97
        sta     $72
        lda     #$1B
        sta     $98
        ldx     #$3D
        ldy     #$42
        jsr     HGR_FILL_RECT
        ldy     #$3E
        jsr     N_SET_HGR_X_FROM_Y
        lda     #$65
        ldx     CASE_HOUR
        cpx     #$0C
        bcc     N_DRAW_CLOCK_MERIDIEM_GLYPH
        lda     #$66
N_DRAW_CLOCK_MERIDIEM_GLYPH:  jsr     N_DRAW_GLYPH_INDEX
        rts

; Draw the shared HGR frame. Modal mode ($6B) returns after its common glyphs;
; city mode also draws the landmark decoration and live clock.
N_DRAW_COMMON_SCREEN_BACKGROUND:  lda     #$27
        sta     $BF
        lda     #$00
        sta     $BE
        sta     $A2
        sta     $5F
        sta     $70
        tax
        ldy     #$BF
        lda     #$F8
        jsr     N_FILL_HGR_COLUMN_ROWS
        lda     #$27
        sta     $70
        ldx     #$00
        ldy     #$BF
        lda     #$8F
        jsr     N_FILL_HGR_COLUMN_ROWS
        ldx     #$01
        ldy     #$27
        lda     #$00
        jsr     N_FILL_FOUR_ROW_BYTE_SPAN
        ldx     #$01
        ldy     #$27
        lda     #$BC
        jsr     N_FILL_FOUR_ROW_BYTE_SPAN
        ldx     #$03
        lda     $6B
        bne     N_SET_BACKGROUND_GLYPH_INDEX
        dex
N_SET_BACKGROUND_GLYPH_INDEX:  stx     $9C
N_DRAW_BACKGROUND_GLYPH:  ldx     $9C
        lda     N_GLYPH_SET_A_X_BYTE,x
        sta     $70
        lda     N_GLYPH_SET_A_X_BIT,x
        sta     $71
        lda     N_GLYPH_SET_A_ROW,x
        sta     $72
        lda     N_GLYPH_SET_A_GLYPH_INDEX,x
        jsr     N_DRAW_GLYPH_INDEX
        dec     $9C
        bpl     N_DRAW_BACKGROUND_GLYPH
        lda     $6B
        beq     N_DRAW_CITY_SCREEN_DETAILS
        rts

N_DRAW_CITY_SCREEN_DETAILS:  lda     #$14
        sta     $70
        ldx     #$04
        ldy     #$BB
        lda     #$8F
        jsr     N_FILL_HGR_COLUMN_ROWS
        ldx     #$01
        ldy     #$14
        lda     #$22
        jsr     N_FILL_FOUR_ROW_BYTE_SPAN
        ldx     #$14
        ldy     #$27
        lda     #$8A
        jsr     N_FILL_FOUR_ROW_BYTE_SPAN
        lda     #$04
        sta     $9C
N_DRAW_CITY_DETAIL_GLYPH:  ldx     $9C
        lda     N_GLYPH_SET_C_X_BYTE,x
        sta     $70
        lda     N_GLYPH_SET_C_X_BIT,x
        sta     $71
        lda     N_GLYPH_SET_C_ROW,x
        sta     $72
        lda     N_GLYPH_SET_C_GLYPH_INDEX,x
        jsr     N_DRAW_GLYPH_INDEX
        dec     $9C
        bpl     N_DRAW_CITY_DETAIL_GLYPH
        jsr     N_DRAW_COMMON_PANEL_GLYPHS
        ldy     #$01
        jsr     HGR_RLE_DRAW_N
        jsr     N_DRAW_CLOCK_WEEKDAY
        jsr     N_DRAW_CLOCK_HOUR
        jsr     N_DRAW_CLOCK_AM_PM
        rts

N_FILL_FOUR_ROW_BYTE_SPAN:  stx     $95
        sty     $96
        sta     $72
        lda     #$04
        sta     $85
N_FILL_NEXT_SPAN_ROW:  ldy     $72
        jsr     N_SET_HGR_ROW_ADDRESS
        ldy     $95
        lda     #$FF
N_FILL_NEXT_SPAN_BYTE:  sta     ($C0),y
        iny
        cpy     $96
        bne     N_FILL_NEXT_SPAN_BYTE
        inc     $72
        dec     $85
        bne     N_FILL_NEXT_SPAN_ROW
        rts

N_FILL_HGR_COLUMN_ROWS:  sta     N_COLUMN_FILL_BYTE_IMMEDIATE
        stx     $72
        sty     $87
N_FILL_NEXT_COLUMN_ROW:  ldy     $72
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        lda     #$00
N_COLUMN_FILL_BYTE_IMMEDIATE  := * - 1
        sta     ($C0),y
N_CHECK_COLUMN_LAST_ROW:  lda     $72
        cmp     $87
        beq     N_COLUMN_FILL_DONE
        inc     $72
        jmp     N_FILL_NEXT_COLUMN_ROW

N_COLUMN_FILL_DONE:  rts

N_DRAW_COMMON_PANEL_GLYPHS:  lda     #$27
        sta     $BF
        lda     #$00
N_PANEL_CLIP_END_IMMEDIATE  := * - 1
        sta     $5F
        lda     #$03
        sta     $AA
N_DRAW_PANEL_GLYPH:  ldx     $AA
        lda     N_GLYPH_SET_B_X_BYTE,x
        sta     $70
        lda     N_GLYPH_SET_B_X_BIT,x
        sta     $71
        lda     N_GLYPH_SET_B_ROW,x
        sta     $72
        lda     N_GLYPH_SET_B_GLYPH_INDEX,x
        jsr     N_DRAW_GLYPH_INDEX
        dec     $AA
        bpl     N_DRAW_PANEL_GLYPH
        rts

; Draw an unsigned decimal byte without leading zeroes at the HGR cursor.
N_DRAW_DECIMAL_A:  ldx     #$00
        stx     $AD
N_COUNT_DECIMAL_HUNDREDS:  cmp     #$64
        bcc     N_PRINT_DECIMAL_HUNDREDS
        sbc     #$64
        inx
        jmp     N_COUNT_DECIMAL_HUNDREDS

N_PRINT_DECIMAL_HUNDREDS:  cpx     #$00
        beq     N_COUNT_DECIMAL_TENS
        pha
        txa
        clc
        adc     #$30
        jsr     N_DRAW_GLYPH_CHAR
        inc     $AD
        pla
        ldx     #$00
N_COUNT_DECIMAL_TENS:  cmp     #$0A
        bcc     N_CHECK_DECIMAL_TENS
        sbc     #$0A
        inx
        jmp     N_COUNT_DECIMAL_TENS

N_CHECK_DECIMAL_TENS:  cpx     #$00
        bne     N_PRINT_DECIMAL_TENS
        ldy     $AD
        beq     N_PRINT_DECIMAL_ONES
N_PRINT_DECIMAL_TENS:  pha
        txa
        clc
        adc     #$30
        jsr     N_DRAW_GLYPH_CHAR
        pla
N_PRINT_DECIMAL_ONES:  clc
        adc     #$30
        jsr     N_DRAW_GLYPH_CHAR
        rts

; Return a pseudorandom value in 0..A-1. A=0 returns zero.
; $59/$5A hold the evolving generator state; $5E is the bound.
N_RANDOM_BELOW:  ora     #$00
        beq     N_RANDOM_RESULT_READY
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
        bvc     N_UPDATE_RANDOM_STATE
        inc     $5A
N_UPDATE_RANDOM_STATE:  sta     $59
        dec     $59
N_REDUCE_RANDOM_TO_BOUND:  cmp     $5E
        bcc     N_RANDOM_RESULT_READY
        sbc     $5E
        bcs     N_REDUCE_RANDOM_TO_BOUND
N_RANDOM_RESULT_READY:  rts

; Draw UI string Y with a fixed left margin, or use the current HGR X position
; at N_DRAW_UI_TEXT. N_DRAW_TEXT_XY accepts an arbitrary string pointer.
; This report renderer measures a run, then reveals its glyphs one at a time.
; It checks global commands between glyphs and scrolls at a line boundary.
N_DRAW_UI_TEXT_AT_LEFT_MARGIN:  sty     $5E
        lda     #$0C
        sta     $73
        jsr     N_SET_HGR_X_FROM_73
        ldy     $5E
N_DRAW_UI_TEXT:  jsr     N_SELECT_UI_TEXT
N_DRAW_TEXT_XY:  stx     $C2
        stx     $C6
        sty     $C3
        sty     $C7
        lda     #$0C
        sta     $91
        lda     #$99
        sta     $72
        ldx     #$00
N_TYPEWRITER_MEASURE_RUN:  lda     $70
        sta     $80
        lda     $71
        sta     $81
N_TYPEWRITER_SCAN_CHAR:  lda     ($C6,x)
        bne     N_TYPEWRITER_MEASURE_GLYPH
        lda     $C2
        cmp     $C6
        bne     N_TYPEWRITER_RESTORE_CURSOR
        lda     $C3
        cmp     $C7
        bne     N_TYPEWRITER_RESTORE_CURSOR
        jmp     N_TYPEWRITER_END_LINE

N_TYPEWRITER_MEASURE_GLYPH:  cmp     #$8D
        bcs     N_TYPEWRITER_HANDLE_BREAK
        jsr     N_PREPARE_GLYPH_CHAR
        jsr     N_ADVANCE_GLYPH_CURSOR
        lda     $70
        cmp     #$12
        bcs     N_TYPEWRITER_BACKTRACK_SPACE
        inc     $C6
        bne     N_TYPEWRITER_SCAN_CHAR
        inc     $C7
        jmp     N_TYPEWRITER_SCAN_CHAR

N_TYPEWRITER_HANDLE_BREAK:  lda     $C3
        cmp     $C7
        bne     N_TYPEWRITER_RESTORE_CURSOR
        lda     $C2
        cmp     $C6
        bne     N_TYPEWRITER_RESTORE_CURSOR
        jmp     N_TYPEWRITER_END_LINE

N_TYPEWRITER_BACKTRACK_SPACE:  lda     ($C6,x)
        cmp     #$20
        beq     N_TYPEWRITER_RESTORE_CURSOR
        lda     $C6
        bne     N_TYPEWRITER_BACKTRACK_POINTER
        dec     $C7
N_TYPEWRITER_BACKTRACK_POINTER:  dec     $C6
        jmp     N_TYPEWRITER_BACKTRACK_SPACE

N_TYPEWRITER_RESTORE_CURSOR:  lda     $80
        sta     $70
        lda     $81
        sta     $71
N_TYPEWRITER_DRAW_NEXT_CHAR:  jsr     N_TOGGLE_TEXT_CURSOR
        ldx     #$00
        lda     ($C2,x)
        jsr     N_DRAW_GLYPH_CHAR
        jsr     N_TOGGLE_TEXT_CURSOR
        lda     $C061
        bmi     N_TYPEWRITER_POLL_INTERRUPT_KEY
        jsr     N_TYPEWRITER_TICK
        lda     #$80
        jsr     N_DELAY_NESTED_A_Y
N_TYPEWRITER_POLL_INTERRUPT_KEY:  lda     $C000
        bpl     N_TYPEWRITER_ADVANCE_SOURCE
        bit     $C010
        and     #$7F
        sta     $76
        lda     $C2
        pha
        lda     $C3
        pha
        lda     $C6
        pha
        lda     $C7
        pha
        jsr     N_DISPATCH_CONTROL_KEY
        pla
        sta     $C7
        pla
        sta     $C6
        pla
        sta     $C3
        pla
        sta     $C2
N_TYPEWRITER_ADVANCE_SOURCE:  inc     $C2
        bne     N_TYPEWRITER_CHECK_RUN_END
        inc     $C3
N_TYPEWRITER_CHECK_RUN_END:  lda     $C2
        cmp     $C6
        bne     N_TYPEWRITER_DRAW_NEXT_CHAR
        lda     $C3
        cmp     $C7
        bne     N_TYPEWRITER_DRAW_NEXT_CHAR
N_TYPEWRITER_END_LINE:  lda     #$5F
        jsr     N_DRAW_GLYPH_INDEX
        jsr     N_SCROLL_REPORT_WINDOW
        lda     #$99
        sta     $72
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        ldx     #$00
        lda     ($C6,x)
        beq     N_TYPEWRITER_DONE
        lda     $C061
        bmi     N_TYPEWRITER_SELECT_NEXT_MARGIN
        lda     #$A0
        jsr     N_DELAY_NESTED_A_Y
N_TYPEWRITER_SELECT_NEXT_MARGIN:  ldy     $91
        lda     ($C6,x)
        cmp     #$8F
        bne     N_TYPEWRITER_SET_NEXT_MARGIN
        ldy     $92
N_TYPEWRITER_SET_NEXT_MARGIN:  jsr     N_SET_HGR_X_FROM_Y
N_TYPEWRITER_ADVANCE_BREAK:  inc     $C6
        bne     N_TYPEWRITER_SKIP_SPACES
        inc     $C7
N_TYPEWRITER_SKIP_SPACES:  lda     ($C6,x)
        cmp     #$80
        beq     N_TYPEWRITER_SKIP_MARKER_80
        cmp     #$20
        bne     N_TYPEWRITER_RESUME_NEXT_LINE
        jmp     N_TYPEWRITER_ADVANCE_BREAK

N_TYPEWRITER_SKIP_MARKER_80:  inc     $C6
        bne     N_TYPEWRITER_RESUME_NEXT_LINE
        inc     $C7
N_TYPEWRITER_RESUME_NEXT_LINE:  lda     $C6
        sta     $C2
        lda     $C7
        sta     $C3
        jsr     N_TOGGLE_TEXT_CURSOR
        jmp     N_TYPEWRITER_MEASURE_RUN

N_TYPEWRITER_DONE:  ldy     $91
        jsr     N_SET_HGR_X_FROM_Y
        lda     #$99
        sta     $72
        jsr     N_TOGGLE_TEXT_CURSOR
        rts

; Copy $6F report scanlines upward by ten rows between HGR pages, then
; refresh the lower border. The page parity chooses source and destination directions.
N_SCROLL_REPORT_WINDOW:  inc     $74
        lda     #$34
        sta     $72
        lda     #$2A
        sta     $87
        lda     #$6F
        sta     $AA
        jsr     N_SCROLL_NEXT_REPORT_ROW
        lda     #$99
        sta     $97
        lda     #$A2
        sta     $98
        ldx     #$0A
        ldy     #$3E
        jsr     HGR_FILL_RECT
        rts

N_SCROLL_NEXT_REPORT_ROW:  ldy     $72
        lda     $74
        lsr     a
        bcc     N_SCROLL_OTHER_PAGE_SETUP
        lda     $D600,y
        sta     $C0
        clc
        lda     $D6C0,y
        adc     #$20
        sta     $C1
        ldy     $87
        lda     $D600,y
        sta     $CE
        lda     $D6C0,y
        sta     $CF
        bne     N_SCROLL_COPY_ROW_BYTES
N_SCROLL_OTHER_PAGE_SETUP:  lda     $D600,y
        sta     $C0
        lda     $D6C0,y
        sta     $C1
        ldy     $87
        lda     $D600,y
        sta     $CE
        lda     $D6C0,y
        adc     #$20
        sta     $CF
N_SCROLL_COPY_ROW_BYTES:  ldy     #$03
N_SCROLL_COPY_NEXT_BYTE:  lda     ($C0),y
        sta     ($CE),y
        iny
        cpy     #$12
        bne     N_SCROLL_COPY_NEXT_BYTE
        inc     $72
        inc     $87
        dec     $AA
        bne     N_SCROLL_NEXT_REPORT_ROW
        rts

N_TYPEWRITER_TICK:  ldy     #$02
        lda     #$3A
        jsr     N_PLAY_FEEDBACK_TONE
        lda     #$40
        jsr     N_DELAY_NESTED_A_Y
        rts

N_SHOW_WARRANT_FOLLOWUP:  ldx     #$68
        ldy     #$97
        lda     #$09
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     #$68
        ldy     $72
        lda     #$0A
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     #$68
        ldy     $72
        lda     #$0B
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_WAIT_KEY_OR_BUTTON
        jsr     N_CLEAR_REPORT_FOLLOWUP_PANEL
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        rts

N_CLEAR_REPORT_FOLLOWUP_PANEL:  lda     #$95
        sta     $97
        lda     #$B3
        sta     $98
        ldx     #$49
        ldy     #$87
        jsr     HGR_CLEAR_RECT
        rts

N_TOGGLE_TEXT_CURSOR:  lda     #$5F
        jsr     N_DRAW_GLYPH_INDEX
        jsr     N_REWIND_GLYPH_CURSOR
        rts

; Wait for an ordinary key or either joystick button; dispatch control keys.
N_WAIT_KEY_OR_BUTTON:  bit     $C010
N_POLL_KEY_OR_BUTTON:  lda     $C000
        bmi     N_CHECK_WAITING_CONTROL_KEY
        lda     $C061
        bmi     N_KEY_OR_BUTTON_READY
        lda     $C062
        bmi     N_KEY_OR_BUTTON_READY
        jmp     N_POLL_KEY_OR_BUTTON

N_CHECK_WAITING_CONTROL_KEY:  bit     $C010
        and     #$7F
        sta     $76
        jsr     N_DISPATCH_CONTROL_KEY
        bcs     N_POLL_KEY_OR_BUTTON
N_KEY_OR_BUTTON_READY:  rts

N_PREPARE_REPORT_SCREEN:  jsr     N_CLEAR_NEXT_MODAL_HGR_PAGE
        jsr     N_DRAW_COMMON_SCREEN_BACKGROUND
        ldy     #$02
        jsr     HGR_RLE_DRAW_N
        ldy     #$0C
        sty     $73
        jsr     N_SET_HGR_X_FROM_Y
        lda     #$99
        sta     $72
        lda     #$5F
        jsr     N_DRAW_GLYPH_INDEX
        ldx     #$1C
        ldy     #$0E
        lda     #$02
        jsr     N_DRAW_CENTERED_UI_TEXT
        rts

; $2B requests the write-protection warning. Other statuses show the
; "Please insert" prompt with Side A/B selected by $BB.
N_DRAW_DISK_PROMPT:  lda     $E0
        cmp     #$2B
        bne     N_DRAW_INSERT_DISK_PROMPT
        ldy     #$05
        jsr     N_DRAW_FRAMED_MENU_RECT
        ldy     #$48
        lda     #$61
        ldx     #$44
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldy     $72
        lda     #$75
        ldx     #$44
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldy     $72
        lda     #$08
        bne     N_DRAW_DISK_CONTINUE_LINE
N_DRAW_INSERT_DISK_PROMPT:  ldy     #$00
        jsr     N_DRAW_FRAMED_MENU_RECT
        ldx     #$44
        ldy     #$34
        lda     #$03
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     #$44
        ldy     $72
        lda     #$04
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldx     #$44
        ldy     $72
        lda     #$05
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldy     $72
        ldx     $BB
        dex
        lda     N_DIALOG_OPTION_CODES,x
        ldx     #$44
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_ADVANCE_ROW_10
        ldy     $72
        lda     #$08
N_DRAW_DISK_CONTINUE_LINE:  ldx     #$44
        jsr     N_DRAW_CENTERED_UI_TEXT
        rts

N_DIALOG_OPTION_CODES: .byte $06, $07
; Six selections for each rectangle parameter used by N_DRAW_FRAMED_MENU_RECT.
N_RECT_PARAM_97: .byte $30, $40, $28, $42, $35, $3F
N_RECT_PARAM_98: .byte $68, $50, $00, $96, $68, $6C
N_RECT_PARAM_X:  .byte $1F, $27, $0A, $07, $12, $22
N_RECT_PARAM_Y:  .byte $67, $63, $3F, $4C, $74, $64

N_DRAW_SAVE_CASE_PROMPT:  ldx     #$45
        ldy     #$39
        lda     #N_UI_SAVE_CASE_QUESTION
        jsr     N_DRAW_CENTERED_UI_TEXT
        lda     $72
        clc
        adc     #$0F
        tay
        ldx     #$17
        stx     $91
        lda     #N_UI_SAVE_CASE_HELP
        jsr     N_DRAW_UI_TEXT_AT_XY
        rts

N_SHOW_VERSION_SCREEN: jsr N_BEGIN_MODAL_SCREEN
        lda     $BE
        sta     N_VERSION_RESTORE_BE
        lda     $A2
        sta     N_VERSION_RESTORE_A2
        lda     $BF
        sta     N_VERSION_RESTORE_BF
        lda     $5F
        sta     N_VERSION_RESTORE_5F
        ldx     #$04
        ldy     #$87
        jsr     N_SET_HGR_HORIZONTAL_CLIP
        lda     $74
        lsr     a
        bcs     N_VERSION_COPY_PAGE2_BRANCH
        jsr     N_COPY_HGR_PAGE1_TO_PAGE2
        jsr     N_DRAW_VERSION_DIALOG
        jsr     N_COPY_HGR_PAGE1_TO_PAGE2
        jsr     N_END_MODAL_SCREEN
        lda     #$00
N_VERSION_RESTORE_BE  := * - 1
        sta     $BE
        lda     #$00
N_VERSION_RESTORE_A2  := * - 1
        sta     $A2
        lda     #$00
N_VERSION_RESTORE_BF  := * - 1
        sta     $BF
        lda     #$00
N_VERSION_RESTORE_5F  := * - 1
        sta     $5F
        rts

N_VERSION_COPY_PAGE2_BRANCH:  jsr     N_COPY_HGR_PAGE2_TO_PAGE1
        jsr     N_DRAW_VERSION_DIALOG
        jsr     N_COPY_HGR_PAGE2_TO_PAGE1
        jsr     N_END_MODAL_SCREEN
        rts

N_DRAW_VERSION_DIALOG:  ldy     #$01
        jsr     N_DRAW_FRAMED_MENU_RECT
        ldx     #$45
        ldy     #$45
        lda     #N_UI_VERSION_TITLE
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        jsr     N_WAIT_KEY_OR_BUTTON
        inc     $74
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        rts

N_DELETE_DETECTIVE: jsr N_BEGIN_MODAL_SCREEN
        lda     $6E
        sta     $F9
        lda     $6F
        sta     $FA
        lda     $D0
        sta     $D2
        lda     $D1
        sta     $D3
        lda     $6C
        pha
        ldy     #$1F
N_DELETE_SAVE_MENU_BOUNDS:  lda     MENU_LEFT_PIXEL,y
        sta     $9E90,y
        dey
        bpl     N_DELETE_SAVE_MENU_BOUNDS
        lda     #$00
        sta     $64
        sta     $6A
        ldx     #$46
        ldy     #$B1
        lda     #N_UI_DELETE_CANCEL
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_DRAW_DETECTIVE_ROSTER
        lda     $AC
        bne     N_DELETE_HAS_ROSTER_ENTRIES
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        jsr     N_READ_GAME_KEY
        jmp     N_DELETE_RESTORE_MENU_STATE

N_DELETE_HAS_ROSTER_ENTRIES:  ldy     #$0F
N_DELETE_SET_SELECTION_BOUNDS:  lda     #$05
        sta     MENU_LEFT_PIXEL,y
        lda     #$82
        sta     MENU_RIGHT_PIXEL,y
        dey
        bpl     N_DELETE_SET_SELECTION_BOUNDS
        lda     $AC
        sta     $6F
        dec     $6F
        lda     #$DD
        sta     $D0
        lda     #$8B
        sta     $D1
        lda     #$00
        sta     $6C
        sta     $6E
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_SHOW_ACTIVE_HGR_PAGE
N_DELETE_WAIT_SELECTION:  jsr     N_WAIT_MENU_SELECTION
        lda     $76
        cmp     #$1B
        bne     N_DELETE_CHECK_SELECTED_NAME
        jmp     N_DELETE_RESTORE_MENU_STATE

N_DELETE_CHECK_SELECTED_NAME:  ldy     $6C
        lda     $9EB0,y
        tay
        ldx     C_DETECTIVE_OFFSETS,y
        stx     N_DELETE_ROSTER_OFFSET_IMMEDIATE
        ldy     #$0C
        jsr     N_COMPARE_INPUT_NAME
        bcs     N_DELETE_CONFIRM_OTHER_DETECTIVE
        jsr     N_INVERT_MENU_SELECTION_RECTANGLE
        jsr     N_DEFAULT_FEEDBACK_TONE
        jmp     N_DELETE_WAIT_SELECTION

N_DELETE_CONFIRM_OTHER_DETECTIVE:  lda     #$00
N_DELETE_ROSTER_OFFSET_IMMEDIATE  := * - 1
        sta     $C4
        lda     #$0C
        sta     $C5
        ldy     #$12
        lda     #$FF
N_DELETE_CLEAR_ROSTER_RECORD:  sta     ($C4),y
        dey
        bpl     N_DELETE_CLEAR_ROSTER_RECORD
        jsr     B_SAVE_F
N_DELETE_RESTORE_MENU_STATE:  ldy     #$1F
N_DELETE_RESTORE_MENU_BOUNDS:  lda     $9E90,y
        sta     MENU_LEFT_PIXEL,y
        dey
        bpl     N_DELETE_RESTORE_MENU_BOUNDS
        lda     $D2
        sta     $D0
        lda     $D3
        sta     $D1
        lda     $F9
        sta     $6E
        lda     $FA
        sta     $6F
        pla
        sta     $6C
        jsr     N_END_MODAL_SCREEN
        rts

N_SHOW_HALL_OF_FAME:  lda     $6B
        beq     N_DRAW_HALL_OF_FAME
        jsr     N_DEFAULT_FEEDBACK_TONE
        rts

N_DRAW_HALL_OF_FAME:  jsr     N_BEGIN_MODAL_SCREEN
        jsr     N_DRAW_COMMON_SCREEN_BACKGROUND
        ldx     #$45
        ldy     #$0A
        lda     #N_UI_HALL_OF_FAME_TITLE
        jsr     N_DRAW_CENTERED_UI_TEXT
        clc
        lda     $72
        adc     #$08
        sta     $72
        ldx     #$0A
        ldy     #$7F
        jsr     N_DRAW_DOUBLE_ROW_RULE
        lda     #$00
        sta     $C4
        lda     #$0D
        sta     $C5
        lda     #$16
        sta     $72
N_HALL_NEXT_NAME:  ldy     #$00
        lda     ($C4),y
        cmp     #$FF
        beq     N_HALL_WAIT_AND_CLOSE
        lda     #$0C
        sta     $70
        lda     #$00
        sta     $71
        ldx     $C4
        ldy     $C5
        jsr     N_DRAW_FF_TERMINATED_GLYPHS
        jsr     N_ADVANCE_ROW_10
        clc
        lda     $C4
        adc     #$10
        sta     $C4
        bne     N_HALL_NEXT_NAME
N_HALL_WAIT_AND_CLOSE:  jsr     N_SHOW_ACTIVE_HGR_PAGE
        jsr     N_READ_GAME_KEY
        jsr     N_END_MODAL_SCREEN
        rts

N_SHOW_DETECTIVE_ROSTER: jsr N_BEGIN_MODAL_SCREEN
        jsr     N_DRAW_DETECTIVE_ROSTER
        ldx     #$46
        ldy     #$B1
        lda     #N_UI_PRESS_TO_CONTINUE
        jsr     N_DRAW_CENTERED_UI_TEXT
        jsr     N_SHOW_ACTIVE_HGR_PAGE
        jsr     N_READ_GAME_KEY
        jsr     N_END_MODAL_SCREEN
        rts

N_BEGIN_MODAL_SCREEN:  lda     $6B
        beq     N_MODAL_SCREEN_READY
        jsr     N_DEFAULT_FEEDBACK_TONE
        pla
        pla
        rts

N_MODAL_SCREEN_READY:  jsr     N_SAVE_MODAL_DISPLAY_STATE
        lda     $65
        beq     N_MARK_MODAL_SCREEN_ACTIVE
        lda     $9E
        bne     N_MARK_MODAL_SCREEN_ACTIVE
        jsr     N_REFRESH_CITY_PICTURE
N_MARK_MODAL_SCREEN_ACTIVE:  lda     #$01
        sta     $6B
        sta     $89
N_CLEAR_NEXT_MODAL_HGR_PAGE:  inc     $74
        lda     $74
        lsr     a
        bcs     N_CLEAR_MODAL_PAGE1
        jsr     N_CLEAR_HGR_PAGE2
        rts

N_CLEAR_MODAL_PAGE1:  jsr     N_CLEAR_HGR_PAGE1
        rts

N_END_MODAL_SCREEN:  inc     $74
        jsr     N_PRESENT_AND_MIRROR_HGR_PAGE
        jsr     N_RESTORE_MODAL_DISPLAY_STATE
        lda     #$00
        sta     $6B
        rts

N_SAVE_MODAL_DISPLAY_STATE:  lda     $70
        sta     $F5
        lda     $71
        sta     $F6
        lda     $72
        sta     $F7
        lda     $C4
        sta     $D4
        lda     $C5
        sta     $D5
        lda     $6A
        sta     $FC
        lda     $64
        sta     $FB
        lda     $89
        sta     $F8
        rts

N_RESTORE_MODAL_DISPLAY_STATE:  lda     $F5
        sta     $70
        lda     $F6
        sta     $71
        lda     $F7
        sta     $72
        lda     $D4
        sta     $C4
        lda     $D5
        sta     $C5
        lda     $FB
        sta     $64
        lda     $FC
        sta     $6A
N_RESTORE_MODAL_INPUT_FLAG:  lda     $F8
        sta     $89
        rts

N_DRAW_DETECTIVE_ROSTER:  jsr     N_DRAW_COMMON_SCREEN_BACKGROUND
        ldx     #$46
        ldy     #$07
        lda     #N_UI_ROSTER_TITLE
        jsr     N_DRAW_CENTERED_UI_TEXT
        ldx     #$0C
        ldy     #$13
        sty     $72
        lda     #N_UI_NAME_COLUMN
        jsr     N_DRAW_UI_TEXT_AT_XY
        ldx     #$3C
        ldy     $72
        lda     #N_UI_RANK_COLUMN
        jsr     N_DRAW_UI_TEXT_AT_XY
        ldx     #$68
        ldy     $72
        lda     #N_UI_CASES_COLUMN
        jsr     N_DRAW_UI_TEXT_AT_XY
        lda     #$0F
        sta     $72
        ldx     #$16
        ldy     #$76
        jsr     N_DRAW_DOUBLE_ROW_RULE
        lda     #$1B
        sta     $72
        ldx     #$0C
        ldy     #$1C
        jsr     N_DRAW_DOUBLE_ROW_RULE
        ldx     #$3C
        ldy     #$4B
        jsr     N_DRAW_DOUBLE_ROW_RULE
        ldx     #$68
        ldy     #$82
        jsr     N_DRAW_DOUBLE_ROW_RULE
        lda     #$20
        sta     $72
        lda     #$00
        sta     $AC
        sta     $88
        lda     #$0C
        sta     $C5
N_NEXT_ROSTER_RECORD:  ldy     $88
        lda     C_DETECTIVE_OFFSETS,y
        sta     $C4
        ldy     #$00
        lda     ($C4),y
        cmp     #$FF
        beq     N_ADVANCE_DISPLAYED_ROSTER_SLOT
        ldy     $AC
        lda     $88
        sta     $9EB0,y
        inc     $AC
        ldx     $C4
        ldy     $C5
        lda     #$01
        sta     $70
        lda     #$05
        sta     $71
        jsr     N_DRAW_FF_TERMINATED_GLYPHS
        ldy     #$10
        lda     ($C4),y
        ldx     #<C_DETECTIVE_RANKS
        ldy     #>C_DETECTIVE_RANKS
        jsr     C_SKIP_NUL_STRINGS
        lda     #$37
        jsr     N_DRAW_TEXT_POINTER_AT_X
        lda     #$22
        sta     $70
        lda     #$01
        sta     $71
        ldy     #$11
        lda     ($C4),y
        jsr     N_DRAW_DECIMAL_A
        jsr     N_ADVANCE_ROW_11
N_ADVANCE_DISPLAYED_ROSTER_SLOT:  lda     $88
        cmp     #$0C
        beq     N_ROSTER_DRAW_DONE
        inc     $88
        jmp     N_NEXT_ROSTER_RECORD

N_ROSTER_DRAW_DONE:  rts

N_DRAW_DOUBLE_ROW_RULE:  stx     $95
        stx     $73
        sty     $96
        ldx     #$00
        lda     $72
        sta     $87
        jsr     N_DRAW_NEXT_RULE_PIXEL
        inc     $87
        lda     $95
        sta     $73
        jsr     N_DRAW_NEXT_RULE_PIXEL
        rts

N_DRAW_NEXT_RULE_PIXEL:  jsr     N_SET_HGR_X_FROM_73
        ldx     #$00
        ldy     $87
        jsr     N_SET_HGR_ROW_PLUS_COLUMN
        ldy     $71
        lda     N_HGR_PIXEL_MASKS,y
        ora     ($C0,x)
        sta     ($C0,x)
        inc     $73
        lda     $73
        cmp     $96
        bne     N_DRAW_NEXT_RULE_PIXEL
        rts

N_DRAW_FF_TERMINATED_GLYPHS:  stx     $C2
        sty     $C3
N_DRAW_NEXT_FF_GLYPH:  ldy     #$00
        lda     ($C2),y
        cmp     #$FF
        beq     N_FF_GLYPH_STRING_DONE
        jsr     N_DRAW_GLYPH_CHAR
        inc     $C2
        bne     N_DRAW_NEXT_FF_GLYPH
        inc     $C3
        bne     N_DRAW_NEXT_FF_GLYPH
N_FF_GLYPH_STRING_DONE:  rts

; Play one of twelve speaker sequences when sound is enabled in $18.
; A selects a track; the stream contains note indices and duration changes.
N_PLAY_SOUND_TRACK:  ldx     SOUND_ENABLED
        beq     N_SOUND_TRACK_DONE
        asl     a
        tax
        lda     SOUND_TRACK_PTRS,x
        sta     $C2
        lda     SOUND_TRACK_PTRS+1,x
        sta     $C3
        lda     #$00
        sta     $88
N_READ_SOUND_COMMAND:  ldy     $88
        lda     ($C2),y
        cmp     #$FF
        beq     N_SOUND_TRACK_DONE
        bpl     N_PLAY_SOUND_NOTE
        and     #$7F
        sta     SOUND_DURATION_IMMEDIATE
        inc     $88
        jmp     N_READ_SOUND_COMMAND

N_PLAY_SOUND_NOTE:  tax
        lda     SOUND_PERIODS,x
        bne     N_SET_SOUND_PERIOD
        sta     SOUND_SPEAKER_ADDRESS_HIGH
N_SET_SOUND_PERIOD:  sta     $83
        inc     $88
SOUND_DURATION_IMMEDIATE := * + 1
        lda     #$14
        sta     $BD
        ldx     #$00
        jsr     N_PLAY_SOUND_PERIOD
        lda     #$C0
        sta     SOUND_SPEAKER_ADDRESS_HIGH
        jmp     N_READ_SOUND_COMMAND

N_SOUND_TRACK_DONE:  rts

N_PLAY_SOUND_PERIOD:  lda     $83
        sta     $85
        sec
        sbc     #$01
        sta     $84
        sta     $86
N_SOUND_PERIOD_LOOP:  lda     #$01
        sta     $9B
        dec     $83
        bne     N_ADVANCE_SECOND_SOUND_COUNTER
        lsr     $9B
        lda     $85
        sta     $83
N_ADVANCE_SECOND_SOUND_COUNTER:  dec     $84
        bne     N_CHECK_SPEAKER_TOGGLE
        lsr     $9B
        lda     $86
        sta     $84
N_CHECK_SPEAKER_TOGGLE:  lda     $9B
        bne     N_COUNT_SOUND_PERIOD_LOOP
SOUND_SPEAKER_ADDRESS_HIGH := * + 2
        lda     $C030
N_COUNT_SOUND_PERIOD_LOOP:  dex
        bne     N_SOUND_PERIOD_LOOP
        dec     $BD
        bne     N_SOUND_PERIOD_LOOP
        lda     #$60
        jsr     N_DELAY_NESTED_A_Y
        rts

        .include "../shared/n_sounds.inc"

        .include "../shared/n_glyph_placements.inc"
        .include "../shared/n_picture_tables.inc"
; Evenly spaced values; no caller identified yet.
N_STEP_11_TABLE:
        .byte   $20, $2B, $36, $41, $4C, $57, $62, $6D, $78, $83
        .byte   $8E, $99, $A4, $AF

; Seven HGR bit masks used by the point plotter.
N_HGR_PIXEL_MASKS:
        .byte   $81, $82, $84, $88, $90, $A0, $C0

; Eight accepted input codes.
N_KEY_DISPATCH_CODES:
        .byte   $04, $06, $0C, $11, $12, $13, $14, $16

; Low bytes of the patched JSR targets.
N_KEY_DISPATCH_LO:
        .byte   <N_DELETE_DETECTIVE, <N_SHOW_HALL_OF_FAME
        .byte   <N_SHOW_DETECTIVE_ROSTER, <N_EXIT_TO_PRODOS
        .byte   <N_RESTART_DETECTIVE_SESSION, <N_TOGGLE_SOUND
        .byte   <N_TOGGLE_JOYSTICK, <N_SHOW_VERSION_SCREEN

; High bytes of the patched JSR targets.
N_KEY_DISPATCH_HI:
        .byte   >N_DELETE_DETECTIVE, >N_SHOW_HALL_OF_FAME
        .byte   >N_SHOW_DETECTIVE_ROSTER, >N_EXIT_TO_PRODOS
        .byte   >N_RESTART_DETECTIVE_SESSION, >N_TOGGLE_SOUND
        .byte   >N_TOGGLE_JOYSTICK, >N_SHOW_VERSION_SCREEN

; Thirty (HGR byte column, bit offset, row) triples.
N_POSITION_TRIPLES:
        .byte   $15, $05, $84
        .byte   $16, $05, $87
        .byte   $13, $02, $90
        .byte   $1A, $05, $93
        .byte   $15, $03, $7D
        .byte   $0F, $05, $A9
        .byte   $15, $05, $89
        .byte   $18, $06, $95
        .byte   $16, $01, $83
        .byte   $19, $02, $8B
        .byte   $15, $04, $99
        .byte   $0E, $01, $9D
        .byte   $13, $02, $79
        .byte   $0D, $01, $8F
        .byte   $0E, $06, $7A
        .byte   $16, $06, $9D
        .byte   $16, $06, $7A
        .byte   $18, $05, $8B
        .byte   $0F, $00, $7D
        .byte   $13, $05, $71
        .byte   $13, $06, $7B
        .byte   $1B, $01, $86
        .byte   $1E, $01, $9C
        .byte   $12, $00, $71
        .byte   $10, $05, $A2
        .byte   $14, $06, $82
        .byte   $14, $06, $81
        .byte   $1B, $01, $97
        .byte   $1D, $03, $AD
        .byte   $1D, $05, $89

; One route X coordinate per city, in two-pixel units, indexed by $11.
; Each equals floor((7 * byte column + bit offset) / 2) from the triple above.
N_CITY_ROUTE_X:
        .byte   $4C, $4F, $43, $5D, $4B, $37, $4C, $57, $4D, $58
        .byte   $4B, $31, $43, $2E, $34, $50, $50, $56, $34, $45
        .byte   $45, $5F, $69, $3F, $3A, $49, $49, $5F, $67, $68

; Three text centering offsets.
N_TEXT_CENTER_OFFSETS:
        .byte   $14, $2A, $40

; First endpoint mask for HGR clear.
N_HGR_CLEAR_MASK_A:
        .byte   $F0, $E1, $C3, $87, $8F, $9F, $BF

; Second endpoint mask for HGR clear.
N_HGR_CLEAR_MASK_B:
        .byte   $FF, $FF, $FF, $FF, $FE, $FC, $F8
; Case counts for promotion and the next-rank progress message.
RANK_PROMOTION_CASES:  .byte   $01, $05, $0C, $14, $FF, $FF
RANK_PROGRESS_CASES:  .byte   $01, $05, $0C, $14, $1E
; Three code entrypoints selected for the patched JSR at $65BA.
N_RANDOM_ANIMATION_ENTRY_LO:  .byte   <N_ANIMATE_PLACE_EVENT_ZERO, <N_ANIMATE_PLACE_EVENT_ONE, <N_ANIMATE_PLACE_EVENT_TWO
N_RANDOM_ANIMATION_ENTRY_HI:  .byte   >N_ANIMATE_PLACE_EVENT_ZERO, >N_ANIMATE_PLACE_EVENT_ONE, >N_ANIMATE_PLACE_EVENT_TWO
; Six clue categories in order: sex, hobby, hair, feature, vehicle, food.
; String-list pointers in C, maximum counts, and base indices into the $5000
; text list follow. $1B-$20 hold the category counters.
N_CLUE_STRING_PTR_LO:  .byte   $7C, $88, $BC, $D2, $F1, $1A ; pointer low bytes
N_CLUE_STRING_PTR_HI:  .byte   $DD, $DD, $DD, $DD, $DD, $DE ; pointer high bytes
N_CLUE_CATEGORY_LIMIT:  .byte   $01, $05, $03, $04, $03, $01 ; count limits
N_CLUE_TEXT_BASE:  .byte   $00, $09, $0D, $16, $1F, $21 ; text base indices
; Five pointers to variable-length clue offset lists below.
N_CLUE_OFFSET_PTR_LO:  .byte   <N_CLUE_OFFSET_LIST_0, <N_CLUE_OFFSET_LIST_1, <N_CLUE_OFFSET_LIST_2, <N_CLUE_OFFSET_LIST_3, <N_CLUE_OFFSET_LIST_4
N_CLUE_OFFSET_PTR_HI:  .byte   >N_CLUE_OFFSET_LIST_0, >N_CLUE_OFFSET_LIST_1, >N_CLUE_OFFSET_LIST_2, >N_CLUE_OFFSET_LIST_3, >N_CLUE_OFFSET_LIST_4
; List lengths are six, four, five, four, and two bytes.
N_CLUE_OFFSET_LIST_0:  .byte   $03, $00, $03, $00, $00, $03
N_CLUE_OFFSET_LIST_1:  .byte   $01, $01, $01, $01
N_CLUE_OFFSET_LIST_2:  .byte   $00, $03, $03, $00, $03
N_CLUE_OFFSET_LIST_3:  .byte   $03, $03, $00, $03
N_CLUE_OFFSET_LIST_4:  .byte   $01, $01
; Ten suspects by the six categories above, indexed as suspect * 6 + category.
SUSPECT_TRAIT_MATRIX:
        .byte   $01, $00, $00, $04, $00, $00 ; suspect 0
        .byte   $01, $02, $00, $04, $01, $00 ; suspect 1
        .byte   $01, $00, $01, $02, $01, $01 ; suspect 2
        .byte   $01, $00, $02, $01, $00, $00 ; suspect 3
        .byte   $01, $02, $00, $02, $03, $01 ; suspect 4
        .byte   $00, $02, $02, $02, $00, $01 ; suspect 5
        .byte   $00, $05, $02, $01, $01, $00 ; suspect 6
        .byte   $00, $02, $03, $01, $03, $00 ; suspect 7
        .byte   $00, $05, $03, $04, $00, $00 ; suspect 8
        .byte   $00, $05, $01, $02, $01, $01 ; suspect 9
; Seven first-byte masks for clearing a two-pixel HGR stroke.
HGR_STROKE_MASK_FIRST:  .byte   $FC, $F9, $F3, $E7, $CF, $9F, $BF
; Corresponding second-byte masks; only the last stroke crosses a byte.
HGR_STROKE_MASK_SECOND:  .byte   $FF, $FF, $FF, $FF, $FF, $FF, $FE
; Travel-menu rectangle bottom row indexed by the current city route count.
N_TRAVEL_RECT_BOTTOM_BY_ROUTE_COUNT:  .byte   $2C, $37, $42, $4D, $58, $63
; Three investigation-choice text rows.
N_INVESTIGATION_CHOICE_ROWS:  .byte   $74, $7F, $8A
; Four main city-menu text rows, also used by the secondary menu.
N_MAIN_MENU_ROWS:  .byte   $90, $9B, $A6, $B1
; Seven row positions used for clue category text.
CLUE_TEXT_ROW:  .byte   $12, $1D, $28, $33, $3E, $49, $68
; Seven low-bit masks used by the HGR fill routine.
HGR_LOW_BIT_MASK:  .byte   $01, $03, $07, $0F, $1F, $3F, $7F
; Small drawing patterns. Mode 1 alternates between B and C.
N_PATTERN_A:  .byte   $03, $06
N_PATTERN_B:  .byte   $02, $03, $01
N_PATTERN_C:  .byte   $01, $03, $02
N_PATTERN_D:  .byte   $06, $03
; Mode-indexed pattern pointers, size, and starting coordinate.
N_PATTERN_PTR_LO: .byte <N_PATTERN_A, $00, <N_PATTERN_D
N_PATTERN_PTR_HI: .byte >N_PATTERN_A, $00, >N_PATTERN_D
N_PATTERN_SIZE:  .byte   $02, $03, $02
N_PATTERN_START:  .byte   $1C, $2A, $36
; Six coordinate changes for each of the three modes.
N_STEP_PTR_LO: .byte <N_STEP_A, <N_STEP_B, <N_STEP_C
N_STEP_PTR_HI: .byte >N_STEP_A, >N_STEP_B, >N_STEP_C
N_STEP_A:  .byte   $00, $01, $FD, $01, $FD, $01
N_STEP_B:  .byte   $00, $01, $FF, $01, $FF, $01
N_STEP_C:  .byte   $00, $FF, $03, $FF, $03, $FF
; No entry in N_STEP_PTR_LO/HI points here. The stroke loop reads six bytes
; from its selected step table, so these six following bytes remain unclassified.
N_UNCLASSIFIED_TRAILING_BYTES: .byte $00,$03,$03,$03,$03,$03
; Thirty cities by twelve weighted clue choices. This is the final 360 bytes.
N_CITY_CLUE_COUNTS:
        .include "../shared/n_city_clue_counts.inc"
