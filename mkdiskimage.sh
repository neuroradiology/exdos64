#!/bin/sh
echo Building ExDOS...
# Assemble bootloader
mkdir tmp_out
fasm boot/mbr.asm tmp_out/mbr.sys
fasm boot/boot_hdd.asm tmp_out/boot_hdd.sys

# Assemble kernel
fasm os/kernel.asm tmp_out/kernel64.sys

# Assemble root directory
fasm tmp/root.asm tmp_out/root.sys

# Install OS on disk image
dd if=/dev/zero bs=512 conv=notrunc count=71568 of=disk.img
dd if=tmp_out/mbr.sys conv=notrunc bs=512 count=1 of=disk.img
dd if=tmp_out/boot_hdd.sys conv=notrunc bs=512 seek=63 of=disk.img
dd if=tmp_out/root.sys conv=notrunc bs=512 seek=64 of=disk.img
dd if=tmp_out/kernel64.sys conv=notrunc bs=512 seek=200 of=disk.img

# Clean up directory
rm tmp_out/*
rmdir tmp_out
echo Finished.


