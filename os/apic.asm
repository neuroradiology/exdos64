
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "SMP & APIC implementation",0

;; 
;; This file contains SMP, local APIC and I/O APIC routines, using ACPI's MADT table for information.
;; The Intel MP tables are not supported.
;; It also has a legacy PIC driver as a fallback, for systems that don't have the I/O APIC for interrupt redirection.
;; 

;; Functions:
; init_smp
; ap_init
; init_ioapic
; calculate_cpu_speed
; init_pic
; remap_pic
; ioapic_setup_irqs
; ioapic_remap_irqs
; install_irq
; ioapic_read_register
; ioapic_write_register
; ioapic_init_irq
; send_eoi
; enable_interrupts
; disable_interrupts
; lapic_read_register
; lapic_write_register
; master_pic_cascade_irq
; master_pic_spurious_irq
; slave_pic_spurious_irq
; mask_irq
; unmask_irq
; restore_bios_pic

MAXIMUM_CPUS			= 16			; use up to 16 CPUs
TIMER_FREQUENCY			= 1000			; system heartbeat frequency
IOAPIC_IRQ_BASE			= 0x30			; IRQs start at INT 0x30

local_apic			dq 0
apic_table			dq 0
number_of_cpus			dq 0
disabled_cpus			dq 0
number_of_ioapics		dq 0
list_of_cpus:			times MAXIMUM_CPUS+1 db 0xFF
list_of_ioapics:		times MAXIMUM_CPUS+1 dd 0xFFFFFFFF
list_of_ioapics_id:		times MAXIMUM_CPUS+1 db 0xFF
ap_interrupts_enabled		db 0
ioapic_enabled			db 0
spurious_irqs			dq 0
pic1_spurious_irqs		dq 0
pic2_spurious_irqs		dq 0
interrupt_remaps		db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,21,22,23,24
apic_timer_frequency		dq 0
cpu_speed			dq 0
using_ioapic			dq 0
bios_pic1_mask			db 0
bios_pic2_mask			db 0

; init_smp:
; Initializes all cores on the system

init_smp:
	mov rsi, .apic_table
	call acpi_find_table		; find the APIC table

	cmp rsi, 0
	je .no_smp			; we should fall back to the MP tables, but I don't feel like doing that..
					; anyway, any modern 64-bit PC should have ACPI support --
					; -- and either way ExDOS fails to boot without ACPI

.start:
	mov [apic_table], rsi
	call show_apic_table		; shows the information of the APIC table

	mov rsi, .starting_msg
	call kprint

	; enable the BSP's local APIC if it is not already enabled
	mov rcx, 0x1B
	rdmsr
	test eax, 0x800
	jz .enable_lapic

	and eax, 0xFFFFF000
	cmp eax, dword[local_apic]
	jne .enable_lapic
	cmp edx, 0
	jne .enable_lapic
	jmp .start_finding_cpus

.enable_lapic:
	mov rdx, 0
	mov rax, [local_apic]
	or rax, 0x900			; is a BSP
	mov rcx, 0x1B
	wrmsr

.start_finding_cpus:
	mov rsi, [apic_table]
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.table_end], rsi

	mov rsi, [apic_table]
	add rsi, 44
	mov [.table_start], rsi

.find_cpus:
	mov rsi, [.table_start]

.find_cpu_loop:
	cmp rsi, [.table_end]
	jge .found_all_cpus

	mov al, [rsi]
	cmp al, 0
	je .found_cpu

	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	cmp rsi, [.table_end]
	jge .found_all_cpus
	jmp .find_cpu_loop

.found_cpu:
	test dword[rsi+4], 1	; is the CPU enabled?
	jz .next_cpu

	push rsi
	mov al, [rsi+3]		; APIC ID
	mov rdi, [.list]
	stosb
	mov [.list], rdi
	pop rsi
	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	inc [number_of_cpus]
	cmp [number_of_cpus], MAXIMUM_CPUS
	jge .found_all_cpus
	jmp .find_cpu_loop

.next_cpu:
	inc [disabled_cpus]
	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	jmp .find_cpu_loop

