
;;
;; Ex86 -- A free and open source x86 emulator for 64-bit software
;; (C) 2016 by Omar Mohammad, all rights reserved
;; Intended to replace v8086 without requiring VMX, and with 32-bit pmode support!
;; For information:
;;  [ omarx024@gmail.com ] 
;;

use64

ex86_in_al_dx:
	mov edx, [ex86_state.edx]
	in al, dx
	mov byte[ex86_state.eax], al
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_in_ax_dx:
	cmp [ex86_operand_size], 0
	je .16

.32:
	mov edx, [ex86_state.edx]
	in eax, dx
	mov [ex86_state.eax], eax
	inc [ex86_state.eip]
	jmp ex86_interpret

.16:
	mov edx, [ex86_state.edx]
	in ax, dx
	mov word[ex86_state.eax], ax
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_in_al_imm8:
	movzx edx, byte[rsi+1]
	in al, dx
	mov byte[ex86_state.eax], al
	add [ex86_state.eip], 2
	jmp ex86_interpret

ex86_in_ax_imm8:
	movzx edx, byte[rsi+1]
	cmp [ex86_operand_size], 0
	je .16

.32:
	in eax, dx
	mov [ex86_state.eax], eax
	add [ex86_state.eip], 2
	jmp ex86_interpret

.16:
	in ax, dx
	mov word[ex86_state.eax], ax
	add [ex86_state.eip], 2
	jmp ex86_interpret

ex86_out_dx_al:
	mov edx, [ex86_state.edx]
	mov eax, [ex86_state.eax]
	out dx, al
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_out_dx_ax:
	mov edx, [ex86_state.edx]
	mov eax, [ex86_state.eax]
	cmp [ex86_operand_size], 0
	je .16

.32:
	out dx, eax
	inc [ex86_state.eip]
	jmp ex86_interpret

.16:
	out dx, ax
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_out_imm8_al:
	movzx edx, byte[rsi+1]
	mov eax, [ex86_state.eax]
	out dx, al
	add [ex86_state.eip], 2
	jmp ex86_interpret

ex86_out_imm8_ax:
	movzx edx, byte[rsi+1]
	mov eax, [ex86_state.eax]
	cmp [ex86_operand_size], 0
	je .16

.32:
	out dx, eax
	add [ex86_state.eip], 2
	jmp ex86_interpret

.16:
	out dx, ax
	add [ex86_state.eip], 2
	jmp ex86_interpret





