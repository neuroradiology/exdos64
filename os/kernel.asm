
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use16
org 0x500

jmp short kmain16

KSTACK_SIZE			= 4096
API_VERSION			= 1
define				TODAY "26.03.2016"

times 32 - ($-$$) db 0
newline				db 10,0
kernel_version			db "ExDOS64 version 0.01 built ",TODAY,0
KERNEL_VERSION_STR_SIZE		= $ - kernel_version

kmain16:
	cli
	cld
	mov ax, 0
	mov ss, ax
	mov sp, stack16+512

	mov ax, 0
	mov es, ax
	mov di, boot_partition
	mov cx, 16
	rep movsb

	mov ax, 0
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov [bootdisk], dl

	sti

	mov ah, 0xF
	mov bx, 0
	int 0x10

	cmp al, 3
	jne .set_mode_3

	jmp .mode_done

.set_mode_3:
	mov ax, 3
	int 0x10

.mode_done:
	mov si, newline
	call print_string_16

	mov si, kernel_version
	call print_string_16

	mov si, newline
	call print_string_16

	mov eax, 0
	mov cr4, eax			; disable all unwanted features...

	; ensure the PC has at least 512 KB RAM
	mov ax, 0
	int 0x12
	jc detect_memory.too_little

	cmp ax, 0x200
	jle detect_memory.too_little

	call check_cpu			; make sure we have a 64-bit capable CPU
	call detect_memory		; uses BIOS E820 to detect memory
	call enable_a20			; enable A20 gate
	call check_a20			; check A20 gate status
	call setup_identity_paging	; set up identity paging

	; detect EBDA
	clc
	mov eax, 0
	int 0x12
	jc .default_ebda

	cmp ax, 0
	je .default_ebda

	and eax, 0xFFFF
	shl eax, 10
	mov dword[ebda_base], eax
	jmp .detect_pci

.default_ebda:
	mov dword[ebda_base], 0x80000	; if the BIOS fails, make the EBDA 0x80000 by default

.detect_pci:
	; detect PCI
	mov eax, 0xB101
	mov edi, 0
	int 0x1A
	jc .no_pci
	cmp edx, 0x20494350
	jne .no_pci
	test al, 1
	jz .no_pci

	mov si, .pci_present_msg
	call print_string_16

	; to help with detecting disks later on, we will save the MBR of the boot disk
	mov ax, 0
	mov dl, [bootdisk]
	int 0x13			; reset the disk
	jc .cannot_read_mbr

	mov ah, 2			; read sectors
	mov al, 1
	mov ch, 0
	mov cl, 1
	mov dh, 0
	mov bx, bootdrive_mbr
	mov dl, [bootdisk]
	int 0x13
	jc .cannot_read_mbr

	jmp .keep_booting

.pci_present_msg		db "PCI bus is present.",10,0

.no_pci:
	mov si, .no_pci_msg
	call err16

	jmp $

.no_pci_msg			db "PCI BIOS not found, assuming PCI bus doesn't exist.",10,0

.cannot_read_mbr:
	mov si, .cannot_read_mbr_msg
	call err16

	jmp $

.cannot_read_mbr_msg		db "BIOS error! Cannot read the master boot record!",10,0

.keep_booting:
	sti

	call bios_get_drive_size	; get drive size to help with detecting MEMDISK
	call do_vbe			; enable the VBE framebuffer

	; notify the BIOS that we're going to run in long mode
	;mov eax, 0xEC00
	;mov ebx, 2
	;int 0x15			; this function doesn't seem to do anything
					; besides, the BIOS doesn't need to know what we're doing --
					; -- because we don't depend on BIOS for anything

	sti
	mov al, 0x8B			; disable NMI and CMOS interrupts
	out 0x70, al

	out 0x80, al
	out 0x80, al			; I/O delay

	in al, 0x71
	and al, 7

	push ax
	mov al, 0x8B
	out 0x70, al

	out 0x80, al
	out 0x80, al			; I/O delay

	pop ax
	out 0x71, al

	; save BIOS PIC masks
	in al, 0x21
	mov [bios_pic1_mask], al
	in al, 0xA1
	mov [bios_pic2_mask], al

	out 0x80, al
	out 0x80, al

	mov al, 0xFF			; disable PIC by masking all IRQs
	out 0x21, al
	out 0xA1, al

	mov ecx, 0xFFFF

