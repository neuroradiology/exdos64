
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "CMOS driver",0

;; Functions:
; init_cmos
; cmos_read_register
; cmos_write_register
; cmos_irq
; cmos_wait_irq
; cmos_read_time
; cmos_read_date
; cmos_set_time
; cmos_read_time12_string

; CMOS Registers Index
CMOS_REGISTER_SECONDS		= 0
CMOS_REGISTER_MINUTES		= 2
CMOS_REGISTER_HOURS		= 4
CMOS_REGISTER_DAY		= 7
CMOS_REGISTER_MONTH		= 8
CMOS_REGISTER_YEAR		= 9

cmos_register_century		db 0x32		; this should be taken from ACPI FADT, but defaults to 0x32
cmos_24hr			db 0
cmos_irq_happened		db 0

system_time:
	.hours			db 0
	.mins			db 0
	.secs			db 0
	.day			db 0
	.month			db 0
	.year			dw 0

; init_cmos:
; Initializes the CMOS

init_cmos:
	mov rsi, .starting_msg
	call kprint

	cmp [acpi_fadt.century], 0
	je .century_default

	mov al, [acpi_fadt.century]
	mov [cmos_register_century], al

	mov rsi, .century_msg
	call kprint
	mov al, [cmos_register_century]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	jmp .check_24hr

.century_default:
	mov rsi, .century_msg2
	call kprint

.check_24hr:
	mov cl, 0xB			; status register B
	call cmos_read_register

	test al, 2
	jnz .24hr
	mov [cmos_24hr], 0
	call cmos_update
	ret

.24hr:
	mov [cmos_24hr], 1
	call cmos_update
	ret

.starting_msg			db "[cmos] initializing CMOS...",10,0
.century_msg			db "[cmos] ACPI FADT CMOS century register is 0x",0
.century_msg2			db "[cmos] ACPI FADT CMOS century register is not present, defaulting to 0x32...",10,0

; cmos_read_register:
; Reads a CMOS register
; In\	CL = Register number
; Out\	AL = Contents of register

cmos_read_register:
	mov al, cl
	or al, 0x80		; disable NMI
	out 0x70, al
	call iowait
	in al, 0x71
	ret

; cmos_write_register:
; Writes a CMOS register
; In\	AL = Value to write
; In\	CL = Register number
; Out\	Nothing

cmos_write_register:
	push rax
	mov al, cl
	or al, 0x80		; disable NMI
	out 0x70, al
	call iowait
	pop rax
	out 0x71, al
	call iowait
	ret

; cmos_update:
; Updates the CMOS time and date

cmos_update:
	mov al, [system_time.mins]
	mov [.mins_old], al

	; first, read the seconds
	mov cl, CMOS_REGISTER_SECONDS
	call cmos_read_register
	call bcd_to_int
	mov [system_time.secs], al

	; next, the minutes...
	mov cl, CMOS_REGISTER_MINUTES
	call cmos_read_register
	call bcd_to_int
	mov [system_time.mins], al

	; finally, the hours
	mov cl, CMOS_REGISTER_HOURS
	call cmos_read_register
	cmp [cmos_24hr], 0
	je .12_hour
	call bcd_to_int
	mov [system_time.hours], al
	jmp .read_date

.12_hour:
	; if the CMOS uses 12-hour time --
	; -- we need to find if we are in AM or PM and convert it to 24 hour time
	mov [system_time.hours], al
	test al, 0x80
	jnz .pm
	call bcd_to_int
	cmp al, 12		; 12 AM?
	je .hour_zero
	mov [system_time.hours], al
	jmp .read_date

.hour_zero:
	mov [system_time.hours], 0
	jmp .read_date

.pm:
	and al, 0x7F
	call bcd_to_int
	add al, 12
	mov [system_time.hours], al

.read_date:
	; now we need to read the date
	mov cl, CMOS_REGISTER_DAY
	call cmos_read_register
	call bcd_to_int
	mov [system_time.day], al

	mov cl, CMOS_REGISTER_MONTH
	call cmos_read_register
	call bcd_to_int
	mov [system_time.month], al

	mov cl, [cmos_register_century]
	call cmos_read_register
	call bcd_to_int
	;inc al			; seems this register contains century-1, not century
	and ax, 0xFF
	mov bx, 100
	mul bx
	mov [system_time.year], ax

	mov cl, CMOS_REGISTER_YEAR
	call cmos_read_register
	call bcd_to_int
	and ax, 0xFF
	add [system_time.year], ax

	cmp [is_wm_running], 0
	je .done

	mov al, [system_time.mins]
	cmp al, [.mins_old]
	je .done

	call wm_redraw

