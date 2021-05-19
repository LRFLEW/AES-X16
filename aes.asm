; X16 AES Speed Demo
; Written by LRFLEW
; Licensed under the BSD 2-clause license

; The AES implementation here is based on the byte-oriented-aes project
; by Karl Malbrain, which was released to the public domain by the author.
; https://code.google.com/archive/p/byte-oriented-aes/

	; Vera Addresses
	!src "vera.inc"

	SETLFS = $FFBA
	SETNAM = $FFBD
	LOAD = $FFD5

	BLOCKSIZE = 16
	!ifndef KEYSIZE {
		KEYSIZE = 128 / 8
		ROUNDS = 10
	}
	
	KEYCOUNT = ROUNDS * BLOCKSIZE / KEYSIZE

	PIXELS = 320 * 240
	BLOCKS = PIXELS / BLOCKSIZE
	CBLOCKS = $10000 - BLOCKS

	; Addresses
	ctr = $08
	cvec = $10
	ctxt = cvec + BLOCKSIZE
	ptxt = ctxt + BLOCKSIZE
	temp = ptxt + BLOCKSIZE

	; boilerplate
	!cpu 65c02
	*= $0801
	!byte $0b,$08,$01,$00,$9e,$32,$30,$36,$31,$00,$00,$00

init:
	; init vera
	stz VERA_IEN
	stz VERA_CTRL

	; disable video
	lda VERA_DC_VIDEO
	and #$07
	sta VERA_DC_VIDEO

	; set scaling
	ldx #$40
	stx VERA_DC_HSCALE
	stx VERA_DC_VSCALE

	; set layer 0 to 8bpp bitmap
	ldx #$07
	stx VERA_L0_CONFIG
	; with address of $00000
	stz VERA_L0_TILEBASE
	; set layer 0 palette offset
	stz VERA_L0_HSCROLL_H

loads:
	; Load Bitmap
	lda #0
	ldx #8
	ldy #0
	jsr SETLFS
	lda #(dpathend - dpath)
	ldx #<dpath
	ldy #>dpath
	jsr SETNAM
	lda #2
	ldx #$00
	ldy #$00
	jsr LOAD

	; Load Palette
	lda #0
	ldx #8
	ldy #0
	jsr SETLFS
	lda #(ppathend - ppath)
	ldx #<ppath
	ldy #>ppath
	jsr SETNAM
	lda #(2 + (VERA_PALETTE_BASE >> 16))
	ldx #<VERA_PALETTE_BASE
	ldy #>VERA_PALETTE_BASE
	jsr LOAD

	; Load initial IV into cvec
	!for .I, 0, BLOCKSIZE - 1 {
		lda iv + .I
		sta cvec + .I
	}

	; enable layer 0
	lda VERA_DC_VIDEO
	ora #$10
	sta VERA_DC_VIDEO

expandkey:
	ldx #KEYCOUNT
	stx ctr

exk1:
	lda rconend - KEYCOUNT - 1, x
	ldy expoff - 1, x
	
	!macro EXPKEY .OUT, .IN, .E {
		!if .E > 0 {
			ldx keys + KEYSIZE + .IN, y
			!if .E = 2 { eor sbox, x } else { lda sbox, x }
		} else { lda keys + KEYSIZE + .IN, y }
		eor keys + .OUT, y
		sta keys + KEYSIZE + .OUT, y
	}

	+EXPKEY 0, -3, 2
	+EXPKEY 1, -2, 1
	+EXPKEY 2, -1, 1
	+EXPKEY 3, -4, 1
	!if (KEYSIZE / 4) > 6 {
		!for .I, 4, 15 {
			+EXPKEY .I, .I - 4, 0
		}
		!for .I, 16, 19 {
			+EXPKEY .I, .I - 4, 1
		}
		!for .I, 20, KEYSIZE - 1 {
			+EXPKEY .I, .I - 4, 0
		}
	} else {
		!for .I, 4, KEYSIZE - 1 {
			+EXPKEY .I, .I - 4, 0
		}
	}

	ldx ctr
	dex
	beq encinit
	stx ctr
	jmp exk1

