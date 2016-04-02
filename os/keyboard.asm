
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "PS/2 keyboard driver",0

;; Functions:
; wait_ps2_write
; wait_ps2_read
; init_keyboard
; keyboard_irq
; get_char_wait
; get_char_nowait
; get_string_echo
; get_string_masked

; wait_ps2_write:
; Waits to write to the PS/2 controller

wait_ps2_write:
	push rax

.wait:
	in al, 0x64
	test al, 2
	jnz .wait

	pop rax
	ret

; wait_ps2_read:
; Waits to read the PS/2 controller

wait_ps2_read:
	push rax

.wait:
	in al, 0x64
	test al, 1
	jz .wait

	pop rax
	ret

; init_keyboard:
; Initializes the keyboard

init_keyboard:
	mov rsi, .msg
	call kprint

	; Install the IRQ handler
	mov al, 1
	mov rbp, keyboard_irq
	call install_irq

	; Reset the keyboard
	call wait_ps2_write
	mov al, 0xFF
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	; Set autorepeat rate
	call wait_ps2_write
	mov al, 0xF3
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	call wait_ps2_write
	mov al, 0x20
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	; Set scancode set 2
	call wait_ps2_write
	mov al, 0xF0
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	call wait_ps2_write
	mov al, 2
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	; Enable autorepeat and make/break codes
	call wait_ps2_write
	mov al, 0xFA
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	; Enable keyboard
	call wait_ps2_write
	mov al, 0xF4
	out 0x60, al

	call wait_ps2_read
	in al, 0x60

	ret

.msg				db "[ps2] initializing PS/2 keyboard...",10,0

; keyboard_irq:
; Keyboard IRQ 1 handler
align 16
keyboard_irq:
	pushaq

	in al, 0x60
	mov [last_scancode], al
	and rax, 0xFF

	cmp al, 0x36
	je .shift

	cmp al, 0x2A
	je .shift

	cmp al, 0xB6
	je .shift_release

	cmp al, 0xAA
	je .shift_release

	test al, 0x80
	jnz .ignore

	cmp [shift_status], 1
	je .use_shift

.no_shift:
	;mov [ss:last_scancode], al
	add rax, ascii_codes
	mov dl, [rax]
	mov [last_key], dl
	jmp .done

.use_shift:
	;mov [ss:last_scancode], al
	add rax, ascii_codes_shift
	mov dl, [rax]
	mov [last_key], dl
	jmp .done

.shift:
	mov [shift_status], 1
	jmp .ignore

.shift_release:
	mov [shift_status], 0
	jmp .ignore

.ignore:
	mov byte[last_key], 0
	mov byte[last_scancode], 0
	jmp .quit

.done:
	cmp [is_wm_running], 1
	jne .quit

	mov rax, WM_EVENT_KEYPRESS
	call wm_event_handler

.quit:
	call send_eoi

	popaq
	iretq

align 16
shift_status			db 0
align 16
last_key			db 0
align 16
last_scancode			db 0

align 16
ascii_codes:
	db 0,27
	db "1234567890-=",8
	db "	"
	db "qwertyuiop[]",13,0
	db "asdfghjkl;'`",0
	db "\zxcvbnm,./",0
	db "*",0
	db " "
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db "-",0,0,0,"+"
	times 128 - ($-ascii_codes) db 0

align 16
ascii_codes_shift:
	db 0,27
	db "!@#$%^&*()_+",8
	db "	"
	db "QWERTYUIOP{}",13,0
	db "ASDFGHJKL:", '"', "~",0
	db "|ZXCVBNM<>?",0
	db "*",0
	db " "
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db "-",0,0,0,"+"
	times 128 - ($-ascii_codes_shift) db 0


; get_char_wait:
; Gets a character from the keyboard with waiting
; In\	Nothing
; Out\	AL = Character
; Out\	AH = Scancode

get_char_wait:
	pushaq
	mov [last_key], 0
	mov [last_scancode], 0

.loop:
	call enable_interrupts

	cmp [last_key], 0
	jne .done
	jmp .loop

.done:
	popaq

	mov al, [last_key]
	mov ah, [last_scancode]
	mov [last_key], 0
	mov [last_scancode], 0
	ret

; get_char_nowait:
; Gets a character from the keyboard without waiting
; In\	Nothing
; Out\	AL = Character
; Out\	AH = Scancode

get_char_nowait:
	mov al, [last_key]
	mov ah, [last_scancode]
	ret

; get_string_echo:
; Gets a string
; In\	DL = Maximum characters to get
; Out\	RSI = Pointer to string

get_string_echo:
	pushaq
	and rdx, 0xFF
	mov [.end_string], rdx
	add [.end_string], .string

	mov rdi, .string
	mov rax, 0
	mov rcx, 256/8
	rep stosq

	mov ax, [vbe_screen.x_cur]
	mov [.x], ax

	mov rdi, .string

.loop:
	cmp rdi, [.end_string]
	jge .done

	call get_char_wait
	cmp al, 13
	je .done

	cmp al, 8
	je .backspace

.character:
	stosb
	pushaq
	mov byte[.char], al
	mov rsi, .char
	call print_string_cursor
	popaq

	jmp .loop

.backspace:
	mov ax, [vbe_screen.x_cur]
	cmp ax, [.x]
	je .loop

	dec rdi
	dec [vbe_screen.x_cur]
	push rdi
	mov rsi, .space
	call print_string_cursor
	pop rdi
	dec [vbe_screen.x_cur]

	jmp .loop

.done:
	mov al, 0
	stosb
	popaq
	mov rsi, .string
	ret

.string:			times 256 db 0
.end_string			dq 0
.space				db " ",0
.char:				times 2 db 0
.x				dw 0

; get_string_masked:
; Gets a string and mask it
; In\	AL = Mask character (0 for completely invisible)
; In\	DL = Maximum characters to get
; Out\	RSI = Pointer to string

get_string_masked:
	pushaq
	mov byte[.char], al
	and rdx, 0xFF
	mov [.end_string], rdx
	add [.end_string], .string

	mov rdi, .string
	mov rax, 0
	mov rcx, 256/8
	rep stosq

	mov ax, [vbe_screen.x_cur]
	mov [.x], ax

	mov rdi, .string

.loop:
	cmp rdi, [.end_string]
	jge .done

	call get_char_wait
	cmp al, 13
	je .done

	cmp al, 8
	je .backspace

.character:
	stosb
	pushaq
	mov rsi, .char
	call print_string_cursor
	popaq

	jmp .loop

.backspace:
	mov ax, [vbe_screen.x_cur]
	cmp ax, [.x]
	je .loop

	dec rdi
	dec [vbe_screen.x_cur]
	push rdi
	mov rsi, .space
	call print_string_cursor
	pop rdi
	dec [vbe_screen.x_cur]

	call redraw_screen
	jmp .loop

.done:
	mov al, 0
	stosb
	popaq
	mov rsi, .string
	ret

.string:			times 256 db 0
.end_string			dq 0
.space				db " ",0
.char:				times 2 db 0
.x				dw 0




