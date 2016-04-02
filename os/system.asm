
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Core system routines",0

use16

;; Functions:
; check_cpu
; detect_memory
; enable_a20
; check_a20
; go32
; go16_32
; setup_identity_paging
; go64
; wait_second
; iowait

align 16
stack16:			rb 512

; check_cpu:
; Checks for 64-bit long mode features

check_cpu:
	mov eax, 0x80000000
	cpuid

	cmp eax, 0x80000001
	jl .no

	mov eax, 0x80000001
	cpuid

	test edx, 0x20000000		; long mode
	jz .no

	mov si, .done_msg
	call print_string_16

	ret

.no:
	mov si, .no_msg
	call err16

	jmp $

.done_msg			db "64-bit CPU found.",10,0
.no_msg				db "CPU is not 64-bit capable...",10,0

; detect_memory:
; Detects memory using BIOS function 0xE820

detect_memory:
	; ensure at least 4 MB of RAM so that we can initialize the paging tables
	mov cx, 0
	mov dx, 0
	mov eax, 0xE801
	int 0x15
	jc .error2

	cmp ah, 0x86
	je .error2
	cmp ah, 0x80
	je .error2

	jcxz .use_ax

	mov ax, cx
	mov bx, dx

.use_ax:
	cmp ax, 3072
	jl .too_little

.detect_e820:
	; now start the memory map detection
	mov di, memory_map+4
	mov ebx, 0

.get_map_loop:
	mov dword[di+20], 1	; for compatibility with ACPI 3.0
	mov edx, 0x534D4150
	mov eax, 0xE820		; some BIOSes require the high bits of eax to be zero
	mov ecx, 24
	push di
	int 0x15
	pop di
	jc .error

	cmp eax, 0x534D4150
	jne .error

	inc dword[.entries]

	cmp ebx, 0
	je .done

	and ecx, 0xFF
	mov dword[di-4], ecx
	add di, cx
	add di, 4
	jmp .get_map_loop

.done:
	ret

.error:
	mov si, .error_msg
	call err16

	jmp $

.error2:
	mov si, .error_msg2
	call err16

	jmp $

.too_little:
	mov si, .too_little_msg
	call err16

	jmp $

.error_msg			db "BIOS function 0xE820 failed.",10,0
.error_msg2			db "BIOS function 0xE801 failed.",10,0
.too_little_msg			db "Less than 4 MB of RAM found.",10,0
.entries			dd 0
memory_map:			rb 1024

; enable_a20:
; Enables A20 gate

enable_a20:
	mov ax, 0x2401
	int 0x15		; use BIOS
	jc .try_quick

	cmp ah, 0x86
	je .try_quick

	cmp ah, 0x80
	je .try_quick

	ret

.try_quick:
	; use the quick method of enabling A20
	in al, 0x92
	test al, 2			; if A20 is already enabled --
	jnz .quit			; -- a write to this port should be avoided

	or al, 2
	and al, 0xFE			; don't accidentally reset the system!
	out 0x92, al

.quit:
	ret

; check_a20:
; Checks A20 gate status

check_a20:
	mov ecx, 0xFFFF			; DexOS says some PCs need a delay

.delay:
	nop
	nop
	nop
	nop
	out 0x80, al
	out 0x80, al
	loop .delay

	mov di, 0x500
	mov eax, 0
	stosd

	mov ax, 0xFFFF
	mov es, ax
	mov di, 0x510

	mov eax, "A20 "
	stosd

	mov ax, 0
	mov es, ax

	mov si, 0x500
	lodsd

	cmp eax, "A20 "
	je .no

	mov si, .done_msg
	call print_string_16

	ret

.no:
	mov si, .no_msg
	call err16

	jmp $

.no_msg				db "A20 gate is not responding!",10,0
.done_msg			db "A20 gate enabled.",10,0

; go32:
; Enters 32-bit mode from 16-bit real mode

go32:
	cli

	pop bp			; return address

	lgdt [gdtr]
	mov eax, cr0
	or eax, 1
	mov cr0, eax
	jmp 8:.pmode

use32

.pmode:
	mov ax, 0x10
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	movzx esp, sp

	and ebp, 0xFFFF
	jmp ebp

; go16_32:
; Enters 16-bit mode from 32-bit protected mode

go16_32:
	cli

	pop ebp
	jmp 0x18:.pmode16

use16

.pmode16:
	mov ax, 0x20
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	mov eax, cr0
	and eax, not 1
	mov cr0, eax
	jmp 0:.rmode

.rmode:
	mov ax, 0
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	lidt [rm_ivt]
	sti
	jmp bp

use16

; setup_identity_paging:
; Sets up 64-bit identity paging

setup_identity_paging:
	call go32			; so we can access high memory

use32

	mov edi, pml4
	mov eax, 0
	mov ecx, 4096
	rep stosb

	mov edi, pml4
	mov eax, pdpt
	or eax, 7
	stosd
	mov eax, 0
	stosd

	mov edi, pdpt
	mov ebx, page_table
	mov ecx, 16			; handle a maximum of 16 GB

