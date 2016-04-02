
;;
;; Ex86 -- A free and open source x86 emulator for 64-bit software
;; (C) 2016 by Omar Mohammad, all rights reserved
;; Intended to replace v8086 without requiring VMX, and with 32-bit pmode support!
;; For information:
;;  [ omarx024@gmail.com ] 
;;

use64

;-----------------------------------------------------------;
; ex86_state:
; Description:	Ex86 register state
;-----------------------------------------------------------;

ex86_state:
	.eax			dd 0
	.ebx			dd 0
	.ecx			dd 0
	.edx			dd 0
	.esi			dd 0
	.edi			dd 0
	.ebp			dd 0
	.esp			dd 0

	.eip			dd 0
	.eflags			dd 0

	.cs			dw 0
	.ds			dw 0
	.es			dw 0
	.fs			dw 0
	.gs			dw 0

	.cr0			dd 0
	.gdt_base		dd 0
	.gdt_limit		dw 0
	.idt_base		dd 0
	.idt_limit		dw 0
ex86_state_size			= $ - ex86_state

ex86_address_size		db 0
ex86_operand_size		db 0
ex86_rep			db 0

;-----------------------------------------------------------;
; run_ex86:                                                 ;
; Description:	Starts the Ex86 virtual machine             ;
; Params:	CX:DX = Segment:Offset of realmode code     ;
; Output:	RAX = Pointer to register state             ;
;-----------------------------------------------------------;

run_ex86:
	push rcx
	push rdx

	; clear the VM state
	mov rdi, ex86_state
	mov rcx, ex86_state_size
	mov al, 0
	rep stosb

	mov [ex86_state.edx], 0x80
	mov [ex86_state.cr0], 0x00000010

	mov [ex86_address_size], 0
	mov [ex86_operand_size], 0
	mov [ex86_rep], 0

	pop rdx
	pop rcx

	mov [ex86_state.cs], cx
	mov word[ex86_state.eip], dx

	jmp ex86_interpret

.quit:
	mov rax, ex86_state
	ret

include			"ex86/interpreter.asm"
include			"ex86/basic.asm"
include			"ex86/io.asm"