.wait:		; wait for any queued interrupts to happen and let the BIOS handle them...
	sti
	nop
	nop
	nop
	nop
	nop
	nop
	out 0x80, al
	out 0x80, al
	loop .wait

	cli

	lgdt [gdtr]
	lidt [idtr]

	mov eax, 0x130			; enable PAE and PSE and PMC
	mov cr4, eax

	mov eax, pml4
	or eax, 8
	mov cr3, eax

	mov ecx, 0xC0000080
	rdmsr
	or eax, 0x100			; enable long mode
	wrmsr

	mov eax, cr0
	or eax, 0x80000001		; enable paging and protection together
	and eax, 0x9FFFFFFF		; enable caching
	mov cr0, eax
	jmp 0x28:kmain64

use64

macro pushaq {			; because PUSHA is not available on x86_64..
	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	push rbp
	push r8
	push r9
	push r10
	push r11
	push r12
	push r13
	push r14
	push r15
}

macro popaq {			; POPA..
	pop r15
	pop r14
	pop r13
	pop r12
	pop r11
	pop r10
	pop r9
	pop r8
	pop rbp
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax
}

align 16
kmain64:
	mov ax, 0x30
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov rsp, kstack+KSTACK_SIZE

	lgdt [gdtr]
	lidt [idtr]

	call init_serial			; initialize the serial port for debugging
	mov rsi, kernel_version
	call kprint
	mov rsi, newline
	call kprint

	call init_exceptions			; install exception handlers
	call show_serial_info			; show information on the serial ports
	call parse_memory_map			; parse the E820 memory map
	call pmm_init				; initialize the physical memory manager
	call init_acpi				; initialize the ACPI subsystem
	call init_smp				; initialize up to 16 processors
	call init_ioapic			; initialize the I/O APIC
	call enable_acpi			; enable ACPI hardware mode
	;call acpi_detect_batteries		; detect ACPI batteries -- will be fully implemented after AML is finished
	call init_pci				; initialize the PCI bus
	;call init_pcie				; initialize the PCI Express bus
	call init_pit				; initialize the PIT to 100 Hz
	call init_cmos				; initialize the CMOS
	;call init_hpet				; initialize the HPET and disable the PIT
	call init_keyboard			; initialize the keyboard
	call init_mouse				; initialize the mouse
	;call init_apic_timer			; initialize APIC timer -- has problems on real hardware
	call free_unused_memory			; free unused kernel memory
	call map_vbe_framebuffer		; initialize a buffer for VBE
	call calculate_cpu_speed		; calculate CPU speed
	;call init_mtrr				; initialize MTRR -- has problems on at least one PC
	call init_storage			; initialize storage devices
	call init_vfs				; initialize the virtual file system
	call init_user				; initialize usermode stuff
	;call init_tasking			; start multitasking
	call random_seed			; seed the random number generator
	;call load_drivers			; loads all boot-time drivers
	call enable_interrupts			; enable interrupts on all CPUs

	jmp gui

include				"os/early16.asm"		; early 16-bit code
include				"os/system.asm"			; Internal system routines
include				"os/kdebug.asm"			; Kernel logger and debugger
include				"os/serial.asm"			; Serial port driver
include				"os/string.asm"			; String-manipulation
include				"os/exception.asm"		; Exception Handlers
include				"os/pmm.asm"			; Physical memory manager
include				"os/vmm.asm"			; Virtual memory manager
include				"os/gdi.asm"			; Graphics device interface
include				"os/user.asm"			; Usermode stuff
include				"os/math.asm"			; Math routines
include				"os/acpi.asm"			; ACPI subsystem
include				"os/apic.asm"			; SMP & APIC implementation
include				"os/vbe.asm"			; VESA framebuffer driver
include				"os/pit.asm"			; PIT driver
include				"os/hpet.asm"			; HPET driver
include				"os/tasking.asm"		; Multitasking
include				"os/cmos.asm"			; CMOS driver
include				"os/keyboard.asm"		; PS/2 keyboard driver
include				"os/mouse.asm"			; PS/2 mouse driver
include				"os/pci.asm"			; PCI driver
include				"os/pcie.asm"			; PCI-E driver
include				"os/storage.asm"		; Storage device abstraction layer
include				"os/ata.asm"			; ATA/ATAPI disk driver
include				"os/ahci.asm"			; SATA/SATAPI (PCI AHCI) disk driver
include				"os/memdisk.asm"		; MEMDISK disk driver
include				"os/fs.asm"			; File system abstraction layer
include				"os/exdfs.asm"			; ExDFS filesystem driver
include				"os/drivers.asm"		; Driver API
include				"os/mtrr.asm"			; MTRR manager
include				"ex86/exdos64/exdos64.asm"	; x86 emulator
include				"os/gui.asm"			; Graphical User Interface

align 16			; stack should be aligned
kstack:				rb KSTACK_SIZE


