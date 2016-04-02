
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Internal kernel debugger",0

;; Functions:
; kprint
; boot_error_early
; start_debugging

KDEBUGGER_BASE			= 0x60000
kdebugger_free_area		dq KDEBUGGER_BASE
is_debugging_mode		db 0

; kprint:
; Prints a kernel debug message
; In\	RSI = String
; Out\	Nothing

kprint:
	pushaq
	mov [.string], rsi

	mov rdi, [kdebugger_free_area]
	cmp byte[rdi-1], 10		; newline
	jne .normal_print

.print_prefix:
	mov rdi, [kdebugger_free_area]
	mov byte[rdi], '['
	inc rdi
	push rdi
	mov rax, [timer_ticks]
	call hex_qword_to_string
	mov rcx, 2
	pop rdi
	push rsi
	rep movsq
	mov byte[rdi], ']'
	mov byte[rdi+1], ' '
	inc rdi
	inc rdi
	mov [kdebugger_free_area], rdi

	mov al, '['
	call send_byte_via_serial
	pop rsi
	call send_string_via_serial
	mov al, ']'
	call send_byte_via_serial
	mov al, ' '
	call send_byte_via_serial

.normal_print:
	mov rsi, [.string]
	call get_string_size
	mov rdi, [kdebugger_free_area]
	mov rsi, [.string]
	mov rcx, rax
	rep movsb
	mov [kdebugger_free_area], rdi
	mov byte[rdi], 0

	mov rsi, [.string]
	call send_string_via_serial

	cmp [is_debugging_mode], 0
	je .quit

	mov rsi, [.string]
	call print_string_cursor

.quit:
	popaq
	ret

.string				dq 0

; boot_error_early:
; Handler for early boot errors
; In\	RSI = Text to display
; Out\	Nothing

boot_error_early:
	mov [.text], rsi
	pushaq

	mov rax, [vbe_screen.height]
	inc rax
	mov rbx, [vbe_screen.bytes_per_line]
	mul rbx
	mov [vbe_screen.size_bytes], rax

	mov rax, [vbe_screen.width]
	mov rbx, [vbe_screen.height]
	mul rbx
	mov [vbe_screen.size_pixels], rax

	movzx rax, [vbe_info_block.memory]
	mov rbx, 64
	mul rbx
	mov [vbe_memory_kb], rax
	mov rbx, 1024
	mul rbx
	mov [vbe_memory_bytes], rax
	mov rbx, 0x200000
	call round_forward
	shr rax, 21
	mov [vbe_memory_pages], rax

	mov rax, [vbe_screen.physical_buffer]
	mov rbx, VBE_VIRTUAL_BUFFER
	mov rcx, [vbe_memory_pages]
	mov dl, 3
	call vmm_map_memory

	mov rax, [vbe_screen.physical_buffer]
	mov rbx, VBE_BACK_BUFFER
	mov rcx, [vbe_memory_pages]
	mov dl, 3
	call vmm_map_memory

	mov [redraw_enabled], 0
	mov ebx, 0x800000
	call clear_screen

	mov ebx, 0x800000
	mov ecx, 0x9F9F9F
	call set_text_color

	mov rsi, .msg
	call print_string_cursor

	mov ebx, 0x800000
	mov ecx, 0xFFFFFF
	call set_text_color

	mov rsi, [.text]
	call print_string_cursor

	mov ebx, 0x800000
	mov ecx, 0x9F9F9F
	call set_text_color

	jmp $

.text					dq 0
.msg					db 10
					db " ExDOS64",10
					db "=========",10,10
					db " An error has occured during startup. This can occur due to incompatible hardware configurations.",10
					db " If you want to help me fix the problem, you can copy the error message shown below and",10
					db " send it to me at omarx024@gmail.com",10,10
					db "   ERROR DESCRIPTION: ",0
.dump_msg				db "   DUMPING REGISTERS: ",10,0

; start_debugging:
; Starts the kernel debugger

start_debugging:
	call unlock_screen

	mov [.string], rsi
	mov ebx, 0x000080
	call clear_screen

	mov ebx, 0x000080
	mov ecx, 0xFFFFFF
	call set_text_color

	mov [is_debugging_mode], 1

	call show_text_cursor
	mov rsi, newline
	call print_string_cursor
	mov rsi, kernel_version
	call print_string_cursor
	mov rsi, .debugger_title
	call print_string_cursor

	mov rsi, .hint_msg
	call print_string_cursor

	mov rsi, [.string]
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor

.start:
	call enable_interrupts
	mov rsi, .start_msg
	call print_string_cursor

