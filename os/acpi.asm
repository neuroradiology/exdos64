
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ACPI subsystem",0

;; Functions:
; init_acpi
; acpi_do_rsdp_checksum
; show_acpi_tables
; acpi_do_checksum
; acpi_find_table
; enable_acpi
; acpi_detect_batteries
; acpi_irq
; dsdt_find_object
; acpi_sleep
; acpi_shutdown
; shutdown
; acpi_reset
; acpi_run_aml

;; 
;; The first part of this file is basic ACPI routines
;; These include ACPI table functions, ACPI reset and ACPI sleeping code
;; Later in this file is an ACPI Machine Language Virtual Machine
;; 

rsdp					dq 0
acpi_root				dq 0
acpi_version				db 0
acpi_bst_package			dq 0
acpi_bif_package			dq 0
acpi_sleeping				db 0

acpi_bif:
	.power_unit			dd 0
	.design_capacity		dd 0
	.full_charge_capacity		dd 0
	.battery_technology		dd 0
	.design_voltage			dd 0
	.design_warning			dd 0
	.design_low			dd 0
	.granularity1			dd 0
	.granularity2			dd 0
	.model:				times 16 db 0
	.serial_number:			times 16 db 0
	.battery_type:			times 16 db 0
	.oem_information:		times 16 db 0

acpi_bst:
	.state				dd 0
	.present_state			dd 0
	.remaining_capacity		dd 0
	.present_voltage		dd 0

acpi_battery				db 0		; 0 not present, 1 SBST, 2 standard ACPI AML battery
battery_percentage			dq 0
is_there_fadt				db 0

ACPI_SDT_SIZE				= 36	; size of ACPI SDT header

; init_acpi:
; Initializes the ACPI subsystem

init_acpi:
	mov rsi, .starting_msg
	call kprint

	movzx rsi, word[0x40E]		; there *may* be a real mode segment pointer to the RSD PTR at 0x40E
	shl rsi, 4
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp

	; first, search the EBDA for the RSDP
	mov rsi, [ebda_base]

.search_ebda_loop:
	push rsi
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp
	pop rsi

	inc rsi
	mov rdi, [ebda_base]
	add rdi, 1024
	cmp rsi, rdi
	jge .search_rom
	jmp .search_ebda_loop

.search_rom:
	mov rsi, 0xE0000

.find_rsdp_loop:
	push rsi
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp
	pop rsi

	add rsi, 0x10
	cmp rsi, 0xFFFFF
	jge .no_acpi
	jmp .find_rsdp_loop

.found_rsdp:
	pop rsi
	mov [rsdp], rsi

	call acpi_do_rsdp_checksum

	mov rsi, [rsdp]
	mov al, [rsi+15]
	inc al
	mov [acpi_version], al

	mov rsi, .found_acpi
	call kprint

	mov rax, [rsdp]
	call hex_dword_to_string
	call kprint

	mov rsi, .found_acpi2
	call kprint

	mov rax, 0
	mov al, [acpi_version]
	call int_to_string
	call kprint

	mov rsi, newline
	call kprint

	cmp [acpi_version], 2
	jl .show_warning
	jmp .show_all_tables

.show_warning:
	mov rsi, .old_acpi_warning
	call kprint
	jmp .show_all_tables

.no_acpi:
	mov rsi, .no_acpi_msg
	call kprint

	mov rsi, .no_acpi_msg
	call boot_error_early

	jmp $

.show_all_tables:
	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rsi, [rsdp]
	mov rax, [rsi+24]
	mov [acpi_root], rax

	mov rsi, .found_xsdt
	call kprint
	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint
	jmp .show_tables

.use_rsdt:
	mov rsi, [rsdp]
	mov rax, 0
	mov eax, [rsi+16]
	mov [acpi_root], rax

	mov rsi, .found_rsdt
	call kprint
	mov rax, [acpi_root]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

.show_tables:
	call show_acpi_tables
	ret

