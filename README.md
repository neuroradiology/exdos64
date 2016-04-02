ExDOS
=====
![Screenshot of ExDOS64 running in VirtualBox](http://s9.postimg.org/okj1tuuyn/exdos64.png)

What is ExDOS?
================
ExDOS is a tiny, yet very powerful and fast graphical multiprocessing multitasking operating system for x86_64 PCs written from scratch entirely in assembly language. It can run on most any PC with a 64-bit Intel or AMD CPU. It features a powerful graphical user interface, multitasking, EXDFS filesystem access, a modular kernel, and many other things all under 200 KB!  
Most OS software today is bloated. ExDOS aims to change this, and shows what we can do with the full power of the x86_64 CPU. To achieve this, ExDOS supports all latest x86/x86_64 features, including but not limited to long mode, AVX-256, symmetric multiprocessing, while remaining small in size and in requirements. In fact, ExDOS can boot with as little as 64 MB of RAM, although for performance, 192 MB is recommended.  
ExDOS is not based on any standards and uses its own custom design, which is designed for easy assembly language programming. It uses a hybrid kernel, with the core drivers (disk, SMP, keyboard, ...) in ring 0 and other optional drivers (network, sound, USB, ...) in ring 3.  

Features
========
- Fully 64-bit -- independent of BIOS.
- SMP up to 16 CPUs, and I/O APIC.
- Read/write ATA driver.
- VESA 2.0 framebuffer driver, up to 16 million colors.
- Window Manager.
- PCI/PCIe scanner.
- ACPI driver (with shutdown and reset, and partial AML interpreter under development).
- Driver interface in userspace (hybrid kernel).

Running ExDOS
=============
ExDOS runs in Bochs, QEMU, VirtualBox, VMware and some real hardware. In Bochs, performance is low. Use disk.img as a hard disk image, with CHS values 71/16/63. In QEMU, VirtualBox and VMware, be sure to use the disk image with ATA and not SATA, as the AHCI driver is not yet functional.

Source code organization
========================
The source code is somewhat commented, and is mostly obvious. The /boot directory contains the source code of the boot loader. The /os directory contains the kernel and core OS code. The /ex86 directory contains the source of Ex86, an x86 emulator I am currently working on to replace v8086 in long mode. The /out directory contains the built kernel and boot loader binaries.

Contact
=======
You can contact me at omarx024@gmail.com.