.found_all_cpus:
	mov rsi, .total_cpus
	call kprint
	mov rax, [number_of_cpus]
	call int_to_string
	call kprint
	mov rsi, .total_cpus2
	call kprint
	mov rax, [disabled_cpus]
	call int_to_string
	call kprint
	mov rsi, .total_cpus3
	call kprint

	mov rsi, .cpu0_msg
	call kprint

	cmp [number_of_cpus], 1
	je .done

	mov rsi, list_of_cpus+1
	mov al, [rsi]

.loop:
	mov rax, 0
	mov al, [rsi]
	cmp al, 0xFF
	je .done

	pushaq
	mov rsi, .init_cpu
	call kprint

	mov rax, [.curr_cpu]
	call int_to_string
	call kprint

	mov rsi, newline
	call kprint
	popaq

	mov rax, 0
	mov al, [rsi]
	shl rax, 24
	mov rcx, 0x310
	call lapic_write_register		; send the APIC ID of the AP
	call flush_caches

	mov rax, 0x4500
	mov rcx, 0x300
	call lapic_write_register		; send INIT IPI
	call flush_caches

	mov rcx, 0xFFFF

.delay:
	nop
	nop
	;pause
	loop .delay

	mov rax, ap_init
	shr rax, 12
	or rax, 0x4600
	mov rcx, 0x300
	call lapic_write_register		; send SIPI
	call flush_caches

	mov rcx, 0
	not rcx

.wait_for_cpu:
	cmp [ap_init.done], 0
	jne .continue

	dec rcx
	cmp rcx, 0
	je .cpu_init_error

	nop
	nop
	nop
	nop
	;pause

	jmp .wait_for_cpu

.continue:
	mov byte[ap_init.done], 0
	inc rsi
	inc [.curr_cpu]

	cmp [.curr_cpu], MAXIMUM_CPUS
	jg .done
	jmp .loop

.done:
	mov rsi, .done_msg
	call kprint

	ret

.no_smp:
	; we really can find information from the MP tables, but I don't feel like doing that...
	mov rsi, .no_smp_msg
	call kprint

	ret

.cpu_init_error:
	mov rax, [.curr_cpu]
	call hex_byte_to_string
	mov rdi, .cpu_init_apic_id
	movsw

	mov rsi, .cpu_init_msg
	call kprint

	mov rsi, .cpu_init_msg
	call boot_error_early

	jmp $

.cmos_sec			db 0
.apic_table			db "APIC"		; MADT table signature
.starting_msg			db "[apic] attempting to initialize SMP...",10,0
.no_smp_msg			db "[apic] warning: ACPI APIC/MADT table not found or corrupt.",10,0
.found_local_apic		db "[apic] local APIC is at 0x",0
.total_cpus			db "[apic] total of ",0
.total_cpus2			db " usable CPU(s) found, ",0
.total_cpus3			db " disabled CPU(s) found.",10,0
.cpu0_msg			db "[apic] CPU #0 is always BSP...",10,0
.init_cpu			db "[apic] starting up CPU #",0
.done_msg			db "[apic] all CPUs successfully started up.",10,0
.cpu_init_msg			db "[apic] CPU with local APIC ID 0x"
.cpu_init_apic_id		db "00 did not respond within the specified time duration.",10,0
.table_start			dq 0
.table_end			dq 0
.list				dq list_of_cpus
.curr_cpu			dq 1

; show_apic_table:
; Shows the information of the APIC/MADT table

show_apic_table:
	pushaq

	mov rsi, .starting_msg
	call kprint

	mov rsi, [apic_table]
	mov rax, 0
	mov eax, dword[rsi+4]
	add rsi, rax
	mov [.end_apic_table], rsi

	; get address of local APIC
	mov rsi, [apic_table]
	mov eax, [rsi+ACPI_SDT_SIZE]
	mov dword[local_apic], eax

	mov rsi, .found_lapic_msg
	call kprint
	mov rax, [local_apic]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, [apic_table]
	add rsi, 44

.parse:
	cmp rsi, [.end_apic_table]
	jge .done

	mov [.tmp], rsi

	mov al, [rsi]
	cmp al, 0		; local APIC
	je .found_lapic

	cmp al, 1		; IO APIC
	je .found_ioapic

	cmp al, 2		; interrupt override
	je .found_override

	jmp .found_unknown

