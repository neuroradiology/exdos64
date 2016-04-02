
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "VESA 2.0 framebuffer driver",0

;; Functions:
; do_vbe
; vbe_set_mode
; map_vbe_framebuffer
; vbe_enable_pat

use16

VBE_VIRTUAL_BUFFER		= 0x120000000
VBE_BACK_BUFFER			= 0x100000000

; Default resolution
VBE_DEFAULT_WIDTH		= 800
VBE_DEFAULT_HEIGHT		= 600

align 16			; Not sure if this has to be aligned, but it doesn't hurt.
vbe_info_block:
	.signature		db "VBE2"	; tell BIOS we support VBE 2.0+
	.version		dw 0
	.oem			dd 0
	.capabilities		dd 0
	.video_modes		dd 0
	.memory			dw 0
	.software_rev		dw 0
	.vendor			dd 0
	.product_name		dd 0
	.product_rev		dd 0
	.reserved:		times 222 db 0
	.oem_data:		times 256 db 0

align 16
mode_info_block:
	.attributes		dw 0
	.window_a		db 0
	.window_b		db 0
	.granularity		dw 0
	.window_size		dw 0
	.segmentA		dw 0
	.segmentB		dw 0
	.win_func_ptr		dd 0
	.pitch			dw 0

	.width			dw 0
	.height			dw 0

	.w_char			db 0
	.y_char			db 0
	.planes			db 0
	.bpp			db 0
	.banks			db 0

	.memory_model		db 0
	.bank_size		db 0
	.image_pages		db 0

	.reserved0		db 0

	.red			dw 0
	.green			dw 0
	.blue			dw 0
	.reserved_mask		dw 0
	.direct_color		db 0

	.framebuffer		dd 0
	.off_screen_mem		dd 0
	.off_screen_mem_size	dw 0
	.reserved1:		times 206 db 0

align 16
vbe_edid_record:
	.padding:		times 8 db 0
	.manufacture		dw 0
	.edid_code		dw 0
	.serial_number		dd 0
	.week_number		db 0
	.manufacture_year	db 0
	.edid_version		db 0
	.edid_revision		db 0
	.video_input_type	db 0
	.horizontal_size	db 0
	.vertical_size		db 0
	.gamma_factor		db 0
	.dpms_flags		db 0
	.chroma_green_red	db 0
	.chroma_white_blue	db 0
	.chrome_red		dw 0
	.chroma_green		dw 0
	.chrome_blue		dw 0
	.chrome_white		dw 0
	.timings1		db 0
	.timings2		db 0
	.reserved_timing	db 0
	.timing_id:		times 8 dw 0
	.timing_desc1:		times 18 db 0
	.timing_desc2:		times 18 db 0
	.timing_desc3:		times 18 db 0
	.timing_desc4:		times 18 db 0
	.reserved		db 0
	.checksum		db 0

align 32
vbe_screen:
	.width			dq 0
	align 16
	.height			dq 0
	align 16
	.bpp			dq 0			; bits per pixel
	align 16
	.bytes_per_pixel	dq 0
	align 16
	.bytes_per_line		dq 0
	.framebuffer		dq VBE_VIRTUAL_BUFFER
	.virtual_buffer		dq VBE_VIRTUAL_BUFFER
	.physical_buffer	dq 0			; hardware linear framebuffer PHYSICAL address
	.back_buffer		dq 0			; back buffer PHYSICAL address
	align 16
	.size_bytes		dq 0			; in bytes
	align 16
	.size_pages		dq 0			; in 2 MB pages
	align 16
	.size_pixels		dq 0
	.x_cur			dw 0
	.y_cur			dw 0
	.x_cur_max		dw 0
	.y_cur_max		dw 0

vbe_memory_bytes		dq 0
vbe_memory_kb			dq 0
vbe_memory_pages		dq 0
vbe_is_there_edid		db 0
vbe_card_model			dq 0

vbe_width			dw VBE_DEFAULT_WIDTH
vbe_height			dw VBE_DEFAULT_HEIGHT

; do_vbe:
; Enables the VBE framebuffer

do_vbe:
	push es
	mov ax, 0x4F00
	mov di, vbe_info_block
	int 0x10
	pop es

	cmp ax, 0x4F
	jne .no_vbe

	cmp dword[vbe_info_block.signature], "VESA"	; ensure "VESA" signature
	jne .no_vbe

	cmp [vbe_info_block.version], 0x200		; we need VBE 2.0+ to boot
	jl .old_vbe

	mov si, .found_msg
	call print_string_16

	movzx eax, word[vbe_info_block.product_name+2]
	shl eax, 4
	movzx ebx, word[vbe_info_block.product_name]
	add eax, ebx
	mov dword[vbe_card_model], eax

	; TO-DO: Use EDID to find preferred video mode!
	mov ax, [vbe_width]
	mov bx, [vbe_height]
	mov cl, 32			; 32 bpp
	call vbe_set_mode
	jc .try_24bpp

	push es
	mov dword[vbe_info_block], "VBE2"
	mov ax, 0x4F00				; get VBE BIOS info, and keep the information there after we quit
	mov di, vbe_info_block
	int 0x10
	pop es

	ret

