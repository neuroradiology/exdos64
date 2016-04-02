
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Math functions",0

;; Functions:
; is_number_multiple
; round_forward
; round_backward
; float_add
; float_sub
; float_mul
; float_div
; int_to_float
; float_to_int
; bcd_to_int
; random_seed
; generate_random_number

; is_number_multiple:
; Checks if a number is a multiple of another
; In\	RAX = Number 1 
; In\	RBX = Number 2
; Out\	RFLAGS = Carry set if is multiple, carry clear if not, carry clear also if number 2 is zero

is_number_multiple:
	cmp rbx, 0
	je .not

	mov rdx, 0
	div rbx
	cmp rdx, 0
	je .multiple

.not:
	clc
	ret

.multiple:
	stc
	ret

; round_forward:
; Rounds a number forward
; In\	RAX = Number
; In\	RBX = Number to get closer to
; Out\	RAX = Number

round_forward:
	mov [.number], rax
	mov [.round], rbx

	cmp [.number], 0
	je .next

	cmp rbx, 0
	je .done

.loop:
	mov rax, [.number]
	mov rbx, [.round]
	call is_number_multiple
	jc .done

	inc [.number]
	jmp .loop

.done:
	mov rax, [.number]
	ret

.next:
	mov rax, [.round]
	ret

.number					dq 0
.round					dq 0

; round_backward:
; Rounds a number backward
; In\	RAX = Number
; In\	RBX = Number to get closer to
; Out\	RAX = Number

round_backward:
	mov [.number], rax
	mov [.round], rbx

	cmp [.number], 0
	je .next

	cmp rbx, 0
	je .done

.loop:
	mov rax, [.number]
	mov rbx, [.round]
	call is_number_multiple
	jc .done

	dec [.number]
	jmp .loop

.done:
	mov rax, [.number]
	ret

.next:
	mov rax, [.round]
	ret

.number					dq 0
.round					dq 0

; float_add:
; Adds two floating point numbers
; In\	RAX = Number 1
; In\	RBX = Number 2
; Out\	RAX = Result

float_add:
	pushaq
	mov [.number1], rax
	mov [.number2], rbx

	finit
	fwait

	fld [.number1]
	fld [.number2]

	fadd st0, st1
	fwait
	fst [.number1]

	popaq
	mov rax, [.number1]
	ret

.number1			dq 0
.number2			dq 0

; float_sub:
; Subtracts two floating point numbers
; In\	RAX = Number 1
; In\	RBX = Number 2
; Out\	RAX = Result

float_sub:
	pushaq
	mov [.number1], rax
	mov [.number2], rbx

	finit
	fwait

	fld [.number1]
	fld [.number2]

	fsub st0, st1
	fwait
	fst [.number1]

	popaq
	mov rax, [.number1]
	ret

.number1			dq 0
.number2			dq 0

; float_mul:
; Multiplies two floating point numbers
; In\	RAX = Number 1
; In\	RBX = Number 2
; Out\	RAX = Result

float_mul:
	pushaq
	mov [.number1], rax
	mov [.number2], rbx

	finit
	fwait

	fld [.number1]
	fld [.number2]

	fmul st0, st1
	fwait
	fst [.number1]

	popaq
	mov rax, [.number1]
	ret

.number1			dq 0
.number2			dq 0

; float_div:
; Divides two floating point numbers
; In\	RAX = Number 1
; In\	RBX = Number 2
; Out\	RAX = Result

float_div:
	pushaq
	mov [.number1], rax
	mov [.number2], rbx

	finit
	fwait

	fld [.number1]

	fdiv [.number2]
	fwait
	fst [.number1]

	popaq
	mov rax, [.number1]
	ret

.number1			dq 0
.number2			dq 0

; int_to_float:
; Converts an integer to a double-precision floating point
; In\	RAX = Integer
; Out\	RAX = Floating point

int_to_float:
	mov [.number], rax

	finit
	fwait

	fild qword[.number]
	fwait
	fst qword[.number]
	mov rax, [.number]
	ret

.number				dq 0

; float_to_int:
; Converts a double-precision floating point to an integer
; In\	RAX = Floating point
; Out\	RAX = Integer

float_to_int:
	mov [.number], rax
	finit
	fwait

	fld qword[.number]
	fist dword[.number]
	mov rax, 0
	mov eax, dword[.number]
	ret

.number				dq 0

; bcd_to_int:
; Converts a binary coded decimal to a binary number
; In\	AL = BCD number
; Out\	AL = Binary number

bcd_to_int:
	mov [.tmp], al
	and rax, 0xF
	mov [.tmp2], ax
	mov al, [.tmp]
	and rax, 0xF0
	shr rax, 4
	and rax, 0xF

	mov rbx, 10
	mul rbx
	mov bx, [.tmp2]
	add ax, bx
	and rax, 0xFF

	ret

.tmp			db 0
.tmp2			dw 0

; int_to_bcd:
; Converts an integer to a binary coded decimal
; In\	AL = Binary number
; Out\	AL = BCD number

int_to_bcd:
	mov [.number], al
	mov [.tmp], 0

	mov rdx, 0
	and rax, 0xFF
	mov rbx, 10
	div rbx
	mov [.tmp], dl

	mov rdx, 0
	and rax, 0xFF
	mov rbx, 10
	div rbx
	shl dl, 4
	or [.tmp], dl

	mov al, [.tmp]
	ret

.number			db 0
.tmp			db 0

; random_seed:
; Seeds the random number generator

random_seed:
	mov cl, CMOS_REGISTER_SECONDS
	call cmos_read_register

	mov byte[generate_random_number.seed], al
	ret

; generate_random_number:
; Generates a random number
; In\	RAX = Minimum range
; In\	RBX = Maximum range
; Out\	RAX = Number

generate_random_number:
	cmp rax, rbx		; to avoid divide by zero error
	je .equal

	pushaq
	sub rbx, rax
	mov [.range], rbx

	mov rax, [.seed]
	mov rbx, 1103515245
	mul rbx
	add rax, 12345
	mov [.seed], rax

	mov rax, [.seed]
	mov rbx, [.range]
	shr rbx, 1
	mov rdx, 0
	div rbx

	mov rdx, 0
	mov rbx, [.range]
	div rbx
	mov [.tmp], rdx

	popaq
	mov rax, [.tmp]
	ret

.equal:
	ret			; no need to do anything; RAX already has the number

.range				dq 0
.tmp				dq 0
.seed				dq 0





