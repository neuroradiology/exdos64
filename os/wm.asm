
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "ExDOS Window Manager",0

;; Functions:
; init_wm
; wm_get_free_handle
; wm_create_handle
; wm_kill_window
; wm_kill_all
; wm_get_window_properties
; wm_create_window
; wm_redraw
; wm_check_mouse_range
; wm_check_mouse_title_range
; wm_is_mouse_on_window
; wm_is_mouse_on_window_title
; wm_event_handler
; wm_get_canvas
; wm_get_pixel_offset

use64
MAXIMUM_WINDOWS				= 255

align 16
window_structure			dq 0
align 16
open_windows				dq 0
align 16
active_window				dq 0
align 16
is_wm_running				db 0
align 16
window_transparency			db WINDOW_DEFAULT_TRANSPARENCY

WINDOW_STRUCTURE:
	.present			= $ - WINDOW_STRUCTURE
					dq 0
	.process			= $ - WINDOW_STRUCTURE
					dq 0
	.event_handler			= $ - WINDOW_STRUCTURE
					dq 0
	.framebuffer			= $ - WINDOW_STRUCTURE
					dq 0
	.framebuffer_size		= $ - WINDOW_STRUCTURE
					dq 0
	.width				= $ - WINDOW_STRUCTURE
					dw 0
	.height				= $ - WINDOW_STRUCTURE
					dw 0
	.x				= $ - WINDOW_STRUCTURE
					dw 0
	.y				= $ - WINDOW_STRUCTURE
					dw 0
	.max_x				= $ - WINDOW_STRUCTURE
					dw 0
	.max_y				= $ - WINDOW_STRUCTURE
					dw 0
	.title				= $ - WINDOW_STRUCTURE
					times 65 db 0

WINDOW_STRUCTURE_SIZE			= $ - WINDOW_STRUCTURE
WINDOW_STRUCTURE_MEMORY			= WINDOW_STRUCTURE_SIZE * MAXIMUM_WINDOWS
;WINDOW_COLOR				= 0x202040	; window color
WINDOW_COLOR				= 0x404050
WINDOW_INACTIVE_COLOR			= 0x808090
WINDOW_BODY_COLOR			= 0xC0C0C0
WINDOW_DEFAULT_TRANSPARENCY		= 0		; 0 = solid color, 4 = maximum transparency
							; valid range is 0-4
							; illegal values make solid colors

WM_EVENT_LOAD				= 0
WM_EVENT_UNLOAD				= 1
WM_EVENT_KEYPRESS			= 2
WM_EVENT_MOUSE				= 3
WM_EVENT_IPC				= 4

; init_wm:
; Initializes the window manager

init_wm:
	mov rsi, .starting_msg
	call kprint

	mov rax, 0
	mov rbx, WINDOW_STRUCTURE_MEMORY
	mov dl, 7
	call kmalloc
	cmp rax, 0
	je .no_memory
	mov [window_structure], rax

	mov [is_wm_running], 1
	ret

.no_memory:
	mov rsi, .no_memory_msg
	call kprint

	mov rsi, .no_memory_msg
	call start_debugging

	jmp $

.starting_msg				db "[wm] initializing window system...",10,0
.no_memory_msg				db "[wm] failed to initialize windowing system...",10,0

; wm_get_free_handle:
; Gets a free window handle
; In\	Nothing
; Out\	RAX = Window handle, -1 on error

wm_get_free_handle:
	cmp [open_windows], MAXIMUM_WINDOWS
	jge .not_found

	mov rax, [window_structure]
	mov rcx, MAXIMUM_WINDOWS

.loop:
	test qword[rax], 1
	jz .found
	add rax, WINDOW_STRUCTURE_SIZE
	loop .loop
	jmp .not_found

.found:
	sub rax, [window_structure]
	mov rdx, 0
	mov rbx, WINDOW_STRUCTURE_SIZE
	div rbx

	ret

.not_found:
	mov rax, -1
	ret