.starting_msg			db "[acpi] initializing ACPI...",10,0
.no_acpi_msg			db "[acpi] system doesn't support ACPI...",10,0
.found_acpi			db "[acpi] found RSDP at 0x",0
.found_acpi2			db ", ACPI version ",0
.checksum_error_msg		db "[acpi] checksum error.",10,0
.old_acpi_warning		db "[acpi] warning: ACPI 2.0+ was not found, using 32-bit RSDT instead of XSDT...",10,0
.rsd_ptr			db "RSD PTR "
.found_rsdt			db "[acpi] found RSDT at 0x",0
.found_xsdt			db "[acpi] found XSDT at 0x",0

; acpi_do_rsdp_checksum:
; Does the RSDP checksum

acpi_do_rsdp_checksum:
	; verify the checksum of the first part of the RSDP
	mov rsi, [rsdp]
	mov rdi, rsi
	add rdi, 20
	mov rax, 0
	mov rbx, 0

.rsdp1_loop:
	cmp rsi, rdi
	jge .rsdp1_done
	lodsb
	add bl, al
	jmp .rsdp1_loop

.rsdp1_done:
	cmp bl, 0
	jne .error

	mov rsi, [rsdp]
	cmp byte[rsi+15], 1		; ACPI v2+
	jge .do_rsdp2

	ret

.do_rsdp2:
	mov rsi, [rsdp]
	mov rax, 0
	mov eax, [rsi+20]
	mov rdi, rsi
	add rdi, rax

	mov rax, 0
	mov rbx, 0

.rsdp2_loop:
	cmp rsi, rdi
	jge .rsdp2_done
	lodsb
	add bl, al
	jmp .rsdp2_loop

.rsdp2_done:
	cmp bl, 0
	jne .error

	ret

.error:
	mov rsi, [rsdp]
	mov al, [rsi+8]
	call hex_byte_to_string
	mov rdi, .error_msg2
	movsw

	mov rsi, .error_msg
	call kprint
	mov rsi, .error_msg
	call boot_error_early

	jmp $

.error_msg			db "[acpi] checksum error: table 'RSD PTR ', checksum 0x"
.error_msg2			db "00",10,0

; show_acpi_tables:
; Shows ACPI tables

show_acpi_tables:
	; first, show the XSDT/RSDT
	mov rsi, .prefix
	call kprint

	cmp [acpi_version], 2
	jl .show_rsdt

.show_xsdt:
	mov rsi, .xsdt
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [acpi_root]
	mov rax, 0
	mov al, [rsi+8]			; version
	call int_to_string
	call kprint

	mov rsi, [acpi_root]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem_str
	call kprint
	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	jmp .start_tables

.show_rsdt:
	mov rsi, .rsdt
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [acpi_root]
	mov rax, 0
	mov al, [rsi+8]			; version
	call int_to_string
	call kprint

	mov rsi, [acpi_root]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem_str
	call kprint
	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

.start_tables:
	mov rsi, [acpi_root]
	add rsi, ACPI_SDT_SIZE
	mov [.root], rsi

	mov rsi, [acpi_root]
	mov rax, 0
	mov eax, [rsi+4]
	mov [.end_root], rax
	mov rax, [acpi_root]
	add [.end_root], rax

	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rsi, [.root]
	cmp rsi, [.end_root]
	jge .done
	add [.root], 8

	mov rax, [rsi]
	mov [.table], rax
	jmp .parse_table

.use_rsdt:
	mov rsi, [.root]
	cmp rsi, [.end_root]
	jge .done
	add [.root], 4

	mov rax, 0
	mov eax, [rsi]
	mov [.table], rax

.parse_table:
	mov rsi, [.table]
	mov rdi, .signature
	mov rcx, 4
	rep movsb

	mov rsi, .prefix
	call kprint

	mov rsi, .signature
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [.table]
	mov rax, 0
	mov al, [rsi+8]
	call int_to_string
	call kprint

	mov rsi, .oem_str
	call kprint

	mov rsi, [.table]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [.table]
	call hex_qword_to_string
	call kprint

	mov rsi, newline
	call kprint

	cmp [acpi_version], 2
	jl .use_rsdt

	jmp .use_xsdt

.done:
	ret

.prefix				db "[acpi] ",0
.xsdt				db "XSDT",0
.rsdt				db "RSDT",0
.version			db " version ",0
.oem_str			db " OEM '",0
.address			db "' address 0x",0
.oem:				times 7 db 0
.table				dq 0
.root				dq 0
.end_root			dq 0
.signature:			times 5 db 0

