
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "PS/2 mouse driver",0

;; Functions:
; send_mouse_data
; init_mouse
; mouse_irq
; get_mouse_status
; set_mouse_cursor
; show_mouse_cursor
; hide_mouse_cursor
; redraw_cursor

align 16			; for faster memory access
mouse_x				dq 0
mouse_y				dq 0
mouse_status			dq 0
old_mouse_x			dq 0
old_mouse_y			dq 0
old_mouse_status		dq 0

align 16
mouse_width			dq 0
mouse_height			dq 0
mouse_color			dd 0
align 16
is_mouse_visible		db 0
align 16
mouse_speed			dq 0	; mouse speed is x1
					; control mouse speed from here
					; 0 = x1, 1 = x2, 2 = x4, 3 = x8

align 16
mouse_id			db 0

align 16
mouse_color2			dq 0

; send_mouse_data:
; Sends a command or data to the mouse
; In\	AL = Command or data byte
; Out\	Nothing

send_mouse_data:
	push rax

	call wait_ps2_write
	mov al, 0xD4
	out 0x64, al

	call wait_ps2_write		; this command doesn't generate an ACK
	pop rax
	out 0x60, al			; send the command/data

	ret

; init_mouse:
; Initializes the PS/2 mouse

init_mouse:
	mov rsi, .starting_msg
	call kprint

	mov al, 12
	mov rbp, mouse_irq
	call install_irq		; install mouse IRQ handler

	; mask the IRQ
	mov al, 12
	call mask_irq

	call disable_interrupts

	; enable auxiliary mouse device
	call wait_ps2_write
	mov al, 0xA8
	out 0x64, al

.retry_reset:
	mov al, 0xFF
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60
	cmp al, 0xFC
	je .no_mouse

.wait_for_status:
	; The mouse will return 0xAA on success.
	call wait_ps2_read
	in al, 0x60

	cmp al, 0xAA
	je .reset_finished

	cmp al, 0xFC
	je .no_mouse

	jmp .wait_for_status

.reset_finished:
	call wait_ps2_read
	in al, 0x60			; read MouseID byte
	mov [mouse_id], al

	;call init_mouse_scroll		; still no support for scrollwheel mice

	; disable packets
	mov al, 0xF5
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	; set resolution
	mov al, 0xE8
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 3
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	; set packets per second
	mov al, 0xF3
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 200
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	; enable packets
	mov al, 0xF4
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	; enable IRQ 12
	call wait_ps2_write
	mov al, 0x20
	out 0x64, al

	call wait_ps2_read
	in al, 0x60
	or al, 2
	push rax

	call wait_ps2_write
	mov al, 0x60
	out 0x64, al

	call wait_ps2_write
	pop rax
	out 0x60, al
	call iowait

	; mouse by default is gray 16x16
	mov rax, 16
	mov rbx, 16
	mov edx, 0x808080
	call set_mouse_cursor

	; position mouse at center of screen
	call get_screen_center
	mov [mouse_x], rax
	mov [mouse_y], rbx

	; and of course, the mouse by default is hidden during boot time
	call hide_mouse_cursor

	call enable_interrupts
	call iowait
	call iowait
	call iowait
	call iowait
	;call wait_second

	; unmask the IRQ
	mov al, 12
	call unmask_irq

	ret

.no_mouse:
	mov rsi, .no_mouse_msg
	call kprint

	mov rsi, .no_mouse_msg
	call boot_error_early

	jmp $

.starting_msg			db "[ps2] initializing PS/2 mouse...",10,0
.no_mouse_msg			db "[ps2] no PS/2 mouse found.",10,0
.reset_try			db 0
.status_wait			db 0

; init_mouse_scroll:
; Tries to initialize the mouse scroll wheel

init_mouse_scroll:
	mov al, 0xF3
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 200
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60


	mov al, 0xF3
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 100
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 0xF3
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 80
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	mov al, 0xF2
	call send_mouse_data

	call wait_ps2_read
	in al, 0x60

	call wait_ps2_read
	in al, 0x60
	mov [mouse_id], al
	cmp al, 3
	je .yes

	ret

.yes:
	mov rsi, .msg
	call kprint

	ret

.msg				db "[ps2] scroll wheel mouse detected.",10,0

; mouse_irq:
; Mouse IRQ 12 handler
align 16
mouse_irq:
	pushaq

	in al, 0x64
	test al, 0x20
	jz .done

	cmp byte[.status], 0
	je .data_packet

	cmp byte[.status], 1
	je .x_packet

	cmp byte[.status], 2
	je .y_packet

	cmp byte[.status], 3
	je .scroll_packet

.data_packet:
	in al, 0x60
	mov [.data], al

	mov byte[.status], 1
	jmp .done

.x_packet:
	in al, 0x60
	mov [.x], al

	mov byte[.status], 2
	jmp .done

.y_packet:
	in al, 0x60
	mov [.y], al

	cmp [mouse_id], 0
	je .complete_packet

	mov byte[.status], 3
	jmp .done

.scroll_packet:
	in al, 0x60
	mov [.scroll], al

.complete_packet:
	mov byte[.status], 0
	call get_mouse_status

	cmp [is_wm_running], 1
	je .handle_wm_event

	call redraw_cursor
	jmp .done

.handle_wm_event:
	mov rax, WM_EVENT_MOUSE
	call wm_event_handler

.done:
	call send_eoi
	popaq
	iretq

