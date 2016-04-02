
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ExDOS GUI Core",0

;; Functions:
; gui
; gui_draw_background
; redraw_background
; gui_background_event_handler

GUI_DEFAULT_COLOR		= 0x2020A0		; default color when wallpaper is unavailable
GUI_DEFAULT_MOUSE_COLOR		= 0x000000
MENU_COLOR			= 0x00A010
TASKBAR_CONTROLS_COLOR		= 0x404080
DEFAULT_TASKBAR_TRANSPARENCY	= 0

align 16
gui_wallpaper			dq 0
align 16
gui_wallpaper_size		dq 0
align 16
wallpaper_width			dw 0
align 16
wallpaper_height		dw 0
align 16
taskbar_y			dw 0
align 16
taskbar_transparency		db DEFAULT_TASKBAR_TRANSPARENCY
align 16
taskbar_time_x			dw 0

; gui:
; GUI entry point

gui:
	mov rsi, .starting_msg
	call kprint

	mov ebx, GUI_DEFAULT_COLOR
	call clear_screen
	call hide_text_cursor

	mov ebx, 0xFFFFFF
	mov ecx, 0
	call set_text_color

	mov rax, 10
	mov rbx, 10
	mov edx, GUI_DEFAULT_MOUSE_COLOR
	call set_mouse_cursor
	call show_mouse_cursor

	mov rax, [vbe_screen.height]
	sub rax, 32
	mov [taskbar_y], ax

	mov rax, [vbe_screen.width]
	sub rax, 72
	mov [taskbar_time_x], ax

	call gui_draw_background
	call init_wm

	mov ax, 0
	mov bx, 0
	mov si, 350
	mov di, 128
	mov r10, .title1
	mov rdx, .event
	call wm_create_window

	mov ax, 64
	mov bx, 64
	mov si, 400
	mov di, 120
	mov r10, .title2
	mov rdx, .event
	call wm_create_window

	mov rax, 0
	call wm_get_canvas

	mov rdi, rax
	mov rax, 0xC0C0C000FF0000
	mov rcx, 8192
	rep stosq

	mov rax, 1
	call wm_get_canvas

	mov rdi, rax
	mov rax, 0x00F000000000FF
	mov rcx, 8192
	rep stosq

	call wm_redraw

	jmp $

.event:
	ret

.starting_msg				db "[gui] starting graphical user interface...",10,0
.title1					db "Test Window #1",0
.title2					db "Test Window #2",0

; gui_draw_background:
; Draws the background

gui_draw_background:
	mov rsi, .background_filename
	mov rdx, 1
	call open
	cmp rax, -1
	je .no_bg
	mov [.file_handle], rax

	mov rax, [.file_handle]
	mov rcx, -1
	call seek
	cmp rax, -1
	je .no_bg2
	mov [.file_size], rax

	mov rax, 0
	mov rbx, [.file_size]
	mov dl, 3
	call kmalloc
	cmp rax, 0
	je .no_bg2
	mov [.memory], rax

	mov rax, [.file_handle]
	mov rcx, [.file_size]
	mov rdi, [.memory]
	call read
	cmp rax, -1
	je .no_bg3

	mov rax, [.file_handle]
	call close

	mov rsi, [.memory]
	call decode_bmp24

	pushaq
	mov rax, [.memory]
	mov rbx, [.file_size]
	call kfree
	popaq

	mov [gui_wallpaper], rax
	mov [gui_wallpaper_size], rcx
	mov [wallpaper_width], si
	mov [wallpaper_height], di

	call redraw_background
	ret

.no_bg3:
	mov rax, [.memory]
	mov rbx, [.file_size]
	call kfree
	
.no_bg2:
	mov rax, [.file_handle]
	call close
	jmp .no_bg

.no_bg:
	mov ebx, GUI_DEFAULT_COLOR
	call clear_screen

	ret

.file_handle				dq 0
.file_size				dq 0
.memory					dq 0
.background_filename			db "bg.bmp",0

; redraw_background:
; Redraws the GUI background
align 16
redraw_background:
	cmp [gui_wallpaper], 0
	je .clear

	mov ebx, GUI_DEFAULT_COLOR
	call clear_screen

	mov rdx, [gui_wallpaper]
	mov si, [wallpaper_width]
	mov di, [wallpaper_height]
	mov ax, 0
	mov bx, 0
	call blit_buffer

	ret

.clear:
	mov ebx, GUI_DEFAULT_COLOR
	call clear_screen

	ret

; redraw_taskbar:
; Redraws the GUI taskbar
align 16
redraw_taskbar:
	mov ax, 0
	mov bx, [taskbar_y]
	mov rsi, [vbe_screen.width]
	mov di, 32
	mov edx, WINDOW_COLOR
	mov cl, [taskbar_transparency]
	call alpha_fill_rect

	mov ax, 0
	mov bx, [taskbar_y]
	mov si, 64
	mov di, 32
	mov edx, MENU_COLOR
	call fill_rect

	mov ebx, 0
	mov ecx, 0
	call set_text_color

	mov cx, 13
	mov dx, [taskbar_y]
	add dx, 9
	mov rsi, taskbar_text
	call print_string_transparent

	mov ebx, 0
	mov ecx, 0xFFFFFF
	call set_text_color

	mov cx, 12
	mov dx, [taskbar_y]
	add dx, 8
	mov rsi, taskbar_text
	call print_string_transparent

	call cmos_read_time12_string
	mov rsi, rax
	mov cx, [taskbar_time_x]
	mov dx, [taskbar_y]
	add dx, 8
	call print_string_transparent

	ret

taskbar_text			db "DEBUG",0

; gui_background_event_handler:
; Handler for GUI background -- the only event handler in the OS that runs in ring 0
align 16
gui_background_event_handler:
	cmp rax, WM_EVENT_MOUSE
	jne .just_quit

	test [mouse_status], 1
	jz .just_quit

	mov rax, [mouse_x]
	mov rbx, [mouse_y]

	cmp rax, 64
	jg .just_quit

	cmp bx, [taskbar_y]
	jl .just_quit

	mov [is_wm_running], 0
	call send_eoi
	mov rsi, .msg
	call start_debugging

	;jmp shutdown

.just_quit:
	call wm_redraw
	ret

.msg				db "[gui] user clicked debug button.",0

include					"os/wm.asm"	; Window Manager



