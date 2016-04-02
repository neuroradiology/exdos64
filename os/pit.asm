
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "PIT timer driver",0

;; Functions:
; init_pit
; disable_pit
; pit_irq
; pit_sleep

; init_pit:
; Initializes the PIT

init_pit:
	call disable_interrupts

	mov rsi, .msg
	call kprint
	mov rax, TIMER_FREQUENCY
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	mov al, 0x36
	out 0x43, al
	call iowait

	mov rbx, TIMER_FREQUENCY
	mov rdx, 0
	mov rax, 1193182
	div rbx

	out 0x40, al
	call iowait

	mov al, ah
	out 0x40, al
	call iowait

	mov rbp, pit_irq
	mov al, 0
	call install_irq

	ret

.msg				db "[pit] initializing PIT to ",0
.msg2				db " Hz.",10,0

; disable_pit:
; Disables the PIT

disable_pit:
	mov rsi, .msg
	call kprint

	call enable_interrupts
	mov al, 0x30
	out 0x43, al

	; wait for any queued IRQs to happen
	mov rcx, 0xFFFF

.wait:
	nop
	nop
	nop
	nop
	nop
	nop
	out 0x80, al
	out 0x80, al
	loop .wait

	ret

.msg				db "[pit] disabling PIT...",10,0

; pit_irq:
; PIT IRQ0 handler
align 16
pit_irq:
	pushaq
	call timer_irq_common
	popaq
	call send_eoi
	iretq

align 16
.tmp				dq 0

; pit_sleep:
; Sleeps for RAX 1/100 seconds
; In\	RAX = Time to sleep
; Out\	Nothing

pit_sleep:
	call enable_interrupts
	add rax, [timer_ticks]

.loop:
	cmp rax, [timer_ticks]
	jge .loop

	ret





