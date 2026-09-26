; N's speaker sequences, shared by the floppy and 800 KB revisions.
; A track is a series of period-table indices ($00-$20). Bytes $80-$FE
; change the duration to their low seven bits; $FF ends the track.
; Period zero silences the speaker for a rest.
SOUND_PERIODS:
        .byte $00,$1A,$1C,$1E,$20,$22,$24,$26,$28,$2A,$2C
        .byte $30,$34,$38,$3C,$40,$44,$48,$4C,$50,$54,$58
        .byte $60,$68,$70,$78,$80,$88,$90,$98,$A0,$A8,$B0

; Track IDs are the A values supplied to the player (0 through 11).
SOUND_TRACK_PTRS:
        .word SOUND_TRACK_0,SOUND_TRACK_1,SOUND_TRACK_2,SOUND_TRACK_3
        .word SOUND_TRACK_4,SOUND_TRACK_5,SOUND_TRACK_6,SOUND_TRACK_7
        .word SOUND_TRACK_8,SOUND_TRACK_9,SOUND_TRACK_10,SOUND_TRACK_11

SOUND_TRACK_0:
        .byte $94,$1E,$1E,$1B,$1E,$19,$1E,$18,$17,$1E,$14,$1B
        .byte $1E,$19,$1E,$18,$17,$1E,$15,$1B,$1E,$19,$1E,$18
        .byte $17,$16,$10,$11,$13,$16,$00,$14,$00,$E0,$13,$98,$FF
SOUND_TRACK_1:
        .byte $1A,$00,$18,$00,$17,$00,$0F,$00,$E0,$15,$98,$14,$FF
SOUND_TRACK_2:
        .byte $17,$10,$17,$11,$17,$13,$17,$14,$FF
SOUND_TRACK_7:
        .byte $92,$0C,$0B,$0C,$0E,$E0,$0C,$98,$FF
SOUND_TRACK_8:
        .byte $17,$14,$11,$C8,$0E,$98,$00,$17,$14,$0E,$E0,$10,$98,$FF
SOUND_TRACK_10:
        .byte $1E,$1E,$1B,$1E,$19,$1E,$18,$17,$89,$13,$15,$F8,$13,$98,$FF
SOUND_TRACK_11:
        .byte $1C,$1C,$19,$1C,$1A,$A4,$1B,$B0,$1C,$C8,$1D,$E0,$1E,$98,$FF
SOUND_TRACK_9:
        .byte $B0,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$98,$FF
SOUND_TRACK_3:
        .byte $13,$17,$18,$17,$8C,$13,$11,$98,$10,$FF
SOUND_TRACK_4:
        .byte $1E,$17,$1E,$16,$1E,$8D,$14,$1E,$B0,$13,$98,$FF
SOUND_TRACK_5:
        .byte $8D,$08,$0B,$0C,$0E,$B0,$11,$98,$FF
SOUND_TRACK_6:
        .byte $8A,$0D,$12,$0F,$10,$0D,$12,$0F,$10,$98,$FF
