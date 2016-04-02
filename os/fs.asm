
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Generic file I/O abstraction layer",0

;; Functions:
; init_vfs
; set_system_root
; get_free_file
; create_file_structure
; open
; close
; seek
; read

system_root_drive		db 0
system_root_partition		db 0

system_root_partition_table:
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

FILE_STRUCTURE:
	.present		= $ - FILE_STRUCTURE
				db 0
	.flags			= $ - FILE_STRUCTURE
				dq 0
	.position		= $ - FILE_STRUCTURE
				dq 0
	.size			= $ - FILE_STRUCTURE
				dq 0
	.filename		= $ - FILE_STRUCTURE
				times 16 db 0

FILE_STRUCTURE_SIZE		= $ - FILE_STRUCTURE
MAXIMUM_FILES			= 256			; OS can open up to 256 files
FILE_STRUCTURE_MEMORY		= MAXIMUM_FILES*FILE_STRUCTURE_SIZE

file_structure			dq 0
open_files			dq 0
disk_buffer			dq 0

; init_vfs:
; Initializes the virtual file system

init_vfs:
	mov rsi, .starting_msg
	call kprint

	; set the boot partition
	mov al, [bootdisk]
	mov ah, 0
	call set_system_root
	jmp .allocate_mem

	; First, we need to determine the boot partition
	mov al, [bootdisk]
	mov rbx, 0
	mov rcx, 1
	mov rdi, mbr_tmp
	call read_sectors
	jc .no_boot

	mov rsi, boot_partition
	mov rdi, mbr_tmp+0x1BE
	mov rax, 0
	mov rcx, 4

.find_boot_partition:
	pushaq
	mov rcx, 16
	rep cmpsb
	je .found_boot_partition
	popaq

	inc rax
	loop .find_boot_partition
	jmp .no_boot

.found_boot_partition:
	mov ah, al		; boot partition
	mov al, [bootdisk]	; boot drive
	call set_system_root

	popaq

.allocate_mem:
	; Allocate memory for file structures
	mov rax, 0
	mov rbx, FILE_STRUCTURE_MEMORY
	mov dl, 7				; users can access the files
	call kmalloc
	cmp rax, 0
	je .no_memory_file

	mov [file_structure], rax

	; Allocate memory for disk buffer
	mov rax, 0
	mov rbx, 0x200000			; allocate 2 MB
	mov dl, 3
	call kmalloc
	cmp rax, 0
	je .no_memory_buffer

	mov [disk_buffer], rax

	mov rsi, .disk_buffer_msg
	call kprint
	mov rax, [disk_buffer]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	; calculate drive speed
	;mov rax, [timer_ticks]
	;mov [.ticks], rax

	;mov al, [bootdisk]
	;mov rbx, 0
	;mov rcx, 4096
	;mov rdi, [disk_buffer]
	;call read_sectors
	;jc .no_speed

	;mov rax, [timer_ticks]
	;sub rax, [.ticks]
	;shr rax, 2
	;mov [.ticks], rax

	;mov rsi, .speed_msg
	;call kprint
	;mov rax, [.ticks]
	;call int_to_string
	;call kprint
	;mov rsi, .speed_msg2
	;call kprint

	ret

.no_speed:
	mov rsi, .no_speed_msg
	call kprint

	mov rsi, .no_speed_msg
	call start_debugging

	jmp $

.no_boot:
	mov rsi, .no_boot_partition
	call kprint

	mov rsi, .no_boot_partition
	call start_debugging

	jmp $

.no_memory_file:
	mov rsi, .no_memory_file_msg
	call kprint

	mov rsi, .no_memory_file_msg
	call start_debugging

	jmp $

.no_memory_buffer:
	mov rsi, .no_memory_buffer_msg
	call kprint

	mov rsi, .no_memory_buffer_msg
	call start_debugging

	jmp $

.starting_msg			db "[vfs] initializing virtual file system...",10,0
.disk_buffer_msg		db "[vfs] disk buffer is at 0x",0
.no_boot_partition		db "[vfs] unable to determine the boot partition...",10,0
.no_memory_file_msg		db "[vfs] not enough memory for file tables!",10,0
.no_memory_buffer_msg		db "[vfs] not enough memory for disk I/O buffer!",10,0
.speed_msg			db "[vfs] bootdisk is capable of 1 MB/",0
.speed_msg2			db " hundredths of seconds.",10,0
.dot				db ".",0
.no_speed_msg			db "[vfs] unable to determine drive speed.",10,0
.seconds			dq 0
.microseconds			dq 0
.ticks				dq 0

; set_system_root:
; Sets the system root
; In\	AL = Logical drive number
; In\	AH = Partition number, 0xFF for CD/DVD
; Out\	RFLAGS = Carry set if drive/partition doesn't exist