encinit:
	; setup read/write to VRAM
	lda #$10
	ldx #$01
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	sta VERA_ADDR_H
	stx VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	sta VERA_ADDR_H

	lda #<CBLOCKS
	sta ctr
	lda #>CBLOCKS
	sta ctr+1

	; Use current cvec value (last encrypted block after first loop) as IV
	!for .I, 0, BLOCKSIZE - 1 {
		lda cvec + .I
		sta ctxt + .I
	}

encrypt:
	!for .I, 0, BLOCKSIZE - 1 {
		lda VERA_DATA0
		eor ctxt + .I
		eor keys + .I
		sta ctxt + .I
	}

	ldy #ROUNDS - 1

enc1:
	!macro SubShiftMix .OUT, .IN2, .IN3, .INA, .INB {
		ldx ctxt + .IN2
		lda xt2s, x
		ldx ctxt + .IN3
		eor xt3s, x
		ldx ctxt + .INA
		eor sbox, x
		ldx ctxt + .INB
		eor sbox, x
		sta temp + .OUT
	}

	+SubShiftMix  0,  0,  5, 10, 15
	+SubShiftMix  1,  5, 10, 15,  0
	+SubShiftMix  2, 10, 15,  0,  5
	+SubShiftMix  3, 15,  0,  5, 10

	+SubShiftMix  4,  4,  9, 14,  3
	+SubShiftMix  5,  9, 14,  3,  4
	+SubShiftMix  6, 14,  3,  4,  9
	+SubShiftMix  7,  3,  4,  9, 14

	+SubShiftMix  8,  8, 13,  2,  7
	+SubShiftMix  9, 13,  2,  7,  8
	+SubShiftMix 10,  2,  7,  8, 13
	+SubShiftMix 11,  7,  8, 13,  2

	+SubShiftMix 12, 12,  1,  6, 11
	+SubShiftMix 13,  1,  6, 11, 12
	+SubShiftMix 14,  6, 11, 12,  1
	+SubShiftMix 15, 11, 12,  1,  6

	ldx rkeyoff - 1, y
	!for .I, 0, BLOCKSIZE - 1 {
		lda temp + .I
		eor keys + .I, x
		sta ctxt + .I
	}

	dey
	beq enc2
	jmp enc1

enc2:
	!macro SubShift .OUT, .IN {
		ldx ctxt + .IN
		lda sbox, x
		sta temp + .OUT
	}

	+SubShift  0,  0
	+SubShift  1,  5
	+SubShift  2, 10
	+SubShift  3, 15

	+SubShift  4,  4
	+SubShift  5,  9
	+SubShift  6, 14
	+SubShift  7,  3

	+SubShift  8,  8
	+SubShift  9, 13
	+SubShift 10,  2
	+SubShift 11,  7

	+SubShift 12, 12
	+SubShift 13,  1
	+SubShift 14,  6
	+SubShift 15, 11

	!for .I, 0, BLOCKSIZE - 1 {
		lda temp + .I
		eor keys + (BLOCKSIZE * ROUNDS) + .I
		sta ctxt + .I
		sta VERA_DATA1
	}

	inc ctr
	bne enc3
	inc ctr+1
	beq decinit
enc3:
	jmp encrypt

decinit:
	; setup read/write to VRAM
	lda #$10
	ldx #$01
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	sta VERA_ADDR_H
	stx VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	sta VERA_ADDR_H

	lda #<CBLOCKS
	sta ctr
	lda #>CBLOCKS
	sta ctr+1

