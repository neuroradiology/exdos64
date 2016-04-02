
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

;; Functions:
; init_user
; enter_usermode
; enter_ring0
; syscall_entry_point
; user_api
; kernel_info
; memory_info

db "ExDOS user-side code",0

MAXIMUM_PROGRAMS			= 255
running_programs			db 0
programs_list				dq 0
is_enter_ring0				db 0

align 32
tss:
					dd 0
	.rsp0				dq 0
	.rsp1				dq 0
	.rsp2				dq 0
					dq 0
	.ist1				dq 0
	.ist2				dq 0
	.ist3				dq 0
	.ist4				dq 0
	.ist5				dq 0
	.ist6				dq 0
	.ist7				dq 0
					dq 0
					dw 0
					dw 0
SIZE_OF_TSS				= $ - tss

APPLICATION_HEADER:
	.signature			= 0
	.version			= 7
	.type				= 8
	.entry_point			= 9
	.program_size			= 17
	.program_name			= 25
	.driver_hardware		= 33
	.reserved1			= 41
	.reserved2			= 49

new_stack				dq 0

; init_user:
; Iniitializes the user API

init_user:
	pop rax
	mov [.return], rax

	mov rsi, .starting_msg
	call kprint

	; load the TSS
	mov rax, 0x48+3
	ltr ax

	; enable SYSCALL/SYSRET
	mov rcx, 0xC0000080
	rdmsr
	or eax, 1
	wrmsr

	; set up SYSCALL/SYSRET MSRs
	mov rcx, 0xC0000081
	mov eax, 0
	mov edx, 0x00480028
	wrmsr

	mov rcx, 0xC0000082
	mov eax, syscall_entry_point
	mov edx, 0
	wrmsr

	mov rcx, 0xC0000084
	mov edx, 0
	not edx
	mov eax, 0x200
	not eax
	wrmsr

	mov rax, 0
	mov rbx, 0x200000
	mov dl, 7
	call kmalloc
	cmp rax, 0
	je .no_memory

	add rax, 65536			; give all ISRs 64 KB stack spaces
					; drivers that handle IRQs have about 64 KB minus a few QWORDS stack space
	mov [tss.rsp0], rax
	sub rax, 65536
	add rax, 0x200000
	mov rsp, rax			; set up a new kernel stack in high memory

	mov rax, 0			; let the user access the kernel
	mov rbx, 0
	mov rcx, 1
	mov dl, 7
	call vmm_map_memory

	mov rax, [.return]
	push rax
	ret

.no_memory:
	mov rsi, .no_memory_msg
	call kprint

	mov rsi, .no_memory_msg
	call start_debugging

	jmp $

.starting_msg				db "[user] initializing user API...",10,0
.no_memory_msg				db "[user] couldn't allocate a stack...",10,0
.return					dq 0
;kernel_stack				dq 0

; enter_usermode:
; Puts the system in user mode

enter_usermode:
	pushaq
	cli
	mov rax, rsp
	push 0x40+3			; SS
	push rax			; RSP
	pushfq				; RFLAGS
	pop rax
	or rax, 0x202			; enable interrupts
	push rax
	push 0x38+3			; CS
	push .next			; RIP
	iretq

.next:
	mov ax, 0x40+3
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	popaq
	ret

; enter_ring0:
; Enters ring 0

enter_ring0:
	mov [is_enter_ring0], 1
	syscall
	mov [is_enter_ring0], 0
	ret

; syscall_entry_point:
; Entry point for SYSCALL instruction

syscall_entry_point:
	push rax
	mov ax, 0x30
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	pop rax

	cmp [is_enter_ring0], 1
	je .ring0

	sysexit

.ring0:
	jmp rcx

MAX_USER_API			= 0x28

; user_api:
; User API entry point

user_api:
	call disable_tasking
	mov [.return], rcx
	cmp r15, MAX_USER_API
	jg .bad

	shl r15, 3
	add r15, .table
	mov rbp, [r15]
	call rbp

	call enter_usermode
	mov r15, [.return]
	jmp r15

.bad:
	call enter_usermode
	mov rax, [.return]
	push rax
	mov rax, -1
	ret

.return				dq 0
.table:
				; Kernel routines
				;dq create_task			; 00
				;dq kernel_info			; 01
				;dq yield			; 02
				;dq print_string_cursor		; 03


; kernel_info:
; Gets kernel information
; In\	Nothing
; Out\	RAX = Pointer to kernel information structure

kernel_info:
	mov rax, .struct
	ret

.struct:
	dq API_VERSION
	dq kernel_version

; memory_info:
; Gets memory information
; In\	Nothing
; Out\	RAX = Pointer to kernel information structure

memory_info:
	mov rax, [total_memory_mb]
	mov [.total], rax
	mov rax, [usable_memory_mb]
	mov [.usable], rax
	mov rax, [free_memory_mb]
	mov [.free], rax
	mov rax, [used_memory_mb]
	mov [.used], rax

	mov rax, .struct
	ret

.struct:
	.total		dq 0
	.usable		dq 0
	.free		dq 0
	.used		dq 0