.found_lapic:
	mov rsi, .prefix
	call kprint
	mov rsi, .lapic_msg
	call kprint
	mov rsi, [.tmp]
	mov al, [rsi+3]
	call hex_byte_to_string
	call kprint
	mov rsi, .flags_msg
	call kprint
	mov rsi, [.tmp]
	mov eax, [rsi+4]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

	jmp .next_entry

.found_ioapic:
	mov rsi, .prefix
	call kprint
	mov rsi, .ioapic_msg
	call kprint
	mov rsi, [.tmp]
	mov al, [rsi+2]
	call hex_byte_to_string
	call kprint
	mov rsi, .base_msg
	call kprint
	mov rsi, [.tmp]
	mov eax, [rsi+4]
	call hex_dword_to_string
	call kprint
	mov rsi, .gsi_msg
	call kprint
	mov rax, 0
	mov rsi, [.tmp]
	mov eax, [rsi+8]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint
	jmp .next_entry

.found_override:
	mov rsi, .prefix
	call kprint
	mov rsi, .override_msg
	call kprint
	mov rsi, [.tmp]
	movzx rax, byte[rsi+3]
	call int_to_string
	call kprint
	mov rsi, .gsi_msg
	call kprint
	mov rsi, [.tmp]
	mov rax, 0
	mov eax, [rsi+4]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint
	jmp .next_entry

.found_unknown:
	mov rsi, .prefix
	call kprint
	mov rsi, .unknown_msg
	call kprint
	mov rsi, [.tmp]
	mov al, [rsi]
	call hex_byte_to_string
	call kprint
	mov rsi, .unknown_msg2
	call kprint
	mov rsi, [.tmp]
	mov al, [rsi+1]
	call hex_byte_to_string
	call kprint
	mov rsi, .unknown_msg3
	call kprint
	jmp .next_entry

.next_entry:
	mov rsi, [.tmp]
	movzx rax, byte[rsi+1]
	add rsi, rax
	jmp .parse

.done:
	popaq
	ret


.end_apic_table			dq 0
.tmp				dq 0
.starting_msg			db "[apic] showing contents of ACPI MADT table:",10,0
.found_lapic_msg		db "[apic] local APIC base is 0x",0
.prefix				db "[apic] ",0
.lapic_msg			db "local APIC, ID ",0
.ioapic_msg			db "I/O APIC, ID ",0
.flags_msg			db ", flags 0x",0
.gsi_msg			db ", GSI ",0
.base_msg			db ", base 0x",0
.override_msg			db "interrupt source override, source interrupt ",0
.comma				db ", ",0
.unknown_msg			db "warning: unknown entry type 0x",0
.unknown_msg2			db " with size 0x",0
.unknown_msg3			db "; ignoring...",10,0

align 4096
use16

; ap_init:
; Entry point for application processors
; Starts in real mode, just like all x86 CPUs, and sets it up to run in long mode with its own stack and a 16 GB address space

ap_init:
	jmp 0:.next			; fix CS

.next:
	mov ax, 0
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	lgdt [gdtr]
	lidt [idtr]

	mov eax, pml4
	or eax, 8
	mov cr3, eax
	mov eax, 0x130			; PMC | PAE | PSE
	mov cr4, eax

	mov ecx, 0xC0000080
	rdmsr
	or eax, 0x100
	wrmsr

	mov eax, cr0
	or eax, 0x80000001	; enable paging and protection
	and eax, 0x9FFAFFFF	; enable caching, enable kernel writing to read-only pages
	mov cr0, eax
	jmp 0x28:.long_mode

use64

.long_mode:
	mov ax, 0x30
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	lgdt [gdtr]
	lidt [idtr]

	mov rax, [init_smp.curr_cpu]
	shl rax, 13			; mul 0x2000
	add rax, 0x40000
	mov rsp, rax

	mov rsi, .life_msg		; show signs of life
	call kprint
	mov rax, [init_smp.curr_cpu]
	call int_to_string
	call kprint
	mov rsi, .life_msg2
	call kprint

	; enable the local APIC
	mov ecx, 0x1B
	rdmsr
	test eax, 0x800
	jz .enable_apic

	; ensure the local APIC is at the same address as the BSP
	and eax, 0xFFFFF000
	cmp eax, dword[local_apic]
	jne .enable_apic
	cmp edx, 0
	jne .enable_apic

	jmp .configure_lapic

