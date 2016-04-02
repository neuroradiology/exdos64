
;;
;; Ex86 -- A free and open source x86 emulator for 64-bit software
;; (C) 2016 by Omar Mohammad, all rights reserved
;; Intended to replace v8086 without requiring VMX, and with 32-bit pmode support!
;; For information:
;;  [ omarx024@gmail.com ] 
;;

use64

ex86_cli:
	cli
	and [ex86_state.eflags], not 0x200
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_sti:
	sti
	or [ex86_state.eflags], 0x200
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_hlt:
	inc [ex86_state.eip]
	hlt
	jmp ex86_interpret

ex86_cld:
	and [ex86_state.eflags], not 0x400
	inc [ex86_state.eip]
	jmp ex86_interpret

ex86_std:
	or [ex86_state.eflags], 0x400
	inc [ex86_state.eip]
	jmp ex86_interpret




