
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "String manipulation routines",0

;; Functions:
; hex_nibble_to_string
; hex_byte_to_string
; hex_word_to_string
; hex_dword_to_string
; hex_qword_to_string
; int_to_string
; get_string_size
; convert_string_endianness
; trim_string
; hex_string_to_value
; find_byte_in_string
; replace_byte_in_string

hex_values			db "0123456789ABCDEF"

; hex_nibble_to_string:
; Converts a nibble to a hex string
; In\	Lower bits of AL = Nibble value
; Out\	RSI = Pointer to string

hex_nibble_to_string:
	and rax, 0xF			; keep only the nibble
	add rax, hex_values
	mov dl, [rax]
	mov [.string], dl

	mov rsi, .string
	ret

.string:			times 2 db 0

; hex_byte_to_string:
; Converts a byte to a hex string
; In\	AL = Byte
; Out\	RSI = Pointer to string

hex_byte_to_string:
	mov [.byte], al
	movzx rax, al
	shr rax, 4			; high nibble
	call hex_nibble_to_string

	mov rdi, .string
	movsb

	movzx rax, [.byte]
	and rax, 0xF			; low nibble
	call hex_nibble_to_string

	mov rdi, .string+1
	movsb

	mov rsi, .string
	ret

.byte				db 0
.string:			times 3 db 0

; hex_word_to_string:
; Converts a 16-bit word to a hex string
; In\	AX = Word
; Out\	RSI = Pointer to string

hex_word_to_string:
	mov [.word], ax
	movzx rax, ax
	shr rax, 8			; high byte
	call hex_byte_to_string

	mov rdi, .string
	movsb
	movsb

	movzx rax, [.word]
	and rax, 0xFF			; low byte
	call hex_byte_to_string

	mov rdi, .string+2
	movsb
	movsb

	mov rsi, .string
	ret


.word				dw 0
.string:			times 5 db 0

; hex_dword_to_string:
; Converts a 32-bit DWORD to a hex string
; In\	EAX = DWORD
; Out\	RSI = Pointer to string

hex_dword_to_string:
	mov [.dword], eax
	shr rax, 16			; high word
	call hex_word_to_string

	mov rdi, .string
	mov rcx, 4
	rep movsb

	mov rax, 0
	mov eax, [.dword]
	and rax, 0xFFFF			; low word
	call hex_word_to_string

	mov rdi, .string+4
	mov rcx, 4
	rep movsb

	mov rsi, .string
	ret

.dword				dd 0
.string:			times 9 db 0

; hex_qword_to_string:
; Converts a 64-bit QWORD to a hex string
; In\	RAX = QWORD
; Out\	RSI = Pointer to string

hex_qword_to_string:
	mov [.qword], rax
	shr rax, 32			; high dword
	call hex_dword_to_string

	mov rdi, .string
	mov rcx, 8
	rep movsb

	mov rax, [.qword]
	;and rax, 0xFFFFFFFF		; low dword
	call hex_dword_to_string

	mov rdi, .string+8
	mov rcx, 8
	rep movsb

	mov rsi, .string
	ret

.qword				dq 0
.string:			times 17 db 0

; int_to_string:
; Converts an integer to a string
; In\	RAX = Integer
; Out\	RSI = Pointer to string

int_to_string:
	mov [.int], rax

	mov [.counter], 0
	mov rdi, .string
	mov rax, 0
	mov rcx, 32
	rep stosb

	mov rdi, .string+30
	mov rax, [.int]
	;cli
	;hlt

.loop:
	mov rdx, 0
	mov rbx, 10
	div rbx
	add dl, '0'
	mov [rdi], dl

	cmp rax, 0
	je .done

	dec rdi
	jmp .loop

.done:
	mov rsi, rdi
	ret

.int				dq 0
.counter			dq 0
.string:			times 32 db 0

; get_string_size:
; Gets size of an ASCIIZ string
; In\	RSI = String
; Out\	RAX = Size

get_string_size:
	pushaq
	mov rcx, 0

.loop:
	lodsb
	cmp al, 0
	je .done
	inc rcx
	jmp .loop

.done:
	mov [.tmp], rcx
	popaq
	mov rax, [.tmp]
	ret

.tmp				dq 0

; convert_string_endianness:
; Converts the value in a string from little-endian to big-endian or vice versa
; In\	RSI = String
; Out\	RSI = Unmodified, same string modified

convert_string_endianness:
	push rsi
	call get_string_size
	test rax, 1			; don't work on strings with odd size
	jnz .done