decrypt:
	!for .I, 0, BLOCKSIZE - 1 {
		lda VERA_DATA0
		sta ctxt + .I
		eor keys + (BLOCKSIZE * ROUNDS) + .I
		sta ptxt + .I
	}

	!macro InvShiftSub .OUT, .IN {
		ldx ptxt + .IN
		lda ibox, x
		sta temp + .OUT
	}

	+InvShiftSub  0,  0
	+InvShiftSub  5,  1
	+InvShiftSub 10,  2
	+InvShiftSub 15,  3

	+InvShiftSub  4,  4
	+InvShiftSub  9,  5
	+InvShiftSub 14,  6
	+InvShiftSub  3,  7

	+InvShiftSub  8,  8
	+InvShiftSub 13,  9
	+InvShiftSub  2, 10
	+InvShiftSub  7, 11

	+InvShiftSub 12, 12
	+InvShiftSub  1, 13
	+InvShiftSub  6, 14
	+InvShiftSub 11, 15

	ldy #ROUNDS - 1

dec1:
	ldx keyoff - 1, y
	!for .I, 0, BLOCKSIZE - 1 {
		lda temp + .I
		eor keys + .I, x
		sta ptxt + .I
	}

	!macro InvMixShiftSub .OUT, .INE, .INB, .IND, .IN9 {
		ldx ptxt + .INE
		lda xtme, x
		ldx ptxt + .INB
		eor xtmb, x
		ldx ptxt + .IND
		eor xtmd, x
		ldx ptxt + .IN9
		eor xtm9, x
		tax
		lda ibox, x
		sta temp + .OUT
	}

	+InvMixShiftSub  0,  0,  1,  2,  3
	+InvMixShiftSub  5,  1,  2,  3,  0
	+InvMixShiftSub 10,  2,  3,  0,  1
	+InvMixShiftSub 15,  3,  0,  1,  2

	+InvMixShiftSub  4,  4,  5,  6,  7
	+InvMixShiftSub  9,  5,  6,  7,  4
	+InvMixShiftSub 14,  6,  7,  4,  5
	+InvMixShiftSub  3,  7,  4,  5,  6

	+InvMixShiftSub  8,  8,  9, 10, 11
	+InvMixShiftSub 13,  9, 10, 11,  8
	+InvMixShiftSub  2, 10, 11,  8,  9
	+InvMixShiftSub  7, 11,  8,  9, 10

	+InvMixShiftSub 12, 12, 13, 14, 15
	+InvMixShiftSub  1, 13, 14, 15, 12
	+InvMixShiftSub  6, 14, 15, 12, 13
	+InvMixShiftSub 11, 15, 12, 13, 14

	dey
	beq dec2
	jmp dec1

dec2:
	!for .I, 0, BLOCKSIZE - 1 {
		lda temp + .I
		eor keys + .I
		eor cvec + .I
		sta VERA_DATA1
	}

	!for .I, 0, BLOCKSIZE - 1 {
		lda ctxt + .I
		sta cvec + .I
	}

	inc ctr
	bne dec3
	inc ctr+1
	beq loop
dec3:
	jmp decrypt

loop:
	jmp encinit

dpath:
	!text "AES-DEMO-BITMAP.BIN"
dpathend:

ppath:
	!text "AES-DEMO-PALETTE.BIN"
ppathend:

rcon:
	!byte $36,$1b,$80,$40,$20,$10,$08,$04,$02,$01
rconend:
expoff:
	!for .I, KEYCOUNT - 1, 0 { !byte (.I * KEYSIZE) }
rkeyoff:
	!for .I, ROUNDS - 1, 2 { !byte (.I * BLOCKSIZE) }
	; .I = 1 covered by next lookup table
keyoff:
	!for .I, 1, ROUNDS - 1 { !byte (.I * BLOCKSIZE) }

iv:
	!byte $af,$59,$18,$12,$03,$30,$4e,$17,$5e,$3d,$5c,$eb,$2c,$db,$c8,$09
	; Key is at end of file to minimize zero-padding

	; Align lookup tables to page boundary to avoid timing attacks
	!align 255, 0, 0