align 8
.status				db 0
align 8
.data				db 0
align 8
.x				db 0
align 8
.y				db 0
align 8
.scroll				db 0

; get_mouse_status:
; Gets the mouse status
; In\	Nothing
; Out\	AX/BX = X/Y pos
; Out\	CL = Button status
align 16
get_mouse_status:
	mov rax, [mouse_x]
	mov [old_mouse_x], rax
	mov rax, [mouse_y]
	mov [old_mouse_y], rax
	mov rax, [mouse_status]
	mov [old_mouse_status], rax

	; start by waiting for an IRQ

.wait_for_irq:
	cmp [mouse_irq.status], 0
	jne .wait_for_irq

	; here, we know an IRQ happened

.start:
	; if the X or Y overflow bits are set, then just quit
	test byte[mouse_irq.data], 0x80
	jnz .quit

	test byte[mouse_irq.data], 0x40
	jnz .quit

	; Now, let's see where the mouse moved...

.do_x:
	mov rax, [mouse_x]
	movzx rbx, [mouse_irq.x]

	test [mouse_irq.data], 0x10
	jnz .x_negative

.x_positive:
	mov rcx, [mouse_speed]
	shl rbx, cl
	add rax, rbx
	jmp .do_y

.x_negative:
	not bl
	mov rcx, [mouse_speed]
	shl rbx, cl
	sub rax, rbx
	jc .x_zero
	jmp .do_y

.x_zero:
	mov rax, 0

.do_y:
	mov [mouse_x], rax

	mov rax, [mouse_y]
	movzx rbx, [mouse_irq.y]

	test [mouse_irq.data], 0x20
	jnz .y_negative

.y_positive:
	mov rcx, [mouse_speed]
	shl rbx, cl
	sub rax, rbx
	jc .y_zero
	jmp .check_x_overflow

.y_zero:
	mov rax, 0
	jmp .check_x_overflow

.y_negative:
	not bl
	mov rcx, [mouse_speed]
	shl rbx, cl
	add rax, rbx

.check_x_overflow:
	mov [mouse_y], rax

	mov rbx, [vbe_screen.width]
	cmp [mouse_x], rbx
	jge .x_max

	jmp .check_y_overflow

.x_max:
	mov [mouse_x], rbx
	dec [mouse_x]

.check_y_overflow:
	mov rbx, [vbe_screen.height]
	cmp [mouse_y], rbx
	jge .y_max

	jmp .do_status

.y_max:
	mov [mouse_y], rbx
	dec [mouse_y]

.do_status:
	movzx rax, [mouse_irq.data]
	mov [mouse_status], rax

.quit:
	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	mov rcx, [mouse_status]
	and rcx, 7
	ret

; set_mouse_cursor:
; Sets properties of the mouse cursor
; In\	RAX = Width
; In\	RBX = Height
; In\	EDX = Color
; Out\	Nothing

set_mouse_cursor:
	mov [mouse_width], rax
	mov [mouse_height], rbx
	mov [mouse_color], edx
	mov dword[mouse_color2], edx
	mov dword[mouse_color2+4], edx
	call redraw_cursor
	ret

; show_mouse_cursor:
; Shows the mouse cursor

show_mouse_cursor:
	mov [is_mouse_visible], 1
	call redraw_cursor
	ret

; hide_mouse_cursor:
; Hides the mouse cursor

hide_mouse_cursor:
	mov [is_mouse_visible], 0
	call redraw_screen
	ret

; redraw_cursor:
; Redraws the mouse cursor
align 16
redraw_cursor:
	cmp [is_mouse_visible], 0
	je .just_redraw

	cmp [vbe_screen.bpp], 16
	je redraw_cursor16

	call redraw_screen

	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	call get_pixel_offset
	mov rbx, VBE_VIRTUAL_BUFFER
	add rax, rbx
	mov [.offset], rax
	mov [.current_line], 0

	mov rax, [mouse_width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [.bytes_per_line]
	mov rax, [mouse_color2]

.loop:
	cmp [vbe_screen.bpp], 32
	jne .24_bpp

.32_bpp:
	shr rcx, 3
	rep stosq

.next_line:
	inc [.current_line]
	mov rdi, [.offset]
	add rdi, [vbe_screen.bytes_per_line]
	mov [.offset], rdi

	mov rcx, [mouse_height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.24_bpp:
	mov eax, [mouse_color]
	stosw
	shr eax, 16
	stosb
	sub rcx, 3
	cmp rcx, 0
	jne .24_bpp
	jmp .next_line

.just_redraw:
	call redraw_screen

.done:
	ret

align 16
.offset					dq 0
.bytes_per_line				dq 0
.current_line				dq 0
.color					dd 0

; redraw_cursor16:
; Redraws the mouse cursor in 16-bit graphics mode
align 16
redraw_cursor16:
	call redraw_screen

	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	call get_pixel_offset
	mov rbx, VBE_VIRTUAL_BUFFER
	add rax, rbx
	mov [.offset], rax
	mov [.current_line], 0

	mov rax, [mouse_width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [mouse_width]
	mov eax, [mouse_color]

.loop:
	call make_color16
	rep stosw

.next_line:
	inc [.current_line]
	mov rdi, [.offset]
	add rdi, [vbe_screen.bytes_per_line]
	mov [.offset], rdi

	mov rcx, [mouse_height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.done:
	ret

align 16
.offset					dq 0
.bytes_per_line				dq 0
.current_line				dq 0
.color					dd 0