; wm_create_handle:
; Creates a window handle
; In\	AX/BX = X/Y pos
; In\	SI/DI = Width/Height
; In\	RDX = Event handler
; In\	R10 = Framebuffer address
; In\	R11 = Window handle
; In\	R12 = Title
; Out\	Nothing

wm_create_handle:
	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di
	mov [.event], rdx
	mov [.fbsize], r9
	mov [.fb], r10
	mov [.title], r12

	mov rax, r11
	mov rbx, WINDOW_STRUCTURE_SIZE
	mul rbx
	add rax, [window_structure]

	mov qword[rax], 1		; mark as present
	mov rdx, [.event]
	mov [rax+WINDOW_STRUCTURE.event_handler], rdx
	mov rdx, [.fb]
	mov [rax+WINDOW_STRUCTURE.framebuffer], rdx
	mov rdx, [.fbsize]
	mov [rax+WINDOW_STRUCTURE.framebuffer_size], rdx
	mov dx, [.width]
	mov [rax+WINDOW_STRUCTURE.width], dx
	mov dx, [.height]
	mov [rax+WINDOW_STRUCTURE.height], dx
	mov dx, [.x]
	mov [rax+WINDOW_STRUCTURE.x], dx
	mov dx, [.y]
	mov [rax+WINDOW_STRUCTURE.y], dx
	mov rdx, [vbe_screen.width]
	sub dx, [.width]
	sub dx, 8
	mov [rax+WINDOW_STRUCTURE.max_x], dx
	mov rdx, [vbe_screen.height]
	sub dx, [.height]
	sub dx, 28
	mov [rax+WINDOW_STRUCTURE.max_y], dx

	mov rdi, rax
	mov rsi, [.title]
	;call get_string_size
	;mov rcx, rax
	add rdi, WINDOW_STRUCTURE.title
	mov rcx, 64/8
	rep movsq
	mov al, 0
	stosb

	ret


.x					dw 0
.y					dw 0
.width					dw 0
.height					dw 0
.event					dq 0
.fb					dq 0
.title					dq 0
.fbsize					dq 0

; wm_kill_window:
; Kills a window
; In\	RAX = Window handle
; Out\	RAX = 0

wm_kill_window:
	pushaq

	mov rbx, WINDOW_STRUCTURE_SIZE
	mul rbx
	add rax, [window_structure]
	mov rdi, rax
	push rdi

	; free the window canvas memory
	mov rax, [rdi+WINDOW_STRUCTURE.framebuffer]
	mov rbx, [rdi+WINDOW_STRUCTURE.framebuffer_size]
	call kfree
	pop rdi

	; free the window handle
	mov rax, 0
	mov rcx, WINDOW_STRUCTURE_SIZE
	rep stosb

	mov [active_window], 0xFF

.done:
	dec [open_windows]
	call wm_redraw
	popaq
	mov rax, 0
	ret

; wm_kill_all:
; Kills all windows

wm_kill_all:
	pushaq
	cmp [open_windows], 0
	je .done

	mov [.current_window], 0

.loop:
	mov rax, [.current_window]
	call wm_kill_window
	inc [.current_window]

	cmp [open_windows], 0
	jne .loop

.done:
	popaq
	ret

.current_window				dq 0
.count					dq 0

; wm_get_window_properties:
; Gets window properties
; In\	RAX = Window handle
; Out\	RFLAGS = Carry clear if window is present
; Out\	AX/BX = X/Y pos
; Out\	SI/DI = Width/Height
; Out\	RDX = Framebuffer address
; Out\	R10 = Window Title
; Out\	R11 = Event handler

wm_get_window_properties:
	cmp rax, 0xFF
	je .no

	mov rbx, WINDOW_STRUCTURE_SIZE
	mul rbx
	mov r10, rax
	add r10, [window_structure]
	test byte[r10], 1
	jz .no

	mov ax, [r10+WINDOW_STRUCTURE.x]
	mov bx, [r10+WINDOW_STRUCTURE.y]
	mov si, [r10+WINDOW_STRUCTURE.width]
	mov di, [r10+WINDOW_STRUCTURE.height]
	mov rdx, [r10+WINDOW_STRUCTURE.framebuffer]
	mov r12, r10
	mov r10, WINDOW_STRUCTURE.title
	add r10, r12
	mov r11, [r12+WINDOW_STRUCTURE.event_handler]
	clc
	ret

