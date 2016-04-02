
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Generic storage abstraction layer",0

;; Functions:
; init_storage
; read_sectors

MAX_DISKS		= 40				; OS can handle up to 40 physical drives

list_of_disks:		times MAX_DISKS dw 0xFFFF	; Byte 0 is 0 for ATA, 1 for AHCI, 2 for MEMDISK, 3 for USB
							; Byte 1 is drive number for ATA, port for AHCI, reserved for MEMDISK
number_of_drives	db 0

; init_storage:
; Detects mass storage drives

init_storage:
	mov rsi, .msg
	call kprint

	call ata_detect			; detect ATA drives
	;call ahci_detect		; detect AHCI devices
	;call nvme_detect		; detect NVMe devices -- will be implemented after I have PCI-E driver
	call memdisk_detect		; detect MEMDISK memory-mapped drives

	mov rsi, .done_msg
	call kprint
	movzx rax, [number_of_drives]
	call int_to_string
	call kprint
	mov rsi, .done_msg2
	call kprint

	; Now, we need to determine the boot disk
	mov rcx, MAX_DISKS
	mov [.current_disk], 0

.find_bootdisk_loop:
	push rcx
	mov al, [.current_disk]
	mov rbx, 0
	mov rdi, mbr_tmp
	mov rcx, 1
	call read_sectors

	mov rsi, mbr_tmp
	mov rdi, bootdrive_mbr
	mov rcx, 512
	rep cmpsb
	je .found_bootdisk

.next:
	inc [.current_disk]
	pop rcx
	loop .find_bootdisk_loop
	jmp .no_bootdisk

.found_bootdisk:
	mov al, [.current_disk]
	mov [bootdisk], al

	mov rsi, .found_bootdisk_msg
	call kprint

	movzx rax, [.current_disk]
	shl rax, 1
	add rax, list_of_disks

	cmp byte[rax], 0
	je .ata

	cmp byte[rax], 1
	je .ahci

	cmp byte[rax], 2
	je .memdisk

.ata:
	push rax
	mov rsi, .ata_msg
	call kprint
	pop rax
	movzx rdx, byte[rax+1]
	mov rax, rdx
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	pop rcx
	ret

.ahci:
	push rax
	mov rsi, .ahci_msg
	call kprint
	pop rax
	movzx rdx, byte[rax+1]
	mov rax, rdx
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	pop rcx
	ret

.memdisk:
	mov rsi, .memdisk_msg
	call kprint

	pop rcx
	ret

.no_bootdisk:
	mov rsi, .bootdisk_error
	call kprint

	mov rsi, .bootdisk_error
	call start_debugging

	jmp $

.msg				db "[storage] initializing mass storage devices...",10,0
.done_msg			db "[storage] total of ",0
.done_msg2			db " hard disks onboard.",10,0
.bootdisk_error			db "[storage] unable to access the boot disk!",10,0
.found_bootdisk_msg		db "[storage] found boot disk: ",0
.ata_msg			db "ATA drive number ",0
.ahci_msg			db "SATA device on AHCI port number ",0
.memdisk_msg			db "memory-mapped MEMDISK drive",10,0
.current_disk			db 0
.device				db 0

; read_sectors:
; Generic read sectors from any type of disk
; In\	AL = Logical disk number
; In\	RDI = Buffer to read sectors to
; In\	RBX = LBA sector
; In\	RCX = Number of sectors to read
; Out\	RFLAGS = Carry flag set on error

read_sectors:
	mov [.buffer], rdi
	mov [.lba], rbx
	mov [.count], rcx

	cmp al, MAX_DISKS-1
	jg .error

	movzx rax, al
	shl rax, 1		; quick multiply by 2
	add rax, list_of_disks

	mov dl, [rax+1]
	mov [.drive], dl

	cmp byte[rax], 0
	je .ata

	cmp byte[rax], 1
	je .ahci

	cmp byte[rax], 2
	je .memdisk

	jmp .error		; for now, because there's still no ATAPI, USB, or NVMe support

.ata:
	cmp [.count], 0
	je .ata_done

	cmp [.count], 255
	jg .ata_big

	mov al, [.drive]
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, [.count]
	call ata_read
	jc .error

.ata_done:
	clc
	ret

.ata_big:
	mov al, [.drive]
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, 255
	call ata_read
	jc .error

	add [.buffer], 512*255
	add [.lba], 255
	sub [.count], 255
	jmp .ata

.ahci:
	;mov dl, [rax+1]	; AHCI port
	;mov al, dl
	;call ahci_read
	;jc .error
	jmp .error

.memdisk:
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, [.count]
	call memdisk_read
	jc .error

	clc
	ret

.error:
	stc
	ret

.drive				db 0
.lba				dq 0
.count				dq 0
.buffer				dq 0


