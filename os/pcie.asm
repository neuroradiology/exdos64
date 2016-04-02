
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "PCI Express bus scanner",0

;; Functions:
; init_pcie
; generate_pcie_address
; pcie_read_dword
; pcie_write_dword

is_there_pcie			db 0
acpi_mcfg			dq 0
end_mcfg			dq 0
pcie_allocation_structures	dq 0
pcie_buses			db 0
pcie_base			dq 0

PCIE_BASE_VIRTUAL		= 0x140000000

; init_pcie:
; Detects PCI-E

init_pcie:
	mov rsi, .starting_msg
	call kprint

	; Find the ACPI MCFG table
	mov rsi, .mcfg
	call acpi_find_table
	cmp rsi, 0
	je .no_pcie
	mov [acpi_mcfg], rsi

	mov rsi, [acpi_mcfg]
	mov rax, 0
	mov eax, [rsi+4]
	sub rax, 44
	shr rax, 4		; div 16
	cmp rax, 0
	je .no_pcie

	mov [pcie_allocation_structures], rax

	mov rsi, .found_msg
	call kprint

	mov rsi, [acpi_mcfg]
	add rsi, 44

.decode_buses:
	mov rcx, [.current_structure]
	cmp rcx, [pcie_allocation_structures]
	jge .done

	push rsi

	mov rsi, .bus_msg
	call kprint

	pop rsi
	push rsi

	mov al, [rsi+11]
	sub al, byte[rsi+10]
	inc al
	add [pcie_buses], al

	movzx rax, byte[rsi+10]
	call int_to_string
	call kprint

	pop rsi
	push rsi
	mov rsi, .bus_msg2
	call kprint

	pop rsi
	push rsi

	movzx rax, byte[rsi+11]
	call int_to_string
	call kprint

	pop rsi
	push rsi

	mov rsi, .bus_msg3
	call kprint

	pop rsi
	push rsi

	mov rax, [rsi]
	mov [pcie_base], rax
	push rax
	and eax, 0xFFE00000
	mov rbx, PCIE_BASE_VIRTUAL
	mov rcx, 16			; 32 MB
	mov dl, 3
	call vmm_map_memory

	pop rax
	call hex_qword_to_string
	call kprint

	mov rsi, newline
	call kprint

	pop rsi
	add rsi, 16
	inc [.current_structure]
	jmp .decode_buses

.done:
	mov rsi, .done_msg
	call kprint

	movzx rax, [pcie_buses]
	call int_to_string
	call kprint

	mov rsi, .done_msg2
	call kprint

	mov [is_there_pcie], 1		; tell the PCI code to use PCI-E instead of traditional PCI
	ret

.no_pcie:
	mov rsi, .no_pcie_msg
	call kprint

	mov [is_there_pcie], 0
	ret

.mcfg				db "MCFG"
.starting_msg			db "[pcie] initializing PCI-E...",10,0
.found_msg			db "[pcie] PCI-E is supported.",10,0
.bus_msg			db "[pcie] bus ",0
.bus_msg2			db "-",0
.bus_msg3			db " at memory address 0x",0
.no_pcie_msg			db "[pcie] warning: PCI-E is not present, using parallel PCI bus...",10,0
.current_structure		dq 0
.done_msg			db "[pcie] done, ",0
.done_msg2			db " buses present.",10,0

; generate_pcie_address:
; Returns the memory-mapped I/O address of the PCI-E configuration space
; In\	AL = Bus number
; In\	AH = Slot number
; In\	BL = Function
; In\	BH = Offset
; Out\	RDI = Virtual address of PCI-E configuration space

generate_pcie_address:
	pushaq
	mov [.bus], al
	mov [.slot], ah
	mov [.function], bl
	mov [.offset], bh

	mov rdi, 0
	movzx rax, [.bus]
	shl rax, 20
	or rdi, rax

	movzx rax, [.slot]
	shl rax, 15
	or rdi, rax

	movzx rax, [.function]
	shl rax, 12
	or rdi, rax

	movzx rax, [.offset]
	;shl rax, 2
	or rdi, rax

	mov rax, PCIE_BASE_VIRTUAL
	add rdi, rax
	mov [.tmp], rdi
	popaq
	mov rdi, [.tmp]
	ret

.bus				db 0
.slot				db 0
.function			db 0
.offset				db 0
.tmp				dq 0

; pcie_read_dword:
; Reads a DWORD from the PCI-E configuration space
; In\	AL = Bus number
; In\	AH = Slot
; In\	BL = Function
; In\	BH = Offset
; Out\	EAX = DWORD from PCI-E configuration space

pcie_read_dword:
	pushaq
	call generate_pcie_address
	mov eax, [rdi]
	mov [.tmp], eax
	popaq
	mov eax, [.tmp]
	ret

.tmp			dd 0

; pcie_write_dword:
; Writes a DWORD to the PCI-E configuration space
; In\	AL = Bus number
; In\	AH = Slot
; In\	BL = Function
; In\	BH = Offset
; In\	EDX = DWORD
; Out\	Nothing

pcie_write_dword:
	pushaq
	push rdx
	call generate_pcie_address
	pop rdx
	mov [rdi], edx
	call flush_caches
	popaq
	ret