.no:
	stc
	ret

; wm_create_window:
; Creates a window
; In\	AX/BX = X/Y pos
; In\	SI/DI = Width/Height
; In\	RDX = Event handler
; In\	R10 = Title text
; Out\	RAX = Window handle, -1 on error

wm_create_window:
	pushaq

	cmp [open_windows], MAXIMUM_WINDOWS
	jge .error

	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di
	mov [.event], rdx
	mov [.title], r10

	call wm_get_free_handle
	cmp rax, -1
	je .error
	mov [.handle], rax

	movzx rax, [.width]
	movzx rbx, [.height]
	mul rbx
	shl rax, 2
	mov [.framebuffer_size], rax
	mov rbx, rax
	mov rax, 0
	mov dl, 7
	call kmalloc
	cmp rax, -1
	je .error
	mov [.framebuffer], rax

	movzx rax, [.width]
	movzx rbx, [.height]
	mul rbx
	mov rcx, rax
	mov rdi, [.framebuffer]
	mov eax, WINDOW_BODY_COLOR
	rep stosd

	mov ax, [.x]
	mov bx, [.y]
	mov si, [.width]
	mov di, [.height]
	mov rdx, [.event]
	mov r9, [.framebuffer_size]
	mov r10, [.framebuffer]
	mov r11, [.handle]
	mov r12, [.title]
	call wm_create_handle
	inc [open_windows]
	mov rax, [.handle]
	mov [active_window], rax

	call wm_redraw

	popaq
	mov rax, [.handle]
	ret

.error:
	popaq
	mov rax, -1
	ret

align 16
.handle					dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.width					dw 0
align 16
.height					dw 0
align 16
.framebuffer				dq 0
align 16
.event					dq 0
align 16
.title					dq 0
align 16
.framebuffer_size			dq 0

; wm_redraw:
; Redraws all windows
align 16
wm_redraw:
	mov [.current_window], 0

	cmp [open_windows], 0
	je .done

	call get_text_color
	mov [.bg], ebx
	mov [.fg], ecx

	mov ebx, 0
	mov ecx, 0xFFFFFF
	call set_text_color

	call lock_screen		; lock the screen while we modify it
					; this prevents the user from seeing things while they are being drawn
					; it also gives a major performance improvement (at least 5 times on real hardware)

	call redraw_background

.loop:
	cmp [.current_window], MAXIMUM_WINDOWS
	jge .done
	mov rax, [.current_window]
	cmp rax, [active_window]
	je .next
	call wm_get_window_properties
	jc .next

	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di
	mov [.title], r10
	mov [.buffer], rdx

	mov ax, [.x]
	mov bx, [.y]
	mov si, [.width]
	add si, 8
	mov di, [.height]
	add di, 28
	mov edx, WINDOW_INACTIVE_COLOR
	mov cl, [window_transparency]
	call alpha_fill_rect

	mov rsi, [.title]
	mov cx, [.x]
	mov dx, [.y]
	add cx, 4
	add dx, 4
	call print_string_transparent

	mov rdx, [.buffer]
	mov ax, [.x]
	mov bx, [.y]
	add ax, 4
	add bx, 24
	mov si, [.width]
	mov di, [.height]
	call blit_buffer

.next:
	inc [.current_window]
	jmp .loop

