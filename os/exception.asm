
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Exception Handlers",0

divide_error_msg			db "Divide by zero.",0
debug_error_msg				db "Debug interrupt.",0
nmi_error_msg				db "Non-maskable interrupt.",0
breakpoint_error_msg			db "Breakpoint.",0
overflow_error_msg			db "Overflow.",0
bound_error_msg				db "BOUND range exceeded.",0
opcode_error_msg			db "Undefined opcode.",0
device_error_msg			db "Device not present.",0
double_fault_error_msg			db "Double fault.",0
coprocessor_error_msg			db "Coprocessor segment overrun.",0
tss_error_msg				db "Corrupt task state segment.",0
segment_error_msg			db "Memory segment not present.",0
stack_error_msg				db "Stack segment fault.",0
gpf_error_msg				db "General protection fault.",0
page_fault_error_msg			db "Page fault (0x"
page_fault_address			db "0000000000000000, error code "
page_fault_error_code			db "0).",0

; init_exceptions:
; Install exceptions handlers

init_exceptions:
	mov al, 0
	mov rbp, divide_error
	call install_isr

	mov al, 1
	mov rbp, debug_error
	call install_isr

	mov al, 2
	mov rbp, nmi_error
	call install_isr

	mov al, 3
	mov rbp, breakpoint_error
	call install_isr

	mov al, 4
	mov rbp, overflow_error
	call install_isr

	mov al, 5
	mov rbp, bound_error
	call install_isr

	mov al, 6
	mov rbp, opcode_error
	call install_isr

	mov al, 7
	mov rbp, device_error
	call install_isr

	mov al, 8
	mov rbp, double_fault_error
	call install_isr

	mov al, 9
	mov rbp, coprocessor_error
	call install_isr

	mov al, 10
	mov rbp, tss_error
	call install_isr

	mov al, 11
	mov rbp, segment_error
	call install_isr

	mov al, 12
	mov rbp, stack_error
	call install_isr

	mov al, 13
	mov rbp, gpf_error
	call install_isr

	mov al, 14
	mov rbp, page_fault_error
	call install_isr

	ret

; exception_handler:
; Handler for exceptions
; In\	RSI = String to print
; Out\	Nothing

exception_handler:
	mov [.string], rsi

	mov ebx, 0x000080
	call clear_screen

	mov ebx, 0x000080
	mov ecx, 0xFFFFFF
	call set_text_color

	mov rsi, .exception_title
	call print_string_cursor
	mov rsi, [.string]
	call print_string_cursor

	mov rsi, newline
	call print_string_cursor

	add rsp, 8
	mov rax, [rsp]
	call hex_qword_to_string
	mov rdi, .rip
	mov rcx, 16
	rep movsb

	mov rax, [rsp+32]
	call hex_word_to_string
	mov rdi, .ss
	mov rcx, 4
	rep movsb

	mov rax, [rsp+24]
	call hex_qword_to_string
	mov rdi, .rsp
	mov rcx, 16
	rep movsb

	mov rsi, .regs
	call print_string_cursor

	call wait_second
	call wait_second
	call wait_second

	mov rsi, KDEBUGGER_BASE
	call print_string_cursor

	jmp $

.exception_title			db 10," A FATAL ERROR HAS OCCURED AND CANNOT BE RECOVERED!",10
					db " PLEASE RECORD THE INFORMATION BELOW AND REPORT THIS.",10," ",0
.string					dq 0
.regs					db " rip: "
.rip					db "0000000000000000  ss: "
.ss					db "0000  rsp: "
.rsp					db "0000000000000000",10,0

; EXCEPTION HANDLERS

divide_error:
	mov rsi, divide_error_msg
	jmp exception_handler

debug_error:
	mov rsi, debug_error_msg
	jmp exception_handler

nmi_error:
	mov rsi, nmi_error_msg
	jmp exception_handler

breakpoint_error:
	mov rsi, breakpoint_error_msg
	jmp exception_handler

overflow_error:
	mov rsi, overflow_error_msg
	jmp exception_handler

bound_error:
	mov rsi, bound_error_msg
	jmp exception_handler

opcode_error:
	mov rsi, opcode_error_msg
	jmp exception_handler

device_error:
	mov rsi, device_error_msg
	jmp exception_handler

double_fault_error:
	mov rsi, double_fault_error_msg
	jmp exception_handler

coprocessor_error:
	mov rsi, coprocessor_error_msg
	jmp exception_handler

tss_error:
	mov rsi, tss_error_msg
	jmp exception_handler

segment_error:
	mov rsi, segment_error_msg
	jmp exception_handler

stack_error:
	mov rsi, stack_error_msg
	jmp exception_handler

gpf_error:
	mov rsi, gpf_error_msg
	jmp exception_handler

page_fault_error:
	mov eax, [rsp]
	call int_to_string
	mov al, [rsi]
	mov [page_fault_error_code], al

	mov rax, cr2
	call hex_qword_to_string
	mov rdi, page_fault_address
	mov rcx, 16
	rep movsb

	mov rsi, page_fault_error_msg
	jmp exception_handler





