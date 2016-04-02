
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Physical memory manager",0

;; Functions:
; parse_memory_map
; pmm_init
; pmm_mark_page_used
; pmm_mark_used
; pmm_mark_page_free
; pmm_mark_free
; pmm_is_page_free
; pmm_malloc
; pmm_free
; memcpy
; memcpy_avx
; memxchg

use64

ebda_base				dq 0		; Extended BIOS Data Area

align 32
total_memory_mb				dq 0
total_memory_bytes			dq 0
usable_memory_mb			dq 0
usable_memory_bytes			dq 0
free_memory_mb				dq 0
used_memory_mb				dq 0

align 32
is_there_avx				dq 0

PMM_BITMAP				= 0x200000		; 2 MB

; parse_memory_map:
; Parses the E820 memory map

parse_memory_map:
	mov rsi, .ebda_msg
	call kprint
	mov rax, [ebda_base]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rsi, .starting_msg
	call kprint
	mov rsi, .title
	call kprint

	mov rsi, memory_map
	mov rcx, 0
	mov ecx, [detect_memory.entries]

.loop:
	pushaq
	mov eax, [rsi]
	mov [.entry_size], eax

	push rsi
	mov rsi, .space
	call kprint
	pop rsi

	push rsi

	mov rax, [rsi+4]			; Base
	mov [.tmp_base], rax
	call hex_qword_to_string
	call kprint

	mov rsi, .dash
	call kprint

	pop rsi
	push rsi
	mov rax, [rsi+4+8]
	mov [.tmp_size], rax
	add [.total_bytes], rax
	add rax, [.tmp_base]
	call hex_qword_to_string		; Size
	call kprint

	mov rsi, .dash
	call kprint

	pop rsi
	push rsi
	mov rax, 0
	mov eax, [rsi+4+8+8]
	push rax
	shl rax, 3
	add rax, .table
	mov rsi, [rax]
	call kprint
	pop rax
	cmp al, 1
	je .found_usable

	jmp .continue

.found_usable:
	mov rax, [.tmp_size]
	add [.usable_bytes], rax

.continue:
	mov rsi, newline
	call kprint
	pop rsi

	popaq

	mov rax, 0
	mov eax, [.entry_size]
	add rsi, rax
	add rsi, 4

	dec rcx
	cmp rcx, 0
	jle .done
	jmp .loop

.done:
	mov rax, [.total_bytes]
	mov [total_memory_bytes], rax
	mov rdx, 0
	mov rbx, 1024
	div rbx				; KB
	mov rdx, 0
	mov rbx, 1024
	div rbx				; MB
	mov [total_memory_mb], rax

	mov rax, [.usable_bytes]
	mov [usable_memory_bytes], rax
	mov rdx, 0
	mov rbx, 1024
	div rbx				; KB
	mov rdx, 0
	mov rbx, 1024
	div rbx				; MB
	mov [usable_memory_mb], rax

	mov rsi, .done_msg1
	call kprint
	mov rax, [total_memory_mb]
	call int_to_string
	call kprint

	mov rsi, .done_msg2
	call kprint
	mov rax, [usable_memory_mb]
	call int_to_string
	call kprint

	mov rsi, .done_msg3
	call kprint

	ret


.tmp_base				dq 0
.tmp_size				dq 0
.ebda_msg				db "[pmm] extended BIOS data area is at 0x",0
.starting_msg				db "[pmm] showing BIOS E820 memory map:",10,0
.done_msg1				db "[pmm] total RAM size is ",0
.done_msg2				db " MB, of which ",0
.done_msg3				db " MB are usable.",10,0
.dash					db " - ",0
.space					db " ",0
.title					db " STARTING ADDRESS - ENDING ADDRESS   - TYPE",10,0
.entry_size				dd 0
.table:					dq 0
					dq .usable
					dq .reserved
					dq .acpi_reclaimable
					dq .acpi_nvs
					dq .bad_memory
.usable					db "usable RAM",0
.reserved				db "hardware-reserved",0
.acpi_reclaimable			db "ACPI reclaimable",0
.acpi_nvs				db "ACPI NVS",0
.bad_memory				db "bad memory area",0
.total_bytes				dq 0
.usable_bytes				dq 0

; pmm_init:
; Initializes the physical memory manager