.fill_pdpt:
	mov eax, ebx
	or eax, 7
	stosd
	mov eax, 0
	stosd

	add ebx, 4096
	loop .fill_pdpt

	mov edi, page_table
	mov ecx, 16384
	mov eax, 0
	rep stosd

	mov edi, page_table
	mov ebx, 0
	mov edx, 0
	mov ecx, 16384/2			; identity page 16 GB

.fill_table:
	mov eax, ebx
	or eax, 0x87
	stosd
	mov eax, edx
	stosd

	add ebx, 0x200000
	cmp ebx, 0
	je .add_high
	loop .fill_table

.add_high:
	inc edx
	loop .fill_table

.done:
	call go16_32

use16

	mov si, .done_msg
	call print_string_16

	ret

.done_msg			db "64-bit identity paging set up.",10,0

; go64:
; Enters long mode from real mode

go64:
	cli
	pop bp				; return address

	lgdt [gdtr]

	mov eax, cr4
	or eax, 0x30			; enable PAE and PSE
	mov cr4, eax

	mov eax, pml4
	or eax, 8
	mov cr3, eax

	mov ecx, 0xC0000080
	rdmsr
	or eax, 0x100			; enable long mode
	wrmsr

	mov eax, cr0
	or eax, 0x80000001		; enable paging | protection
	mov cr0, eax
	jmp 0x28:.long_mode

use64

.long_mode:
	mov ax, 0x30
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	movzx rsp, sp

	lidt [idtr]

	and rbp, 0xFFFF
	jmp rbp	

use64

; wait_second:
; Waits for one second to pass

wait_second:
	pushaq

	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71
	mov [.tmp], al

.loop:
	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71

	cmp al, [.tmp]
	je .loop

.done:
	popaq
	ret

.tmp:				db 0

; iowait:
; Waits for an I/O operation to complete

iowait:
	out 0x80, al
	out 0x80, al
	ret

; gdt:
; Global Descriptor Table
align 32
gdt:
	; null descriptor 0x00
	dq 0

	; 32-bit code descriptor 0x08
	dw 0xFFFF				; limit low
	dw 0					; base low
	db 0					; base middle
	db 10011010b				; access
	db 11001111b				; flags and limit high
	db 0					; base high

	; 32-bit data descriptor 0x10
	dw 0xFFFF
	dw 0
	db 0
	db 10010010b
	db 11001111b
	db 0

	; 16-bit code descriptor 0x18
	dw 0xFFFF
	dw 0
	db 0
	db 10011010b
	db 10001111b
	db 0

	; 16-bit data descriptor 0x20
	dw 0xFFFF
	dw 0
	db 0
	db 10010010b
	db 10001111b
	db 0

	; 64-bit kernel code descriptor 0x28
	dw 0xFFFF
	dw 0
	db 0
	db 10011010b
	db 10101111b
	db 0

	; 64-bit kernel data descriptor 0x30
	dw 0xFFFF
	dw 0
	db 0
	db 10010010b
	db 10101111b
	db 0

	; Usermode code descriptor 0x38
	dw 0xFFFF
	dw 0
	db 0
	db 11111010b
	db 10101111b
	db 0

	; Usermode data descriptor 0x40
	dw 0xFFFF
	dw 0
	db 0
	db 11110010b
	db 10101111b
	db 0

	; TSS descriptor 0x48
	dw SIZE_OF_TSS
	dw tss
	db 0
	db 11101001b
	db 00100000b
	db 0
	dq 0

end_of_gdt:

align 32
gdtr:
	dw end_of_gdt - gdt - 1
	dq gdt

; idt:
; Interrupt Descriptor Table

align 32
idt:
	times 256 dw unhandled_isr, 0x28, 0x8E00, 0, 0, 0, 0, 0

end_of_idt:

align 32
idtr:
	dw end_of_idt - idt - 1
	dq idt

rm_ivt:
	dw 0x3FF
	dq 0

use64

; install_isr:
; Installs an interrupt service routine
; In\	AL = Interrupt number
; In\	RBP = Interrupt service routine address
; Out\	Nothing

install_isr:
	push rbp
	and rax, 0xFF
	shl rax, 4
	add rax, idt
	mov rdi, rax
	pop rbp

	mov [rdi], bp
	shr rbp, 16
	mov [rdi+6], bp
	shr rbp, 16
	mov [rdi+8], ebp

	ret

; unhandled_isr:
; Unhandled interrupt service routines...
align 32
unhandled_isr:
	pushaq
	inc [unhandled_irqs]

	;mov rsi, .msg
	;call kprint
	;mov rax, [unhandled_irqs]
	;call int_to_string
	;call kprint
	;mov rsi, .msg2
	;call kprint

	popaq
	call send_eoi
	iretq

.msg					db "[irq] unhandled IRQ received, total of ",0
.msg2					db " unhandled IRQs since startup.",10,0

unhandled_irqs				dq 0



