
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Generic resolution-independent graphics device interface",0

;; 
;; This is the default graphics library used internally by the ExDOS kernel, written entirely from scratch.
;; It supports all 32-bit, 24-bit and 16-bit framebuffers, and always appears to the user as a 32-bit framebuffer.
;; It also includes some acceleration: SSE/AVX double-buffering, 64-bit operations when possible, shift instead of MUL/DIV...
;; It contains little OS-dependent code and can easily be ported to other OS kernel software.
;;
;; Features:
;; - SSE/AVX double buffering, screen locking/unlocking.
;; - Basic text rendering engine.
;; - Rectangle drawing.
;; - Blitting raw pixel buffers.
;; - BMP decoder (BMP => raw pixel buffer).
;; - Resolution-independent.
;; - BPP-independent: 32-bit, 24-bit and 16-bit BPP support.
;; - Alpha blending with 4 different intensities.
;; 

;; Functions:
; lock_screen
; unlock_screen
; get_fb_address
; get_screen_resolution
; redraw_screen
; redraw_screen_avx
; clear_screen
; show_text_cursor
; hide_text_cursor
; set_text_color
; get_text_color
; get_screen_center
; get_pixel_offset
; put_pixel
; put_char
; put_char_transparent
; print_string_cursor
; print_string
; print_string_transparent
; scroll_screen
; fill_rect
; blit_buffer
; read_buffer
; invert_buffer_vertically
; decode_bmp24
; alpha_blend_colors
; alpha_fill_rect
; make_color16
; make_color32
; clear_screen16
; put_pixel16
; put_char16
; put_char_transparent16
; fill_rect16
; blit_buffer16
; alpha_fill_rect16

use64
align 16
font_data:			;include "os/glaux-mono.asm"	; Glaux Mono -- public domain
				file "os/font.bin"		; Alotware font

align 16
text_background			dd 0
align 16
text_foreground			dd 0
align 16
is_cursor_shown			db 0
align 16
redraw_enabled			dq 1

; lock_screen:
; Prevents screen redraws
align 16
lock_screen:
	mov [redraw_enabled], 0
	ret

; unlock_screen:
; Enables screen redraws
align 16
unlock_screen:
	mov [redraw_enabled], 1
	ret

; get_fb_address:
; Returns the address of the framebuffer
; In\	Nothing
; Out\	RAX = Physical address of hardware framebuffer
; Out\	RDX = Virtual address of software back buffer
align 16
get_fb_address:
	mov rax, [vbe_screen.physical_buffer]
	mov rdx, VBE_BACK_BUFFER
	ret

; get_screen_resolution:
; Returns the screen resolution
; In\	Nothing
; Out\	AX/BX = Width/Height
; Out\	CL = Bits per pixel
align 16
get_screen_resolution:
	mov ax, word[vbe_screen.width]
	mov bx, word[vbe_screen.height]
	mov cl, byte[vbe_screen.bpp]
	ret

; redraw_screen:
; Redraws the screen
align 16
redraw_screen:
	cmp [redraw_enabled], 1
	jne .quit

	cmp [is_there_avx], 1			; if there is AVX --
	je redraw_screen_avx			; -- why use SSE?

	mov rsi, VBE_BACK_BUFFER
	mov rdi, VBE_VIRTUAL_BUFFER
	mov rcx, [vbe_screen.size_bytes]
	shr rcx, 8				; div 256

.loop:
	cmp rcx, 0
	je .quit

	movdqa xmm0, [rsi]
	movdqa xmm1, [rsi+16]
	movdqa xmm2, [rsi+32]
	movdqa xmm3, [rsi+48]
	movdqa xmm4, [rsi+64]
	movdqa xmm5, [rsi+80]
	movdqa xmm6, [rsi+96]
	movdqa xmm7, [rsi+112]
	movdqa xmm8, [rsi+128]
	movdqa xmm9, [rsi+144]
	movdqa xmm10, [rsi+160]
	movdqa xmm11, [rsi+176]
	movdqa xmm12, [rsi+192]
	movdqa xmm13, [rsi+208]
	movdqa xmm14, [rsi+224]
	movdqa xmm15, [rsi+240]

	movdqa [rdi], xmm0
	movdqa [rdi+16], xmm1
	movdqa [rdi+32], xmm2
	movdqa [rdi+48], xmm3
	movdqa [rdi+64], xmm4
	movdqa [rdi+80], xmm5
	movdqa [rdi+96], xmm6
	movdqa [rdi+112], xmm7
	movdqa [rdi+128], xmm8
	movdqa [rdi+144], xmm9
	movdqa [rdi+160], xmm10
	movdqa [rdi+176], xmm11
	movdqa [rdi+192], xmm12
	movdqa [rdi+208], xmm13
	movdqa [rdi+224], xmm14
	movdqa [rdi+240], xmm15

	add rsi, 256
	add rdi, 256
	dec rcx
	jmp .loop