set_system_root:
	cmp al, 33
	jg .no

	;cmp ah, 0xFF			; unfortunately there's still no support for CDs and DVDs..
	;je .no_partition

	cmp ah, 3
	jg .no

	push rax
	mov rdi, mbr_tmp
	mov rbx, 0
	mov rcx, 0			; read the master boot record
	call read_sectors
	pop rax
	jc .no

	mov [system_root_drive], al
	mov [system_root_partition], ah

	mov rsi, mbr_tmp
	add rsi, 0x1BE
	movzx rax, [system_root_partition]
	shl rax, 4			; mul 16
	add rsi, rax
	mov rdi, system_root_partition_table
	mov rcx, 16
	rep movsb

	mov rsi, .done_msg
	call kprint
	movzx rax, [system_root_drive]
	call int_to_string
	call kprint
	mov rsi, .done_msg2
	call kprint
	movzx rax, [system_root_partition]
	call int_to_string
	call kprint
	mov rsi, .done_msg3
	call kprint
	mov al, [system_root_partition_table.type]
	call hex_byte_to_string
	call kprint
	mov rsi, .done_msg4
	call kprint
	mov rax, 0
	mov eax, [system_root_partition_table.size]
	shr rax, 11
	call int_to_string
	call kprint
	mov rsi, .done_msg5
	call kprint

	clc
	ret

.no:
	stc
	ret

.done_msg			db "[vfs] set system root to drive ",0
.done_msg2			db " partition ",0
.done_msg3			db " type 0x",0
.done_msg4			db " size ",0
.done_msg5			db " MB.",10,0

; get_free_file:
; Returns a pointer to a free file structure
; In\	Nothing
; Out\	RAX = File handle

get_free_file:
	pushaq

	mov rsi, [file_structure]
	add rsi, FILE_STRUCTURE_MEMORY
	mov [.end], rsi
	sub rsi, FILE_STRUCTURE_MEMORY

.loop:
	cmp rsi, [.end]
	jge .no
	cmp byte[rsi], 0
	je .found
	add rsi, FILE_STRUCTURE_SIZE
	jmp .loop

.found:
	push rsi
	mov rdi, rsi
	mov rax, 0
	mov rcx, FILE_STRUCTURE_SIZE
	rep stosb
	pop rsi

	sub rsi, [file_structure]
	mov rax, rsi
	mov rbx, FILE_STRUCTURE_SIZE
	mov rdx, 0
	div rbx
	mov [.return], rax

	popaq
	mov rax, [.return]
	ret

.no:
	popaq
	mov rax, -1
	ret

.end				dq 0
.return				dq 0

; create_file_structure:
; Creates the file structure in memory
; In\	RAX = File handle
; In\	RBX = Position in file
; In\	RCX = Size of file
; In\	RSI = File name
; Out\	Nothing

create_file_structure:
	pushaq
	mov [.file], rax
	mov [.pos], rbx
	mov [.size], rcx
	mov [.flags], rdx
	mov [.filename], rsi

	mov rax, [.file]
	mov rbx, FILE_STRUCTURE_SIZE
	mul rbx
	add rax, [file_structure]
	mov byte[rax], 1				; mark the file structure as used
	mov rbx, [.flags]
	mov qword[rax+FILE_STRUCTURE.flags], rbx
	mov rbx, [.pos]
	mov qword[rax+FILE_STRUCTURE.position], rbx
	mov rbx, [.size]
	mov qword[rax+FILE_STRUCTURE.size], rbx

	mov rdi, rax
	add rdi, FILE_STRUCTURE.filename
	push rdi

	mov rsi, [.filename]
	call get_string_size
	mov rcx, rax
	mov rsi, [.filename]
	pop rdi
	rep movsb
	mov al, 0
	stosb

	popaq
	ret
.file				dq 0
.pos				dq 0
.size				dq 0
.filename			dq 0
.flags				dq 0

; open:
; Opens a file
; In\	RSI = Filename
; In\	RDX = Flags (bit 0 = read, bit 1 = write)
; Out\	RAX = File handle, -1 on error

open:
	pushaq
	mov [.filename], rsi
	mov [.flags], rdx

	cmp [open_files], MAXIMUM_FILES
	jge .error

	mov rsi, [.filename]
	call get_file_size
	cmp rax, -1
	je .error

	mov rsi, .starting_msg
	call kprint
	mov rsi, [.filename]
	call kprint

	; If the file exists, we need to place it in the file structure
	call get_free_file
	mov [.file], rax

	mov rsi, .starting_msg2
	call kprint
	mov rax, [.file]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, [.filename]
	call get_file_size
	mov rcx, rax			; file size
	mov rsi, [.filename]		; file name
	mov rbx, 0			; position, start at the beginning of the file
	mov rax, [.file]		; file handle
	mov rdx, [.flags]		; flags
	call create_file_structure

	inc [open_files]
	popaq
	mov rax, [.file]
	ret