pmm_init:
	mov rsi, .starting_msg
	call kprint

	cmp [usable_memory_mb], 64
	jl .too_little

	mov rax, [total_memory_mb]
	mov [free_memory_mb], rax
	mov [used_memory_mb], 0

	mov rdi, PMM_BITMAP
	mov rcx, 2048/8
	mov rax, 0
	rep stosq			; mark all memory as unused

	mov rsi, .next_msg
	call kprint

	mov rax, 0
	mov rcx, 8/2			; reserve the lowest 8 MB for the kernel
	call pmm_mark_used

	; now we need to mark all the E820 non-usable areas are used, to prevent applications writing there
	mov rcx, 0
	mov ecx, [detect_memory.entries]
	mov rsi, memory_map

.hardware_loop:
	mov eax, [rsi]
	mov [.entry_size], eax

	mov eax, [rsi+4+8+8]
	cmp al, 1
	jne .found_unusable_memory

.next:
	mov rax, 0
	mov eax, [.entry_size]
	add rsi, rax
	add rsi, 4
	loop .hardware_loop
	jmp .done

.found_unusable_memory:
	push rcx
	mov rax, [rsi+4]
	mov rcx, [rsi+4+8]
	shr rcx, 21			; pages
	inc rcx
	call pmm_mark_used

	pop rcx
	jmp .next
	loop .hardware_loop

.done:
	mov rax, cr0
	and eax, 0x9FFAFFFF	; enable caching, disable AC, enable writing to read-only pages
	mov cr0, rax

	; enable SSE
	mov rax, cr0
	and eax, not 4
	or eax, 2
	mov cr0, rax

	mov rax, cr4
	or eax, 0x600
	mov cr4, rax

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; At least on one CPU, SSE is faster than AVX                   ;;
	;; Needs testing because I don't have any other PCs with AVX     ;;
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	; check for AVX-256 and enable it if supported
	;mov rax, 1
	;cpuid

	;test ecx, 0x18000000
	;jz .quit

	; enable AVX
	;mov rax, cr4
	;or eax, 0x40000
	;mov cr4, rax

	;mov rcx, 0
	;xgetbv

	;or eax, 6
	;mov rcx, 0
	;xsetbv

	;mov rsi, .avx_msg
	;call kprint

	;mov [is_there_avx], 1

.quit:
	ret

.too_little:
	mov rsi, .too_little_msg
	call kprint

	mov rsi, .too_little_msg
	call boot_error_early
	jmp $

.starting_msg				db "[pmm] initializing physical memory manager...",10,0
.too_little_msg				db "[pmm] ExDOS64 requires at least 64 MB of usable RAM to boot!",10,0
.next_msg				db "[pmm] done, reserving kernel and hardware memory areas...",10,0
.avx_msg				db "[pmm] CPU supports AVX-256, using it for memory access acceleration.",10,0
.entry_size				dd 0

; pmm_mark_page_used:
; Marks a single physical page as used
; In\	RAX = Address (2 MB aligned)
; Out\	RFLAGS = Carry set if too little memory

pmm_mark_page_used:
	pushaq
	mov [.base], rax

	;add rax, 0x200000
	;cmp rax, [total_memory_bytes]
	;jge .error

	; determine the page group of the memory
	mov rax, [.base]
	shr rax, 24
	mov [.group], rax

	mov rbx, [.group]
	shl rbx, 24
	mov rax, [.base]
	sub rax, rbx
	shr rax, 21
	;dec rax
	add rax, .bitmap_values

	mov dl, [rax]
	mov rdi, [.group]
	add rdi, PMM_BITMAP
	or byte[rdi], dl

	add [used_memory_mb], 2
	sub [free_memory_mb], 2
	popaq
	ret

.error:
	popaq
	stc
	ret

.base					dq 0
.group					dq 0
.bitmap_values:				db 1			; for page 1
					db 2			; for page 2
					db 4			; for page 3
					db 8			; for page 4
					db 16			; for page 5
					db 32			; for page 6
					db 64			; for page 7
					db 128			; for page 8

; pmm_mark_used:
; Marks a region of physical memory as used
; In\	RAX = Base address
; In\	RCX = Pages
; Out\	RFLAGS = Carry set if too little memory