.quit:
	ret

; redraw_screen_avx:
; Redraws the screen using AVX for acceleration
align 32
redraw_screen_avx:
	mov rsi, VBE_BACK_BUFFER
	mov rdi, VBE_VIRTUAL_BUFFER
	mov rcx, [vbe_screen.size_bytes]
	shr rcx, 9				; div 512

.loop:
	cmp rcx, 0
	je .quit

	vmovdqa ymm0, [rsi]
	vmovdqa ymm1, [rsi+32]
	vmovdqa ymm2, [rsi+64]
	vmovdqa ymm3, [rsi+96]
	vmovdqa ymm4, [rsi+128]
	vmovdqa ymm5, [rsi+160]
	vmovdqa ymm6, [rsi+192]
	vmovdqa ymm7, [rsi+224]
	vmovdqa ymm8, [rsi+256]
	vmovdqa ymm9, [rsi+288]
	vmovdqa ymm10, [rsi+320]
	vmovdqa ymm11, [rsi+352]
	vmovdqa ymm12, [rsi+384]
	vmovdqa ymm13, [rsi+416]
	vmovdqa ymm14, [rsi+448]
	vmovdqa ymm15, [rsi+480]

	vmovdqa [rdi], ymm0
	vmovdqa [rdi+32], ymm1
	vmovdqa [rdi+64], ymm2
	vmovdqa [rdi+96], ymm3
	vmovdqa [rdi+128], ymm4
	vmovdqa [rdi+160], ymm5
	vmovdqa [rdi+192], ymm6
	vmovdqa [rdi+224], ymm7
	vmovdqa [rdi+256], ymm8
	vmovdqa [rdi+288], ymm9
	vmovdqa [rdi+320], ymm10
	vmovdqa [rdi+352], ymm11
	vmovdqa [rdi+384], ymm12
	vmovdqa [rdi+416], ymm13
	vmovdqa [rdi+448], ymm14
	vmovdqa [rdi+480], ymm15

	add rsi, 512
	add rdi, 512
	dec rcx
	jmp .loop

.quit:
	ret

; show_text_cursor:
; Shows the text cursor

show_text_cursor:
	mov [is_cursor_shown], 1
	call redraw_screen
	ret

; hide_text_cursor:
; Hides the text cursor

hide_text_cursor:
	mov [is_cursor_shown], 0
	call redraw_screen
	ret

; clear_screen:
; Clears the screen
; In\	EBX = Color
; Out\	Nothing
align 16
clear_screen:
	cmp [vbe_screen.bpp], 16
	je clear_screen16

	mov [vbe_screen.x_cur], 0
	mov [vbe_screen.y_cur], 0

	cmp [vbe_screen.bpp], 24
	je .24

.32:
	mov rdi, VBE_BACK_BUFFER
	mov eax, ebx
	mov rcx, [vbe_screen.size_bytes]
	shr rcx, 3
	mov dword[.color], ebx
	mov dword[.color+4], ebx

	mov rax, [.color]
	rep stosq
	call redraw_screen

	ret

.24:
	mov rdi, VBE_BACK_BUFFER
	mov rcx, [vbe_screen.size_bytes]

.24_loop:
	mov eax, ebx
	stosw
	shr eax, 16
	stosb
	sub rcx, 3
	cmp rcx, 3
	jle .24_loop

	call redraw_screen
	ret

.color				dq 0

; set_text_color:
; Sets the text color
; In\	EBX = Background
; In\	ECX = Foreground
; Out\	Nothing
align 16
set_text_color:
	mov [text_background], ebx
	mov [text_foreground], ecx
	ret

; get_text_color:
; Gets the text color
; In\	Nothing
; Out\	EBX = Background
; Out\	ECX = Foreground
align 16
get_text_color:
	mov ebx, [text_background]
	mov ecx, [text_foreground]
	ret