.enable_apic:
	mov edx, 0
	mov eax, dword[local_apic]
	or eax, 0x800
	mov ecx, 0x1B
	wrmsr

.configure_lapic:
	; configure the local APIC
	mov rax, 0
	mov rcx, 0x80
	call lapic_write_register

	mov rax, 0x1FF
	mov rcx, 0xF0
	call lapic_write_register	; enable spurious IRQ at INT 0xFF

	mov rcx, 0xE0
	mov eax, 0xFFFFFFFF
	call lapic_write_register

	mov rax, 0
	mov rcx, 0xB0
	call lapic_write_register	; just send an EOI

	call flush_caches

	mov byte[.done], 1		; notify the BSP that we're done

.loop:
	cmp byte[ap_interrupts_enabled], 0
	je .disable

	sti
	jmp .loop

.disable:
	cli
	jmp .loop

.life_msg			db "[apic] CPU #",0
.life_msg2			db " initialized and running!",10,0
.done				db 0

; init_ioapic:
; Detect and initialize the I/O APIC

init_ioapic:
	mov rsi, .starting_msg
	call kprint

	cmp [apic_table], 0
	je .no_ioapics

	mov rsi, [apic_table]		; ACPI APIC table
	add rsi, 44
	mov [.table_start], rsi

	mov rsi, [apic_table]
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.table_end], rsi

	mov rsi, [.table_start]

.find_ioapic_loop:
	cmp rsi, [.table_end]
	jge .found_all_ioapics
	push rsi
	mov al, [rsi]
	cmp al, 1			; is it an I/O APIC?
	je .found_ioapic

	mov rax, 0
	mov al, [rsi+1]
	pop rsi
	add rsi, rax
	jmp .find_ioapic_loop

.found_ioapic:
	push rsi

	mov rsi, .found_ioapic_msg
	call kprint

	pop rsi
	push rsi
	mov rax, 0
	mov eax, [rsi+4]
	call hex_dword_to_string
	call kprint

	mov rsi, .found_ioapic_msg2
	call kprint

	pop rsi
	push rsi
	mov rax, 0
	mov eax, [rsi+8]
	call int_to_string
	call kprint

	mov rsi, newline
	call kprint

	pop rsi

	mov rdi, [.list_of_ioapics]
	mov eax, [rsi+4]
	mov [rdi], eax
	add [.list_of_ioapics], 4

	mov rdi, [.list_of_ioapics_id]
	mov al, [rsi+2]
	mov [rdi], al
	inc [.list_of_ioapics_id]

	inc [number_of_ioapics]

	pop rsi

	cmp [number_of_ioapics], MAXIMUM_CPUS
	je .found_all_ioapics

	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	jmp .find_ioapic_loop

.found_all_ioapics:
	cmp [number_of_ioapics], 0
	je .no_ioapics

	mov rsi, .found_all_ioapic_msg
	call kprint
	mov rax, [number_of_ioapics]
	call int_to_string
	call kprint
	mov rsi, .found_all_ioapic_msg2
	call kprint

	mov [using_ioapic], 1

	; map the PIC to INT 0x20 => 0x2F so that we can handle spurious IRQs
	mov al, 0x20
	mov ah, 0x28
	call remap_pic

	; disable the PIC
	mov al, 0xFF
	out 0x21, al
	out 0xA1, al

	; install spurious IRQ handlers
	mov al, 7
	mov rbp, apic_spurious_irq
	call install_irq

	mov al, 0xFF
	mov rbp, apic_spurious_irq
	call install_isr

	mov al, 0x20+7				; master PIC spurious IRQ
	mov rbp, master_pic_spurious_irq
	call install_isr

	mov al, 0x20+2				; master PIC cascade IRQ
	mov rbp, master_pic_cascade_irq
	call install_isr

	mov al, 0x20+15				; slave PIC spurious IRQ
	mov rbp, slave_pic_spurious_irq
	call install_isr

	call ioapic_setup_irqs
	mov [ioapic_enabled], 1
	ret