pmm_mark_used:
	pushaq
	mov [.base], rax
	mov [.pages], rcx

	mov rax, [.pages]
	shl rax, 21
	;add rax, [.base]
	;cmp rax, [total_memory_bytes]
	;jge .error

	;mov rsi, .msg1
	;call kprint
	;mov rax, [.pages]
	;call int_to_string
	;call kprint
	;mov rsi, .msg2
	;call kprint
	;mov rax, [.base]
	;call hex_qword_to_string
	;call kprint
	;mov rsi, .msg3
	;call kprint

	mov rax, [.base]
	mov rcx, [.pages]

.loop:
	call pmm_mark_page_used
	add rax, 0x200000
	loop .loop

	popaq
	clc
	ret

.error:
	;mov rsi, .error_msg
	;call kprint
	;mov rax, [.base]
	;call hex_qword_to_string
	;call kprint
	;mov rsi, newline
	;call kprint

	popaq
	stc
	ret

.base					dq 0
.pages					dq 0
.msg1					db "[pmm] marking ",0
.msg2					db " pages at address 0x",0
.msg3					db " as used.",10,0
.error_msg				db "[pmm] not enough memory at 0x",0

; pmm_mark_page_free:
; Marks a single physical page as free
; In\	RAX = Address (2 MB aligned)
; Out\	RFLAGS = Carry set if too little memory

pmm_mark_page_free:
	pushaq
	mov [.base], rax

	;add rax, 0x200000
	;cmp rax, [total_memory_bytes]
	;jge .error

	; determine the page group of the memory
	mov rax, [.base]
	shr rax, 24
	mov [.group], rax

	mov rbx, [.group]
	shl rbx, 24
	mov rax, [.base]
	sub rax, rbx
	shr rax, 21
	;dec rax
	add rax, .bitmap_values

	mov dl, [rax]
	mov rdi, [.group]
	add rdi, PMM_BITMAP
	not dl
	and byte[rdi], dl

	add [free_memory_mb], 2
	sub [used_memory_mb], 2
	popaq
	ret

.error:
	popaq
	stc
	ret

.base					dq 0
.group					dq 0
.bitmap_values:				db 1			; for page 1
					db 2			; for page 2
					db 4			; for page 3
					db 8			; for page 4
					db 16			; for page 5
					db 32			; for page 6
					db 64			; for page 7
					db 128			; for page 8

; pmm_mark_free:
; Marks a region of physical memory as free
; In\	RAX = Base address
; In\	RCX = Pages
; Out\	RFLAGS = Carry set if too little memory

pmm_mark_free:
	pushaq
	mov [.base], rax
	mov [.pages], rcx

	mov rax, [.pages]
	shl rax, 21
	;add rax, [.base]
	;cmp rax, [total_memory_bytes]
	;jge .error

	;mov rsi, .msg1
	;call kprint
	;mov rax, [.pages]
	;call int_to_string
	;call kprint
	;mov rsi, .msg2
	;call kprint
	;mov rax, [.base]
	;call hex_qword_to_string
	;call kprint
	;mov rsi, .msg3
	;call kprint

	mov rax, [.base]
	mov rcx, [.pages]

.loop:
	call pmm_mark_page_free
	add rax, 0x200000
	loop .loop

	popaq
	clc
	ret

.error:
	;mov rsi, .error_msg
	;call kprint
	;mov rax, [.base]
	;call hex_qword_to_string
	;call kprint
	;mov rsi, newline
	;call kprint

	popaq
	stc
	ret

.base					dq 0
.pages					dq 0
.msg1					db "[pmm] freeing ",0
.msg2					db " pages at address 0x",0
.msg3					db ".",10,0
.error_msg				db "[pmm] not enough memory at 0x",0

; pmm_is_page_free:
; Tests if an address of physical memory is free
; In\	RAX = Address
; Out\	RAX = 0 if free, 1 if not
; Out\	RFLAGS = Carry set if out of memory

pmm_is_page_free:
	pushaq
	mov [.address], rax

	cmp rax, [total_memory_bytes]
	jge .out_of_mem

	mov rax, [.address]
	shr rax, 24
	mov [.group], rax

	mov rbx, [.group]
	shl rbx, 24
	mov rax, [.address]
	sub rax, rbx
	shr rax, 21
	add rax, .bitmap_values

	mov dl, [rax]
	mov rdi, [.group]
	add rdi, PMM_BITMAP
	test byte[rdi], dl
	jz .free

