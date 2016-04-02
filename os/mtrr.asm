
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "MTRR manager",0

;; Functions:
; init_mtrr
; disable_mtrr
; enable_mtrr
; calculate_mtrr_mask
; mtrr_set_range

use64

; MTRR registers...
IA32_MTRRCAP			= 0xFE
IA32_MTRR_DEF_TYPE		= 0x2FF
IA32_MTRR_PHYSBASE		= 0x200
IA32_MTRR_PHYSMASK		= 0x201
IA32_MTRR_FIX64K_00000		= 0x250
IA32_MTRR_FIX16K_80000		= 0x258
IA32_MTRR_FIX16K_A0000		= 0x259
IA32_MTRR_FIX4K_C0000		= 0x268
IA32_MTRR_FIX4K_C8000		= 0x269
IA32_MTRR_FIX4K_D0000		= 0x26A
IA32_MTRR_FIX4K_D8000		= 0x26B
IA32_MTRR_FIX4K_E0000		= 0x26C
IA32_MTRR_FIX4K_E8000		= 0x26D
IA32_MTRR_FIX4K_F0000		= 0x26E
IA32_MTRR_FIX4K_F8000		= 0x26F

; MTRR memory types
MTRR_UNCACHEABLE		= 0
MTRR_WRITE_COMBINE		= 1
MTRR_WRITE_THROUGH		= 4
MTRR_WRITE_PROTECTED		= 5
MTRR_WRITEBACK			= 6

is_mtrr_available		db 0

align 16
max_phys_address		dq 0
mtrr_ranges			dq 0
mtrr_used_ranges		dq 0
mtrr_mask			dq 0xFFFFFFFFF		; default 36-bit mask

; init_mtrr:
; Initialize MTRR

init_mtrr:
	mov rsi, .starting_msg
	call kprint

	mov eax, 1
	cpuid
	test edx, 0x1000
	jz .no_mtrr

	call disable_mtrr

	mov eax, 0x80000000
	cpuid
	cmp eax, 0x80000008
	jl .no_mtrr

	mov eax, 0x80000008
	cpuid
	mov byte[max_phys_address], al

	mov rsi, .max_msg
	call kprint
	mov rax, [max_phys_address]
	call int_to_string
	call kprint
	mov rsi, .max_msg2
	call kprint

	mov rcx, IA32_MTRRCAP
	rdmsr
	mov byte[mtrr_ranges], al

	cmp [mtrr_ranges], 0
	je .no_mtrr

	mov rsi, .ranges_msg
	call kprint
	mov rax, [mtrr_ranges]
	call int_to_string
	call kprint
	mov rsi, .ranges_msg2
	call kprint

	call calculate_mtrr_mask

	mov [is_mtrr_available], 1

	mov rcx, IA32_MTRR_DEF_TYPE
	rdmsr
	and eax, 0xFFFFF3FF
	wrmsr

	; enable writeback caching for the kernel memory
	mov rax, 0
	mov rcx, 0x80000		; lowest 512 KB
	mov dl, MTRR_WRITEBACK
	call mtrr_set_range

	; enable write-combining for the VESA framebuffer
	mov rax, [vbe_screen.physical_buffer]
	mov rcx, [vbe_screen.size_bytes]
	mov dl, MTRR_WRITE_COMBINE
	call mtrr_set_range

	call enable_mtrr
	ret

.no_mtrr:
	mov rsi, .no_msg
	call kprint

	mov [is_mtrr_available], 0
	ret

.starting_msg			db "[mtrr] initializing MTRR...",10,0
.no_msg				db "[mtrr] warning: couldn't configure MTRR, performance may be low.",10,0
.max_msg			db "[mtrr] maximum physical address is ",0
.max_msg2			db " bits.",10,0
.ranges_msg			db "[mtrr] ",0
.ranges_msg2			db " variable ranges available.",10,0
.current_mtrr			dq 0

; disable_mtrr:
; Disables MTRR

disable_mtrr:
	mov rcx, IA32_MTRR_DEF_TYPE
	rdmsr
	and eax, 0xFFFFF7FF
	wrmsr
	ret

