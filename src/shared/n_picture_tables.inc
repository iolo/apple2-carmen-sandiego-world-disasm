; Six pictures consumed by N's external-header HGR RLE decoder.
; 0 and 5 point into P after it is copied to $1100; 1-4 point into O.
; Picture 0 takes its stride from $1100 instead of the zero entry below.
N_IMAGE_STRIDE:
        .byte $00,$01,$01,$01,$01,$02
N_IMAGE_PTR_LO:
        .byte $01,$60,$00,$30,$68,$05
N_IMAGE_PTR_HI:
        .byte $11,$B1,$A7,$AD,$A8,$11
N_IMAGE_Y_START:
        .byte $26,$03,$97,$68,$0C,$07
N_IMAGE_Y_END:
        .byte $BB,$22,$BB,$B9,$89,$83
N_IMAGE_X_START:
        .byte $01,$01,$01,$07,$15,$16
N_IMAGE_X_END:
        .byte $13,$13,$13,$20,$26,$23

; Masks for the first and last byte of a seven-bit HGR span.
N_OR_START_MASK:
        .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0
N_OR_END_MASK:
        .byte $81,$83,$87,$8F,$9F,$BF,$FF
N_AND_START_MASK:
        .byte $80,$81,$83,$87,$8F,$9F,$BF
N_AND_END_MASK:
        .byte $FE,$FC,$F8,$F0,$E0,$C0,$80
