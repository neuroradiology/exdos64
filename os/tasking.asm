
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ExDOS kernel multitasking subsystem",0

;; Functions:
; init_tasking
; enable_tasking
; disable_tasking

task_structure				dq 0
running_tasks				dq 0
current_task				dq 0
tasking_enabled				db 0

MAXIMUM_TASKS				= 255
TASK_STRUCTURE:
	.flags				= $ - TASK_STRUCTURE
					dq 0			; Bit 0: Task is running
								; Bit 1: Task is active
								; Bit 2: Task has run in this scheduler
	.cpu				= $ - TASK_STRUCTURE
					dq 0			; APIC ID of the CPU
	.physical_address		= $ - TASK_STRUCTURE
					dq 0
	.pages				= $ - TASK_STRUCTURE
					dq 0
	.rip				= $ - TASK_STRUCTURE
					dq 0
	.rax				= $ - TASK_STRUCTURE
					dq 0
	.rbx				= $ - TASK_STRUCTURE
					dq 0
	.rcx				= $ - TASK_STRUCTURE
					dq 0
	.rdx				= $ - TASK_STRUCTURE
					dq 0
	.rsi				= $ - TASK_STRUCTURE
					dq 0
	.rdi				= $ - TASK_STRUCTURE
					dq 0
	.rbp				= $ - TASK_STRUCTURE
					dq 0
	.rsp				= $ - TASK_STRUCTURE
					dq 0
	.r8				= $ - TASK_STRUCTURE
					dq 0
	.r9				= $ - TASK_STRUCTURE
					dq 0
	.r10				= $ - TASK_STRUCTURE
					dq 0
	.r11				= $ - TASK_STRUCTURE
					dq 0
	.r12				= $ - TASK_STRUCTURE
					dq 0
	.r13				= $ - TASK_STRUCTURE
					dq 0
	.r14				= $ - TASK_STRUCTURE
					dq 0
	.r15				= $ - TASK_STRUCTURE
					dq 0
	.rflags				= $ - TASK_STRUCTURE
					dq 0

TASK_STRUCTURE_SIZE			= $ - TASK_STRUCTURE
TASK_STRUCTURE_MEMORY			= MAXIMUM_TASKS * TASK_STRUCTURE_SIZE
PROGRAM_LOAD_ADDRESS			= 0x8000000	; 128 MB
PROGRAM_STACK_SIZE			= 0x200000
TASK_SWITCH_INTERRUPT			= 0x90	; for quickly switching tasks without an IRQ
						; this is an internal interrupt and may change and users don't have anything to do with it

; init_tasking:
; Starts the multitasking subsystem

init_tasking:
	mov rsi, .starting_msg
	call kprint

	call disable_interrupts

	mov rax, 0
	mov rbx, TASK_STRUCTURE_MEMORY
	mov dl, 3
	call kmalloc
	cmp rax, 0
	je .no_memory
	mov [task_structure], rax

	call enable_tasking
	ret

.no_memory:
	mov rsi, .no_memory_msg
	call kprint

	mov rsi, .no_memory_msg
	call start_debugging

	jmp $

.starting_msg				db "[tasking] initializing multitasking subsystem...",10,0
.no_memory_msg				db "[tasking] no memory for task structure...",10,0

; enable_tasking:
; Enables kernel multitasking

enable_tasking:
	mov [tasking_enabled], 1
	ret

; disable_tasking:
; Disables kernel multitasking

disable_tasking:
	mov [tasking_enabled], 0
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TODO: Rewrite the multitasking system	;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;