; acpi_do_checksum:
; Does a checksum on an ACPI table
; In\	RSI = Address of table
; Out\	RFLAGS.CF = 0 on success

acpi_do_checksum:
	mov [.table], rsi
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.end_table], rsi

	; now add all the bytes in the table
	mov rsi, [.table]
	mov rax, 0
	mov rbx, 0

.loop:
	cmp rsi, [.end_table]
	jge .done
	lodsb
	add bl, al
	jmp .loop

.done:
	cmp bl, 0
	je .yes

.no:
	mov rsi, .error_msg
	call kprint
	mov rsi, [.table]
	mov rdi, .signature
	movsd
	mov rsi, .signature
	call kprint
	mov rsi, .error_msg2
	call kprint
	mov rsi, [.table]
	mov al, [rsi+9]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	stc
	ret

.yes:
	clc
	ret

.table				dq 0
.end_table			dq 0
.signature:			times 5 db 0
.error_msg			db "[acpi] checksum error: table '",0
.error_msg2			db "', checksum 0x",0

; acpi_find_table:
; Returns address of an ACPI table
; In\	RSI = Signature
; Out\	RSI = Table address (0 if not found)

acpi_find_table:
	mov rdi, .signature
	mov rcx, 4
	rep movsb

	mov rax, [acpi_root]
	add rax, ACPI_SDT_SIZE
	mov [.root], rax

	mov rsi, [acpi_root]
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.end_root], rsi

	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rax, [.root]
	cmp rax, [.end_root]
	jge .no_table
	mov rsi, [rax]
	add [.root], 8
	jmp .check_table

.use_rsdt:
	mov rax, [.root]
	cmp rax, [.end_root]
	jge .no_table
	mov rsi, 0
	mov esi, [rax]
	add [.root], 4

.check_table:
	mov rdi, .signature
	mov rcx, 4
	rep cmpsb
	je .found_table

	cmp [acpi_version], 2
	jl .use_rsdt
	jmp .use_xsdt

.found_table:
	sub rsi, 4
	mov [.table], rsi

	; verify the table's checksum
	mov rsi, [.table]
	call acpi_do_checksum
	jc .no_table

	mov rsi, [.table]
	ret

.no_table:
	mov rsi, 0
	ret

.signature:			times 4 db 0
.root				dq 0
.end_root			dq 0
.table				dq 0

; enable_acpi:
; Enables ACPI hardware mode

enable_acpi:
	mov rsi, .facp
	call acpi_find_table
	cmp rsi, 0
	je .no_fadt

	mov [is_there_fadt], 1

	mov rdi, acpi_fadt
	mov rcx, acpi_fadt_size
	rep movsb

	; install ACPI IRQ handler
	mov rsi, .irq_msg
	call kprint
	movzx rax, [acpi_fadt.sci_interrupt]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov ax, [acpi_fadt.sci_interrupt]
	mov rbp, acpi_irq
	call install_irq

	mov rsi, .acpi_event
	call kprint
	movzx rax, [acpi_fadt.pm1_event_length]
	shr rax, 1
	call int_to_string
	call kprint
	mov rsi, .acpi_event2
	call kprint

	call enable_interrupts

	mov rsi, .starting_msg
	call kprint

	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	test ax, 1
	jnz .already_enabled

	cmp [acpi_fadt.smi_command_port], 0
	je .already_enabled

	mov edx, [acpi_fadt.smi_command_port]
	mov al, [acpi_fadt.acpi_enable]
	out dx, al		; enable ACPI

	call iowait		; give the hardware some time to change into ACPI mode

	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71
	mov [.cmos_sec], al

.wait_for_enable:
	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	test ax, 1			; now poll the ACPI status...
	jnz .done_enabled

	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71
	cmp al, [.cmos_sec]
	jg .enable_error
	jmp .wait_for_enable

.already_enabled:
	mov rsi, .already_msg
	call kprint

	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	or ax, 1
	and ax, 0xE3FF
	out dx, ax

	ret

.done_enabled:
	mov rsi, .done_msg
	call kprint

	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	or ax, 1
	and ax, 0xE3FF
	out dx, ax

	ret

