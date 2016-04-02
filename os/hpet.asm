
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "High Precision Event Timer Driver",0

;; Functions:
; init_hpet
; hpet_read_register
; hpet_write_register
; hpet_irq
; timer_irq_common

hpet_freq				dq 0
HPET_MEMORY				= 0x200000000
hpet_base				dq HPET_MEMORY
hpet_divider				dq 0

;;
;; HPET Registers
;;

HPET_REGISTER_CAPABILITIES		= 0
HPET_GENERAL_CONFIGURATION		= 0x10
HPET_INTERRUPT_STATUS			= 0x20
HPET_MAIN_COUNTER			= 0xF0
HPET_TIMER0_CAPABILITIES		= 0x120
HPET_TIMER0_COMPARATOR			= 0x128

; init_hpet:
; Initializes the HPET

init_hpet:
	mov rsi, .starting_msg
	call kprint

	mov rsi, .hpet_table
	call acpi_find_table		; find the ACPI HPET table
	cmp rsi, 0
	je .no
	mov rdi, hpet_table
	mov rcx, HPET_TABLE_SIZE
	rep movsb

	mov rsi, .base_msg
	call kprint
	mov rax, [hpet_table.address]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	; map the HPET into the virtual address space
	mov rax, [hpet_table.address]
	and eax, 0xFFE00000
	mov rbx, HPET_MEMORY
	mov rcx, 2
	mov dl, 3
	call vmm_map_memory

	mov rax, [hpet_table.address]
	mov rbx, 0x200000
	call round_backward

	mov rbx, [hpet_table.address]
	sub rbx, rax
	add [hpet_base], rbx

	mov rsi, .vendor_msg
	call kprint

	mov rcx, HPET_REGISTER_CAPABILITIES
	call hpet_read_register
	shr rax, 16
	and rax, 0xFFFF
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

	; disable the HPET
	mov rax, 0
	mov rcx, HPET_GENERAL_CONFIGURATION
	call hpet_write_register

	; edge-trigger interrupts
	mov rcx, HPET_INTERRUPT_STATUS
	mov rax, 0
	call hpet_write_register

	; calculate the HPET frequency
	mov rcx, HPET_REGISTER_CAPABILITIES
	call hpet_read_register
	shr rax, 32
	mov rbx, rax
	mov rax, 0x38D7EA4C68000
	mov rdx, 0
	div rbx
	mov [hpet_freq], rax

	; debugging...
	mov rsi, .freq_msg
	call kprint
	mov rax, [hpet_freq]
	call int_to_string
	call kprint
	mov rsi, .freq_msg2
	call kprint

	; well, now we have enough information to disable the PIT and start using the HPET
	call disable_pit
	call disable_interrupts

	; install IRQ handler
	mov al, 0
	mov rbp, hpet_irq
	call install_irq

	; enable edge-trigger interrupts for HPET timer #0
	mov rcx, HPET_TIMER0_CAPABILITIES
	call hpet_read_register
	mov eax, 0x10C
	mov rcx, HPET_TIMER0_CAPABILITIES
	call hpet_write_register

	mov rax, [hpet_freq]
	mov rdx, 0
	mov rbx, TIMER_FREQUENCY
	div rbx
	mov [hpet_divider], rax
	mov rcx, HPET_TIMER0_COMPARATOR
	call hpet_write_register

	mov rax, 0
	mov rcx, HPET_MAIN_COUNTER
	call hpet_write_register

	; enable the HPET
	mov rax, 1
	mov rcx, HPET_GENERAL_CONFIGURATION
	call hpet_write_register

	mov rsi, .done_msg
	call kprint
	mov rax, TIMER_FREQUENCY
	call int_to_string
	call kprint
	mov rsi, .freq_msg2
	call kprint

	ret

.no:
	mov rsi, .no_msg
	call kprint

	ret

.hpet_table			db "HPET"
.starting_msg			db "[hpet] initializing HPET...",10,0
.no_msg				db "[hpet] HPET not present, falling back to PIT...",10,0
.base_msg			db "[hpet] HPET base address is 0x",0
.vendor_msg			db "[hpet] HPET vendor ID is ",0
.freq_msg			db "[hpet] HPET frequency is ",0
.done_msg			db "[hpet] finished, HPET set up to ",0
.freq_msg2			db " Hz.",10,0

; hpet_read_register:
; Reads a HPET register
; In\	RCX = Register number
; Out\	RAX = Value from register

hpet_read_register:
	add rcx, [hpet_base]
	mov rax, [rcx]
	ret

; hpet_write_register:
; Writes to a HPET register
; In\	RAX = Value to write
; In\	RCX = Register number
; Out\	Nothing

hpet_write_register:
	add rcx, [hpet_base]
	mov [rcx], rax
	call flush_caches
	ret

; hpet_irq:
; HPET IRQ handler
align 16
hpet_irq:
	pushaq
	call timer_irq_common

	mov rax, 0
	mov rcx, HPET_MAIN_COUNTER
	call hpet_write_register

	popaq
	call send_eoi
	iretq

; timer_irq_common:
; Common stub for timer IRQs
align 16
timer_irq_common:
	inc [timer_ticks]
	inc [.tmp]
	cmp [.tmp], TIMER_FREQUENCY
	je .second

	ret

.second:
	mov [.tmp], 0
	call cmos_update
	ret

.tmp				dq 0

; hpet_table:
; HPET table
align 16
hpet_table:
	; ACPI SDT Header
	.signature:		times 4 db 0
	.length			dd 0
	.revision		db 0
	.checksum		db 0
	.oemid:			times 6 db 0
	.oem_table_id		dq 0
	.oem_revision		dd 0
	.creator_id		dd 0
	.creator_revision	dd 0

	; HPET information
	.event_timer_id		dd 0

	.address_space_id	db 0
	.register_bit_width	db 0
	.register_bit_offset	db 0
	.reserved		db 0
	.address		dq 0

	.hpet_number		db 0
	.minimum_tick		dw 0
	.page_protection	db 0

HPET_TABLE_SIZE			= $ - hpet_table