sbox:
	!byte $63,$7c,$77,$7b,$f2,$6b,$6f,$c5,$30,$01,$67,$2b,$fe,$d7,$ab,$76
	!byte $ca,$82,$c9,$7d,$fa,$59,$47,$f0,$ad,$d4,$a2,$af,$9c,$a4,$72,$c0
	!byte $b7,$fd,$93,$26,$36,$3f,$f7,$cc,$34,$a5,$e5,$f1,$71,$d8,$31,$15
	!byte $04,$c7,$23,$c3,$18,$96,$05,$9a,$07,$12,$80,$e2,$eb,$27,$b2,$75
	!byte $09,$83,$2c,$1a,$1b,$6e,$5a,$a0,$52,$3b,$d6,$b3,$29,$e3,$2f,$84
	!byte $53,$d1,$00,$ed,$20,$fc,$b1,$5b,$6a,$cb,$be,$39,$4a,$4c,$58,$cf
	!byte $d0,$ef,$aa,$fb,$43,$4d,$33,$85,$45,$f9,$02,$7f,$50,$3c,$9f,$a8
	!byte $51,$a3,$40,$8f,$92,$9d,$38,$f5,$bc,$b6,$da,$21,$10,$ff,$f3,$d2
	!byte $cd,$0c,$13,$ec,$5f,$97,$44,$17,$c4,$a7,$7e,$3d,$64,$5d,$19,$73
	!byte $60,$81,$4f,$dc,$22,$2a,$90,$88,$46,$ee,$b8,$14,$de,$5e,$0b,$db
	!byte $e0,$32,$3a,$0a,$49,$06,$24,$5c,$c2,$d3,$ac,$62,$91,$95,$e4,$79
	!byte $e7,$c8,$37,$6d,$8d,$d5,$4e,$a9,$6c,$56,$f4,$ea,$65,$7a,$ae,$08
	!byte $ba,$78,$25,$2e,$1c,$a6,$b4,$c6,$e8,$dd,$74,$1f,$4b,$bd,$8b,$8a
	!byte $70,$3e,$b5,$66,$48,$03,$f6,$0e,$61,$35,$57,$b9,$86,$c1,$1d,$9e
	!byte $e1,$f8,$98,$11,$69,$d9,$8e,$94,$9b,$1e,$87,$e9,$ce,$55,$28,$df
	!byte $8c,$a1,$89,$0d,$bf,$e6,$42,$68,$41,$99,$2d,$0f,$b0,$54,$bb,$16

ibox:
	!byte $52,$09,$6a,$d5,$30,$36,$a5,$38,$bf,$40,$a3,$9e,$81,$f3,$d7,$fb
	!byte $7c,$e3,$39,$82,$9b,$2f,$ff,$87,$34,$8e,$43,$44,$c4,$de,$e9,$cb
	!byte $54,$7b,$94,$32,$a6,$c2,$23,$3d,$ee,$4c,$95,$0b,$42,$fa,$c3,$4e
	!byte $08,$2e,$a1,$66,$28,$d9,$24,$b2,$76,$5b,$a2,$49,$6d,$8b,$d1,$25
	!byte $72,$f8,$f6,$64,$86,$68,$98,$16,$d4,$a4,$5c,$cc,$5d,$65,$b6,$92
	!byte $6c,$70,$48,$50,$fd,$ed,$b9,$da,$5e,$15,$46,$57,$a7,$8d,$9d,$84
	!byte $90,$d8,$ab,$00,$8c,$bc,$d3,$0a,$f7,$e4,$58,$05,$b8,$b3,$45,$06
	!byte $d0,$2c,$1e,$8f,$ca,$3f,$0f,$02,$c1,$af,$bd,$03,$01,$13,$8a,$6b
	!byte $3a,$91,$11,$41,$4f,$67,$dc,$ea,$97,$f2,$cf,$ce,$f0,$b4,$e6,$73
	!byte $96,$ac,$74,$22,$e7,$ad,$35,$85,$e2,$f9,$37,$e8,$1c,$75,$df,$6e
	!byte $47,$f1,$1a,$71,$1d,$29,$c5,$89,$6f,$b7,$62,$0e,$aa,$18,$be,$1b
	!byte $fc,$56,$3e,$4b,$c6,$d2,$79,$20,$9a,$db,$c0,$fe,$78,$cd,$5a,$f4
	!byte $1f,$dd,$a8,$33,$88,$07,$c7,$31,$b1,$12,$10,$59,$27,$80,$ec,$5f
	!byte $60,$51,$7f,$a9,$19,$b5,$4a,$0d,$2d,$e5,$7a,$9f,$93,$c9,$9c,$ef
	!byte $a0,$e0,$3b,$4d,$ae,$2a,$f5,$b0,$c8,$eb,$bb,$3c,$83,$53,$99,$61
	!byte $17,$2b,$04,$7e,$ba,$77,$d6,$26,$e1,$69,$14,$63,$55,$21,$0c,$7d