.enable_error:
	mov rsi, .enable_error_msg
	call kprint

	mov rsi, .enable_error_msg
	call boot_error_early

	jmp $

.no_fadt:
	mov rsi, .no_fadt_msg
	call kprint
	mov rsi, .no_fadt_msg
	call boot_error_early

	ret	

.facp				db "FACP"
.starting_msg			db "[acpi] enabling ACPI hardware mode...",10,0
.already_msg			db "[acpi] system is already in ACPI mode.",10,0
.done_msg			db "[acpi] system is now in ACPI mode.",10,0
.irq_msg			db "[acpi] ACPI using IRQ ",0
.no_fadt_msg			db "[acpi] FACP table is not present or corrupt, will not be able to manage power.",10,0
.acpi_event			db "[acpi] ACPI event register size is ",0
.acpi_event2			db " bytes.",10,0
.enable_error_msg		db "[acpi] failed to enable ACPI.",10,0
.cmos_sec			db 0

ACPI_EVENT_TIMER		= 1
ACPI_EVENT_BUSMASTER		= 0x10
ACPI_EVENT_GBL			= 0x20
ACPI_EVENT_POWERBUTTON		= 0x100
ACPI_EVENT_SLEEPBUTTON		= 0x200
ACPI_EVENT_RTC			= 0x400
ACPI_EVENT_PCIE_WAKE		= 0x4000
ACPI_EVENT_WAKE			= 0x8000

; acpi_irq:
; ACPI IRQ handler

acpi_irq:
	pushaq

	mov rsi, .msg
	call kprint

	mov rdx, 0
	mov edx, [acpi_fadt.pm1a_event_block]
	in ax, dx

	mov [.event], rax
	call hex_word_to_string
	call kprint

	mov rsi, newline
	call kprint

	mov rax, [.event]
	test rax, ACPI_EVENT_POWERBUTTON	; if the power button is pressed, shut down
	jnz shutdown

.end:
	call send_eoi
	popaq
	iretq

.msg				db "[acpi] SCI interrupt; event block data is: 0x",0
.event				dq 0

; acpi_detect_batteries:
; Detects ACPI-compatible batteries

acpi_detect_batteries:
	pushaq

	mov rsi, .starting_msg
	call kprint

	;;
	;; TO-DO: use the ACPI SBST table for battery information
	;;

	; Find the _BIF object
	mov rsi, .bif
	call dsdt_find_object
	cmp rsi, 0
	je .no_battery

	; Now we need to find the BIF package
	; We will search for 0xA4 (AML opcode for return) because it is standard the _BIF returns a package

.find_bif_package:
	lodsb
	cmp al, 0xA4
	je .found_bif_package
	jmp .find_bif_package

.found_bif_package:
	mov rdi, .bif_package
	mov rcx, 4
	rep movsb

	mov rsi, .bif_package
	call dsdt_find_object
	cmp rsi, 0
	je .no_battery
	mov [acpi_bif_package], rsi

	; Now fill up the ACPI BIF
	mov rsi, [acpi_bif_package]
	add rsi, 7
	mov rdi, acpi_bif
	mov rcx, 9

.fill_bif:
	cmp rcx, 0
	je .find_bst

	cmp byte[rsi], 0xA	; byteprefix
	je .bif_byte

	cmp byte[rsi], 0xB	; word prefix
	je .bif_word

	cmp byte[rsi], 0xC	; dword prefix
	je .bif_dword

	movzx rax, byte[rsi]
	stosd
	inc rsi
	dec rcx
	jmp .fill_bif

.bif_byte:
	movzx rax, byte[rsi+1]
	stosd
	add rsi, 2
	dec rcx
	jmp .fill_bif

.bif_word:
	movzx rax, word[rsi+1]
	stosd
	add rsi, 3
	dec rcx
	jmp .fill_bif

.bif_dword:
	mov eax, dword[rsi+1]
	stosd
	add rsi, 5
	dec rcx
	jmp .fill_bif

.find_bst:
	; Now we need to find the battery status package
	mov rsi, .bst
	call dsdt_find_object
	cmp rsi, 0
	je .no_battery

	; Like above, we need to find the BST package
	; We will search for 0xA4 (AML opcode for return) because it is standard the _BST returns a package