.no_ioapics:
	mov rsi, .no_ioapic_msg
	call kprint

	call init_pic
	ret

.starting_msg			db "[ioapic] initializing I/O APIC...",10,0
.no_ioapic_msg			db "[ioapic] warning: no I/O APIC present, using legacy PIC...",10,0
.found_ioapic_msg		db "[ioapic] found I/O APIC at address 0x",0
.found_ioapic_msg2		db ", GSI ",0
.found_all_ioapic_msg		db "[ioapic] found a total of ",0
.found_all_ioapic_msg2		db " I/O APICs.",10,0
.table_start			dq 0
.table_end			dq 0
.list_of_ioapics		dq list_of_ioapics
.list_of_ioapics_id		dq list_of_ioapics_id

; calculate_cpu_speed:
; Calculates CPU speed

calculate_cpu_speed:
	call enable_interrupts

	mov rbx, [timer_ticks]

.wait_for_irq:
	cmp rbx, [timer_ticks]
	je .wait_for_irq

	rdtsc
	mov dword[.tsc], eax
	mov dword[.tsc+4], edx

	add rbx, TIMER_FREQUENCY/10		; 1 tenth of a second

.wait_again:
	cmp rbx, [timer_ticks]
	jne .wait_again
	rdtsc

	mov dword[.tsc2], eax
	mov dword[.tsc2+4], edx

	mov rax, [.tsc2]
	mov rbx, [.tsc]
	sub rax, rbx
	;mov rbx, 10
	;mul rbx			; in Hz
	mov rdx, 0
	mov rbx, 100000
	div rbx				; to MHz
	mov [cpu_speed], rax

	mov rsi, .msg
	call kprint
	mov rax, [cpu_speed]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	ret

.tsc				dq 0
.tsc2				dq 0
.msg				db "[apic] BSP speed is ",0
.msg2				db " MHz.",10,0

; init_pic:
; Initializes the PIC

init_pic:
	mov rsi, .msg
	call kprint

	mov al, IOAPIC_IRQ_BASE
	mov ah, IOAPIC_IRQ_BASE+8
	call remap_pic

	; install spurious IRQ handlers
	mov al, 7
	mov rbp, master_pic_spurious_irq
	call install_irq
	mov al, 15
	mov rbp, slave_pic_spurious_irq
	call install_irq

	; install cascade IRQ handler
	mov al, 2
	mov rbp, master_pic_cascade_irq
	call install_irq

	; unmask the PIC
	mov al, 0
	out 0x21, al
	out 0xA1, al
	call iowait

	ret

.msg				db "[pic] initializing legacy dual-installation PIC...",10,0

; remap_pic:
; Remaps vectors on the PIC
; In\	AL = Master PIC offset
; In\	AH = Slave PIC offset
; Out\	Nothing

remap_pic:
	pushfq
	cli
	mov [.master], al
	mov [.slave], ah

	; save masks
	in al, 0x21
	mov [.data1], al
	call iowait
	in al, 0xA1
	mov [.data2], al
	call iowait

	mov al, 0x11			; initialize command
	out 0x20, al
	call iowait
	mov al, 0x11
	out 0xA0, al
	call iowait

	mov al, [.master]
	out 0x21, al
	call iowait
	mov al, [.slave]
	out 0xA1, al
	call iowait

	mov al, 4
	out 0x21, al
	call iowait
	mov al, 2
	out 0xA1, al
	call iowait

	mov al, 1
	out 0x21, al
	call iowait
	mov al, 1
	out 0xA1, al
	call iowait

	; restore masks
	mov al, [.data1]
	out 0x21, al
	call iowait
	mov al, [.data2]
	out 0xA1, al
	call iowait

	popfq
	ret
.data1				db 0
.data2				db 0
.master				db 0
.slave				db 0

; ioapic_setup_irqs:
; Sets up the I/O APIC IRQs

ioapic_setup_irqs:
	call ioapic_remap_irqs	; get the PIC -> IOAPIC remappings

	mov rax, 0		; start at IRQ 0
	mov rcx, 24