xt2s:
	!byte $c6,$f8,$ee,$f6,$ff,$d6,$de,$91,$60,$02,$ce,$56,$e7,$b5,$4d,$ec
	!byte $8f,$1f,$89,$fa,$ef,$b2,$8e,$fb,$41,$b3,$5f,$45,$23,$53,$e4,$9b
	!byte $75,$e1,$3d,$4c,$6c,$7e,$f5,$83,$68,$51,$d1,$f9,$e2,$ab,$62,$2a
	!byte $08,$95,$46,$9d,$30,$37,$0a,$2f,$0e,$24,$1b,$df,$cd,$4e,$7f,$ea
	!byte $12,$1d,$58,$34,$36,$dc,$b4,$5b,$a4,$76,$b7,$7d,$52,$dd,$5e,$13
	!byte $a6,$b9,$00,$c1,$40,$e3,$79,$b6,$d4,$8d,$67,$72,$94,$98,$b0,$85
	!byte $bb,$c5,$4f,$ed,$86,$9a,$66,$11,$8a,$e9,$04,$fe,$a0,$78,$25,$4b
	!byte $a2,$5d,$80,$05,$3f,$21,$70,$f1,$63,$77,$af,$42,$20,$e5,$fd,$bf
	!byte $81,$18,$26,$c3,$be,$35,$88,$2e,$93,$55,$fc,$7a,$c8,$ba,$32,$e6
	!byte $c0,$19,$9e,$a3,$44,$54,$3b,$0b,$8c,$c7,$6b,$28,$a7,$bc,$16,$ad
	!byte $db,$64,$74,$14,$92,$0c,$48,$b8,$9f,$bd,$43,$c4,$39,$31,$d3,$f2
	!byte $d5,$8b,$6e,$da,$01,$b1,$9c,$49,$d8,$ac,$f3,$cf,$ca,$f4,$47,$10
	!byte $6f,$f0,$4a,$5c,$38,$57,$73,$97,$cb,$a1,$e8,$3e,$96,$61,$0d,$0f
	!byte $e0,$7c,$71,$cc,$90,$06,$f7,$1c,$c2,$6a,$ae,$69,$17,$99,$3a,$27
	!byte $d9,$eb,$2b,$22,$d2,$a9,$07,$33,$2d,$3c,$15,$c9,$87,$aa,$50,$a5
	!byte $03,$59,$09,$1a,$65,$d7,$84,$d0,$82,$29,$5a,$1e,$7b,$a8,$6d,$2c

