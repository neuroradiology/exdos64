
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ExDOS driver abstraction layer",0

DRIVER_LOAD_ADDRESS		= 0x4000000			; drivers are loaded at 64 MB

kernel_config_file		db "kernel.cfg",0
kernel_config			dq 0
kernel_config_size		dq 0
is_driver_running		db 0
driver_stack			dq 0
driver_terminate_point		dq 0

network_driver:			times 16 db 0
sound_driver:			times 16 db 0
usb_driver:			times 16 db 0

; load_drivers:
; Initializes all drivers as stated in the file "kernel.cfg"

load_drivers:
	mov rsi, .starting_msg
	call kprint

	; Allocate a stack for drivers
	mov rax, 0
	mov rcx, 0x200000		; 2 MB stack
	mov dl, 7
	call kmalloc
	cmp rax, 0
	je .no_memory
	add rax, 0x200000
	mov [driver_stack], rax

	mov rsi, kernel_config_file
	mov rdx, 1
	call open			; open the kernel configuration file for reading

	cmp rax, -1
	je .no_config

	mov [.handle], rax

	; get file size
	mov rax, [.handle]
	mov rcx, -1
	call seek
	mov [kernel_config_size], rax

	mov rax, 0
	mov rbx, [kernel_config_size]
	mov dl, 3
	call kmalloc
	cmp rax, 0
	je .no_memory
	mov [kernel_config], rax

	mov rax, [.handle]
	mov rcx, [kernel_config_size]
	mov rdi, [kernel_config]
	call read				; read the file
	cmp rax, -1
	je .no_config

	mov rax, [.handle]
	call close				; close the file

	mov rsi, [kernel_config]
	add rsi, [kernel_config_size]
	mov [.eof], rsi

	mov rsi, [kernel_config]
	mov rdi, .signature
	mov rcx, 10
	rep cmpsb
	jne .no_config

	mov rsi, [kernel_config]
	mov dl, 10
	mov dh, 0
	call replace_byte_in_string

	mov rsi, [kernel_config]
	add rsi, 10

.load_drivers_loop:
	pushaq
	mov rdi, .driver_entry
	mov rcx, 7
	rep cmpsb
	je .found_driver_entry
	popaq
	inc rsi
	cmp rsi, [.eof]
	je .done
	jmp .load_drivers_loop

.found_driver_entry:
	; RSI is now a pointer to a driver entry
	call load_driver

	popaq
	inc rsi
	jmp .load_drivers_loop

.done:
	ret

.no_config:
	mov rsi, .no_config_msg
	call kprint

	ret

.no_memory:
	mov rsi, .no_memory_msg
	call kprint

	ret

.handle				dq 0
.eof				dq 0
.starting_msg			db "[drivers] initializing driver subsystem...",10,0
.no_config_msg			db "[drivers] warning: unable to read the kernel configuration file.",10,0
.no_memory_msg			db "[drivers] warning: not enough memory to perform driver initialization...",10,0
.signature			db "[exdos64]",10
.driver_entry			db "driver="

; load_driver:
; Loads a driver
; In\	RSI = ASCIIZ file name
; Out\	Nothing

load_driver:
	pushaq
	mov [.filename], rsi

	mov rsi, .starting_msg
	call kprint
	mov rsi, [.filename]
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, [.filename]
	mov rdx, 1
	call open
	cmp rax, -1
	je .error
	mov [.handle], rax

	mov rax, [.handle]
	mov rcx, -1
	call seek
	mov [.size], rax

	mov rax, 0
	mov rcx, [.size]
	call pmm_malloc

	cmp rax, 0
	je .error
	mov [.physical], rax

	mov rax, [.size]
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [.pages], rax

	mov rax, [.physical]
	mov rbx, DRIVER_LOAD_ADDRESS
	mov rcx, [.pages]
	mov dl, 7			; drivers run in user mode
	call vmm_map_memory

	mov rax, [.handle]
	mov rcx, [.size]
	mov rdi, DRIVER_LOAD_ADDRESS
	call read

	mov rsi, DRIVER_LOAD_ADDRESS
	mov rdi, .signature
	mov rcx, 7
	rep cmpsb
	jne .error

	mov rsi, DRIVER_LOAD_ADDRESS+APPLICATION_HEADER.version
	cmp byte[rsi], 1
	jne .error

	mov rsi, DRIVER_LOAD_ADDRESS+APPLICATION_HEADER.type
	cmp byte[rsi], 2
	jne .error

	mov rsi, .starting_msg2
	call kprint

	mov rax, DRIVER_LOAD_ADDRESS+APPLICATION_HEADER.program_name
	mov rsi, [rax]
	call kprint

	mov rsi, newline
	call kprint

	mov rax, [.handle]
	call close

	mov [.kstack], rsp
	mov [is_driver_running], 1
	mov [driver_terminate_point], .done

	call enter_usermode
	mov rsp, [driver_stack]
	mov rax, DRIVER_LOAD_ADDRESS+APPLICATION_HEADER.entry_point
	mov rbp, [rax]
	push rbp
	mov rsi, [.filename]
	mov rax, 1
	ret

