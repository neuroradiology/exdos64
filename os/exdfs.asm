
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Extensible Disk File System Driver",0

;; Functions:
; internal_filename
; external_filename
; load_root_directory
; load_file_bytes
; get_file_size

use64

; internal_filename:
; Converts external file name to internal file name
; In\	RSI = External file name
; Out\	RDI = Internal file name as ASCIIZ string

internal_filename:
	mov [.filename], rsi
	call get_string_size
	mov [.size], rax

	mov rsi, [.filename]
	mov rdi, new_filename
	mov rcx, 0

.loop:
	lodsb
	cmp al, '.'
	je .found_dot

	stosb
	inc rcx
	cmp rcx, 8
	jg .bad_filename

	jmp .loop

.found_dot:
	cmp rdi, new_filename+8
	je .do_extension

.fill_spaces:
	mov al, ' '
	stosb
	cmp rdi, new_filename+8
	je .do_extension
	jmp .fill_spaces

.do_extension:
	push rsi
	call get_string_size
	pop rsi
	mov rcx, rax
	cmp rcx, 3
	jg .bad_filename

	mov rdi, new_filename+8
	rep movsb

	mov rax, 0
	mov rdi, new_filename
	ret

.bad_filename:
	mov rdi, new_filename
	mov al, 0xFE
	mov rcx, 11
	rep stosb
	mov al, 0
	stosb

	mov rax, 1
	mov rdi, new_filename
	ret

.filename			dq 0
.size				dq 0

; external_filename:
; Converts internal file name to external file name
; In\	RSI = Internal file name
; Out\	RDI = External file name as ASCIIZ string

external_filename:
	mov [.filename], rsi
	call get_string_size
	cmp rax, 11
	jne .bad_filename

	mov rsi, [.filename]
	mov dl, ' '
	mov rcx, 9
	call find_byte_in_string
	jc .no_spaces

	mov rsi, [.filename]
	mov rcx, 0
	mov rdi, .bad_filename

.loop:
	lodsb
	cmp al, ' '
	je .space
	inc rcx
	cmp rcx, 8
	jge .do_extension
	jmp .loop

.space:

.do_extension:
	mov rsi, [.filename]
	add rsi, 8
	mov al, '.'
	stosb

	mov rcx, 3
	rep movsb

	mov al, 0
	stosb

	mov rdi, new_filename
	mov rax, 0
	ret

.no_spaces:
	mov rsi, [.filename]
	mov rdi, new_filename
	mov rcx, 8
	rep movsb
	mov al, '.'
	stosb
	mov rcx, 3
	rep movsb

	mov al, 0
	stosb

	mov rdi, new_filename
	mov rax, 0
	ret

.bad_filename:
	mov rdi, new_filename
	mov al, 0xFE
	mov rcx, 11
	rep stosb
	mov al, 0
	stosb

	mov rax, 1
	mov rdi, new_filename
	ret

.filename			dq 0

new_filename:			times 12 db 0

; load_root_directory:
; Loads the root directory into the disk buffer

load_root_directory:
	pushaq

	; First we need to get the partition
	mov al, [system_root_drive]
	mov rdi, [disk_buffer]
	mov rbx, 0
	mov rcx, 1
	call read_sectors
	jc .quit

	mov rdi, [disk_buffer]
	add rdi, 0x1BE
	movzx rax, [system_root_partition]
	shl rax, 4
	add rdi, rax

	; Now, read the root directory ;)
	mov rbx, 0
	mov al, [system_root_drive]
	mov ebx, [rdi+8]		; partition LBA
	inc rbx
	mov rdi, [disk_buffer]
	mov rcx, 32
	call read_sectors

.quit:
	popaq
	ret

; load_file_bytes:
; Loads data from a file
; In\	RSI = Filename
; Out\	RAX = Pointer to file data, -1 on error
; Out\	RCX = Size of file in bytes, -1 on error

load_file_bytes:
	pushaq
	mov [.filename], rsi

	mov rsi, [.filename]
	call internal_filename
	call load_root_directory

	mov rsi, [disk_buffer]
	add rsi, 32
	mov rdi, new_filename
	mov rcx, 512

.loop:
	pushaq
	mov rcx, 11
	rep cmpsb
	je .found_file
	popaq

	add rsi, 32
	loop .loop
	jmp .error

.found_file:
	popaq
	mov rax, 0
	mov eax, [rsi+12]
	mov dword[.lba], eax
	mov eax, [rsi+16]
	mov dword[.size_sectors], eax
	mov eax, [rsi+20]
	mov dword[.size_bytes], eax

	mov rax, 0
	mov rbx, [.size_sectors]
	shl rbx, 9
	mov dl, 3
	call kmalloc
	mov [.memory], rax
	jc .error

	mov al, [system_root_drive]
	mov rbx, [.lba]
	mov rcx, [.size_sectors]
	mov rdi, [.memory]
	call read_sectors
	jc .error

	popaq
	mov rax, [.memory]
	mov rcx, [.size_bytes]
	ret

.error:
	popaq
	mov rax, -1
	mov rcx, -1
	ret

.filename				dq 0
.size_sectors				dq 0
.size_bytes				dq 0
.lba					dq 0
.memory					dq 0

; get_file_size:
; Gets size of a file
; In\	RSI = Filename
; Out\	RAX = Size of file in bytes, -1 on error

get_file_size:
	pushaq
	mov [.filename], rsi
	call internal_filename
	call load_root_directory

	mov rsi, [disk_buffer]
	add rsi, 32
	mov rdi, new_filename
	mov rcx, 512

.loop:
	pushaq
	mov rcx, 11
	rep cmpsb
	je .found
	popaq

	add rsi, 32
	loop .loop
	jmp .fnf

.found:
	popaq
	mov eax, [rsi+20]
	mov [.size], eax

	popaq
	mov rax, 0
	mov eax, [.size]
	ret

.fnf:
	popaq
	mov rax, -1
	ret

.filename				dq 0
.size					dd 0