.cmd:
	mov rsi, newline
	call print_string_cursor

	mov rsi, .prompt
	call print_string_cursor

	mov dl, 64
	call get_string_echo

	push rsi
	mov rsi, newline
	call print_string_cursor
	pop rsi

	cmp byte[rsi], 0
	je .cmd

	push rsi
	mov rdi, .help_command
	mov rcx, 4
	rep cmpsb
	je kdebug_help
	pop rsi

	push rsi
	mov rdi, .echo_command
	mov rcx, 4
	rep cmpsb
	je kdebug_echo
	pop rsi

	push rsi
	mov rdi, .inportb_command
	mov rcx, 7
	rep cmpsb
	je kdebug_inportb
	pop rsi

	push rsi
	mov rdi, .inportw_command
	mov rcx, 7
	rep cmpsb
	je kdebug_inportw
	pop rsi

	push rsi
	mov rdi, .inportd_command
	mov rcx, 7
	rep cmpsb
	je kdebug_inportd
	pop rsi

	push rsi
	mov rdi, .debugmsg_command
	mov rcx, 8
	rep cmpsb
	je kdebug_debugmsg
	pop rsi

	push rsi
	mov rdi, .poweroff_command
	mov rcx, 8
	rep cmpsb
	je kdebug_poweroff
	pop rsi

	push rsi
	mov rdi, .outportb_command
	mov rcx, 8
	rep cmpsb
	je kdebug_outportb
	pop rsi

	push rsi
	mov rdi, .outportw_command
	mov rcx, 8
	rep cmpsb
	je kdebug_outportw
	pop rsi

	push rsi
	mov rdi, .outportd_command
	mov rcx, 8
	rep cmpsb
	je kdebug_outportd
	pop rsi

	push rsi
	mov rdi, .clear_command
	mov rcx, 5
	rep cmpsb
	je kdebug_clear
	pop rsi

	push rsi
	mov rdi, .reboot_command
	mov rcx, 6
	rep cmpsb
	je kdebug_reboot
	pop rsi

	push rsi
	mov rdi, .dumpcr_command
	mov rcx, 6
	rep cmpsb
	je kdebug_dumpcr
	pop rsi

	push rsi
	mov rdi, .meminfo_command
	mov rcx, 7
	rep cmpsb
	je kdebug_meminfo
	pop rsi

	push rsi
	mov rdi, .memspeed_command
	mov rcx, 8
	rep cmpsb
	je kdebug_memspeed
	pop rsi

	push rsi
	mov rdi, .apicinfo_command
	mov rcx, 8
	rep cmpsb
	je kdebug_apicinfo
	pop rsi

	mov rsi, .no_command
	call print_string_cursor
	jmp .cmd

.string				dq 0
.debugger_title			db " -- built-in kernel debugger",10,0
.hint_msg			db "Copyright (C) 2015-2016 by Omar Mohammad, all rights reserved.",10
				db "Reason for debugging: ",0
.start_msg			db "Type `help` for a list of commands and descriptions.",10,0
.prompt				db ">",0
.no_prompt			db "Cannot display prompt because the I/O APIC has not yet been enabled...",0
.no_command			db "Unknown command.",10,0
.help_command			db "help"
.echo_command			db "echo"
.inportb_command		db "inportb"
.inportw_command		db "inportw"
.inportd_command		db "inportd"
.debugmsg_command		db "debugmsg"
.poweroff_command		db "poweroff"
.outportb_command		db "outportb"
.outportw_command		db "outportw"
.outportd_command		db "outportd"
.reboot_command			db "reboot"
.clear_command			db "clear"
.dumpcr_command			db "dumpcr"
.meminfo_command		db "meminfo"
.memspeed_command		db "memspeed"
.apicinfo_command		db "apicinfo"

; kdebug_help:
; help command

kdebug_help:
	add rsp, 8		; clean up stack
	mov rsi, .msg
	call print_string_cursor

	jmp start_debugging.cmd

.msg				db "List of commands:",10
				db " apicinfo               -- Displays APIC information",10
				db " clear                  -- Clears the screen",10
				db " debugmsg               -- Shows kernel debug messages",10
				db " dumpcr                 -- Dumps control registers",10
				db " echo                   -- Prints a string",10
				db " inportb [port]         -- Displays the byte data from I/O port [port] in hex.",10
				db " inportd [port]         -- Displays the 32-bit dword data from I/O port [port] in hex.",10
				db " inportw [port]         -- Displays the 16-bit word data from I/O port [port] in hex.",10
				db " meminfo                -- Displays memory usage.",10
				db " memspeed               -- Measures memory access speed.",10
				db " outportb [port] [data] -- Writes the byte data in [data] to I/O port [port].",10
				db " outportd [port] [data] -- Writes the 32-bit dword data in [data] to I/O port [port].",10
				db " outportw [port] [data] -- Writes the 16-bit word data in [data] to I/O port [port.",10
				db " poweroff               -- Powers off the system using ACPI.",10
				db " reboot                 -- Reboots the PC using ACPI.",10
				db 0