.start_work:
	mov ax, [rsi]
	cmp al, 0
	je .done
	xchg al, ah
	mov [rsi], ax
	add rsi, 2
	jmp .start_work

.done:
	pop rsi
	ret

; trim_string:
; Trims a string from forward and backward spaces
; In\	RSI = String
; Out\	RSI = Modified string

trim_string:
	pushaq
	mov [.string], rsi

.count_begin_spaces_loop:
	cmp byte[rsi], ' '
	jne .no_more_begin_spaces

	inc rsi
	jmp .count_begin_spaces_loop

.no_more_begin_spaces:
	push rsi
	call get_string_size
	pop rsi
	mov rcx, rax
	mov rdi, [.string]
	rep movsb
	mov al, 0
	stosb

.count_end_spaces:
	push rsi
	mov rsi, [.string]
	call get_string_size
	pop rsi
	add rsi, rax

.count_end_spaces_loop:
	cmp word[rsi], '  '
	je .found_spaces

	dec rsi
	cmp rsi, [.string]
	jle .done
	jmp .count_end_spaces_loop

.found_spaces:
	mov word[rsi], 0
	jmp .count_end_spaces_loop

.done:
	mov rsi, [.string]
	call get_string_size
	add rsi, rax
	dec rsi
	cmp byte[rsi], 0x20
	jne .quit

	mov byte[rsi], 0

.quit:
	popaq
	ret

.string				dq 0

; hex_string_to_value:
; Converts a hex string (eg "123ABC") to a hex number (0x123ABC)
; In\	RSI = ASCIIZ string
; Out\	RFLAGS = Carry set if string is longer than 16 characters
; Out\	RAX = Hex number

hex_string_to_value:
	pushaq
	mov [.string], rsi
	mov [.number], 0
	mov [.multiplier], 1
	mov rdi, .string_copy
	mov al, '0'
	mov rcx, 16
	rep stosb

	mov rsi, [.string]
	call get_string_size
	cmp rax, 16
	jg .bad

	mov rcx, rax
	mov rdi, 16
	sub rdi, rax
	add rdi, .string_copy
	rep movsb

	mov rsi, .string_copy+15

.loop:
	cmp rsi, .string_copy
	jl .done

	mov rbx, 0
	mov bl, [rsi]
	cmp bl, '9'
	jle .number_char

	cmp bl, 'a'
	jge .small_letter

	cmp bl, 'A'
	jge .capital_letter

.capital_letter:
	cmp bl, 'F'
	jg .bad

	sub bl, 'A'-10
	mov rax, [.multiplier]
	mul rbx
	add [.number], rax
	shl [.multiplier], 4
	dec rsi
	jmp .loop

.small_letter:
	cmp bl, 'f'
	jg .bad

	sub bl, 'a'-10
	mov rax, [.multiplier]
	mul rbx
	add [.number], rax
	shl [.multiplier], 4
	dec rsi
	jmp .loop

.number_char:
	sub bl, '0'
	mov rax, [.multiplier]
	mul rbx
	add [.number], rax
	shl [.multiplier], 4
	dec rsi
	jmp .loop

.done:
	popaq
	clc
	mov rax, [.number]
	ret

.bad:
	popaq
	stc
	ret

.string				dq 0
.string_copy:			times 16 db "0"
				db 0
.number				dq 0
.multiplier			dq 1

; find_byte_in_string:
; Find a byte within a string
; In\	RSI = String
; In\	DL = Byte to find
; In\	RCX = Total bytes to search
; Out\	RFLAGS = Carry clear if byte found
; Out\	RSI = Pointer to byte in string

find_byte_in_string:

.loop:
	lodsb
	cmp al, dl
	je .found
	loop .loop

	stc
	ret

.found:
	dec rsi
	clc
	ret


; replace_byte_in_string:
; Replaces a byte in a string
; In\	RSI = String
; In\	DL = Byte to find
; In\	DH = Byte to replace with
; Out\	Nothing

replace_byte_in_string:
	mov [.byte_to_find], dl
	mov [.byte_to_replace], dh

	call get_string_size
	mov rcx, rax

.loop:
	mov al, byte[esi]
	cmp al, byte[.byte_to_find]
	je .found

	inc rsi
	dec rcx
	cmp rcx, 0
	je .done
	jmp .loop

.found:
	mov al, byte[.byte_to_replace]
	mov byte[rsi], al
	inc rsi
	dec rcx
	cmp rcx, 0
	je .done
	jmp .loop

.done:
	ret

.byte_to_find			db 0
.byte_to_replace		db 0