; get_pixel_offset:
; Gets a pixel's offset
; In\	RAX/RBX = X/Y pos
; Out\	RAX = Pixel offset with base 0
; Out\	RDI = Pixel offset within framebuffer
align 16
get_pixel_offset:
	and rax, 0xFFFF
	and rbx, 0xFFFF
	push rax
	mov rax, rbx
	mov rbx, [vbe_screen.bytes_per_line]
	mul rbx

	pop rbx
	push rax
	mov rax, rbx
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	pop rbx
	add rax, rbx

	mov rdi, VBE_BACK_BUFFER
	add rdi, rax
	ret

; get_screen_center:
; Returns the center of the screen
; In\	Nothing
; Out\	RAX/RBX = X/Y pos
align 16
get_screen_center:
	mov rax, [vbe_screen.width]
	mov rbx, [vbe_screen.height]
	shr rax, 1
	shr rbx, 1
	ret

; put_pixel:
; Puts a pixel
; In\	RAX/RBX = X/Y pos
; In\	EDX = Color
; Out\	Nothing

put_pixel:
	cmp [vbe_screen.bpp], 16
	je put_pixel16

	push rdx
	call get_pixel_offset

	pop rax
	cmp [vbe_screen.bpp], 32
	jne .24_bpp

.32_bpp:
	stosd
	call redraw_screen
	ret

.24_bpp:
	stosw
	shr eax, 16
	stosb
	call redraw_screen
	ret

; put_char:
; Puts a character
; In\	AL = Character
; In\	BX/CX = X/Y pos
; Out\	Nothing
align 16
put_char:
	cmp [vbe_screen.bpp], 16
	je put_char16

	mov [.x], bx
	mov [.y], cx
	and rax, 0xFF
	shl rax, 4			; multiply by 16
	add rax, font_data
	mov [.font], rax

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.column], 0
	mov [.row], 0
	mov rdi, [.offset]

.start:
	mov rsi, [.font]
	mov dl, [rsi]

.put_row:
	test dl, 0x80
	jz .background

.foreground:
	mov eax, [text_foreground]
	cmp [vbe_screen.bpp], 32
	jne .put_24

.put_32:
	stosd
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.background:
	mov eax, [text_background]
	cmp [vbe_screen.bpp], 32
	jne .put_24
	jmp .put_32

.put_24:
	stosw
	shr eax, 16
	stosb
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.next:
	inc [.font]
	mov [.column], 0
	inc [.row]
	cmp [.row], 16
	je .done

	add rdi, [vbe_screen.bytes_per_line]
	push rdi
	mov rax, 8
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	pop rdi
	sub rdi, rax
	jmp .start

.done:
	ret

.x				dw 0
.y				dw 0
.font				dq 0
.offset				dq 0
.column				db 0
.row				db 0
.data				db 0

; put_char_transparent:
; Puts a character with transparent background
; In\	AL = Character
; In\	BX/CX = X/Y pos
; Out\	Nothing
align 16
put_char_transparent:
	cmp [vbe_screen.bpp], 16
	je put_char_transparent16

	mov [.x], bx
	mov [.y], cx
	and rax, 0xFF
	shl rax, 4			; multiply by 16
	add rax, font_data
	mov [.font], rax

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.column], 0
	mov [.row], 0
	mov rdi, [.offset]

.start:
	mov rsi, [.font]
	mov dl, [rsi]

.put_row:
	test dl, 0x80
	jz .background

.foreground:
	mov eax, [text_foreground]
	cmp [vbe_screen.bpp], 32
	jne .put_24

.put_32:
	stosd
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.background:
	add rdi, [vbe_screen.bytes_per_pixel]
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.put_24:
	stosw
	shr eax, 16
	stosb
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.next:
	inc [.font]
	mov [.column], 0
	inc [.row]
	cmp [.row], 16
	je .done

	add rdi, [vbe_screen.bytes_per_line]
	push rdi
	mov rax, 8
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	pop rdi
	sub rdi, rax
	jmp .start

.done:
	ret

align 16
.x				dw 0
align 16
.y				dw 0
align 16
.font				dq 0
.offset				dq 0
align 16
.column				db 0
align 16
.row				db 0
align 16
.data				db 0

; put_char_cursor:
; Puts a character at cursor position
; In\	AL = Character
; Out\	Nothing
align 16
put_char_cursor:
	pushaq
	mov [.char], al

	cmp al, 10
	je .newline

	cmp al, 13
	je .carriage