.try_24bpp:				; use 24bpp as a fallback if 32bpp doesn't work
	mov ax, [vbe_width]
	mov bx, [vbe_height]
	mov cl, 24
	call vbe_set_mode
	jc .try_16bpp

	push es
	mov dword[vbe_info_block], "VBE2"
	mov ax, 0x4F00				; get VBE BIOS info
	mov di, vbe_info_block
	int 0x10
	pop es

	ret

.try_16bpp:				; use 16bpp as a final fallback, performance is very bad with it --
					; -- because the GDI is optimized for 32-bit graphics
	mov ax, [vbe_width]
	mov bx, [vbe_height]
	mov cl, 16
	call vbe_set_mode
	jc .vbe_error

	push es
	mov dword[vbe_info_block], "VBE2"
	mov ax, 0x4F00				; get VBE BIOS info
	mov di, vbe_info_block
	int 0x10
	pop es

	ret

.vbe_error:
	mov ah, 0xF
	mov bx, 0
	int 0x10

	cmp al, 3
	je .vbe_error_continue

	mov ax, 3
	int 0x10

.vbe_error_continue:
	mov si, .error_msg
	call err16
	jmp $

.no_vbe:
	mov si, .no_vbe_msg
	call err16
	jmp $

.old_vbe:
	mov si, .old_vbe_msg
	call err16
	jmp $

.error_msg			db "Failed to set VESA mode.",10,0
.no_vbe_msg			db "VESA BIOS not present.",10,0
.old_vbe_msg			db "VESA BIOS 2.0+ required.",10,0
.found_msg			db "Found VESA BIOS.",10,0

; vbe_set_mode:
; Sets a VESA mode
; In\	AX = Width
; In\	BX = Height
; In\	CL = Bits per pixel
; Out\	FLAGS = Carry clear on success
; Out\	Width, height, bpp, physical buffer, all set in vbe_screen structure

vbe_set_mode:
	mov [.width], ax
	mov [.height], bx
	mov [.bpp], cl

	sti

	push es					; some VESA BIOSes destroy ES, or so I read
	mov dword[vbe_info_block], "VBE2"
	mov ax, 0x4F00				; get VBE BIOS info
	mov di, vbe_info_block
	int 0x10
	pop es

	cmp ax, 0x4F				; BIOS doesn't support VBE?
	jne .error

	mov ax, word[vbe_info_block.video_modes]
	mov [.offset], ax
	mov ax, word[vbe_info_block.video_modes+2]
	mov [.segment], ax

	mov ax, [.segment]
	mov fs, ax
	mov si, [.offset]

.find_mode:
	mov dx, [fs:si]
	add si, 2
	mov [.offset], si
	mov [.mode], dx
	mov ax, 0
	mov fs, ax

	cmp [.mode], 0xFFFF			; end of list?
	je .error

	push es
	mov ax, 0x4F01				; get VBE mode info
	mov cx, [.mode]
	mov di, mode_info_block
	int 0x10
	pop es

	cmp ax, 0x4F
	jne .error

	mov ax, [.width]
	cmp ax, [mode_info_block.width]
	jne .next_mode

	mov ax, [.height]
	cmp ax, [mode_info_block.height]
	jne .next_mode

	mov al, [.bpp]
	cmp al, [mode_info_block.bpp]
	jne .next_mode

	; does the mode support LFB and is it supported by hardware?
	test [mode_info_block.attributes], 0x81
	jz .next_mode

	; If we make it here, we've found the correct mode!
	mov ax, [.width]
	mov word[vbe_screen.width], ax
	mov ax, [.height]
	mov word[vbe_screen.height], ax
	mov eax, [mode_info_block.framebuffer]
	mov dword[vbe_screen.physical_buffer], eax
	mov ax, [mode_info_block.pitch]
	mov word[vbe_screen.bytes_per_line], ax
	mov eax, 0
	mov al, [.bpp]
	mov byte[vbe_screen.bpp], al
	shr eax, 3
	mov dword[vbe_screen.bytes_per_pixel], eax

	mov ax, [.width]
	shr ax, 3
	dec ax
	mov word[vbe_screen.x_cur_max], ax

	mov ax, [.height]
	shr ax, 4
	dec ax
	mov word[vbe_screen.y_cur_max], ax

	; finally set the mode
	push es
	mov ax, 0x4F02
	mov bx, [.mode]
	or bx, 0x4000			; enable LFB
	mov di, 0
	int 0x10
	pop es

	cmp ax, 0x4F
	jne .error

	mov ax, 0
	mov fs, ax
	clc
	ret

.next_mode:
	mov ax, [.segment]
	mov fs, ax
	mov si, [.offset]
	jmp .find_mode

.error:
	mov ax, 0
	mov fs, ax
	stc
	ret

.width				dw 0
.height				dw 0
.bpp				db 0
.segment			dw 0
.offset				dw 0
.mode				dw 0

use64