.loop:
	push rcx
	mov rdx, 0
	mov rsi, [.list_of_cpus]
	mov dl, [rsi]
	cmp dl, 0xFF
	je .reset_cpus

	inc [.list_of_cpus]
	mov dl, [list_of_cpus]
	shl rdx, 56
	mov dl, IOAPIC_IRQ_BASE
	add dl, al
	;or rdx, 0x10000		; mask interrupt
	call ioapic_init_irq

	inc al
	pop rcx
	loop .loop
	jmp .configure_local_apic

.reset_cpus:
	mov [.list_of_cpus], list_of_cpus
	pop rcx
	jmp .loop

.configure_local_apic:
	mov rsi, .configuring_lapic
	call kprint

	mov rax, 0
	mov rcx, 0x80
	call lapic_write_register

	mov rax, 0x1FF
	mov rcx, 0xF0
	call lapic_write_register	; enable spurious IRQ at INT 0xFF

	call iowait
	ret

.configuring_lapic		db "[apic] configuring local APIC...",10,0
.current_cpu			db 0
.list_of_cpus			dq list_of_cpus

; ioapic_remap_irqs:
; Does the PIC => IOAPIC remapping

ioapic_remap_irqs:
	pushaq

	mov rsi, [apic_table]
	mov [.apic], rsi
	mov rax, 0
	mov eax, [rsi+4]
	mov [.end_apic], rax
	add [.end_apic], rsi

	mov rsi, [.apic]
	add rsi, 44

.loop:
	cmp rsi, [.end_apic]
	jge .done

	cmp byte[rsi], 2		; interrupt source override
	je .found

	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	jmp .loop

.found:
	mov [.tmp], rsi

	mov rsi, .found_msg
	call kprint

	mov rsi, [.tmp]
	mov rax, 0
	mov al, [rsi+3]
	mov rdi, interrupt_remaps
	add rdi, rax
	mov eax, [rsi+4]
	mov [rdi], al

	mov rsi, [.tmp]
	mov rax, 0
	mov al, [rsi+3]
	call int_to_string
	call kprint

	mov rsi, .found_msg2
	call kprint

	mov rsi, [.tmp]
	mov rax, 0
	mov eax, [rsi+4]
	call int_to_string
	call kprint

	mov rsi, newline
	call kprint
	mov rsi, [.tmp]
	mov rax, 0
	mov al, [rsi+1]
	add rsi, rax
	jmp .loop

.done:
	popaq
	ret

.found_msg			db "[ioapic] remapping PIC IRQ ",0
.found_msg2			db " to I/O APIC IRQ ",0
.apic				dq 0
.end_apic			dq 0
.tmp				dq 0

; install_irq:
; Installs an IRQ handler
; In\	AL = PIC interrupt mapping
; In\	RBP = Interrupt handler
; Out\	Nothing

install_irq:
	pushaq

	mov [.handler], rbp

	movzx rax, al
	add rax, interrupt_remaps
	mov dl, [rax]
	mov al, dl
	mov [.irq], al

	mov rsi, .starting_msg
	call kprint
	movzx rax, [.irq]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint
	movzx rax, [.irq]
	add rax, IOAPIC_IRQ_BASE
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov al, [.irq]
	add al, IOAPIC_IRQ_BASE
	mov rbp, [.handler]
	call install_isr		; install IRQ handler in the IDT

	popaq
	ret

.handler			dq 0
.irq				db 0
.starting_msg			db "[irq] installing IRQ handler ",0
.starting_msg2			db ", interrupt 0x",0

; ioapic_read_register:
; Reads an I/O APIC register
; In\	CL = I/O APIC number
; In\	EDX = Register number
; Out\	EAX = Content from register
align 16
ioapic_read_register:
	pushaq
	mov [.apic], cl
	mov [.register], edx

	movzx rcx, [.apic]
	shl rcx, 2			; mul 4
	add rcx, list_of_ioapics
	mov rdi, 0
	mov edi, [rcx]			; I/O APIC location

	mov eax, [.register]
	mov [rdi], eax
	call flush_caches
	mov eax, [rdi+0x10]
	mov [.content], eax

	popaq
	mov eax, [.content]
	ret

