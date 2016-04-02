
;;
;; Ex86 -- A free and open source x86 emulator for 64-bit software
;; (C) 2016 by Omar Mohammad, all rights reserved
;; Intended to replace v8086 without requiring VMX, and with 32-bit pmode support!
;; For information:
;;  [ omarx024@gmail.com ] 
;;

use64

ex86_interpret:
	mov [ex86_operand_size], 0
	mov [ex86_address_size], 0

.skip_prefix:
	movzx rsi, word[ex86_state.cs]
	shl rsi, 4
	add esi, [ex86_state.eip]

	; Check for quit
	cmp word[rsi], 0xFFCD		; int 0xFF
	je run_ex86.quit

	; Override prefixes
	cmp byte[rsi], 0x66
	je ex86_operand_override

	cmp byte[rsi], 0x67
	je ex86_address_override

	; Flag instructions
	cmp byte[rsi], 0xF4
	je ex86_hlt

	cmp byte[rsi], 0xFA
	je ex86_cli

	cmp byte[rsi], 0xFB
	je ex86_sti

	cmp byte[rsi], 0xFC
	je ex86_cld

	cmp byte[rsi], 0xFD
	je ex86_std

	; I/O opcodes
	cmp byte[rsi], 0xEC
	je ex86_in_al_dx

	cmp byte[rsi], 0xED
	je ex86_in_ax_dx

	cmp byte[rsi], 0xE4
	je ex86_in_al_imm8

	cmp byte[rsi], 0xE5
	je ex86_in_ax_imm8

	cmp byte[rsi], 0xEE
	je ex86_out_dx_al

	cmp byte[rsi], 0xEF
	je ex86_out_dx_ax

	cmp byte[rsi], 0xE6
	je ex86_out_imm8_al

	cmp byte[rsi], 0xE7
	je ex86_out_imm8_ax

	jmp run_ex86.quit

ex86_operand_override:
	not [ex86_operand_size]
	inc [ex86_state.eip]
	jmp ex86_interpret.skip_prefix

ex86_address_override:
	not [ex86_address_size]
	inc [ex86_state.eip]
	jmp ex86_interpret.skip_prefix







