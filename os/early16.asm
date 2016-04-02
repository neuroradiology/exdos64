
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use16

db "Early 16-bit code",0

; print_string_16:
; Prints a string in 16-bit real mode
; In\	DS:SI = String
; Out\	Nothing

print_string_16:
	pusha

.loop:
	lodsb
	cmp al, 0
	je .done
	cmp al, 10
	je .newline

	mov ah, 0xE
	mov bh, 0
	int 0x10
	jmp .loop

.newline:
	mov ah, 0xE
	mov bh, 0
	mov al, 13
	int 0x10
	mov al, 10
	int 0x10
	jmp .loop

.done:
	popa
	ret

; bios_get_drive_size:
; Gets drive size from BIOS

bios_get_drive_size:
	mov ah, 0x48
	mov dl, [bootdisk]
	mov si, int13_extension_parameters
	int 0x13
	jc .error

	ret

.error:
	mov si, .err_msg
	call print_string_16

	jmp $

.err_msg			db "Extended BIOS INT 0x13 parameters function failed.",0

align 16
int13_extension_parameters:
	.size			dw 0x1A
	.information		dw 0
	.cylinders		dd 0
	.heads			dd 0
	.sectors		dd 0
	.total_sectors		dq 0
	.bytes_per_sector	dw 0

; draw_ui16:
; Draws the 16-bit UI

draw_ui16:
	; hide text mode cursor
	mov ax, 0x0100
	mov cx, 0x2607
	mov bx, 0
	int 0x10

	mov ax, 0xB800
	mov es, ax
	mov di, 0
	mov cx, 80*25

.loop:
	mov al, 0
	stosb
	mov al, 0x4F
	stosb
	loop .loop

	mov ax, 0
	mov es, ax

	mov ah, 2
	mov bh, 0
	mov dx, 0
	int 0x10

	mov cx, 80

.print_top_line_loop:
	push cx
	mov ah, 0xE
	mov al, 219
	int 0x10
	pop cx
	loop .print_top_line_loop

	mov si, newline
	call print_string_16

	mov si, kernel_version
	call print_string_16
	mov si, newline
	call print_string_16

	mov cx, KERNEL_VERSION_STR_SIZE

.print_underline_loop:
	push cx
	mov ah, 0xE
	mov al, '='
	int 0x10
	pop cx
	loop .print_underline_loop

	mov ah, 2
	mov bh, 0
	mov dh, 5
	mov dl, 1
	int 0x10

	ret

; err16:
; Handles early 16-bit boot error
; In\	DS:SI = String to print
; Out\	Nothing

err16:
	push si
	call draw_ui16

	mov si, .msg
	call print_string_16

	pop si
	call print_string_16

.sti:
	sti
	jmp .sti

.msg			db "Boot error: ",0


align 16
bootdrive_mbr:			times 512 db 0		; where the boot drive MBR is to be saved
mbr_tmp:			times 512 db 0		; temporarily

bootdisk			db 0

align 16
boot_partition:
	.boot			db 0
	.start_chs		db 0
				db 0
				db 0
	.type			db 0
	.end_chs		db 0
				db 0
				db 0
	.lba			dd 0
	.size			dd 0