.used:
	popaq
	clc
	mov rax, 1
	ret

.free:
	popaq
	clc
	mov rax, 0
	ret

.out_of_mem:
	popaq
	mov rax, 1
	stc
	ret

.address				dq 0
.group					dq 0
.bitmap_values:				db 1			; for page 1
					db 2			; for page 2
					db 4			; for page 3
					db 8			; for page 4
					db 16			; for page 5
					db 32			; for page 6
					db 64			; for page 7
					db 128			; for page 8

; pmm_malloc:
; Allocates a block of physical memory
; In\	RAX = Starting address
; In\	RCX = Bytes
; Out\	RAX = Address of free memory, 0 on error

pmm_malloc:
	pushaq
	mov [.base], rax
	mov rax, rcx
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [.pages], rax

.start:
	mov [.current_page], 0
	mov rax, [.pages]
	shl rax, 21
	mov [.end_base], rax
	mov rax, [.base]
	add [.end_base], rax
	mov rdx, [.base]

.loop:
	mov rax, rdx
	call pmm_is_page_free
	jc .error

	cmp rax, 0
	je .go_next

.next_base:
	add [.base], 0x200000
	jmp .start

.go_next:
	add rdx, 0x200000
	inc [.current_page]
	mov rcx, [.pages]
	cmp rcx, [.current_page]
	jle .done
	jmp .loop

.done:
	mov rax, [.base]
	mov rcx, [.pages]
	call pmm_mark_used

	popaq
	mov rax, [.base]
	ret

.error:
	popaq
	mov rax, 0
	ret

.base					dq 0
.end_base				dq 0
.pages					dq 0
.current_page				dq 0

; pmm_free:
; Frees physical memory
; In\	RAX = Address
; In\	RCX = Pages
; Out\	Nothing

pmm_free:
	pushaq
	mov [.base], rax
	mov rax, rcx
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [.pages], rax

	mov rax, [.base]
	mov rcx, [.pages]
	call pmm_mark_free

	popaq
	ret
	

.base					dq 0
.pages					dq 0

; memcpy:
; Copies memory
; In\	RSI = Source
; In\	RDI = Destination
; In\	RCX = Bytes to copy
; Out\	Nothing
align 32
memcpy:
	cmp [is_there_avx], 1
	je memcpy_avx			; this is faster

	test rsi, 0xF
	jnz memcpy_u

	test rdi, 0xF
	jnz memcpy_u

	cmp rcx, 128
	jl .plain_bytes

	push rcx
	shr rcx, 7			; div 128

.loop:
	movdqa xmm0, [rsi]
	movdqa xmm1, [rsi+16]
	movdqa xmm2, [rsi+32]
	movdqa xmm3, [rsi+48]
	movdqa xmm4, [rsi+64]
	movdqa xmm5, [rsi+80]
	movdqa xmm6, [rsi+96]
	movdqa xmm7, [rsi+112]

	movdqa [rdi], xmm0
	movdqa [rdi+16], xmm1
	movdqa [rdi+32], xmm2
	movdqa [rdi+48], xmm3
	movdqa [rdi+64], xmm4
	movdqa [rdi+80], xmm5
	movdqa [rdi+96], xmm6
	movdqa [rdi+112], xmm7

	add rsi, 128
	add rdi, 128
	loop .loop

	pop rcx

.plain_bytes:
	push rcx
	and rcx, 127
	shr rcx, 3
	rep movsq
	pop rcx

	and rcx, 7
	rep movsb

	ret

; memcpy_u:
; Same as above, but uses SSE unalignment, used internally and transparently to the user

memcpy_u:
	cmp rcx, 128
	jl .plain_bytes

	push rcx
	shr rcx, 7			; div 128

.loop:
	movdqu xmm0, [rsi]
	movdqu xmm1, [rsi+16]
	movdqu xmm2, [rsi+32]
	movdqu xmm3, [rsi+48]
	movdqu xmm4, [rsi+64]
	movdqu xmm5, [rsi+80]
	movdqu xmm6, [rsi+96]
	movdqu xmm7, [rsi+112]

	movdqu [rdi], xmm0
	movdqu [rdi+16], xmm1
	movdqu [rdi+32], xmm2
	movdqu [rdi+48], xmm3
	movdqu [rdi+64], xmm4
	movdqu [rdi+80], xmm5
	movdqu [rdi+96], xmm6
	movdqu [rdi+112], xmm7

	add rsi, 128
	add rdi, 128
	loop .loop

	pop rcx