.error:
	popaq
	mov rax, -1
	ret

.filename			dq 0
.file				dq 0
.flags				dq 0
.starting_msg			db "[fs] opening file ",0
.starting_msg2			db ", file handle is ",0

; close:
; Closes a file
; In\	RAX = File handle
; Out\	RAX = 0

close:
	pushaq
	mov [.handle], rax

	cmp [open_files], 0
	je .done

	mov rsi, .starting_msg
	call kprint
	mov rax, [.handle]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rax, [.handle]
	mov rbx, FILE_STRUCTURE_SIZE
	mul rbx
	add rax, [file_structure]
	mov rdi, rax
	mov rax, 0
	mov rcx, FILE_STRUCTURE_SIZE
	rep stosb

	dec [open_files]

.done:
	popaq
	mov rax, 0
	ret

.handle				dq 0
.starting_msg			db "[fs] closing file handle ",0

; seek:
; Moves position in a file
; In\	RAX = File handle
; In\	RCX = Position to set, -1 to request file size
; Out\	RAX = 0 on success, -1 on error, file size if RCX = -1

seek:
	pushaq
	mov [.handle], rax
	mov [.pos], rcx

	mov rax, [.handle]
	mov rbx, FILE_STRUCTURE
	mul rbx
	mov rdi, [file_structure]
	add rdi, rax
	mov [.file_struct], rdi

	mov rsi, [.file_struct]
	test byte[rsi], 1			; is file is not present?
	jz .error

	mov rcx, [.pos]
	cmp rcx, -1				; did the user request size?
	je .get_size

	mov rsi, [.file_struct]
	add rsi, FILE_STRUCTURE.size
	mov rax, [rsi]
	cmp [.pos], rax				; is position is larger than file --
	jge .error				; -- we will likely page fault!

	mov rsi, [.file_struct]
	add rsi, FILE_STRUCTURE.position
	mov rax, [.pos]
	mov [rsi], rax

.done:
	popaq
	mov rax, 0
	ret

.get_size:
	mov rsi, [.file_struct]
	add rsi, FILE_STRUCTURE.size
	mov rax, [rsi]
	mov [.pos], rax
	popaq
	mov rax, [.pos]				; return size of file
	ret

.error:
	popaq
	mov rax, -1
	ret

.handle				dq 0
.pos				dq 0
.file_struct			dq 0

; read:
; Reads bytes from a file
; In\	RAX = File handle
; In\	RCX = Bytes to read
; In\	RDI = Buffer to read files
; Out\	RAX = Number of bytes read, -1 on error

read:
	pushaq
	mov [.handle], rax
	mov [.bytes], rcx
	mov [.buffer], rdi

	mov rax, [.handle]
	mov rbx, FILE_STRUCTURE_SIZE
	mul rbx
	mov rdi, [file_structure]
	add rdi, rax
	mov [.file_struct], rdi

	mov rsi, [.file_struct]
	test byte[rsi], 1			; is file opened?
	jz .error				; nope -- can't read from a file that doesn't exist!

	mov rsi, [.file_struct]
	test qword[rsi+FILE_STRUCTURE.flags], 1	; is file readable?
	jz .error				; "Access denied"

	mov rsi, [.file_struct]
	add rsi, FILE_STRUCTURE.filename
	call load_file_bytes
	cmp rax, -1
	je .error

	mov [.file_loc], rax
	mov [.file_size], rcx

	mov rsi, [.file_struct]
	add rsi, FILE_STRUCTURE.position
	mov rax, [rsi]
	mov [.position], rax
	add rax, [.bytes]
	cmp rax, [.file_size]
	jg .error

	mov rsi, [.file_loc]
	add rsi, [.position]
	mov rdi, [.buffer]
	mov rcx, [.bytes]
	call memcpy			; nice SSE/AVX memcpy ;)

	mov rsi, [.file_struct]
	mov rax, [.bytes]
	add [rsi+FILE_STRUCTURE.position], rax	; update the position

	mov rax, [.file_loc]
	mov rbx, [.file_size]
	call kfree

	popaq
	mov rax, [.bytes]
	ret

.error:
	popaq
	mov rax, -1
	ret

.handle				dq 0
.bytes				dq 0
.buffer				dq 0
.file_struct			dq 0
.file_size			dq 0
.file_loc			dq 0
.position			dq 0