.apic				db 0
.register			dd 0
.content			dd 0

; ioapic_write_register:
; Writes an I/O APIC register
; In\	EAX = Value to write
; In\	CL = I/O APIC number
; In\	EDX = Register number
; Out\	Nothing
align 16
ioapic_write_register:
	pushaq
	mov [.content], eax
	mov [.apic], cl
	mov [.register], edx

	movzx rcx, [.apic]
	shl rcx, 2			; mul 4
	add rcx, list_of_ioapics
	mov rdi, 0
	mov edi, [rcx]			; I/O APIC location

	mov eax, [.register]
	mov [rdi], eax
	call flush_caches
	mov eax, [.content]
	mov [rdi+0x10], eax
	call flush_caches

	popaq
	ret

.apic				db 0
.register			dd 0
.content			dd 0

; ioapic_init_irq:
; Changes the value of an I/O APIC IRQ register
; In\	AL = IRQ number
; In\	RDX = Value to write
; Out\	Nothing

ioapic_init_irq:
	pushaq
	mov [.irq], al
	mov [.value], rdx
	and rax, 0xFF

	shl rax, 1
	add rax, 0x10
	mov rdx, rax
	mov cl, 0		; I/O APIC #0
	mov rax, [.value]
	call ioapic_write_register

	add rdx, 1
	shr rax, 32
	call ioapic_write_register

	popaq
	ret

.irq				db 0
.value				dq 0

; send_eoi:
; Sends an EOI to the local APIC
align 16
send_eoi:
	cmp [using_ioapic], 0
	je .pic

	push rax
	push rcx
	mov rax, 0
	mov rcx, 0xB0
	call lapic_write_register	; send the EOI

	pop rcx
	pop rax
	ret

.pic:
	push rax
	mov al, 0x20
	out 0x20, al
	out 0xA0, al
	pop rax
	ret

; enable_interrupts:
; Enables interrupts on all available CPUs

enable_interrupts:
	mov [ap_interrupts_enabled], 1
	sti
	call flush_caches
	call iowait
	ret

; disable_interrupts:
; Disables interrupts on all available CPUs

disable_interrupts:
	mov [ap_interrupts_enabled], 0
	cli
	call flush_caches
	call iowait
	ret

; apic_spurious_irq:
; APIC spurious IRQ handler

apic_spurious_irq:
	pushaq
	inc [spurious_irqs]		; keep a counter on spurious IRQs

	mov rsi, .msg
	call kprint
	mov rax, [spurious_irqs]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	popaq
	iretq

.msg				db "[apic] received a spurious IRQ, total of ",0
.msg2				db " spurious IRQs occured since boot.",10,0


; lapic_read_register:
; Reads a Local APIC register
; In\	RCX = Register number
; Out\	EAX = Value from register
align 16
lapic_read_register:
	add rcx, [local_apic]
	mov eax, [rcx]
	ret

; lapic_write_register:
; Writes a Local APIC register
; In\	EAX = Value to write
; In\	RCX = Register number
; Out\	Nothing
align 16
lapic_write_register:
	add rcx, [local_apic]
	mov [rcx], eax
	ret

apic_timer_divider		= 0x3E0
apic_timer_initial_count	= 0x380
apic_timer_current_count	= 0x390
apic_lvt_timer			= 0x320
apic_timer_disable		= 0x10000
apic_timer_periodic_mode	= 0x20000

; init_apic_timer:
; Initializes the APIC timer