.plain_bytes:
	push rcx
	and rcx, 127
	shr rcx, 3
	rep movsq
	pop rcx

	and rcx, 7
	rep movsb

	ret

; memcpy_avx:
; Copies memory using AVX to speed up
; In\	RSI = Source
; In\	RDI = Destination
; In\	RCX = Bytes to copy
; Out\	Nothing
align 32
memcpy_avx:
	test rsi, 0x1F
	jnz memcpy_avx_u

	test rdi, 0x1F
	jnz memcpy_avx_u

	cmp rcx, 256
	jl .plain_bytes

	push rcx
	shr rcx, 8			; divide by 256

.loop:
	vmovdqa ymm0, [rsi]
	vmovdqa ymm1, [rsi+32]
	vmovdqa ymm2, [rsi+64]
	vmovdqa ymm3, [rsi+96]
	vmovdqa ymm4, [rsi+128]
	vmovdqa ymm5, [rsi+160]
	vmovdqa ymm6, [rsi+192]
	vmovdqa ymm7, [rsi+224]

	vmovdqa [rdi], ymm0
	vmovdqa [rdi+32], ymm1
	vmovdqa [rdi+64], ymm2
	vmovdqa [rdi+96], ymm3
	vmovdqa [rdi+128], ymm4
	vmovdqa [rdi+160], ymm5
	vmovdqa [rdi+192], ymm6
	vmovdqa [rdi+224], ymm7

	add rsi, 256
	add rdi, 256
	loop .loop

	pop rcx

.plain_bytes:
	push rcx
	and rcx, 255
	shr rcx, 3
	rep movsq
	pop rcx

	and rcx, 7
	rep movsb

	ret

; memcpy_avx_u:
; Same as above, used internally and transparently with AVX unaligned instructions

memcpy_avx_u:
	cmp rcx, 256
	jl .plain_bytes

	push rcx
	shr rcx, 8			; divide by 256

.loop:
	vmovdqu ymm0, [rsi]
	vmovdqu ymm1, [rsi+32]
	vmovdqu ymm2, [rsi+64]
	vmovdqu ymm3, [rsi+96]
	vmovdqu ymm4, [rsi+128]
	vmovdqu ymm5, [rsi+160]
	vmovdqu ymm6, [rsi+192]
	vmovdqu ymm7, [rsi+224]

	vmovdqu [rdi], ymm0
	vmovdqu [rdi+32], ymm1
	vmovdqu [rdi+64], ymm2
	vmovdqu [rdi+96], ymm3
	vmovdqu [rdi+128], ymm4
	vmovdqu [rdi+160], ymm5
	vmovdqu [rdi+192], ymm6
	vmovdqu [rdi+224], ymm7

	add rsi, 256
	add rdi, 256
	loop .loop

	pop rcx

.plain_bytes:
	push rcx
	and rcx, 255
	shr rcx, 3
	rep movsq
	pop rcx

	and rcx, 7
	rep movsb

	ret

; memxchg:
; Exchanges memory
; In\	RSI = Memory location #1
; In\	RDI = Memory location #2
; In\	RCX = Bytes to exchange
; Out\	Nothing
align 32
memxchg:
	pushaq

	cmp rcx, 8
	jl .just_bytes

	push rcx
	shr rcx, 3

.loop:
	mov rax, [rsi]
	mov [.tmp], rax
	mov rax, [rdi]
	mov [rsi], rax
	mov rax, [.tmp]
	mov [rdi], rax

	add rsi, 8
	add rdi, 8
	loop .loop

	pop rcx
	and rcx, 7
	cmp rcx, 0
	je .done

.just_bytes:
	mov al, [rsi]
	mov byte[.tmp], al
	mov al, [rdi]
	mov [rsi], al
	mov al, byte[.tmp]
	mov [rdi], al

	inc rsi
	inc rdi
	loop .loop

.done:
	popaq
	ret

align 32
.tmp				dq 0