.done:
	mov rsp, [.kstack]
	mov [is_driver_running], 0
	popaq
	ret

.error:
	mov rsi, .error_msg
	call kprint
	popaq
	ret

.filename			dq 0
.starting_msg			db "[drivers] loading driver ",0
.starting_msg2			db "[drivers] found driver for ",0
.error_msg			db "[drivers] error while loading driver.",10,0
.signature			db "ExDOS64"
.handle				dq 0
.size				dq 0
.pages				dq 0
.physical			dq 0
.kstack				dq 0

DRIVER_API_CALLS		= 0x1D

; driver_api:
; Driver API

driver_api:
	mov [.return], rcx

	cmp r15, DRIVER_API_CALLS
	jg .bad

	shl r15, 3
	add r15, .table
	mov rbp, [r15]
	call rbp

	call enter_usermode
	mov r15, [.return]
	jmp r15

.bad:
	call enter_usermode
	mov rax, [.return]
	push rax
	mov rax, -1
	ret

.tmp_rax			dq 0
.return				dq 0
.table:				dq exit_driver				; 00
				dq kprint				; 01
				dq outportb				; 02
				dq outportw				; 03
				dq outportd				; 04
				dq inportb				; 05
				dq inportw				; 06
				dq inportd				; 07
				dq pci_read_dword			; 08
				dq pci_write_dword			; 09
				dq pci_get_device_class			; 0A
				dq pci_get_device_vendor		; 0B
				dq pci_get_buses			; 0C
				dq kmalloc				; 0D
				dq kfree				; 0E
				dq hex_byte_to_string			; 0F
				dq hex_word_to_string			; 10
				dq hex_dword_to_string			; 11
				dq hex_qword_to_string			; 12
				dq pit_sleep				; 13
				dq install_driver_irq			; 14
				dq read_sectors				; 15
				dq 0 ; dq write_sectors			; 16
				dq open					; 17
				dq close				; 18
				dq seek					; 19
				dq read					; 1A
				dq 0 ; dq write				; 1B
				dq register_driver			; 1C
				dq vmm_get_physical_address		; 1D

; exit_driver:
; Terminate a driver

exit_driver:
	mov [is_driver_running], 0
	mov rax, [driver_terminate_point]
	jmp rax

; outportb:
; Sends a byte to a port
; In\	AL = Byte
; In\	DX = Port
; Out\	Nothing

outportb:
	out dx, al
	call iowait
	ret

; outportw:
; Sends a word to a port
; In\	AX = Word
; In\	DX = Port
; Out\	Nothing

outportw:
	out dx, ax
	call iowait
	ret

; outportd:
; Sends a dword to a port
; In\	EAX = DWORD
; In\	DX = Port
; Out\	Nothing

outportd:
	out dx, eax
	call iowait
	ret

; inportb:
; Gets a byte from a port
; In\	DX = Port
; Out\	AL = Byte

inportb:
	in al, dx
	call iowait
	ret

; inportw:
; Gets a word from a port
; In\	DX = Port
; Out\	AX = Word

inportw:
	in ax, dx
	call iowait
	ret

; inportd:
; Gets a DWORD from a port
; In\	DX = Port
; Out\	EAX = DWORD

inportd:
	in eax, dx
	call iowait
	ret

; install_driver_irq:
; Installs a driver IRQ handler
; In\	AL = IRQ number
; In\	RSI = Driver file name
; Out\	Nothing

install_driver_irq:
	pushaq
	mov [.filename], rsi

	mov [.irq], al
	and rax, 0xFF
	add al, 0x20
	mov rbp, driver_irq_handler
	call install_isr

	int 0x21

	popaq
	ret

	mov rsi, [.filename]
	call get_string_size
	mov rcx, rax
	mov rsi, [.filename]
	mov rdi, driver_irq_handler
	rep movsb
	mov al, 0
	stosb

	mov rsi, .msg
	call kprint
	movzx rax, [.irq]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	popaq
	ret

.irq				db 0
.msg				db "[drivers] install handler for IRQ ",0
.filename			dq 0

; driver_irq_handler:
; Driver IRQ handler stub

driver_irq_handler:
	pushaq

	mov ax, 0x30
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	in al, 0x60

	mov rsi, .msg
	mov cx, 48
	mov dx, 48
	call print_string_cursor

	call send_eoi
	popaq
	iretq

.filename:			times 16 db 0
.msg				db "[drivers] IRQ!",10,0

; register_driver:
; Registers a driver
; In\	AL = Type (0 -- network, 1 -- sound, 2 -- USB)
; In\	RSI = File name
; Out\	RAX = -1 on success

register_driver:
	cmp al, 0
	je .network

	cmp al, 1
	je .sound

	cmp al, 2
	je .usb

	mov rax, -1
	ret

.network:
	call get_string_size
	mov rcx, rax
	mov rdi, network_driver
	call memcpy
	mov rax, 0
	ret

.sound:
	call get_string_size
	mov rcx, rax
	mov rdi, sound_driver
	call memcpy
	mov rax, 0
	ret

.usb:
	call get_string_size
	mov rcx, rax
	mov rdi, usb_driver
	call memcpy
	mov rax, 0
	ret