.done:
	mov rax, [active_window]
	cmp rax, 0xFF
	je .quit

	call wm_get_window_properties
	jc .quit

	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di
	mov [.title], r10
	mov [.buffer], rdx

	mov ax, [.x]
	mov bx, [.y]
	mov si, [.width]
	add si, 8
	mov di, [.height]
	add di, 28
	mov edx, WINDOW_COLOR
	mov cl, [window_transparency]
	call alpha_fill_rect

	mov rsi, [.title]
	mov cx, [.x]
	mov dx, [.y]
	add cx, 4
	add dx, 4
	call print_string_transparent

	mov rdx, [.buffer]
	mov ax, [.x]
	mov bx, [.y]
	add ax, 4
	add bx, 24
	mov si, [.width]
	mov di, [.height]
	call blit_buffer

.quit:
	call redraw_taskbar
	call unlock_screen
	call redraw_cursor

	mov ebx, [.bg]
	mov ecx, [.fg]
	call set_text_color
	call enable_interrupts
	ret

align 16
.drawn_windows				dq 0
.current_window				dq 0

align 16
.x					dw 0
.y					dw 0
.width					dw 0
.height					dw 0

align 16
.buffer					dq 0
.title					dq 0
.bg					dd 0
align 16
.fg					dd 0

; wm_check_mouse_range:
; Checks the mouse X/Y range and returns the handler for the window it is in
; In\	RAX/RBX = X/Y pos
; Out\	RAX = Window handler, -1 if none
align 16
wm_check_mouse_range:
	mov [.x], ax
	mov [.y], bx

	mov [.current_window], 0

.loop:
	cmp [.current_window], MAXIMUM_WINDOWS
	jge .none
	mov rax, [.current_window]
	call wm_get_window_properties
	jc .next

	mov [.win_x], ax
	mov [.win_y], bx
	add ax, si
	add ax, 8
	add bx, di
	add bx, 28
	mov [.win_end_x], ax
	mov [.win_end_y], bx

.check_x:
	mov ax, [.x]
	cmp ax, [.win_x]
	jl .next

	cmp ax, [.win_end_x]
	jg .next

.check_y:
	mov ax, [.y]
	cmp ax, [.win_y]
	jl .next

	cmp ax, [.win_end_y]
	jg .next

.done:
	mov rax, [.current_window]
	ret

.next:
	inc [.current_window]
	jmp .loop

.none:
	mov rax, -1
	ret

align 16
.current_window				dq 0
.x					dw 0
align 16
.y					dw 0
align 16
.win_x					dw 0
align 16
.win_y					dw 0
align 16
.win_end_x				dw 0
align 16
.win_end_y				dw 0

; wm_check_mouse_title_range:
; Checks the mouse X/Y range and returns the handler for the window title it is in
; In\	RAX/RBX = X/Y pos
; Out\	RAX = Window handler, -1 if none
align 16
wm_check_mouse_title_range:
	mov [.x], ax
	mov [.y], bx

	mov [.current_window], 0

.loop:
	cmp [.current_window], MAXIMUM_WINDOWS
	jge .none
	mov rax, [.current_window]
	call wm_get_window_properties
	jc .next

	mov [.win_x], ax
	mov [.win_y], bx
	add ax, si
	add ax, 8
	add bx, 24
	mov [.win_end_x], ax
	mov [.win_end_y], bx

.check_x:
	mov ax, [.x]
	cmp ax, [.win_x]
	jl .next

	cmp ax, [.win_end_x]
	jg .next

.check_y:
	mov ax, [.y]
	cmp ax, [.win_y]
	jl .next

	cmp ax, [.win_end_y]
	jg .next

.done:
	mov rax, [.current_window]
	ret

.next:
	inc [.current_window]
	jmp .loop

.none:
	mov rax, -1
	ret

align 16
.current_window				dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.win_x					dw 0
align 16
.win_y					dw 0
align 16
.win_end_x				dw 0
align 16
.win_end_y				dw 0