xt3s:
	!byte $a5,$84,$99,$8d,$0d,$bd,$b1,$54,$50,$03,$a9,$7d,$19,$62,$e6,$9a
	!byte $45,$9d,$40,$87,$15,$eb,$c9,$0b,$ec,$67,$fd,$ea,$bf,$f7,$96,$5b
	!byte $c2,$1c,$ae,$6a,$5a,$41,$02,$4f,$5c,$f4,$34,$08,$93,$73,$53,$3f
	!byte $0c,$52,$65,$5e,$28,$a1,$0f,$b5,$09,$36,$9b,$3d,$26,$69,$cd,$9f
	!byte $1b,$9e,$74,$2e,$2d,$b2,$ee,$fb,$f6,$4d,$61,$ce,$7b,$3e,$71,$97
	!byte $f5,$68,$00,$2c,$60,$1f,$c8,$ed,$be,$46,$d9,$4b,$de,$d4,$e8,$4a
	!byte $6b,$2a,$e5,$16,$c5,$d7,$55,$94,$cf,$10,$06,$81,$f0,$44,$ba,$e3
	!byte $f3,$fe,$c0,$8a,$ad,$bc,$48,$04,$df,$c1,$75,$63,$30,$1a,$0e,$6d
	!byte $4c,$14,$35,$2f,$e1,$a2,$cc,$39,$57,$f2,$82,$47,$ac,$e7,$2b,$95
	!byte $a0,$98,$d1,$7f,$66,$7e,$ab,$83,$ca,$29,$d3,$3c,$79,$e2,$1d,$76
	!byte $3b,$56,$4e,$1e,$db,$0a,$6c,$e4,$5d,$6e,$ef,$a6,$a8,$a4,$37,$8b
	!byte $32,$43,$59,$b7,$8c,$64,$d2,$e0,$b4,$fa,$07,$25,$af,$8e,$e9,$18
	!byte $d5,$88,$6f,$72,$24,$f1,$c7,$51,$23,$7c,$9c,$21,$dd,$dc,$86,$85
	!byte $90,$42,$c4,$aa,$d8,$05,$01,$12,$a3,$5f,$f9,$d0,$91,$58,$27,$b9
	!byte $38,$13,$b3,$33,$bb,$70,$89,$a7,$b6,$22,$92,$20,$49,$ff,$78,$7a
	!byte $8f,$f8,$80,$17,$da,$31,$c6,$b8,$c3,$b0,$77,$11,$cb,$fc,$d6,$3a

xtme:
	!byte $00,$0e,$1c,$12,$38,$36,$24,$2a,$70,$7e,$6c,$62,$48,$46,$54,$5a
	!byte $e0,$ee,$fc,$f2,$d8,$d6,$c4,$ca,$90,$9e,$8c,$82,$a8,$a6,$b4,$ba
	!byte $db,$d5,$c7,$c9,$e3,$ed,$ff,$f1,$ab,$a5,$b7,$b9,$93,$9d,$8f,$81
	!byte $3b,$35,$27,$29,$03,$0d,$1f,$11,$4b,$45,$57,$59,$73,$7d,$6f,$61
	!byte $ad,$a3,$b1,$bf,$95,$9b,$89,$87,$dd,$d3,$c1,$cf,$e5,$eb,$f9,$f7
	!byte $4d,$43,$51,$5f,$75,$7b,$69,$67,$3d,$33,$21,$2f,$05,$0b,$19,$17
	!byte $76,$78,$6a,$64,$4e,$40,$52,$5c,$06,$08,$1a,$14,$3e,$30,$22,$2c
	!byte $96,$98,$8a,$84,$ae,$a0,$b2,$bc,$e6,$e8,$fa,$f4,$de,$d0,$c2,$cc
	!byte $41,$4f,$5d,$53,$79,$77,$65,$6b,$31,$3f,$2d,$23,$09,$07,$15,$1b
	!byte $a1,$af,$bd,$b3,$99,$97,$85,$8b,$d1,$df,$cd,$c3,$e9,$e7,$f5,$fb
	!byte $9a,$94,$86,$88,$a2,$ac,$be,$b0,$ea,$e4,$f6,$f8,$d2,$dc,$ce,$c0
	!byte $7a,$74,$66,$68,$42,$4c,$5e,$50,$0a,$04,$16,$18,$32,$3c,$2e,$20
	!byte $ec,$e2,$f0,$fe,$d4,$da,$c8,$c6,$9c,$92,$80,$8e,$a4,$aa,$b8,$b6
	!byte $0c,$02,$10,$1e,$34,$3a,$28,$26,$7c,$72,$60,$6e,$44,$4a,$58,$56
	!byte $37,$39,$2b,$25,$0f,$01,$13,$1d,$47,$49,$5b,$55,$7f,$71,$63,$6d
	!byte $d7,$d9,$cb,$c5,$ef,$e1,$f3,$fd,$a7,$a9,$bb,$b5,$9f,$91,$83,$8d