; kdebug_echo:
; echo command

kdebug_echo:
	pop rsi
	add rsi, 5
	cmp byte[rsi], 0
	je start_debugging.cmd

	call print_string_cursor
	mov rsi, newline
	call print_string_cursor
	jmp start_debugging.cmd

; kdebug_inportb:
; inportb command

kdebug_inportb:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	push rsi
	mov rsi, .prefix
	call print_string_cursor
	pop rsi

	call hex_string_to_value
	mov dx, ax
	in al, dx
	call hex_byte_to_string
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor
	jmp start_debugging.cmd

.prefix				db "0x",0

; kdebug_inportw:
; inportw command

kdebug_inportw:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	push rsi
	mov rsi, .prefix
	call print_string_cursor
	pop rsi

	call hex_string_to_value
	mov dx, ax
	in ax, dx
	call hex_word_to_string
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor
	jmp start_debugging.cmd

.prefix				db "0x",0

; kdebug_inportd:
; inportd command

kdebug_inportd:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	push rsi
	mov rsi, .prefix
	call print_string_cursor
	pop rsi

	call hex_string_to_value
	mov dx, ax
	in eax, dx
	call hex_dword_to_string
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor
	jmp start_debugging.cmd

.prefix				db "0x",0

; kdebug_debugmsg:
; debugmsg command

kdebug_debugmsg:
	pop rsi
	mov rsi, KDEBUGGER_BASE
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor
	jmp start_debugging.cmd

; kdebug_poweroff:
; poweroff command

kdebug_poweroff:
	pop rsi
	call acpi_shutdown

	mov rsi, .failure
	call print_string_cursor
	jmp start_debugging.cmd

.failure			db "Failed to shut down...",10,0

; kdebug_outportb:
; outportb command

kdebug_outportb:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	mov rdi, .port

.get_port:
	lodsb
	cmp al, 0
	je start_debugging.cmd
	cmp al, 0x20
	je .get_value_stub

	stosb
	jmp .get_port

.get_value_stub:
	mov rdi, .value

.get_value:
	lodsb
	cmp al, 0
	je .start

	stosb
	jmp .get_value

.start:
	mov rsi, .port
	call hex_string_to_value
	mov [.port_num], rax

	mov rsi, .value
	call hex_string_to_value
	mov [.value_num], rax

	mov rdx, [.port_num]
	mov rax, [.value_num]
	out dx, al
	jmp start_debugging.cmd

.port:				times 16 db 0
.value:				times 16 db 0
.port_num			dq 0
.value_num			dq 0

; kdebug_outportw:
; outportw command

kdebug_outportw:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	mov rdi, .port

.get_port:
	lodsb
	cmp al, 0
	je start_debugging.cmd
	cmp al, 0x20
	je .get_value_stub

	stosb
	jmp .get_port

.get_value_stub:
	mov rdi, .value

.get_value:
	lodsb
	cmp al, 0
	je .start

	stosb
	jmp .get_value

.start:
	mov rsi, .port
	call hex_string_to_value
	mov [.port_num], rax

	mov rsi, .value
	call hex_string_to_value
	mov [.value_num], rax

	mov rdx, [.port_num]
	mov rax, [.value_num]
	out dx, ax
	jmp start_debugging.cmd

.port:				times 16 db 0
.value:				times 16 db 0
.port_num			dq 0
.value_num			dq 0

; kdebug_outportd:
; outportd command

kdebug_outportd:
	pop rsi
	add rsi, 8
	cmp byte[rsi], 0
	je start_debugging.cmd

	mov rdi, .port

.get_port:
	lodsb
	cmp al, 0
	je start_debugging.cmd
	cmp al, 0x20
	je .get_value_stub

	stosb
	jmp .get_port

.get_value_stub:
	mov rdi, .value

.get_value:
	lodsb
	cmp al, 0
	je .start

	stosb
	jmp .get_value

.start:
	mov rsi, .port
	call hex_string_to_value
	mov [.port_num], rax

	mov rsi, .value
	call hex_string_to_value
	mov [.value_num], rax

	mov rdx, [.port_num]
	mov rax, [.value_num]
	out dx, eax
	jmp start_debugging.cmd

.port:				times 16 db 0
.value:				times 16 db 0
.port_num			dq 0
.value_num			dq 0

; kdebug_clear:
; clear command

kdebug_clear:
	pop rsi
	mov ebx, 0x000080
	call clear_screen

	mov ebx, 0x000080
	mov ecx, 0xFFFFFF
	call set_text_color

	jmp start_debugging.cmd

; kdebug_reboot:
; reboot command

kdebug_reboot:
	pop rsi
	call acpi_reset
	cli
	hlt

; kdebug_dumpcr:
; dumpcr command