.done:
	ret

.mins_old			db 0

; cmos_read_time:
; Reads the CMOS time
; In\	Nothing
; Out\	AH:AL:BH = Hours:Minutes:Seconds (24 hour format)

cmos_read_time:
	mov ah, [system_time.hours]
	mov al, [system_time.mins]
	mov bh, [system_time.secs]
	ret

; cmos_read_date:
; Reads the CMOS date
; In\	Nothing
; Out\	AH/AL/BX = Day/Month/Year

cmos_read_date:
	mov ah, [system_time.day]
	mov al, [system_time.month]
	mov bx, [system_time.year]
	ret

; cmos_set_time:
; Sets the CMOS time
; In\	AH:AL:BH = Hours:Minutes:Seconds (24 hour format)
; Out\	RAX = 0 on success

cmos_set_time:
	cmp ah, 23
	jg .error
	cmp al, 59
	jg .error
	cmp bh, 59
	jg .error

	call disable_interrupts
	mov [system_time.hours], ah
	mov [system_time.mins], al
	mov [system_time.secs], bh

	mov rsi, .msg
	call kprint
	movzx rax, [system_time.hours]
	call int_to_bcd
	call hex_byte_to_string
	call kprint
	mov rsi, .msg2
	call kprint
	movzx rax, [system_time.mins]
	call int_to_bcd
	call hex_byte_to_string
	call kprint
	mov rsi, .msg2
	call kprint
	movzx rax, [system_time.secs]
	call int_to_bcd
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	; set the second
	mov al, [system_time.secs]
	call int_to_bcd
	mov cl, CMOS_REGISTER_SECONDS
	call cmos_write_register

	; set the minutes
	mov al, [system_time.mins]
	call int_to_bcd
	mov cl, CMOS_REGISTER_MINUTES
	call cmos_write_register

	; set the hour
	mov al, [system_time.hours]
	cmp [cmos_24hr], 0
	je .12hr

	call int_to_bcd
	mov cl, CMOS_REGISTER_HOURS
	call cmos_write_register
	jmp .done

.12hr:
	cmp al, 0
	je .midnight

	cmp al, 12
	jg .pm

	cmp al, 12
	je .noon

	call int_to_bcd
	mov cl, CMOS_REGISTER_HOURS
	call cmos_write_register
	jmp .done

.midnight:
	mov al, 0x12
	mov cl, CMOS_REGISTER_HOURS
	call cmos_write_register
	jmp .done

.pm:
	sub al, 12
	call int_to_bcd
	mov cl, CMOS_REGISTER_HOURS
	call cmos_write_register
	jmp .done

.noon:
	mov al, 0x92
	mov cl, CMOS_REGISTER_HOURS
	call cmos_write_register

.done:
	call enable_interrupts
	call cmos_update

	mov rax, 0
	ret

.error:
	mov rax, -1
	ret

.msg				db "[cmos] setting system time to ",0
.msg2				db ":",0

; cmos_read_time12_string:
; Reads the CMOS time string in 12 hour format
; In\	Nothing
; Out\	RAX = Pointer to string

cmos_read_time12_string:
	mov rax, "00:00 AM"
	mov qword[.string], rax

	call cmos_read_time
	mov [.mins], al
	mov [.hours], ah

	cmp [.hours], 12
	jge .pm

	cmp [.hours], 0
	je .midnight

.am:
	mov word[.string+6], "AM"
	jmp .do_mins

.pm:
	mov word[.string+6], "PM"
	jmp .do_mins

.midnight:
	mov [.hours], 12
	mov word[.string+6], "AM"

.do_mins:
	movzx rax, [.mins]
	cmp al, 9
	jle .mins_small

.mins_big:
	call int_to_string
	mov rdi, .string+3
	movsb
	movsb
	jmp .do_hours

.mins_small:
	add al, 48
	mov byte[.string+4], al

.do_hours:
	movzx rax, [.hours]
	cmp al, 9
	jle .hours_small

	cmp al, 12
	jg .hours_pm

.hours_big:
	call int_to_string
	mov rdi, .string
	movsb
	movsb
	jmp .done

.hours_small:
	add al, 48
	mov byte[.string+1], al
	jmp .done

.hours_pm:
	sub [.hours], 12
	jmp .do_hours

.done:
	mov byte[.string+8], 0
	mov rax, .string
	ret

.string				db "00:00 AM",0
.hours				db 0
.mins				db 0
.time_of_day			db 0