xtmb:
	!byte $00,$0b,$16,$1d,$2c,$27,$3a,$31,$58,$53,$4e,$45,$74,$7f,$62,$69
	!byte $b0,$bb,$a6,$ad,$9c,$97,$8a,$81,$e8,$e3,$fe,$f5,$c4,$cf,$d2,$d9
	!byte $7b,$70,$6d,$66,$57,$5c,$41,$4a,$23,$28,$35,$3e,$0f,$04,$19,$12
	!byte $cb,$c0,$dd,$d6,$e7,$ec,$f1,$fa,$93,$98,$85,$8e,$bf,$b4,$a9,$a2
	!byte $f6,$fd,$e0,$eb,$da,$d1,$cc,$c7,$ae,$a5,$b8,$b3,$82,$89,$94,$9f
	!byte $46,$4d,$50,$5b,$6a,$61,$7c,$77,$1e,$15,$08,$03,$32,$39,$24,$2f
	!byte $8d,$86,$9b,$90,$a1,$aa,$b7,$bc,$d5,$de,$c3,$c8,$f9,$f2,$ef,$e4
	!byte $3d,$36,$2b,$20,$11,$1a,$07,$0c,$65,$6e,$73,$78,$49,$42,$5f,$54
	!byte $f7,$fc,$e1,$ea,$db,$d0,$cd,$c6,$af,$a4,$b9,$b2,$83,$88,$95,$9e
	!byte $47,$4c,$51,$5a,$6b,$60,$7d,$76,$1f,$14,$09,$02,$33,$38,$25,$2e
	!byte $8c,$87,$9a,$91,$a0,$ab,$b6,$bd,$d4,$df,$c2,$c9,$f8,$f3,$ee,$e5
	!byte $3c,$37,$2a,$21,$10,$1b,$06,$0d,$64,$6f,$72,$79,$48,$43,$5e,$55
	!byte $01,$0a,$17,$1c,$2d,$26,$3b,$30,$59,$52,$4f,$44,$75,$7e,$63,$68
	!byte $b1,$ba,$a7,$ac,$9d,$96,$8b,$80,$e9,$e2,$ff,$f4,$c5,$ce,$d3,$d8
	!byte $7a,$71,$6c,$67,$56,$5d,$40,$4b,$22,$29,$34,$3f,$0e,$05,$18,$13
	!byte $ca,$c1,$dc,$d7,$e6,$ed,$f0,$fb,$92,$99,$84,$8f,$be,$b5,$a8,$a3

xtmd:
	!byte $00,$0d,$1a,$17,$34,$39,$2e,$23,$68,$65,$72,$7f,$5c,$51,$46,$4b
	!byte $d0,$dd,$ca,$c7,$e4,$e9,$fe,$f3,$b8,$b5,$a2,$af,$8c,$81,$96,$9b
	!byte $bb,$b6,$a1,$ac,$8f,$82,$95,$98,$d3,$de,$c9,$c4,$e7,$ea,$fd,$f0
	!byte $6b,$66,$71,$7c,$5f,$52,$45,$48,$03,$0e,$19,$14,$37,$3a,$2d,$20
	!byte $6d,$60,$77,$7a,$59,$54,$43,$4e,$05,$08,$1f,$12,$31,$3c,$2b,$26
	!byte $bd,$b0,$a7,$aa,$89,$84,$93,$9e,$d5,$d8,$cf,$c2,$e1,$ec,$fb,$f6
	!byte $d6,$db,$cc,$c1,$e2,$ef,$f8,$f5,$be,$b3,$a4,$a9,$8a,$87,$90,$9d
	!byte $06,$0b,$1c,$11,$32,$3f,$28,$25,$6e,$63,$74,$79,$5a,$57,$40,$4d
	!byte $da,$d7,$c0,$cd,$ee,$e3,$f4,$f9,$b2,$bf,$a8,$a5,$86,$8b,$9c,$91
	!byte $0a,$07,$10,$1d,$3e,$33,$24,$29,$62,$6f,$78,$75,$56,$5b,$4c,$41
	!byte $61,$6c,$7b,$76,$55,$58,$4f,$42,$09,$04,$13,$1e,$3d,$30,$27,$2a
	!byte $b1,$bc,$ab,$a6,$85,$88,$9f,$92,$d9,$d4,$c3,$ce,$ed,$e0,$f7,$fa
	!byte $b7,$ba,$ad,$a0,$83,$8e,$99,$94,$df,$d2,$c5,$c8,$eb,$e6,$f1,$fc
	!byte $67,$6a,$7d,$70,$53,$5e,$49,$44,$0f,$02,$15,$18,$3b,$36,$21,$2c
	!byte $0c,$01,$16,$1b,$38,$35,$22,$2f,$64,$69,$7e,$73,$50,$5d,$4a,$47
	!byte $dc,$d1,$c6,$cb,$e8,$e5,$f2,$ff,$b4,$b9,$ae,$a3,$80,$8d,$9a,$97