.find_bst_package:
	lodsb
	cmp al, 0xA4
	je .found_bst_package
	jmp .find_bst_package

.found_bst_package:
	mov rdi, .bst_package
	mov rcx, 4
	rep movsb

	mov rsi, .bst_package
	call dsdt_find_object
	cmp rsi, 0
	je .no_battery
	mov [acpi_bst_package], rsi

	; Now we need to fill up the ACPI BST
	mov rsi, [acpi_bst_package]
	add rsi, 7
	mov rdi, acpi_bst
	mov rcx, 4

.fill_bst:
	cmp rcx, 0
	je .done

	cmp byte[rsi], 0xA	; byteprefix
	je .bst_byte

	cmp byte[rsi], 0xB	; word prefix
	je .bst_word

	cmp byte[rsi], 0xC	; dword prefix
	je .bst_dword

	movzx rax, byte[rsi]
	stosd
	inc rsi
	dec rcx
	jmp .fill_bst

.bst_byte:
	movzx rax, byte[rsi+1]
	stosd
	add rsi, 2
	dec rcx
	jmp .fill_bst

.bst_word:
	movzx rax, word[rsi+1]
	stosd
	add rsi, 3
	dec rcx
	jmp .fill_bst

.bst_dword:
	mov eax, dword[rsi+1]
	stosd
	add rsi, 5
	dec rcx
	jmp .fill_bst

.done:
	mov rax, 0
	mov eax, [acpi_bst.remaining_capacity]
	call int_to_float
	mov [.remaining], rax

	mov rax, 0
	mov eax, [acpi_bif.full_charge_capacity]
	call int_to_float
	mov [.maximum], rax

	mov rax, [.remaining]
	mov rbx, [.maximum]
	call float_div

	mov rbx, [.100]
	call float_mul
	call float_to_int

	mov [battery_percentage], rax

	mov rsi, .done_msg
	call kprint

	test [acpi_bst.state], 2
	jz .discharging

	mov rsi, .charging_msg
	call kprint
	jmp .show_percent

.discharging:
	mov rsi, .discharging_msg
	call kprint

.show_percent:
	mov rax, [battery_percentage]
	call int_to_string
	call kprint
	mov rsi, .percent
	call kprint

	popaq
	ret

.no_battery:
	mov rsi, .no_battery_msg
	call kprint

	mov [acpi_battery], 0
	popaq
	ret

.starting_msg			db "[acpi] detecting batteries...",10,0
.no_battery_msg			db "[acpi] no batteries present.",10,0
.done_msg			db "[acpi] found battery ",0
.charging_msg			db "charging ",0
.discharging_msg		db "discharging ",0
.percent			db "%",10,0
.bif				db "_BIF",0
.bst				db "_BST",0
.bif_package			db "    ",0x12,0
.bst_package			db "    ",0x12,0
.remaining			dq 0
.maximum			dq 0
.100				dq 100.0

; dsdt_find_object:
; Finds an object within the ACPI DSDT
; In\	RSI = Object name
; Out\	RSI = Pointer to object, 0 on error

dsdt_find_object:
	pushaq
	mov [.object], rsi

	mov rax, 0
	mov eax, [acpi_fadt.dsdt]
	mov [.dsdt], rax
	mov [.end_dsdt], rax
	mov rax, 0x100000
	add [.end_dsdt], rax

	mov rax, [.dsdt]
	and eax, 0xFFE00000
	mov rbx, rax
	mov rcx, 4
	mov dl, 3
	call vmm_map_memory

	mov rsi, [.object]
	call get_string_size
	mov [.size], rax

	mov rsi, [.dsdt]
	add rsi, ACPI_SDT_SIZE
	mov rdi, [.object]

.loop:
	cmp rsi, [.end_dsdt]
	jge .no
	pushaq
	mov rcx, [.size]
	rep cmpsb
	je .found
	popaq
	inc rsi
	jmp .loop

.found:
	popaq
	mov [.object], rsi
	popaq
	mov rsi, [.object]
	ret

.no:
	popaq
	mov rsi, 0
	ret

