
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Serial port driver",0

;; Functions:
; init_serial
; wait_serial_send
; send_byte_via_serial
; send_string_via_serial
; serial_irq

serial_ioport			dw 0
is_there_serial			db 0

; init_serial:
; Initializes the serial port

init_serial:
	mov rdi, 0x400
	cmp word[rdi], 0
	je .no_serial

	mov ax, word[rdi]
	mov [serial_ioport], ax

	mov al, 0x1			; interrupt whenever the serial port has data
	mov dx, [serial_ioport]
	add dx, 1
	out dx, al

	mov al, 0x80			; enable DLAB
	mov dx, [serial_ioport]
	add dx, 3
	out dx, al

	mov al, 2
	mov dx, [serial_ioport]
	out dx, al

	mov al, 0
	mov dx, [serial_ioport]
	add dx, 1
	out dx, al

	mov al, 3			; disable DLAB
	mov dx, [serial_ioport]
	add dx, 3
	out dx, al

	mov al, 0xC7			; enable FIFO
	mov dx, [serial_ioport]
	add dx, 2
	out dx, al

	mov byte[is_there_serial], 1
	ret

.no_serial:
	mov byte[is_there_serial], 0
	ret

; show_serial_info:
; Shows information on the serial ports

show_serial_info:
	cmp [is_there_serial], 0
	je .no

	mov rsi, .yes_msg
	call kprint
	mov ax, [serial_ioport]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint
	mov rsi, .yes_msg2
	call kprint

	ret

.no:
	mov rsi, .no_msg
	call kprint
	ret

.yes_msg			db "[serial] base I/O port is 0x",0
.yes_msg2			db "[serial] exporting all debug logs to COM1...",10,0
.no_msg				db "[serial] serial port not present.",10,0

; wait_serial_send:
; Waits for the serial port to send data

wait_serial_send:
	pushaq

.wait:
	mov dx, [serial_ioport]
	add dx, 5
	in al, dx
	test al, 0x20
	jz .wait

	popaq
	ret

; send_byte_via_serial:
; Sends a byte via serial port
; In\	AL = Byte to send
; Out\	RAX = 0 on success, 1 if no serial port present

send_byte_via_serial:
	pushaq

	cmp al, 0
	je .quit

	cmp al, 10
	je .newline

	cmp al, 13
	je .quit

	cmp al, 0x7F
	jg .quit

	cmp al, 0x20
	jl .quit

	cmp byte[is_there_serial], 0
	je .no_serial

	call wait_serial_send		; wait for the serial port to be ready to receive data
	popaq
	pushaq

	mov dx, [serial_ioport]
	out dx, al

	call wait_serial_send		; wait again -- wait for the data to be sent

	popaq
	mov rax, 0
	ret

.no_serial:
	popaq
	mov rax, 1
	ret

.newline:
	call wait_serial_send

	mov dx, [serial_ioport]
	mov al, 13
	out dx, al

	call wait_serial_send

	mov dx, [serial_ioport]
	mov al, 10
	out dx, al

	call wait_serial_send

	popaq
	mov rax, 0
	ret

.quit:
	popaq
	mov rax, 0
	ret

; send_string_via_serial:
; Sends a string via serial port
; In\	RSI = String
; Out\	RAX = 0 on success, 1 if no serial port present

send_string_via_serial:
	cmp byte[is_there_serial], 0
	je .no_serial

.loop:
	lodsb
	cmp al, 0
	je .done
	call send_byte_via_serial
	jmp .loop

.done:
	mov rax, 0
	ret

.no_serial:
	mov rax, 1
	ret

; serial_irq:
; Serial port IRQ handler

serial_irq:
	pushaq

	mov dx, [serial_ioport]
	in al, dx
	mov [last_serial_char], al

	cmp al, 13
	je .newline
	jmp .print

.newline:
	mov [last_serial_char], 10

.print:
	mov al, [last_serial_char]
	call send_byte_via_serial

	call send_eoi
	popaq
	iretq

last_serial_char			db 0



