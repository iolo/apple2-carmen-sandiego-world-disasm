; The intro overlay's two speaker tracks use the same period scale as N.
; $80-$FE changes duration, $00 is a rest, and $FF ends a track.
R_SOUND_PERIODS:
        .byte $00,$1A,$1C,$1E,$20,$22,$24,$26,$28,$2A,$2C
        .byte $30,$34,$38,$3C,$40,$44,$48,$4C,$50,$54,$58
        .byte $60,$68,$70,$78,$80,$88,$90,$98,$A0,$A8,$B0
R_SOUND_TRACK_PTRS:
        .word R_SOUND_TRACK_0,R_SOUND_TRACK_1
R_SOUND_TRACK_0:
        .byte $94,$1E,$1E,$1B,$1E,$19,$1E,$18,$17,$1E,$14,$1B
        .byte $1E,$19,$1E,$18,$17,$1E,$15,$1B,$1E,$19,$1E,$18
        .byte $17,$16,$10,$11,$13,$16,$00,$14,$00,$E0,$13,$98,$FF
R_SOUND_TRACK_1:
        .byte $B0,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$98,$FF