.size				dq 0
.dsdt				dq 0
.end_dsdt			dq 0
.object				dq 0

; acpi_sleep:
; Sets an ACPI sleep state
; In\	AL = Sleep state
; Out\	Nothing

acpi_sleep:
	pushaq
	mov [.sleep_state], al

	mov rsi, .starting_msg
	call kprint
	movzx rax, [.sleep_state]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint

	mov al, [.sleep_state]
	add al, '0'
	mov byte[.sx_object+2], al

	mov rsi, .sx_object
	call dsdt_find_object
	cmp rsi, 0
	je .fail
	mov [.sx], rsi

	mov rsi, [.sx]
	add rsi, 7

.do_a:
	lodsb
	cmp al, AML_OPCODE_BYTEPREFIX		; AML byteprefix
	je .byteprefix_a
	mov [.sleep_type_a], al

	jmp .do_b

.byteprefix_a:
	lodsb
	mov [.sleep_type_a], al

.do_b:
	lodsb
	cmp al, AML_OPCODE_BYTEPREFIX
	je .byteprefix_b
	mov [.sleep_type_b], al

	jmp .start_sleeping

.byteprefix_b:
	lodsb
	mov [.sleep_type_b], al

.start_sleeping:
	call disable_interrupts		; prevent interrupts happening at the wrong time
	mov [acpi_sleeping], 1
	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	movzx bx, [.sleep_type_a]
	and bx, 7
	shl bx, 10
	and ax, 0xE3FF
	or ax, bx
	or ax, 0x2000			; enable sleep
	out dx, ax

	mov edx, [acpi_fadt.pm1b_control_block]
	cmp edx, 0
	je .done
	in ax, dx
	movzx bx, [.sleep_type_b]
	and bx, 7
	shl bx, 10
	and ax, 0xE3FF
	or ax, bx
	or ax, 0x2000
	out dx, ax
	call iowait

.done:
	call iowait
	pause
	pause
	pause
	pause
	call iowait

	mov [acpi_sleeping], 0
	popaq
	ret

.fail:
	mov [acpi_sleeping], 0
	mov rsi, .fail_msg
	call kprint
	popaq
	ret

.sleep_state			db 0
.starting_msg			db "[acpi] entering sleep state S",0
.starting_msg2			db "...",10,0
.sx_object			db "_Sx_",0x12,0
.fail_msg			db "[acpi] warning: error while entering sleep state.",10,0
.sx				dq 0
.dsdt				dq 0
.end_dsdt			dq 0
.sleep_type_a			db 0
.sleep_type_b			db 0

; acpi_shutdown:
; Shuts down the system using ACPI

acpi_shutdown:
	mov rsi, .starting_msg
	call kprint

	mov al, 5		; ACPI sleep state S5
	call acpi_sleep

	mov rsi, .fail_msg
	call kprint

	ret

.starting_msg			db "[acpi] attempting ACPI shutdown...",10,0
.fail_msg			db "[acpi] warning: failed to shut down!",10,0

; acpi_reset:
; Resets the system

acpi_reset:
	mov rsi, .starting_msg
	call kprint

	cmp [acpi_fadt.revision], 2		; only exists in version 2+ of the FADT
	jl .bad

	test [acpi_fadt.flags], 0x400		; reset register is an optional feature -- make sure it's supported
	jz .bad

	call disable_interrupts

	; ACPI specs say it can only be mapped in memory, I/O or PCI
	cmp [acpi_reset_register.address_space], 0
	je .memory

	cmp [acpi_reset_register.address_space], 1
	je .io

	cmp [acpi_reset_register.address_space], 2
	je .pci

	jmp .bad

.memory:
	mov rsi, .memory_msg
	call kprint

	mov rdi, [acpi_reset_register.address]
	mov al, [acpi_reset_value]
	mov [rdi], al
	jmp .wait

.io:
	mov rsi, .io_msg
	call kprint

	mov rdx, [acpi_reset_register.address]
	mov al, [acpi_reset_value]
	out dx, al
	jmp .wait

