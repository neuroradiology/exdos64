#!/bin/sh
fasm os/kernel.asm out/kernel64.sys
fasm tmp/root.asm tmp/root.bin
dd if=out/kernel64.sys bs=512 conv=notrunc seek=200 of=disk.img
dd if=tmp/root.bin bs=512 conv=notrunc seek=64 of=disk.img

