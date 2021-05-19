all: AES128.PRG AES192.PRG AES256.PRG

AES128.PRG: aes.asm vera.inc
	acme -DKEYSIZE=16 -DROUNDS=10 -f cbm -o $@ $<

AES192.PRG: aes.asm vera.inc
	acme -DKEYSIZE=24 -DROUNDS=12 -f cbm -o $@ $<

AES256.PRG: aes.asm vera.inc
	acme -DKEYSIZE=32 -DROUNDS=14 -f cbm -o $@ $<

clean:
	rm AES128.PRG AES192.PRG AES256.PRG