; map_vbe_framebuffer:
; Maps the VBE framebuffer into the virtual address space

map_vbe_framebuffer:
	mov rsi, .info_msg
	call kprint

	mov rax, [vbe_screen.width]
	call int_to_string
	call kprint
	mov rsi, .info_msg2
	call kprint
	mov rax, [vbe_screen.height]
	call int_to_string
	call kprint
	mov rsi, .info_msg2
	call kprint
	mov rax, [vbe_screen.bpp]
	call int_to_string
	call kprint
	mov rsi, .info_msg3
	call kprint
	mov rax, [vbe_screen.physical_buffer]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, .model_msg
	call kprint
	mov rsi, [vbe_card_model]
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, .starting_msg
	call kprint

	mov rax, [vbe_screen.height]
	inc rax
	mov rbx, [vbe_screen.bytes_per_line]
	mul rbx
	mov [vbe_screen.size_bytes], rax

	mov rax, [vbe_screen.size_bytes]
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [vbe_screen.size_pages], rax

	mov rax, [vbe_screen.width]
	mov rbx, [vbe_screen.height]
	mul rbx
	mov [vbe_screen.size_pixels], rax

	movzx rax, [vbe_info_block.memory]
	mov rbx, 64
	mul rbx
	mov [vbe_memory_kb], rax
	mov rbx, 1024
	mul rbx
	mov [vbe_memory_bytes], rax
	mov rbx, 0x200000
	call round_forward
	shr rax, 21
	mov [vbe_memory_pages], rax

	mov rsi, .mem_size_msg
	call kprint
	mov rax, [vbe_memory_kb]
	call int_to_string
	call kprint
	mov rsi, .mem_size_msg2
	call kprint

	; first, map the hardware framebuffer into the virtual address space
	mov rax, [vbe_screen.physical_buffer]
	mov rbx, VBE_VIRTUAL_BUFFER
	mov rcx, [vbe_memory_pages]
	mov dl, 3
	call vmm_map_memory

	; next, search for memory to create a back buffer
	mov rax, 0
	mov rcx, [vbe_memory_bytes]
	call pmm_malloc
	jc .no_memory

	mov [vbe_screen.back_buffer], rax
	mov rbx, VBE_BACK_BUFFER
	mov rcx, [vbe_memory_pages]
	mov dl, 3
	call vmm_map_memory

	mov rsi, .done_msg
	call kprint

	mov rax, [vbe_screen.back_buffer]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	call unlock_screen

	jmp .do_boot_screen

.no_memory:
	mov rax, [vbe_screen.physical_buffer]
	mov rbx, VBE_BACK_BUFFER
	mov rcx, [vbe_memory_pages]
	mov dl, 3
	call vmm_map_memory

	mov rsi, .no_mem_msg
	call kprint

	mov rsi, .no_mem_msg
	call start_debugging

	jmp $

.do_boot_screen:
	call lock_screen

	mov ebx, 0
	call clear_screen

	mov ebx, 0
	mov ecx, 0xFFFFFF
	call set_text_color

	mov rsi, bootlogo
	call decode_bmp24

	mov [bootlogo_width], si
	mov [bootlogo_height], di
	mov [bootlogo_size], rcx
	mov [bootlogo_mem], rax

	call get_screen_center

	movzx rcx, [bootlogo_width]
	movzx rdx, [bootlogo_height]
	shr rcx, 1
	shr rdx, 1
	sub rax, rcx
	sub rbx, rdx
	mov si, [bootlogo_width]
	mov di, [bootlogo_height]
	mov rdx, [bootlogo_mem]
	call blit_buffer

	mov rax, [bootlogo_mem]
	mov rbx, [bootlogo_size]
	call kfree			; free this unused memory

	mov rsi, boot_notice
	mov cx, 16
	mov rdx, [vbe_screen.height]
	sub rdx, 3*16
	call print_string_transparent

	mov rsi, kernel_version
	mov cx, 16
	mov dx, 16
	call print_string_transparent

	call unlock_screen
	call redraw_screen

	; let the bootscreen stay for 3 seconds ;)
	;call wait_second
	;call wait_second
	;call wait_second

	ret

.info_msg			db "[vesafb] screen resolution is ",0
.info_msg2			db "x",0
.info_msg3			db ", hardware framebuffer is at 0x",0
.starting_msg			db "[vesafb] trying to create a VBE framebuffer in RAM...",10,0
.mem_size_msg			db "[vesafb] framebuffer requires ",0
.mem_size_msg2			db " KB of contiguous RAM.",10,0
.done_msg			db "[vesafb] done, created a back buffer at physical address 0x",0
.model_msg			db "[vesafb] card model is ",0
.no_mem_msg			db "[vesafb] not enough memory for VESA back buffer...",10,0

align 16
bootlogo:			file "os/bootlogo.bmp"
bootlogo_width			dw 0
bootlogo_height			dw 0
bootlogo_size			dq 0
bootlogo_mem			dq 0
boot_notice			db "(C) 2015-2016 by Omar Mohammad.",10
				db "All rights reserved.",0