; wm_is_mouse_on_window:
; Checks if the mouse is on a window
; In\	RAX/RBX = X/Y pos
; In\	RDX = Window handler
; Out\	RFLAGS = Carry clear if yes
align 16
wm_is_mouse_on_window:
	mov [.mx], ax
	mov [.my], bx

	mov rax, rdx
	call wm_get_window_properties
	jc .no

	mov [.x], ax
	mov [.y], bx
	add ax, si
	add ax, 8
	add bx, di
	add bx, 28
	mov [.end_x], ax
	mov [.end_y], bx

	mov ax, [.mx]
	mov bx, [.my]
	mov cx, [.x]
	mov dx, [.y]
	mov si, [.end_x]
	mov di, [.end_y]

	cmp ax, cx
	jl .no

	cmp ax, si
	jg .no

	cmp bx, dx
	jl .no

	cmp bx, di
	jg .no

	stc
	ret

.no:
	clc
	ret

align 16
.mx					dw 0
align 16
.my					dw 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.end_x					dw 0
align 16
.end_y					dw 0

; wm_is_mouse_on_window_title:
; Checks if the mouse is on a window title
; In\	RAX/RBX = X/Y pos
; In\	RDX = Window handler
; Out\	RFLAGS = Carry clear if yes
align 16
wm_is_mouse_on_window_title:
	mov [.mx], ax
	mov [.my], bx

	mov rax, rdx
	call wm_get_window_properties
	jc .no

	mov [.x], ax
	mov [.y], bx
	add ax, si
	add ax, 8
	add bx, 24
	mov [.end_x], ax
	mov [.end_y], bx

	mov ax, [.mx]
	mov bx, [.my]
	mov cx, [.x]
	mov dx, [.y]
	mov si, [.end_x]
	mov di, [.end_y]

	cmp ax, cx
	jl .no

	cmp ax, si
	jg .no

	cmp bx, dx
	jl .no

	cmp bx, di
	jg .no

	stc
	ret

.no:
	clc
	ret

align 16
.mx					dw 0
align 16
.my					dw 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.end_x					dw 0
align 16
.end_y					dw 0

; wm_event_handler:
; Event Handler for Window Manager
; In\	RAX = Event type
; Out\	Nothing
align 16
wm_event_handler:
	mov [.event], rax

	cmp rax, WM_EVENT_KEYPRESS
	je .keypress

	cmp rax, WM_EVENT_MOUSE
	je .mouse

.keypress:
	cmp [active_window], 0xFF
	je .keypress_background

	mov rax, [active_window]
	call wm_get_window_properties

	push r11
	call enter_usermode
	pop r11
	mov rax, WM_EVENT_KEYPRESS
	call r11
	jmp .return

.keypress_background:
	mov rax, WM_EVENT_KEYPRESS
	call gui_background_event_handler
	jmp .return

.mouse:
	; check if the mouse is on the taskbar
	mov rax, [mouse_y]
	cmp ax, [taskbar_y]
	jge .taskbar

	; first, try to move the window
	cmp [active_window], 0xFF
	je .change_focus

	test [mouse_status], 1
	jz .change_focus

	mov rax, [old_mouse_status]
	cmp rax, [mouse_status]
	jne .change_focus

	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	mov rdx, [active_window]
	call wm_is_mouse_on_window_title
	jnc .change_focus

	mov rax, [active_window]
	mov rbx, WINDOW_STRUCTURE_SIZE
	mul rbx
	add rax, [window_structure]
	mov rdi, rax

.do_x:
	mov rax, [mouse_x]
	sub rax, [old_mouse_x]
	jc .x_negative

	add [rdi+WINDOW_STRUCTURE.x], ax
	mov dx, [rdi+WINDOW_STRUCTURE.x]
	cmp dx, [rdi+WINDOW_STRUCTURE.max_x]
	jg .x_max
	jmp .do_y

.x_max:
	mov dx, [rdi+WINDOW_STRUCTURE.max_x]
	mov [rdi+WINDOW_STRUCTURE.x], dx
	jmp .do_y

.x_negative:
	not ax
	inc ax
	sub [rdi+WINDOW_STRUCTURE.x], ax
	jc .x_zero
	jmp .do_y

.x_zero:
	mov word[rdi+WINDOW_STRUCTURE.x], 0

