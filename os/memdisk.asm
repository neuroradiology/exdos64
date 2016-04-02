
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

;; Functions:
; memdisk_detect
; memdisk_select_lba
; memdisk_read
; memdisk_write

db "MEMDISK memory-mapped disk driver",0

memdisk_phys					dq 0
memdisk_sector_size				dq 0
memdisk_disk_size				dq 0
memdisk_size_pages				dq 0
memdisk_location				dq 0x180000000

; memdisk_detect:
; Detects memory-mapped disks by MEMDISK

memdisk_detect:
	pushaq

	mov rsi, .starting_msg
	call kprint

	mov rax, [int13_extension_parameters.total_sectors]
	movzx rbx, [int13_extension_parameters.bytes_per_sector]
	mul rbx
	mov [memdisk_disk_size], rax

	movzx rax, [int13_extension_parameters.bytes_per_sector]
	mov [memdisk_sector_size], rax

	mov rsi, memory_map
	mov rcx, 0
	mov ecx, [detect_memory.entries]

.find_memdisk:
	add rsi, 4
	mov rax, [memdisk_disk_size]
	cmp rax, [rsi+8]
	je .found_memdisk

	mov rax, 0
	mov eax, [rsi-4]
	add rsi, rax
	loop .find_memdisk

	mov rsi, .fail_msg
	call kprint

	popaq
	ret

.found_memdisk:
	mov rax, [rsi]
	mov [memdisk_phys], rax

	movzx rax, [number_of_drives]
	shl rax, 1
	add rax, list_of_disks
	mov word[rax], 2
	inc [number_of_drives]

	mov rsi, .yes_msg
	call kprint
	mov rax, [memdisk_phys]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rax, [memdisk_disk_size]
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [memdisk_size_pages], rax

	mov rax, [memdisk_phys]
	and eax, 0xFFE00000
	mov rbx, [memdisk_location]
	mov rcx, [memdisk_size_pages]
	add rcx, 2
	mov dl, 3
	call vmm_map_memory

	mov rax, [memdisk_phys]
	mov rbx, 0x200000
	call round_backward

	mov rbx, [memdisk_phys]
	sub rbx, rax
	add [memdisk_location], rbx

	popaq
	ret

.starting_msg				db "[memdisk] detecting MEMDISK drives...",10,0
.yes_msg				db "[memdisk] drive found at 0x",0
.fail_msg				db "[memdisk] no MEMDISK drives found.",10,0

; memdisk_select_lba:
; Returns a pointer to a sector within MEMDISK
; In\	RBX = LBA
; Out\	RSI = Pointer to sector data
; Out\	RFLAGS = Carry set on error

memdisk_select_lba:
	mov [.lba], rbx

	mov rax, [.lba]
	mov rbx, [memdisk_sector_size]
	mul rbx
	mov [.tmp], rax

	cmp rax, [memdisk_disk_size]
	jg .error

	mov rsi, [.tmp]
	mov rax, [memdisk_location]
	add rsi, rax

	clc
	ret

.error:
	stc
	ret

align 16
.lba					dq 0
.tmp					dq 0

; memdisk_read:
; Reads from a MEMDISK drive
; In\	RBX = LBA
; In\	RCX = Sector count
; In\	RDI = Buffer to read sectors
; Out\	RFLAGS = Carry set on error

memdisk_read:
	cmp [memdisk_location], 0
	je .error

	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rdi

	mov rax, [.count]
	mov rbx, [memdisk_sector_size]
	mul rbx
	mov [.bytes], rax

	mov rbx, [.lba]
	call memdisk_select_lba
	jc .error

	mov rdi, [.buffer]
	mov rcx, [.bytes]
	call memcpy

	clc
	ret

.error:
	stc
	ret

align 16
.lba					dq 0
.count					dq 0
.buffer					dq 0
.bytes					dq 0

; memdisk_write:
; Writes to a MEMDISK drive
; In\	RBX = LBA
; In\	RCX = Sector count
; In\	RSI = Buffer to write from
; Out\	RFLAGS = Carry set on error

memdisk_write:
	cmp [memdisk_location], 0
	je .error

	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rsi

	mov rax, [.count]
	mov rbx, [memdisk_sector_size]
	mul rbx
	mov [.bytes], rax

	mov rbx, [.lba]
	call memdisk_select_lba
	jc .error

	mov rdi, rsi
	mov rsi, [.buffer]
	mov rcx, [.bytes]
	call memcpy

	clc
	ret

.error:
	stc
	ret

align 16
.lba					dq 0
.count					dq 0
.buffer					dq 0
.bytes					dq 0