init_apic_timer:
	mov rsi, .starting_msg
	call kprint

	call enable_interrupts

	call wait_second
	mov rcx, apic_timer_divider
	mov rax, 3
	call lapic_write_register

	mov rcx, apic_timer_initial_count
	mov eax, 0xFFFFFFFF
	call lapic_write_register

	call wait_second

	mov rcx, apic_lvt_timer
	mov rax, 0x10000
	call lapic_write_register

	mov byte[interrupt_remaps], 0
	mov al, 0
	mov rbp, apic_timer_irq
	call install_irq

	mov rcx, apic_timer_current_count
	call lapic_read_register

	mov ebx, eax
	mov rax, 0
	mov eax, 0xFFFFFFFF
	sub eax, ebx
	mov [apic_timer_frequency], rax

	mov rsi, .ips_msg
	call kprint
	mov rax, [apic_timer_frequency]
	call int_to_string
	call kprint
	mov rsi, .ips_msg2
	call kprint

	call disable_pit

	mov rcx, apic_lvt_timer
	mov eax, 0x20
	or eax, apic_timer_periodic_mode
	call lapic_write_register

	mov rcx, apic_timer_divider
	mov rax, 3
	call lapic_write_register

	mov rax, [timer_ticks]
	mov rdx, 0
	mov rbx, TIMER_FREQUENCY
	div rbx
	mov rcx, apic_timer_initial_count
	call lapic_write_register

	call wait_second

	mov rax, [timer_ticks]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	call wait_second

	mov rax, [timer_ticks]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	cli
	hlt

	ret

.starting_msg				db "[apic] initializing local APIC timer...",10,0
.ips_msg				db "[apic] local APIC timer is capable of ",0
.ips_msg2				db " interrupts/second.",10,0
.ticks					dq 0

align 16
timer_ticks				dq 0
uptime					dq 0

; apic_timer_irq:
; APIC timer IRQ handler
align 16
apic_timer_irq:
	inc [timer_ticks]
	call send_eoi
	iretq

; master_pic_cascade_irq:
; Master PIC cascade IRQ handler
align 16
master_pic_cascade_irq:
	iretq

; master_pic_spurious_irq:
; Master PIC spurious IRQ handler
align 16
master_pic_spurious_irq:
	pushaq
	inc [pic1_spurious_irqs]		; keep a counter on spurious IRQs

	mov rsi, .msg
	call kprint
	mov rax, [pic1_spurious_irqs]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	popaq
	iretq

.msg				db "[pic] master PIC received a spurious IRQ, total of ",0
.msg2				db " spurious IRQs occured since boot.",10,0

; slave_pic_spurious_irq:
; Slave PIC spurious IRQ handler
align 16
slave_pic_spurious_irq:
	pushaq
	inc [pic2_spurious_irqs]		; keep a counter on spurious IRQs

	mov rsi, .msg
	call kprint
	mov rax, [pic2_spurious_irqs]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	mov al, 0x20
	out 0x20, al

	popaq
	iretq

.msg				db "[pic] slave PIC received a spurious IRQ, total of ",0
.msg2				db " spurious IRQs occured since boot.",10,0

; mask_irq:
; Masks an IRQ
; In\	AL = IRQ number
; Out\	Nothing

mask_irq:
	cmp [using_ioapic], 0
	je .use_pic

.use_ioapic:
	and rax, 0xFF
	shl rax, 1
	mov rdx, rax
	push rdx
	mov rcx, 0
	call ioapic_read_register

	pop rdx
	mov rcx, 0
	or eax, 0x10000
	call ioapic_write_register

	ret

.use_pic:
	cmp al, 7
	jg .slave_pic

.master_pic:
	mov cl, al
	mov rbx, 1
	shl rbx, cl
	in al, 0x21
	or al, bl
	out 0x21, al
	call iowait

	ret

.slave_pic:
	sub al, 8
	mov cl, al
	mov rbx, 1
	shl rbx, cl
	in al, 0xA1
	or al, bl
	out 0xA1, al
	call iowait

	ret

; unmask_irq:
; Unmasks an IRQ

unmask_irq:
	cmp [using_ioapic], 0
	je .use_pic

.use_ioapic:
	and rax, 0xFF
	shl rax, 1
	mov rdx, rax
	push rdx
	mov rcx, 0
	call ioapic_read_register

	pop rdx
	mov rcx, 0
	and eax, not 0x10000
	call ioapic_write_register

	ret

.use_pic:
	cmp al, 7
	jg .slave_pic

.master_pic:
	mov cl, al
	mov rbx, 1
	shl rbx, cl
	in al, 0x21
	not bl
	and al, bl
	out 0x21, al
	call iowait

	ret

.slave_pic:
	sub al, 8
	mov cl, al
	mov rbx, 1
	shl rbx, cl
	in al, 0xA1
	not bl
	and al, bl
	out 0xA1, al
	call iowait

	ret