kdebug_dumpcr:
	pop rsi

	mov rsi, .cr0
	call print_string_cursor

	mov rax, cr0
	call hex_dword_to_string
	call print_string_cursor

	mov rsi, .cr2
	call print_string_cursor

	mov rax, cr2
	call hex_qword_to_string
	call print_string_cursor

	mov rsi, .cr3
	call print_string_cursor

	mov rax, cr3
	call hex_dword_to_string
	call print_string_cursor

	mov rsi, .cr4
	call print_string_cursor

	mov rax, cr4
	call hex_dword_to_string
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor

	jmp start_debugging.cmd


.cr0				db "CR0: 0x",0
.cr2				db "  CR2: 0x",0
.cr3				db "  CR3: 0x",0
.cr4				db "  CR4: 0x",0

; kdebug_meminfo:
; meminfo command

kdebug_meminfo:
	pop rsi

	mov rsi, .total
	call kprint
	mov rax, [total_memory_mb]
	call int_to_string
	call kprint
	mov rsi, .mb
	call kprint

	mov rsi, .usable
	call kprint
	mov rax, [usable_memory_mb]
	call int_to_string
	call kprint
	mov rsi, .mb
	call kprint

	mov rsi, .used
	call kprint
	mov rax, [used_memory_mb]
	call int_to_string
	call kprint
	mov rsi, .mb
	call kprint

	mov rsi, .free
	call kprint
	mov rax, [free_memory_mb]
	call int_to_string
	call kprint
	mov rsi, .mb
	call kprint

	call parse_memory_map

	jmp start_debugging.cmd

.total				db "Total memory: ",0
.usable				db "Usable memory: ",0
.used				db "Used memory: ",0
.free				db "Free memory: ",0
.mb				db " MB",10,0

; kdebug_memspeed:
; memspeed command

kdebug_memspeed:
	pop rsi

.do_byte:
	; start with the speed of MOVSB
	mov rax, [timer_ticks]
	mov [.speed_byte], rax

	mov rsi, 0
	mov rdi, 0
	mov rcx, 0x800000
	rep movsb

	mov rax, [timer_ticks]
	sub rax, [.speed_byte]
	mov [.speed_byte], rax

	mov rsi, .byte
	call print_string_cursor
	mov rsi, .speed_msg
	call print_string_cursor
	mov rax, [.speed_byte]
	call int_to_string
	call print_string_cursor
	mov rsi, .speed_msg2
	call print_string_cursor

.do_qword:
	; the speed of MOVSQ
	mov rax, [timer_ticks]
	mov [.speed_qword], rax

	mov rsi, 0
	mov rdi, 0
	mov rcx, 0x800000/8
	rep movsq

	mov rax, [timer_ticks]
	sub rax, [.speed_qword]
	mov [.speed_qword], rax

	mov rsi, .qword
	call print_string_cursor
	mov rsi, .speed_msg
	call print_string_cursor
	mov rax, [.speed_qword]
	call int_to_string
	call print_string_cursor
	mov rsi, .speed_msg2
	call print_string_cursor

.do_memcpy:
	; the speed of MEMCPY
	mov rax, [timer_ticks]
	mov [.speed_memcpy], rax

	mov rsi, 0
	mov rdi, 0
	mov rcx, 0x800000
	call memcpy

	mov rax, [timer_ticks]
	sub rax, [.speed_memcpy]
	mov [.speed_memcpy], rax

	cmp [is_there_avx], 0
	je .sse

.avx:
	mov rsi, .avx_memcpy
	call print_string_cursor
	mov rsi, .speed_msg
	call print_string_cursor
	mov rax, [.speed_memcpy]
	call int_to_string
	call print_string_cursor
	mov rsi, .speed_msg2
	call print_string_cursor

	mov rax, [timer_ticks]
	mov [.speed_memcpy], rax

	mov rsi, 0
	mov rdi, 0
	mov rcx, 0x800000
	call memcpy_u

	mov rax, [timer_ticks]
	sub rax, [.speed_memcpy]
	mov [.speed_memcpy], rax

.sse:
	mov rsi, .sse_memcpy
	call print_string_cursor
	mov rsi, .speed_msg
	call print_string_cursor
	mov rax, [.speed_memcpy]
	call int_to_string
	call print_string_cursor
	mov rsi, .speed_msg2
	call print_string_cursor

	jmp start_debugging.cmd

.byte				db "Speed of MOVSB: ",0
.qword				db "Speed of MOVSQ: ",0
.sse_memcpy			db "Speed of SSE MEMCPY: ",0
.avx_memcpy			db "Speed of AVX MEMCPY: ",0
.speed_byte			dq 0
.speed_qword			dq 0
.speed_memcpy			dq 0
.speed_msg			db "8 MB/",0
.speed_msg2			db " milliseconds.",10,0


; kdebug_apicinfo:
; apicinfo command

kdebug_apicinfo:
	jmp start_debugging.cmd


