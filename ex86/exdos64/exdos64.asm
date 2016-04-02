
;;
;; Ex86 -- A free and open source x86 emulator for 64-bit software
;; (C) 2016 by Omar Mohammad, all rights reserved
;; Intended to replace v8086 without requiring VMX, and with 32-bit pmode support!
;; For information:
;;  [ omarx024@gmail.com ] 
;;

use64

;; ExDOS64-specific routines

ex86_trace:
	call kprint
	ret

include				"ex86/ex86.asm"