.pci:					; NEEDS TESTING!
					; I don't have any PCs to test this on.
	mov rsi, .pci_msg
	call kprint

	mov al, 0
	mov ah, byte[acpi_reset_register.address]
	mov bl, byte[acpi_reset_register.address+1]
	mov bh, byte[acpi_reset_register.address+2]
	movzx rdx, [acpi_reset_value]
	call pci_write_dword

.wait:
	; For I/O bus, wait for the I/O to complete
	call iowait

	; For memory, flush caches
	call flush_caches

.bad:
	call disable_interrupts
	mov rsi, .fail_msg
	call kprint

	mov al, 0xFE
	out 0x64, al
	call iowait

	mov al, 3
	out 0x92, al
	call iowait

	; If still not reset, triple fault the CPU
	lidt [.idtr]
	int 0
	hlt

.idtr:				dw 0
				dq 0
.starting_msg			db "[acpi] attempting ACPI reset...",10,0
.memory_msg			db "[acpi] memory-mapped reset.",10,0
.io_msg				db "[acpi] I/O bus reset.",10,0
.pci_msg			db "[acpi] PCI bus reset.",10,0
.fail_msg			db "[acpi] warning: failed, falling back to PS/2 reset...",10,0

; shutdown:
; Shuts down the PC

shutdown:
	mov ax, 0x30
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	call wm_kill_all			; destroy all windows

	mov rax, [vbe_screen.width]
	mov rbx, [vbe_screen.height]
	shr rax, 1
	shr rbx, 1

	sub rax, 175
	sub rbx, 64

	; "It's now safe to power off your PC."
	mov si, 350
	mov di, 128
	mov r10, .win_title
	mov rdx, .event
	call wm_create_window

	call acpi_shutdown
	call send_eoi

.hang:
	sti
	jmp .hang

.event:
	ret

.win_title			db "System",0
.win_msg			db "It's now safe to power off your PC.",0

align 16
acpi_fadt:
	; ACPI SDT header
	.signature		rb 4
	.length			rd 1
	.revision		rb 1
	.checksum		rb 1
	.oemid			rb 6
	.oem_table_id		rb 8
	.oem_revision		rd 1
	.creator_id		rd 1
	.creator_revision	rd 1

	; FADT table itself
	.firmware_control	rd 1
	.dsdt			rd 1
	.reserved		rb 1

	.preffered_profile	rb 1
	.sci_interrupt		rw 1
	.smi_command_port	rd 1
	.acpi_enable		rb 1
	.acpi_disable		rb 1
	.s4bios_req		rb 1
	.pstate_control		rb 1
	.pm1a_event_block	rd 1
	.pm1b_event_block	rd 1
	.pm1a_control_block	rd 1
	.pm1b_control_block	rd 1
	.pm2_control_block	rd 1
	.pm_timer_block		rd 1
	.gpe0_block		rd 1
	.gpe1_block		rd 1
	.pm1_event_length	rb 1
	.pm1_control_length	rb 1
	.pm2_control_length	rb 1
	.pm_timer_length	rb 1
	.gpe0_length		rb 1
	.gpe1_length		rb 1
	.gpe1_base		rb 1
	.cstate_control		rb 1
	.worst_c2_latency	rw 1
	.worst_c3_latency	rw 1
	.flush_size		rw 1
	.flush_stride		rw 1
	.duty_offset		rb 1
	.duty_width		rb 1
	.day_alarm		rb 1
	.month_alarm		rb 1
	.century		rb 1

	.boot_arch_flags	rw 1
	.reserved2		rb 1
	.flags			rd 1

acpi_reset_register:
	.address_space		rb 1
	.bit_width		rb 1
	.bit_offset		rb 1
	.access_size		rb 1
	.address		rq 1

acpi_reset_value		rb 1
end_of_acpi_fadt:
acpi_fadt_size			= end_of_acpi_fadt - acpi_fadt

;; 
;; This part of the file is the core of ACPI Machine Language Virtual Machine
;; It is in very early stages of development and may cause undefined opcode errors on real hardware 
;; 

; acpi_run_aml:
; Runs ACPI AML code
; In\	RAX = Address of AML code
; Out\	RAX = Information returned by code, -1 if none

