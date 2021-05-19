# AES-X16

An AES Encryption speed demo for the Commander X16

This program loads an image into the VERA's VRAM and repeatedly encrypts and decripts the image to demonstrate the speed that the Commander X16 can perform encryption. This project works with 128, 192, and 256 bit key variants of AES, and the Makefile builds separate PRG files for each key size.

## Build instructions

```
make
```

## Credits

The image was taken from the [Commander X16 Mode7 Demo](https://github.com/commanderx16/x16-demo/tree/af282c208c89400b64a977de91e31ec7031b2807/assembly). Copyright David "The 8-Bit Guy" Murray and/or Michael "mist64" Steil.

The implementation of AES is based on [byte-oriented-aes](https://code.google.com/archive/p/byte-oriented-aes/) by Karl Malbrain. Released into the public domain by the author.

The file vera.inc is adapted from the [Commander X16 ROM project](https://github.com/commanderx16/x16-rom). Copyright Michael Steil and/or Frank van den Hoef, Licenced under the BSD 2-clause license.
