
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Advanced Host Controller Interface Driver",0

;; Functions:
; ahci_detect
; ahci_detect_ports
; ahci_check_port
; ahci_get_port_base

use64
ahci_available_ports		db 0
ahci_ports			dd 0
ahci_base_phys			dq 0
ahci_pci_bus			db 0
ahci_pci_device			db 0
ahci_pci_function		db 0
ahci_base			dq AHCI_BASE
AHCI_BASE			= 0x300000000

; ahci_detect:
; Detects SATA (AHCI) drives

ahci_detect:
	mov rsi, .starting_msg
	call kprint

	mov ax, 0x106
	call pci_get_device_class		; search for PCI AHCI controller
	cmp ax, 0xFFFF
	je .no_ahci

	mov [ahci_pci_bus], al
	mov [ahci_pci_device], ah
	mov [ahci_pci_function], bl

	mov rsi, .found_msg
	call kprint
	mov al, [ahci_pci_bus]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [ahci_pci_device]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [ahci_pci_function]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 0x24				; BAR5
	call pci_read_dword
	and eax, 0xFFFFFFF0
	mov dword[ahci_base_phys], eax

	; now map the AHCI base memory to the virtual address space
	mov rax, [ahci_base_phys]
	and eax, 0xFFE00000
	mov rbx, AHCI_BASE
	mov rcx, 2
	mov dl, 3
	call vmm_map_memory

	mov rax, [ahci_base_phys]
	mov rbx, 0x200000
	call round_backward

	mov rbx, [ahci_base_phys]
	sub rbx, rax
	add [ahci_base], rbx

	mov rsi, .base_msg
	call kprint
	mov rax, [ahci_base_phys]
	call hex_dword_to_string
	call kprint
	mov rsi, .base_msg2
	call kprint
	mov rax, [ahci_base]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	call ahci_detect_ports

	; enable PCI busmaster DMA
	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 4
	call pci_read_dword
	mov edx, eax
	or edx, 4
	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 4
	call pci_write_dword

	ret				; for now, because I didn't finish AHCI yet..

.no_ahci:
	mov rsi, .no_msg
	call kprint
	ret

.starting_msg			db "[ahci] looking for PCI AHCI controller...",10,0
.no_msg				db "[ahci] AHCI controller not found.",10,0
.found_msg			db "[ahci] found AHCI controller at PCI slot ",0
.base_msg			db "[ahci] base memory is at physical 0x",0
.base_msg2			db ", virtual 0x",0
.colon				db ":",0

; ahci_detect_ports:
; Detects available AHCI ports

ahci_detect_ports:
	mov rsi, [ahci_base]
	add rsi, 0x0C
	mov eax, [rsi]
	mov [ahci_ports], eax

	mov cl, 0

.loop:
	cmp cl, 32
	jge .done

	call ahci_check_port
	jc .no_port

	inc [ahci_available_ports]
	inc cl
	jmp .loop

.no_port:
	inc cl
	jmp .loop

.done:
	mov rsi, .msg
	call kprint
	movzx rax, [ahci_available_ports]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	ret

.msg				db "[ahci] total of ",0
.msg2				db " ports available.",10,0

; ahci_check_port:
; Checks if an AHCI port is present
; In\	CL = Port number (0 => 31)
; Out\	RFLAGS.CF = Clear if port is present

ahci_check_port:
	mov eax, 1
	shl eax, cl
	test [ahci_ports], eax
	jz .no

	clc
	ret

.no:
	stc
	ret

; ahci_get_port_base:
; Returns address of an AHCI port within the AHCI base memory
; In\	CL = Port number (0 => 31)
; Out\	RAX = Virtual address of AHCI port data

ahci_get_port_base:
	movzx rax, cl
	shl rax, 7		; mul 128
	add rax, 0x100
	add rax, [ahci_base]
	ret