; enable_mtrr:
; Enables MTRR

enable_mtrr:
	mov rcx, IA32_MTRR_DEF_TYPE
	rdmsr
	or eax, 0x800
	wrmsr
	ret

; calculate_mtrr_mask:
; Like name says ^^

calculate_mtrr_mask:
	mov rax, 1
	mov rcx, [max_phys_address]
	shl rax, cl
	dec rax
	mov [mtrr_mask], rax

	mov rsi, .msg
	call kprint
	mov rax, [mtrr_mask]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	ret

.msg				db "[mtrr] default mask is 0x",0

; mtrr_get_free_range:
; Gets a free MTRR range
; In\	Nothing
; Out\	RCX = MSR address of PHYSBASE, 0 on error

mtrr_get_free_range:
	mov [.current_mtrr], 0

	mov rcx, IA32_MTRR_PHYSMASK

.loop:
	mov rax, [mtrr_ranges]
	cmp [.current_mtrr], rax
	jge .no

	rdmsr
	test eax, 0x800
	jz .found

	add rcx, 2
	inc [.current_mtrr]
	jmp .loop

.no:
	mov rsi, .no_msg
	call kprint

	mov rcx, 0
	ret

.found:
	dec rcx
	mov [.mtrr], rcx

	mov rsi, .msg
	call kprint
	mov rax, [.mtrr]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rcx, [.mtrr]
	ret

.current_mtrr			dq 0
.mtrr				dq 0
.msg				db "[mtrr] found free MTRR at MSR 0x",0
.no_msg				db "[mtrr] no free MTRR found.",10,0

; mtrr_set_range:
; Sets an MTRR range
; In\	RAX = 4 kb-aligned base
; In\	RCX = Bytes to cache
; In\	DL = MTRR type
; Out\	Nothing

mtrr_set_range:
	mov [.base], rax
	mov [.size], rcx
	mov [.type], dl

	cmp dl, 2		; Intel says these are reserved
	je .done		; using them causes GPF
	cmp dl, 3
	je .done
	cmp dl, 6
	jg .done

	call disable_interrupts
	mov rax, cr4
	mov [.cr4], rax

	call flush_caches

	mov rax, cr0
	or eax, 0x40000000
	mov cr0, rax

	call flush_caches
	call disable_mtrr

	; debugging ... ;)
	mov rsi, .starting_msg
	call kprint
	mov rax, [.size]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint
	mov rax, [.base]
	call hex_qword_to_string
	call kprint
	mov rsi, .starting_msg3
	call kprint

	movzx rax, [.type]
	shl rax, 3
	add rax, .table
	mov rsi, [rax]
	call kprint

	call mtrr_get_free_range
	cmp rcx, 0
	je .done

	mov eax, dword[.base]
	and eax, 0xFFFFF000
	mov edx, dword[.base+4]
	or al, [.type]
	wrmsr

	inc rcx
	mov eax, dword[.size]
	mov edx, dword[.size+4]

	not eax
	not edx

	and edx, dword[mtrr_mask+4]
	and eax, 0xFFFFF000
	or eax, 0x800
	wrmsr

	inc [mtrr_used_ranges]

.done:
	call flush_caches
	call enable_mtrr

	mov rax, cr0
	and eax, not 0x40000000
	mov cr0, rax

	call flush_caches

	mov rax, [.cr4]
	mov cr4, rax
	ret

align 16
.base				dq 0
.size				dq 0
.type				db 0
.cr4				dq 0

.starting_msg			db "[mtrr] setting ",0
.starting_msg2			db " bytes of memory at 0x",0
.starting_msg3			db " as ",0

.table:				dq .uncacheable		; 0
				dq .write_combine	; 1
				dq .reserved		; 2
				dq .reserved		; 3
				dq .write_through	; 4
				dq .write_protect	; 5
				dq .writeback		; 6

.uncacheable			db "uncacheble.",10,0
.write_combine			db "write-combine.",10,0
.reserved			db "reserved.",10,0
.write_through			db "write-through.",10,0
.write_protect			db "write-protected.",10,0
.writeback			db "writeback.",10,0