acpi_run_aml:
	mov [.stack], rsp		; this may corrupt the stack so be safe..
	mov [.code], rax
	mov [.callees], 0

	mov rsi, .msg
	call kprint

	mov rsi, [.code]
	call kprint

	mov rsi, newline
	call kprint

	mov rsi, [.code]
	add rsi, 4

.loop:
	push rsi
	cmp byte[rsi], AML_OPCODE_ZERO
	je aml_noop

	cmp byte[rsi], AML_OPCODE_ONE
	je aml_noop

	cmp byte[rsi], AML_OPCODE_ONES
	je aml_noop

	cmp byte[rsi], AML_OPCODE_NAME
	je aml_skip_name

	cmp byte[rsi], AML_OPCODE_PACKAGE
	je aml_skip_package

	cmp byte[rsi], AML_OPCODE_RETURN
	je aml_return

	jmp aml_bad_opcode

.finish:
	cmp rax, -1
	je .no_return

	pushaq
	mov rsi, .return_msg
	call kprint
	popaq
	pushaq
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

	popaq
	mov rsp, [.stack]
	ret

.no_return:
	pushaq
	mov rsi, .no_return_msg
	call kprint
	popaq
	mov rsp, [.stack]
	ret

.stack				dq 0
.code				dq 0
.callees			dq 0
.msg				db "[acpi] interpreting AML method ",0
.return_msg			db "[acpi] done, return value 0x",0
.no_return_msg			db "[acpi] done, no return value present.",0

;;
;; CORE INTERPRETER
;;

aml_bad_opcode:
	mov rsi, .msg
	call kprint

	pop rsi
	mov al, [rsi]
	call hex_byte_to_string
	call kprint

	mov rsi, .msg2
	call kprint

	mov rax, -1
	jmp acpi_run_aml.finish

.msg				db "[acpi] undefined opcode: 0x",0
.msg2				db ", terminating AML execution...",10,0

aml_noop:
	pop rsi
	inc rsi
	jmp acpi_run_aml.loop

aml_skip_name:
	pop rsi
	add rsi, 5
	jmp acpi_run_aml.loop

aml_skip_package:
	pop rsi
	add rsi, 2		; size of package
	movzx rax, byte[rsi]
	mov [.package_size], rax
	mov [.current_size], 0

	inc rsi			; start of package

.loop:
	mov rax, [.current_size]
	cmp [.package_size], rax
	jle .done

	cmp byte[rsi], AML_OPCODE_BYTEPREFIX
	je .byte

	cmp byte[rsi], AML_OPCODE_WORDPREFIX
	je .word

	cmp byte[rsi], AML_OPCODE_DWORDPREFIX
	je .dword

	cmp byte[rsi], AML_OPCODE_QWORDPREFIX
	je .qword

	cmp byte[rsi], AML_OPCODE_STRINGPREFIX
	je .string

	inc rsi
	inc [.current_size]
	jmp .loop

.byte:
	inc [.current_size]
	add rsi, 2
	jmp .loop

.word:
	inc [.current_size]
	add rsi, 3
	jmp .loop

.dword:
	inc [.current_size]
	add rsi, 5
	jmp .loop

.qword:
	inc [.current_size]
	add rsi, 9
	jmp .loop

.string:
	inc rsi
	call get_string_size
	add rsi, rax
	inc rsi
	inc [.current_size]
	jmp .loop

.done:
	jmp acpi_run_aml.loop

.package_size			dq 0
.current_size			dq 0

aml_return:
	inc rsi
	mov rax, 0
	mov eax, [rsi]
	jmp acpi_run_aml.finish

;;
;; AML OPCODE LOOKUP
;;

AML_OPCODE_ZERO			= 0
AML_OPCODE_ONE			= 1
AML_OPCODE_ALIAS		= 6
AML_OPCODE_NAME			= 8
AML_OPCODE_BYTEPREFIX		= 0x0A
AML_OPCODE_WORDPREFIX		= 0x0B
AML_OPCODE_DWORDPREFIX		= 0x0C
AML_OPCODE_STRINGPREFIX		= 0x0D
AML_OPCODE_QWORDPREFIX		= 0x0E

AML_OPCODE_PACKAGE		= 0x12
AML_OPCODE_RETURN		= 0xA4
AML_OPCODE_ONES			= 0xFF