.start:
	mov bx, [vbe_screen.x_cur]
	cmp bx, [vbe_screen.x_cur_max]
	jge .next_line

	mov bx, [vbe_screen.y_cur]
	cmp bx, [vbe_screen.y_cur_max]
	jg .scroll

	mov al, [.char]
	movzx rbx, [vbe_screen.x_cur]
	shl rbx, 3
	movzx rcx, [vbe_screen.y_cur]
	shl rcx, 4
	call put_char

	inc [vbe_screen.x_cur]

	popaq
	ret

.next_line:
	mov [vbe_screen.x_cur], 0
	inc [vbe_screen.y_cur]

	mov bx, [vbe_screen.y_cur]
	cmp bx, [vbe_screen.y_cur_max]
	jg .scroll
	jmp .start

.scroll:
	call scroll_screen
	jmp .start

.carriage:
	mov [vbe_screen.x_cur], 0
	popaq
	ret

.newline:
	mov [vbe_screen.x_cur], 0
	inc [vbe_screen.y_cur]

	mov bx, [vbe_screen.y_cur]
	cmp bx, [vbe_screen.y_cur_max]
	jg .scroll_newline

	popaq
	ret

.scroll_newline:
	call scroll_screen
	popaq
	ret

.char				db 0

; print_string_cursor:
; Prints a string at cursor position
; In\	RSI = String address
; Out\	Nothing

print_string_cursor:
	pushaq

.loop:
	lodsb
	cmp al, 0
	je .done
	call put_char_cursor
	jmp .loop

.done:
	call redraw_screen
	popaq
	ret

; print_string:
; Prints a string
; In\	RSI = String address
; In\	CX/DX = X/Y pos
; Out\	Nothing
align 16
print_string:
	pushaq

	mov [.x], cx
	mov [.y], dx
	mov [.string], rsi

	mov cx, [.x]
	mov [.curr_x], cx
	mov dx, [.y]
	mov [.curr_y], dx

	mov rsi, [.string]

.loop:
	pushaq
	lodsb
	cmp al, 0
	je .done

	cmp al, 10
	je .newline

	cmp al, 13
	je .carriage

	mov bx, [.curr_x]
	mov cx, [.curr_y]
	call put_char

	add [.curr_x], 8
	popaq
	inc rsi
	jmp .loop

.newline:
	popaq
	add [.curr_y], 16
	mov cx, [.x]
	mov [.curr_x], cx
	inc rsi
	jmp .loop


.carriage:
	popaq
	mov cx, [.x]
	mov [.curr_x], cx
	inc rsi
	jmp .loop

.done:
	call redraw_screen
	popaq
	popaq
	ret

.string					dq 0
.x					dw 0
.y					dw 0
.curr_x					dw 0
.curr_y					dw 0

; print_string_transparent:
; Prints a string with a transparent background
; In\	RSI = String address
; In\	CX/DX = X/Y pos
; Out\	Nothing
align 16
print_string_transparent:
	pushaq

	mov [.x], cx
	mov [.y], dx
	mov [.string], rsi

	mov cx, [.x]
	mov [.curr_x], cx
	mov dx, [.y]
	mov [.curr_y], dx

	mov rsi, [.string]

.loop:
	pushaq
	lodsb
	cmp al, 0
	je .done

	cmp al, 10
	je .newline

	cmp al, 13
	je .carriage

	mov bx, [.curr_x]
	mov cx, [.curr_y]
	call put_char_transparent

	add [.curr_x], 8
	popaq
	inc rsi
	jmp .loop

.newline:
	popaq
	add [.curr_y], 16
	mov cx, [.x]
	mov [.curr_x], cx
	inc rsi
	jmp .loop


.carriage:
	popaq
	mov cx, [.x]
	mov [.curr_x], cx
	inc rsi
	jmp .loop

.done:
	call redraw_screen
	popaq
	popaq
	ret

.string					dq 0
.x					dw 0
.y					dw 0
.curr_x					dw 0
.curr_y					dw 0

; scroll_screen:
; Scrolls the screen one line