xtm9:
	!byte $00,$09,$12,$1b,$24,$2d,$36,$3f,$48,$41,$5a,$53,$6c,$65,$7e,$77
	!byte $90,$99,$82,$8b,$b4,$bd,$a6,$af,$d8,$d1,$ca,$c3,$fc,$f5,$ee,$e7
	!byte $3b,$32,$29,$20,$1f,$16,$0d,$04,$73,$7a,$61,$68,$57,$5e,$45,$4c
	!byte $ab,$a2,$b9,$b0,$8f,$86,$9d,$94,$e3,$ea,$f1,$f8,$c7,$ce,$d5,$dc
	!byte $76,$7f,$64,$6d,$52,$5b,$40,$49,$3e,$37,$2c,$25,$1a,$13,$08,$01
	!byte $e6,$ef,$f4,$fd,$c2,$cb,$d0,$d9,$ae,$a7,$bc,$b5,$8a,$83,$98,$91
	!byte $4d,$44,$5f,$56,$69,$60,$7b,$72,$05,$0c,$17,$1e,$21,$28,$33,$3a
	!byte $dd,$d4,$cf,$c6,$f9,$f0,$eb,$e2,$95,$9c,$87,$8e,$b1,$b8,$a3,$aa
	!byte $ec,$e5,$fe,$f7,$c8,$c1,$da,$d3,$a4,$ad,$b6,$bf,$80,$89,$92,$9b
	!byte $7c,$75,$6e,$67,$58,$51,$4a,$43,$34,$3d,$26,$2f,$10,$19,$02,$0b
	!byte $d7,$de,$c5,$cc,$f3,$fa,$e1,$e8,$9f,$96,$8d,$84,$bb,$b2,$a9,$a0
	!byte $47,$4e,$55,$5c,$63,$6a,$71,$78,$0f,$06,$1d,$14,$2b,$22,$39,$30
	!byte $9a,$93,$88,$81,$be,$b7,$ac,$a5,$d2,$db,$c0,$c9,$f6,$ff,$e4,$ed
	!byte $0a,$03,$18,$11,$2e,$27,$3c,$35,$42,$4b,$50,$59,$66,$6f,$74,$7d
	!byte $a1,$a8,$b3,$ba,$85,$8c,$97,$9e,$e9,$e0,$fb,$f2,$cd,$c4,$df,$d6
	!byte $31,$38,$23,$2a,$15,$1c,$07,$0e,$79,$70,$6b,$62,$5d,$54,$4f,$46

keys:
	!byte $d8,$31,$2b,$f1,$3e,$d1,$15,$65,$ed,$14,$1b,$c2,$d8,$43,$05,$a0
	!byte $5c,$65,$62,$b5,$9b,$1c,$17,$f4,$62,$d4,$f3,$f3,$53,$e4,$d6,$79