.do_y:
	mov rax, [mouse_y]
	sub rax, [old_mouse_y]
	jc .y_negative

	add [rdi+WINDOW_STRUCTURE.y], ax
	mov dx, [rdi+WINDOW_STRUCTURE.y]
	cmp dx, [rdi+WINDOW_STRUCTURE.max_y]
	jg .y_max
	jmp .return

.y_max:
	mov dx, [rdi+WINDOW_STRUCTURE.max_y]
	mov [rdi+WINDOW_STRUCTURE.y], dx
	jmp .return

.y_negative:
	not ax
	inc ax
	sub [rdi+WINDOW_STRUCTURE.y], ax
	jc .y_zero
	jmp .return

.y_zero:
	mov word[rdi+WINDOW_STRUCTURE.y], 0
	jmp .return

.change_focus:
	test [mouse_status], 1
	jz .return

	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	mov rdx, [active_window]
	call wm_is_mouse_on_window
	jnc .switch_focus

	jmp .call_click_event

.switch_focus:
	mov rax, [mouse_x]
	mov rbx, [mouse_y]
	call wm_check_mouse_range

	cmp rax, -1
	je .unfocus

	mov [active_window], rax

.call_click_event:
	cmp [active_window], 0xFF
	je .return

	mov rax, [active_window]
	call wm_get_window_properties

	push r11
	call enter_usermode
	pop r11
	mov rax, WM_EVENT_MOUSE
	call r11
	jmp .return

.unfocus:
	mov [active_window], 0xFF

	mov rax, WM_EVENT_MOUSE
	call gui_background_event_handler
	jmp .return

.taskbar:
	test [mouse_status], 1
	jz .return

	mov [active_window], 0xFF
	mov rax, WM_EVENT_MOUSE
	call gui_background_event_handler
	jmp .return

.return:
	call enter_ring0
	call wm_redraw
	ret

align 16
.event					dq 0
align 16
.mouse_x				dq 0
align 16
.mouse_y				dq 0

; wm_get_canvas:
; Returns the pointer to the 32-bit raw pixel buffer of a window
; In\	RAX = Window handle
; Out\	RAX = Pointer to window canvas; 0 on error

wm_get_canvas:
	cmp rax, MAXIMUM_WINDOWS
	jge .no

	mov rbx, WINDOW_STRUCTURE_SIZE
	mul rbx
	add rax, [window_structure]
	test qword[rax], 1
	jz .no

	mov rax, [rax+WINDOW_STRUCTURE.framebuffer]
	ret

.no:
	mov rax, 0
	ret

; wm_get_pixel_offset:
; Returns pointer to a pixel within the window canvas
; In\	RAX = Window handle
; In\	BX/CX = X/Y coordinates
; Out\	RAX = Pointer to offset within window canvas, 0 on error

wm_get_pixel_offset:
	mov [.handle], rax
	mov [.x], bx
	mov [.y], cx

	mov rax, [.handle]
	call wm_get_canvas

	cmp rax, 0
	je .error

	mov [.base], rax

	mov rax, [.handle]
	call wm_get_window_properties
	and rsi, 0xFFFF
	shl rsi, 2			; mul 4
	mov [.bytes_per_line], rsi

	; Offset = (y * bytes per line) + (x * bytes per pixel)
	movzx rax, [.y]
	mov rbx, [.bytes_per_line]
	mul rbx

	movzx rbx, [.x]
	shl rbx, 2
	add rax, rbx
	add rax, [.base]
	ret

.error:
	mov rax, 0
	ret

.base					dq 0
.handle					dq 0
.x					dw 0
.y					dw 0
.bytes_per_line				dq 0

; wm_put_pixel:
; Puts a pixel in a window
; In\	RAX = Window handle
; In\	BX/CX = X/Y pos
; In\	EDX = 32-bit RGB color
; Out\	Nothing

wm_put_pixel:
	push rdx
	call wm_get_pixel_offset
	cmp rax, 0
	je .error

	pop rdx
	mov dword[rax], edx
	call wm_redraw
	ret

.error:
	pop rdx
	ret