scroll_screen:
	pushaq

	mov rax, 16
	mov rbx, [vbe_screen.bytes_per_line]
	mul rbx
	mov [.line_size], rax
	mov rcx, [vbe_screen.size_bytes]
	sub rcx, rax
	mov rsi, VBE_BACK_BUFFER
	mov rdi, VBE_BACK_BUFFER
	add rsi, [.line_size]
	call memcpy

	mov rax, 0
	mov rbx, [vbe_screen.height]
	sub rbx, 16
	call get_pixel_offset
	mov eax, [text_background]
	mov rcx, [.line_size]
	rep stosd

	mov ax, [vbe_screen.y_cur_max]
	mov [vbe_screen.y_cur], ax
	mov [vbe_screen.x_cur], 0

	call redraw_screen

	popaq
	ret

.line_size				dq 0

; fill_rect:
; Fills a rectangle
; In\	AX/BX = X/Y pos
; In\	EDX = Color
; In\	SI/DI = Width/Height
; Out\	Nothing
align 16
fill_rect:
	cmp [vbe_screen.bpp], 16
	je fill_rect16

	mov [.x], ax
	mov [.y], bx
	mov [.color], edx
	mov dword[.color2], edx
	mov dword[.color2+4], edx
	mov word[.width], si
	mov word[.height], di

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.current_line], 0

	mov rax, [.width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [.bytes_per_line]
	mov rax, [.color2]

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

	mov rcx, [.height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.24_bpp:
	mov eax, [.color]
	stosw
	shr eax, 16
	stosb
	sub rcx, 3
	cmp rcx, 0
	jne .24_bpp
	jmp .next_line

.done:
	call redraw_screen
	ret

align 16
.bytes_per_line				dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.current_line				dq 0
.color					dd 0
align 16
.color2					dq 0
align 16
.width					dq 0
.height					dq 0
.offset					dq 0

; blit_buffer:
; Blits a pixel buffer
; In\	RDX = Pointer to 32-bit RGB pixel buffer, should be aligned to get better performance
; In\	AX/BX = X/Y pos
; In\	SI/DI = Width/Height
; Out\	Nothing
align 16
blit_buffer:
	cmp [vbe_screen.bpp], 16
	je blit_buffer16

	mov [.buffer], rdx
	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di

	movzx rax, [.width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax
	mov [.current_line], 0

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi
	mov rsi, [.buffer]

.start:
	mov rdi, [.offset]
	movzx rcx, [.height]
	cmp [.current_line], rcx
	jge .done

	cmp [vbe_screen.bpp], 24
	je .24_bpp

.32_bpp:
	mov rcx, [.bytes_per_line]
	call memcpy

	mov rax, [vbe_screen.bytes_per_line]
	add [.offset], rax
	inc [.current_line]
	jmp .start

.24_bpp:
	mov rcx, [.bytes_per_line]

.24_loop:
	movsw
	movsb
	inc rsi
	sub rcx, 3
	cmp rcx, 0
	jne .24_loop

	mov rax, [vbe_screen.bytes_per_line]
	add [.offset], rax
	inc [.current_line]
	jmp .start

.done:
	call redraw_screen
	ret

align 16
.buffer					dq 0
.x					dw 0
align 16
.y					dw 0
align 16
.width					dw 0
align 16
.height					dw 0
align 16
.bytes_per_line				dq 0
.offset					dq 0
.current_line				dq 0

; invert_buffer_vertically:
; Inverts a pixel buffer vertically
; In\	RDX = Pointer to pixel data
; In\	SI/DI = Width/Height
; Out\	Buffer inverted
align 16
invert_buffer_vertically:
	mov [.buffer], rdx
	mov [.width], si
	mov [.height], di

	movzx rax, [.width]
	shl rax, 2
	mov [.bytes_per_line], rax

	movzx rax, [.height]
	dec rax
	mov rbx, [.bytes_per_line]
	mul rbx
	add rax, [.buffer]
	mov [.last_line], rax

	mov rsi, [.buffer]
	mov rdi, [.last_line]

.loop:
	cmp rsi, rdi
	jge .done

	mov rcx, [.bytes_per_line]
	call memxchg

	add rsi, [.bytes_per_line]
	sub rdi, [.bytes_per_line]
	jmp .loop

.done:
	ret

.buffer					dq 0
align 16
.width					dw 0
align 16
.height					dw 0
align 16
.current_row				dq 0
.current_line				dq 0
.bytes_per_line				dq 0
.last_line				dq 0

; decode_bmp24:
; Decodes a 24-bit BMP image
; In\	RSI = Pointer to BMP image data
; Out\	RAX = Pointer to pixel data, 0 on error
; Out\	RCX = Size of pixel data in bytes
; Out\	SI/DI = Width/Height of image
align 16
decode_bmp24:
	mov [.image], rsi

	mov rsi, [.image]
	mov rdi, .bmp_signature
	cmpsw
	jne .corrupt

	mov rsi, [.image]
	mov rax,0
	mov eax, [rsi+18]
	mov [.width], rax
	mov rax, 0
	mov eax, [rsi+22]
	mov [.height], rax

	mov rax, [.width]
	mov rbx, [.height]
	mul rbx
	mov rbx, 3
	mul rbx
	mov [.bmp_size], rax

	mov rax, [.width]
	mov rbx, [.height]
	mul rbx
	shl rax, 2
	mov [.size], rax

	mov rax, 0
	mov rbx, [.size]
	mov dl, 7
	call kmalloc

	cmp rax, 0
	je .corrupt
	mov [.pixel_data], rax

	mov rsi, [.image]
	add rsi, 10
	mov rax, 0
	mov eax, [rsi]

	mov rsi, [.image]
	add rsi, rax			; beginning of pixel data
	mov rdi, [.pixel_data]
	mov rcx, [.bmp_size]

.loop:
	movsw
	movsb
	mov al, 0
	stosb

	sub rcx, 3
	cmp rcx, 3
	jl .done
	jmp .loop

.done:
	mov rdx, [.pixel_data]
	mov rsi, [.width]
	mov rdi, [.height]
	call invert_buffer_vertically

	mov rax, [.pixel_data]
	mov rcx, [.size]
	mov rsi, [.width]
	mov rdi, [.height]
	ret

.corrupt:
	mov rax, 0
	mov rcx, 0
	ret

.bmp_signature				db "BM"
.image					dq 0
.pixel_data				dq 0
.bmp_size				dq 0
.size					dq 0
.width					dq 0
.height					dq 0

; alpha_blend_colors:
; Blends two colors
; In\	EAX = Foreground
; In\	EBX = Background
; In\	DL = Number of bits to shift foreground color
; Out\	EAX = New color
align 16
alpha_blend_colors:
	cmp dl, 4
	jg .no_change

	push cx
	and eax, 0xF0F0F0
	and ebx, 0xF0F0F0

	mov cl, dl
	shr eax, cl
	shr ebx, 1
	and eax, 0x7F7F7F
	and ebx, 0x7F7F7F
	lea eax, [eax+ebx]	; probably faster than add eax, ebx
	pop cx
	ret

.no_change:
	ret

; alpha_fill_rect:
; Fills a rectangle with alpha blending
; In\	AX/BX = X/Y pos
; In\	EDX = Color
; In\	SI/DI = Width/Height
; In\	CL = Alpha intensity (1 to 4 are valid values)
; Out\	Nothing
align 16
alpha_fill_rect:
	cmp cl, 0
	jle fill_rect

	cmp cl, 4
	jg fill_rect

	cmp [vbe_screen.bpp], 16
	je alpha_fill_rect16

	mov [.x], ax
	mov [.y], bx
	mov [.color], edx
	mov word[.width], si
	mov word[.height], di
	mov [.shift], cl

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.current_line], 0

	mov rax, [.width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [.bytes_per_line]
	mov eax, [.color]

.loop:
	cmp [vbe_screen.bpp], 32
	jne .24_bpp

.32_bpp:
	shr rcx, 2

.32_bpp_loop:
	mov eax, [.color]
	mov ebx, [rdi]
	mov dl, [.shift]
	call alpha_blend_colors
	stosd
	loop .32_bpp_loop

.next_line:
	inc [.current_line]
	mov rdi, [.offset]
	add rdi, [vbe_screen.bytes_per_line]
	mov [.offset], rdi

	mov rcx, [.height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.24_bpp:
	mov ebx, [rdi]
	and ebx, 0xFFFFFF
	mov eax, [.color]
	mov dl, [.shift]
	call alpha_blend_colors

	stosw
	shr eax, 16
	stosb
	sub rcx, 3
	cmp rcx, 0
	jne .24_bpp
	jmp .next_line

.done:
	call redraw_screen
	ret

align 16
.bytes_per_line				dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.current_line				dq 0
.color					dd 0
align 16
.width					dq 0
.height					dq 0
.offset					dq 0
align 16
.shift					db 0

; make_color16:
; Converts a 32-bit RGB color to a 16-bit color
; In\	EAX = Color
; Out\	AX = Color
align 32
make_color16:
	; A 16-bit color is encoded like this:
	; 5 bits of red
	; 6 bits of green
	; 5 bits of blue
	; So we will take the highest 5 bits of red, highest 6 bits of green, and highest 5 bits of blue

	mov r14d, eax
	mov r15w, 0

	movzx eax, r14b
	shr r14d, 8
	shr eax, 3
	or r15w, ax

	movzx eax, r14b
	shr r14d, 8
	shr eax, 2
	shl eax, 5
	or r15w, ax

	movzx eax, r14b
	shr r14d, 8
	shr eax, 3
	shl eax, 11
	or r15w, ax

	mov ax, r15w
	ret

; make_color32:
; Converts a 16-bit color to a 32-bit RGB color
; In\	AX = Color
; Out\	EAX = Color
align 32
make_color32:
	mov [.color], ax
	mov [.tmp], 0

	and ax, 0x1F			; blue
	shl ax, 3
	mov byte[.tmp], al

	mov ax, [.color]
	and ax, 0xFFE0
	shr ax, 3			; green
	mov byte[.tmp+1], al

	mov ax, [.color]
	and ax, 0xF800
	shr ax, 8
	mov byte[.tmp+2], al		; red

	mov eax, [.tmp]
	ret


align 32
.color					dw 0
align 32
.tmp					dd 0

; clear_screen16:
; Clears the screen in 16-bit graphics mode
; In\	EBX = Color
; Out\	Nothing
align 32
clear_screen16:
	mov [vbe_screen.x_cur], 0
	mov [vbe_screen.y_cur], 0

	mov eax, ebx
	call make_color16

	mov rdi, VBE_BACK_BUFFER
	mov rcx, [vbe_screen.size_bytes]
	shr rcx, 1
	rep stosw

	call redraw_screen
	ret

; put_pixel16:
; Puts a pixel in 16-bit graphics mode
; In\	AX/BX = X/Y pos
; In\	EDX = Color
; Out\	Nothing
align 32
put_pixel16:
	push rdx
	call get_pixel_offset
	pop rax

	call make_color16
	stosw

	call redraw_screen
	ret

; put_char16:
; Puts a character in 16-bit graphics mode
; In\	AL = Character
; In\	BX/CX = X/Y pos
; Out\	Nothing
align 16
put_char16:
	mov [.x], bx
	mov [.y], cx
	and rax, 0xFF
	shl rax, 4			; multiply by 16
	add rax, font_data
	mov [.font], rax

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.column], 0
	mov [.row], 0
	mov rdi, [.offset]

.start:
	mov rsi, [.font]
	mov dl, [rsi]

.put_row:
	test dl, 0x80
	jz .background

.foreground:
	mov eax, [text_foreground]

.put:
	call make_color16
	stosw
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.background:
	mov eax, [text_background]
	jmp .put

.next:
	inc [.font]
	mov [.column], 0
	inc [.row]
	cmp [.row], 16
	je .done

	add rdi, [vbe_screen.bytes_per_line]
	push rdi
	mov rax, 8
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	pop rdi
	sub rdi, rax
	jmp .start

.done:
	ret

align 16
.x				dw 0
align 16
.y				dw 0
align 16
.font				dq 0
align 16
.offset				dq 0
align 16
.column				db 0
align 16
.row				db 0
align 16
.data				db 0

; put_char_transparent16:
; Puts a character with transparent background in 16-bit graphics mode
; In\	AL = Character
; In\	BX/CX = X/Y pos
; Out\	Nothing
align 16
put_char_transparent16:
	mov [.x], bx
	mov [.y], cx
	and rax, 0xFF
	shl rax, 4			; multiply by 16
	add rax, font_data

	mov [.font], rax

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.column], 0
	mov [.row], 0
	mov rdi, [.offset]

.start:
	mov rsi, [.font]
	mov dl, [rsi]

.put_row:
	test dl, 0x80
	jz .background

.foreground:
	mov eax, [text_foreground]

.put:
	call make_color16
	stosw
	shl dl, 1
	inc [.column]
	cmp [.column], 8

	je .next
	jmp .put_row

.background:
	add rdi, [vbe_screen.bytes_per_pixel]
	shl dl, 1
	inc [.column]
	cmp [.column], 8
	je .next
	jmp .put_row

.next:
	inc [.font]
	mov [.column], 0
	inc [.row]
	cmp [.row], 16
	je .done

	add rdi, [vbe_screen.bytes_per_line]
	push rdi
	mov rax, 8
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	pop rdi
	sub rdi, rax
	jmp .start

.done:
	ret

align 16
.x				dw 0
align 16
.y				dw 0
align 16
.font				dq 0
align 16
.offset				dq 0
align 16
.column				db 0
align 16
.row				db 0
align 16
.data				db 0

; fill_rect16:
; Fills a rectangle in 16-bit graphics mode
; In\	AX/BX = X/Y pos
; In\	EDX = Color
; In\	SI/DI = Width/Height
; Out\	Nothing
align 16
fill_rect16:
	mov [.x], ax
	mov [.y], bx
	mov [.color], edx
	mov word[.width], si
	mov word[.height], di

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.current_line], 0

	mov rax, [.width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [.bytes_per_line]
	mov eax, [.color]

	call make_color16
	shr rcx, 1
	rep stosw

.next_line:
	inc [.current_line]
	mov rdi, [.offset]
	add rdi, [vbe_screen.bytes_per_line]
	mov [.offset], rdi

	mov rcx, [.height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.done:
	call redraw_screen
	ret

align 16
.bytes_per_line				dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.current_line				dq 0
.color					dd 0
align 16
.width					dq 0
.height					dq 0
.offset					dq 0

; blit_buffer16:
; Blits a pixel buffer in a 16-bit graphics mode
; In\	RDX = Pointer to 32-bit RGB pixel buffer, should be aligned to get better performance
; In\	AX/BX = X/Y pos
; In\	SI/DI = Width/Height
; Out\	Nothing
align 16
blit_buffer16:
	mov [.buffer], rdx
	mov [.x], ax
	mov [.y], bx
	mov [.width], si
	mov [.height], di

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi
	mov [.current_line], 0

	mov rsi, [.buffer]

.start:
	mov rdi, [.offset]
	movzx rcx, [.width]

.loop:
	lodsd
	call make_color16
	stosw
	loop .loop

.continue:
	inc [.current_line]
	movzx rcx, [.height]
	cmp [.current_line], rcx
	jge .done

	mov rdi, [vbe_screen.bytes_per_line]
	add [.offset], rdi
	jmp .start

.done:
	call redraw_screen
	ret

align 16
.buffer					dq 0
.x					dw 0
align 16
.y					dw 0
align 16
.width					dw 0
align 16
.height					dw 0
align 16
.bytes_per_line				dq 0
.offset					dq 0
.current_line				dq 0

; alpha_fill_rect16:
; Fills a rectangle with alpha blending in 16-bit graphics mode
; In\	AX/BX = X/Y pos
; In\	EDX = Color
; In\	SI/DI = Width/Height
; In\	CL = Alpha intensity (1 to 4 are valid values)
; Out\	Nothing
align 16
alpha_fill_rect16:
	mov [.x], ax
	mov [.y], bx
	mov [.color], edx
	mov word[.width], si
	mov word[.height], di
	mov [.shift], cl

	mov ax, [.x]
	mov bx, [.y]
	call get_pixel_offset
	mov [.offset], rdi

	mov [.current_line], 0

	mov rax, [.width]
	mov rbx, [vbe_screen.bytes_per_pixel]
	mul rbx
	mov [.bytes_per_line], rax

.start:
	mov rdi, [.offset]
	mov rcx, [.width]
	mov eax, [.color]

.loop:
	mov eax, [rdi]
	call make_color32
	mov ebx, eax
	mov eax, [.color]
	mov dl, [.shift]
	call alpha_blend_colors
	call make_color16
	stosw
	loop .loop

.next_line:
	inc [.current_line]
	mov rdi, [.offset]
	add rdi, [vbe_screen.bytes_per_line]
	mov [.offset], rdi

	mov rcx, [.height]
	cmp [.current_line], rcx
	jge .done
	jmp .start

.done:
	call redraw_screen
	ret

align 16
.bytes_per_line				dq 0
align 16
.x					dw 0
align 16
.y					dw 0
align 16
.current_line				dq 0
.color					dd 0
align 16
.width					dq 0
.height					dq 0
.offset					dq 0
align 16
.shift					db 0



