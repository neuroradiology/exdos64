
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ATA/ATAPI disk driver",0

;; Functions:
; ata_detect
; ata_identify_drive
; ata_delay
; ata_reset
; ata_read
; ata_write
; ata_read_lba48
; ata_read_lba28
; ata_write_lba48
; ata_write_lba28
; ata_detect_secondary
; ata_identify_drive_seconaary
; ata_delay_secondary

ATA_MAXIMUM_RETRIES		= 5			; maximum number of times to retry disk operations before aborting

pci_ata_bus			db 0
pci_ata_device			db 0
pci_ata_function		db 0

ata_master			db 0
ata_slave			db 0
ata_master_size			dq 0
ata_slave_size			dq 0
ata_master_size_mb		dq 0			; MB
ata_slave_size_mb		dq 0
ata_io_port			dw 0x1F0		; default primary bus I/O port
ata_io_port_status		dw 0x3F6		; default primary bus alternative status
ata_io_port2			dw 0x170		; default secondary bus I/O port
ata_io_port2_status		dw 0x376		; default secondary bus alternative status
ata_secondary_present		db 0
ata_secondary_disks		db 0

ata_master_model:		times 41 db 0
ata_slave_model:		times 41 db 0
ata_master2_model:		times 41 db 0
ata_slave2_model:		times 41 db 0

; ata_detect:
; Detect ATA drives

ata_detect:
	; ensure interrupts are disabled when we do this..
	call disable_interrupts

	mov al, 14
	mov rbp, ata_irq
	call install_irq				; install ATA IRQ handlers

	mov al, 15
	mov rbp, ata_irq
	call install_irq

	mov rsi, .pci_start_msg
	call kprint

	mov ax, 0x0101
	call pci_get_device_class			; find PCI IDE controller
	cmp ax, 0xFFFF
	je .try_isa

	mov [pci_ata_bus], al
	mov [pci_ata_device], ah
	mov [pci_ata_function], bl

	mov rsi, .pci_done_msg
	call kprint

	mov al, [pci_ata_bus]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ata_device]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ata_function]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov al, [pci_ata_bus]
	mov ah, [pci_ata_device]
	mov bl, [pci_ata_function]
	mov bh, 0x10			; BAR0
	call pci_read_dword

	cmp eax, 1
	jg .not_standard_io

	jmp .got_port

.not_standard_io:
	and eax, 0xFFFFFFFC
	mov [ata_io_port], ax
	add ax, 0x206
	mov [ata_io_port_status], ax
	jmp .got_port

.try_isa:
	mov rsi, .isa_start_msg
	call kprint

	mov dx, 0x1F7			; ATA status port -- hopefully!
	in al, dx
	cmp al, 0xFF			; is there a drive?
	je .no_ata			; no ATA controllers found

	mov rsi, .isa_done_msg
	call kprint

.got_port:
	mov rsi, .got_port_msg
	call kprint
	mov ax, [ata_io_port]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

	; First, let's reset both drives on the bus
	call ata_reset

	; Now, let's identify the drives
	mov al, 0xA0			; Master drive
	mov rdi, ata_identify_master
	call ata_identify_drive
	jc .identify_slave

	mov [ata_master], 1
	mov rdi, [.list_of_disks]
	mov word[rdi], 0
	add [.list_of_disks], 2
	inc [number_of_drives]

.identify_slave:
	mov al, 0xB0			; Slave drive
	mov rdi, ata_identify_slave
	call ata_identify_drive
	jc .finish_detecting

	mov [ata_slave], 1
	mov rdi, [.list_of_disks]
	mov word[rdi], 0x100
	add [.list_of_disks], 2
	inc [number_of_drives]

.finish_detecting:
	cmp [number_of_drives], 0
	je .no_disks

.show_master_info:
	cmp [ata_master], 0
	je .dont_show_master

	mov rsi, .master_info
	call kprint

	mov rsi, ata_identify_master.model
	mov rdi, ata_master_model
	mov rcx, 40
	rep movsb

	mov rsi, ata_master_model
	call convert_string_endianness
	call trim_string
	call kprint

	mov rsi, .close
	call kprint

	test word[ata_identify_master+166], 0x400
	jnz .master_lba48

	cmp dword[ata_identify_master+120], 0
	jne .master_lba28

	mov rsi, newline
	call kprint
	jmp .show_slave_info

.master_lba48:
	mov rsi, .lba48
	call kprint
	jmp .show_slave_info

.master_lba28:
	mov rsi, .lba28
	call kprint
	jmp .show_slave_info

.show_slave_info:
	cmp [ata_slave], 0
	je .dont_show_slave

	mov rsi, .slave_info
	call kprint

	mov rsi, ata_identify_slave.model
	mov rdi, ata_slave_model
	mov rcx, 40
	rep movsb

	mov rsi, ata_slave_model
	call convert_string_endianness
	call trim_string
	call kprint

	mov rsi, .close
	call kprint

	test word[ata_identify_slave+166], 0x400
	jnz .slave_lba48

	cmp dword[ata_identify_slave+120], 0
	jne .slave_lba28

	mov rsi, newline
	call kprint

	;call ata_detect_secondary
	ret

.slave_lba48:
	mov rsi, .lba48
	call kprint

	;call ata_detect_secondary
	ret

.slave_lba28:
	mov rsi, .lba28
	call kprint

	;call ata_detect_secondary
	ret

.dont_show_master:
	mov rsi, .no_master_msg
	call kprint
	jmp .show_slave_info

.dont_show_slave:
	mov rsi, .no_slave_msg
	call kprint

	;call ata_detect_secondary
	ret

.no_ata:
	mov rsi, .no_ata_msg
	call kprint

	ret

.no_disks:
	mov rsi, .no_drive_msg
	call kprint

	ret

.pci_start_msg				db "[ata] looking for PCI IDE controller...",10,0
.pci_done_msg				db "[ata] done, found IDE controller at PCI slot ",0
.colon					db ":",0
.isa_start_msg				db "[ata] not found, looking for ISA ATA controller...",10,0
.isa_done_msg				db "[ata] done, found ISA ATA controller.",10,0
.got_port_msg				db "[ata] base I/O port is 0x",0
.no_ata_msg				db "[ata] no IDE/ATA controllers present...",10,0
.no_drive_msg				db "[ata] ATA controller found, but with no disk drives attached.",10,0
.master_info				db "[ata] master hard disk model is '",0
.slave_info				db "[ata] slave hard disk model is '",0
.no_master_msg				db "[ata] master hard disk is not present.",10,0
.no_slave_msg				db "[ata] slave hard disk is not present.",10,0
.close					db "' ",0
.lba48					db "with LBA48",10,0
.lba28					db "with LBA28",10,0
.list_of_disks				dq list_of_disks

; ata_delay:
; Waits for an ATA I/O to complete

ata_delay:
	mov dx, [ata_io_port]
	add dx, 7

	in al, dx
	in al, dx
	in al, dx
	in al, dx

	ret

; ata_identify_drive:
; Identifies an ATA drive
; In\	AL = Drive number (0xA0 for master, 0xB0 for slave)
; In\	RDI = 512-byte buffer to store the data
; Out\	RFLAGS = Carry set on error

ata_identify_drive:
	mov [.buffer], rdi

	call ata_reset

	mov dx, [ata_io_port]
	add dx, 6
	out dx, al
	call ata_delay

	mov dx, [ata_io_port]
	add dx, 2
	mov al, 0
	out dx, al

	add dx, 1		; 3
	mov al, 0
	out dx, al
	add dx, 1		; 4
	mov al, 0
	out dx, al
	add dx, 1		; 5
	out dx, al
	;call iowait

	mov al, 0xEC		; IDENTIFY command
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call iowait

	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	cmp al, 0
	je .fail

.wait_for_ready:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	cmp al, 0
	je .fail

	test al, 0x80
	jz .check_if_ata
	test al, 8
	jnz .start_reading

	test al, 1			; ERR
	jnz .fail
	test al, 0x20			; drive fault
	jnz .fail

	jmp .wait_for_ready

.check_if_ata:
	mov dx, [ata_io_port]
	add dx, 4
	in al, dx
	cmp al, 0
	jne .fail

	mov dx, [ata_io_port]
	add dx, 5
	in al, dx
	cmp al, 0
	jne .fail

.wait_again:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 8			; DRQ
	jnz .start_reading

	test al, 1			; ERR
	jnz .fail
	jmp .wait_again

.start_reading:
	mov rdi, [.buffer]
	mov dx, [ata_io_port]
	mov rcx, 256
	rep insw
	call ata_delay

	clc
	ret

.fail:
	stc
	ret

.buffer				dq 0

; ata_irq:
; ATA IRQ handler

ata_irq:
	call send_eoi		; ATA IRQ handler doesn't do anything because we use polling
	iretq

; ata_reset:
; Resets the ATA drives

ata_reset:
	pushaq

	; reset the primary bus
	mov al, 6
	mov dx, [ata_io_port_status]
	out dx, al

	call ata_delay

	mov al, 2
	mov dx, [ata_io_port_status]
	out dx, al

	popaq
	ret

	; if the secondary bus is present, reset it as well
	cmp [ata_secondary_disks], 0
	je .quit

	mov al, 6
	mov dx, [ata_io_port2_status]
	out dx, al
	call iowait

	mov al, 2
	mov dx, [ata_io_port2_status]
	out dx, al

.quit:
	popaq
	ret

; ata_read:
; Reads sectors from ATA device
; In\	AL = Drive number (0 for master, 1 for slave)
; In\	RDI = Buffer to read sectors
; In\	RBX = LBA sector
; In\	RCX = Sectors to read
; Out\	RFLAGS = Carry clear on success

ata_read:
	call enable_interrupts

	pushaq

	mov rsi, .msg
	;call kprint

	popaq
	pushaq
	mov rax, rcx
	call int_to_string
	;call kprint

	mov rsi, .msg2
	;call kprint

	popaq

	cmp al, 0
	je .master

.slave:
	;test word[ata_identify_slave+166], 0x400	; is LBA48 supported?
	;jnz ata_read_lba48				; yes -- use it

	;cmp dword[ata_identify_slave+120], 0		; nope, is LBA28 supported?
	;jne ata_read_lba28				; yes -- use it

	; use LBA48 only when necessary; LBA28 is faster because it uses less I/O bandwidth ;)
	cmp rbx, 0xFFFFFFF-0x100
	jge ata_read_lba48
	jmp ata_read_lba28

.master:
	;test word[ata_identify_master+166], 0x400
	;jnz ata_read_lba48

	;cmp dword[ata_identify_master+120], 0
	;jne ata_read_lba28

	cmp rbx, 0xFFFFFFF-0x100
	jge ata_read_lba48
	jmp ata_read_lba28

.msg			db "[ata] reading ",0
.msg2			db " sectors.",10,0

; ata_read_lba48:
; Reads ATA disk in LBA48 mode

ata_read_lba48:
	mov [.drive], al
	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rdi
	mov [.current_try], 0

.retry:
	cmp [.current_try], ATA_MAXIMUM_RETRIES
	je .quit_fail

	mov rsi, .msg
	;call kprint

	mov [.current_count], 0
	call ata_reset

	mov al, [.drive]
	shl al, 4
	or al, 0x40
	mov dx, [ata_io_port]
	add dx, 6
	out dx, al				; select drive
	call ata_delay

	mov al, 0
	mov dx, [ata_io_port]
	add dx, 1
	out dx, al
	;call iowait

	mov rax, [.count]
	shr rax, 8				; sector count high
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 24
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al				; LBA
	;call iowait

	mov rax, [.lba]
	shr rax, 32
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 40
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov rax, [.count]
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al				; sector count low
	;call iowait

	mov rax, [.lba]
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 8
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 16
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov al, 0x24			; 48-bit LBA read
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call iowait

	mov rcx, 0
	not rcx

.check_for_error:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1
	jnz .fail
	test al, 0x20
	jnz .fail
	test al, 8
	jnz .start_reading

	dec rcx
	cmp rcx, 0
	je .fail
	jmp .check_for_error

.start_reading:
	mov dx, [ata_io_port]
	mov rdi, [.buffer]
	mov rcx, 256
	rep insw			; read one sector
	mov [.buffer], rdi
	inc [.current_count]
	call ata_delay			; give the drive time to refresh itself...

	mov rcx, [.count]
	cmp [.current_count], rcx
	jge .done

	mov rcx, 0
	not rcx
	jmp .check_for_error

.done:
	clc
	ret

.fail:
	mov rsi, .fail_msg
	call kprint
	mov rax, [.lba]
	call int_to_string
	call kprint
	mov rsi, .fail_msg2
	call kprint

	mov rax, [.count]
	call int_to_string
	call kprint

	mov rsi, .fail_msg3
	call kprint

	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	call hex_byte_to_string
	call kprint

	inc [.current_try]
	cmp [.current_try], ATA_MAXIMUM_RETRIES
	jge .quit_fail

	mov rsi, .retry_msg
	call kprint

	jmp .retry

.quit_fail:
	mov rsi, .abort_msg
	call kprint

	stc
	ret

.drive				db 0
.lba				dq 0
.count				dq 0
.buffer				dq 0
.current_count			dq 0
.current_try			dq 0
.msg				db "[ata] PIO LBA48 read.",10,0
.fail_msg			db "[ata] warning: PIO LBA48 read failure, sector ",0
.fail_msg2			db ", count ",0
.fail_msg3			db ", status register 0x",0
.retry_msg			db ", retrying...",10,0
.abort_msg			db ", aborting...",10,0
.time_limit			dq 0

; ata_read_lba28:
; Reads ATA disk in LBA28 mode

ata_read_lba28:
	mov [.drive], al
	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rdi
	mov [.current_try], 0

.retry:
	cmp [.current_try], ATA_MAXIMUM_RETRIES
	je .quit_fail

	mov rsi, .msg
	;call kprint

	mov [.current_count], 0
	call ata_reset

	mov al, [.drive]
	shl al, 4
	or al, 0xE0
	mov rbx, [.lba]
	shr rbx, 24
	or al, bl
	mov dx, [ata_io_port]
	add dx, 6
	out dx, al			; select drive
	call ata_delay

	mov al, 0
	mov dx, [ata_io_port]
	add dx, 1
	out dx, al
	;call iowait

	mov rax, [.count]
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al
	;call iowait			; number of sectors

	mov rax, [.lba]
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 8
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 16
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov al, 0x20
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	;call iowait

	mov rcx, 0
	not rcx

.check_for_error:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1		; ERR
	jnz .fail
	test al, 0x20		; drive fault
	jnz .fail
	;test al, 0x10
	;jnz .fail
	;test al, 0x40
	;jnz .fail
	test al, 8		; PIO data ready
	jnz .start_reading

	dec rcx
	cmp rcx, 0
	je .fail

	call iowait
	jmp .check_for_error

.start_reading:
	mov dx, [ata_io_port]
	mov rdi, [.buffer]
	mov rcx, 256
	rep insw			; read one sector
	mov [.buffer], rdi
	inc [.current_count]

	mov rcx, [.count]
	cmp [.current_count], rcx
	jge .done

	call ata_delay
	mov rcx, 0
	not rcx
	jmp .check_for_error

.done:
	clc
	ret

.fail:
	mov rsi, .fail_msg
	call kprint
	mov rax, [.lba]
	call int_to_string
	call kprint
	mov rsi, .fail_msg2
	call kprint

	mov rax, [.count]
	call int_to_string
	call kprint

	mov rsi, .fail_msg3
	call kprint

	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	call hex_byte_to_string
	call kprint

	inc [.current_try]
	cmp [.current_try], ATA_MAXIMUM_RETRIES
	jge .quit_fail

	mov rsi, .retry_msg
	call kprint

	jmp .retry

.quit_fail:
	mov rsi, .abort_msg
	call kprint

	stc
	ret

align 16
.drive				db 0
align 16
.lba				dq 0
align 16
.count				dq 0
align 16
.buffer				dq 0
align 16
.current_count			dq 0
align 16
.current_try			dq 0
align 16
.msg				db "[ata] PIO LBA28 read.",10,0
.fail_msg			db "[ata] warning: PIO LBA28 read failure, LBA ",0
.fail_msg2			db ", sector count ",0
.fail_msg3			db ", status 0x",0
.retry_msg			db ", retrying...",10,0
.abort_msg			db ", aborting...",10,0
.time_limit			dq 0

; ata_write:
; Writes sectors to ATA device
; In\	AL = Drive number (0 for master, 1 for slave)
; In\	RSI = Buffer to write sectors
; In\	RBX = LBA sector
; In\	RCX = Sectors to write
; Out\	RFLAGS = Carry clear on success

ata_write:
	call enable_interrupts

	cmp al, 0
	je .master

.slave:
	test word[ata_identify_slave+166], 0x400		; is LBA48 supported?
	jnz ata_write_lba48				; yes -- use it

	cmp dword[ata_identify_slave+120], 0		; nope, is LBA28 supported?
	jne ata_write_lba28				; yes -- use it

	stc
	ret

.master:
	test word[ata_identify_master+166], 0x400
	jnz ata_write_lba48

	cmp dword[ata_identify_master+120], 0
	jne ata_write_lba28

	stc
	ret

; ata_write_lba48:
; Writes ATA disk in LBA48 mode

ata_write_lba48:
	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rsi

	mov [.current_count], 0
	call ata_reset				; to be safe

	shl al, 4
	or al, 0x40
	mov dx, [ata_io_port]
	add dx, 6
	out dx, al				; select drive
	call ata_delay

	mov al, 0
	mov dx, [ata_io_port]
	add dx, 1
	out dx, al
	;call iowait

	mov rax, [.count]
	shr rax, 8				; sector count high
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 24
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al				; LBA
	;call iowait

	mov rax, [.lba]
	shr rax, 32
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 40
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov rax, [.count]
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al				; sector count low
	;call iowait

	mov rax, [.lba]
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 8
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 16
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov al, 0x34			; 48-bit LBA write
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call iowait

.check_for_error:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1			; is there an error?
	jnz .fail
	test al, 0x20			; is there a drive fault?
	jnz .fail
	test al, 8			; is the PIO data ready?
	jnz .start_writing
	jmp .check_for_error

.start_writing:
	mov dx, [ata_io_port]
	mov rcx, 256
	mov rsi, [.buffer]

.write_loop:
	outsw
	jmp .short_delay
.short_delay:
	loop .write_loop

	mov [.buffer], rsi
	inc [.current_count]
	call ata_delay			; give it some time to refresh its buffers

	mov rcx, [.count]
	cmp [.current_count], rcx
	jge .done
	jmp .check_for_error

.done:
	mov al, 0xE7			; flush caches
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call ata_delay

	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1			; did an error occur?
	jnz .fail
	test al, 0x20			; drive fault?
	jnz .fail

	clc
	ret

.fail:
	stc
	ret

.lba				dq 0
.count				dq 0
.buffer				dq 0
.current_count			dq 0

; ata_write_lba28:
; Writes ATA disk in LBA28 mode

ata_write_lba28:
	mov [.lba], rbx
	mov [.count], rcx
	mov [.buffer], rsi

	mov [.current_count], 0
	call ata_reset

	shl al, 4
	or al, 0xE0
	mov rbx, [.lba]
	shr rbx, 24
	or al, bl
	mov dx, [ata_io_port]
	add dx, 6
	out dx, al			; select drive
	call ata_delay

	mov al, 0
	mov dx, [ata_io_port]
	add dx, 1
	out dx, al
	;call iowait

	mov rax, [.count]
	mov dx, [ata_io_port]
	add dx, 2
	out dx, al
	;call iowait			; number of sectors

	mov rax, [.lba]
	mov dx, [ata_io_port]
	add dx, 3
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 8
	mov dx, [ata_io_port]
	add dx, 4
	out dx, al
	;call iowait

	mov rax, [.lba]
	shr rax, 16
	mov dx, [ata_io_port]
	add dx, 5
	out dx, al
	;call iowait

	mov al, 0x30
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call iowait

.check_for_error:
	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1			; is there an error?
	jnz .fail
	test al, 0x20			; is there a drive fault?
	jnz .fail
	test al, 8			; is the PIO data ready?
	jnz .start_writing
	jmp .check_for_error

.start_writing:
	mov dx, [ata_io_port]
	mov rcx, 256
	mov rsi, [.buffer]

.write_loop:
	outsw
	jmp .short_delay
.short_delay:
	loop .write_loop

	mov [.buffer], rsi
	inc [.current_count]
	call ata_delay			; give it some time to refresh its buffers

	mov rcx, [.count]
	cmp [.current_count], rcx
	jge .done
	jmp .check_for_error

.done:
	mov al, 0xE7			; flush caches
	mov dx, [ata_io_port]
	add dx, 7
	out dx, al
	call ata_delay

	mov dx, [ata_io_port]
	add dx, 7
	in al, dx
	test al, 1			; did an error occur?
	jnz .fail
	test al, 0x20			; drive fault?
	jnz .fail

	clc
	ret

.fail:
	stc
	ret

.lba				dq 0
.count				dq 0
.buffer				dq 0
.current_count			dq 0

; ata_detect_secondary:
; Detects the secondary ATA bus and all drives on it

ata_detect_secondary:
	mov rsi, .starting_msg
	call kprint

	mov al, [number_of_drives]
	mov [.tmp_drives], al

	mov dx, [ata_io_port2]
	add dx, 7			; status port
	in al, dx

	cmp al, 0xFF
	je .no

	mov [ata_secondary_present], 1

	mov rsi, .present_msg
	call kprint

	; now, let's identify the drives
	mov al, 0xA0
	mov rdi, ata_identify_master2
	call ata_identify_drive_secondary
	jc .identify_slave

	movzx rax, [number_of_drives]
	shl rax, 1
	add rax, list_of_disks
	mov word[rax], 0x0201
	inc [number_of_drives]
	mov [.master], 1
	inc [ata_secondary_disks]

.identify_slave:
	mov al, 0xB0
	mov rdi, ata_identify_slave2
	call ata_identify_drive_secondary
	jc .show_disk_info

	movzx rax, [number_of_drives]
	shl rax, 1
	add rax, list_of_disks
	mov word[rax], 0x0301
	inc [number_of_drives]
	mov [.slave], 1
	inc [ata_secondary_disks]

.show_disk_info:
	mov al, [number_of_drives]
	cmp al, [.tmp_drives]
	je .no_drives

	cmp [.master], 0
	je .master_not_present

	mov rsi, .master_info
	call kprint

	mov rsi, ata_identify_master2.model
	mov rdi, ata_master2_model
	mov rcx, 40
	rep movsb

	mov rsi, ata_master2_model
	call convert_string_endianness
	call trim_string
	call kprint

	mov rsi, .close
	call kprint

	test word[ata_identify_master2+83], 0x400
	jnz .master_lba48

	cmp dword[ata_identify_master2+60], 0
	jne .master_lba28

	mov rsi, newline
	call kprint
	jmp .show_slave_info

.master_lba48:
	mov rsi, .lba48
	call kprint
	jmp .show_slave_info

.master_lba28:
	mov rsi, .lba28
	call kprint
	jmp .show_slave_info

.master_not_present:
	mov rsi, .no_master_msg
	call kprint

.show_slave_info:
	cmp [.slave], 0
	je .slave_not_present

	mov rsi, .slave_info
	call kprint

	mov rsi, ata_identify_slave2.model
	mov rdi, ata_slave2_model
	mov rcx, 40
	rep movsb

	mov rsi, ata_slave2_model
	call convert_string_endianness
	call trim_string
	call kprint

	mov rsi, .close
	call kprint

	test word[ata_identify_slave2+83], 0x400
	jnz .slave_lba48

	cmp dword[ata_identify_slave2+60], 0
	jne .slave_lba28

	mov rsi, newline
	call kprint
	jmp .done

.slave_lba48:
	mov rsi, .lba48
	call kprint
	jmp .done

.slave_lba28:
	mov rsi, .lba28
	call kprint
	jmp .done

.slave_not_present:
	mov rsi, .no_slave_msg
	call kprint

.done:
	ret

.no_drives:
	mov rsi, .no_drive_msg
	call kprint
	ret

.no:
	mov rsi, .no_msg
	call kprint
	mov [ata_secondary_present], 0
	ret

.starting_msg			db "[ata] detecting secondary ATA bus...",10,0
.present_msg			db "[ata] bus is present.",10,0
.no_msg				db "[ata] secondary ATA bus not present.",10,0
.no_drive_msg			db "[ata] ATA controller found, but with no disk drives attached.",10,0
.master_info			db "[ata] master hard disk model is '",0
.slave_info			db "[ata] slave hard disk model is '",0
.no_master_msg			db "[ata] master hard disk is not present.",10,0
.no_slave_msg			db "[ata] slave hard disk is not present.",10,0
.close				db "' ",0
.lba48				db "with LBA48",10,0
.lba28				db "with LBA28",10,0
.master				db 0
.slave				db 0
.tmp_drives			db 0

; ata_identify_drive_secondary:
; Identifies an ATA drive on the secondary bus
; In\	AL = Drive number (0xA0 for master, 0xB0 for slave)
; In\	RDI = 512-byte buffer to store the data
; Out\	RFLAGS = Carry set on error

ata_identify_drive_secondary:
	mov [.buffer], rdi

	call ata_reset

	mov dx, [ata_io_port2]
	add dx, 6
	out dx, al
	call ata_delay_secondary

	mov dx, [ata_io_port2]
	add dx, 2
	mov al, 0
	out dx, al

	add dx, 1		; 3
	mov al, 0
	out dx, al
	add dx, 1		; 4
	mov al, 0
	out dx, al
	add dx, 1		; 5
	out dx, al
	call iowait

	mov al, 0xEC		; ATA IDENTIFY
	mov dx, [ata_io_port2]
	add dx, 7
	out dx, al
	call ata_delay_secondary

	mov dx, [ata_io_port2]
	add dx, 7
	in al, dx
	cmp al, 0
	je .fail

.wait_for_ready:
	mov dx, [ata_io_port2]
	add dx, 7
	in al, dx
	test al, 0x80
	jz .check_if_ata
	jmp .wait_for_ready

.check_if_ata:
	mov dx, [ata_io_port2]
	add dx, 4
	in al, dx
	cmp al, 0
	jne .fail

	mov dx, [ata_io_port2]
	add dx, 5
	in al, dx
	cmp al, 0
	jne .fail

.wait_again:
	mov dx, [ata_io_port2]
	add dx, 7
	in al, dx
	test al, 8			; DRQ
	jnz .start_reading

	test al, 1			; ERR
	jnz .fail
	jmp .wait_again

.start_reading:
	mov rdi, [.buffer]
	mov dx, [ata_io_port2]
	mov rcx, 256
	rep insw
	call ata_delay_secondary

	clc
	ret

.fail:
	stc
	ret

.buffer				dq 0

; ata_delay_secondary:
; Waits for a secondary ATA I/O to complete

ata_delay_secondary:
	push rax
	push rdx

	mov dx, [ata_io_port2]
	add dx, 7			; status port

	in al, dx
	in al, dx
	in al, dx
	in al, dx

	pop rdx
	pop rax
	ret


align 16
ata_identify_master:
	.device_type		dw 0		; 0

	.cylinders		dw 0		; 1
	.reserved_word2		dw 0		; 2
	.heads			dw 0		; 3
				dd 0		; 4
	.sectors_per_track	dw 0		; 6
	.vendor_unique:		times 3 dw 0	; 7
	.serial_number:		times 20 db 0	; 10
				dd 0		; 11
	.obsolete1		dw 0		; 13
	.firmware_revision:	times 8 db 0	; 14
	.model:			times 40 db 0	; 18
	.maximum_block_transfer	db 0
				db 0
				dw 0

				db 0
	.dma_support		db 0
	.lba_support		db 0
	.iordy_disable		db 0
	.iordy_support		db 0
				db 0
	.standyby_timer_support	db 0
				db 0
				dw 0

				dd 0
	.translation_fields	dw 0
				dw 0
	.current_cylinders	dw 0
	.current_heads		dw 0
	.current_spt		dw 0
	.current_sectors	dd 0
				db 0
				db 0
				db 0
	.user_addressable_secs	dd 0
				dw 0
	times 512 - ($-ata_identify_master) db 0

align 16
ata_identify_slave:
	.device_type		dw 0

	.cylinders		dw 0
	.reserved_word2		dw 0
	.heads			dw 0
				dd 0
	.sectors_per_track	dw 0
	.vendor_unique:		times 3 dw 0
	.serial_number:		times 20 db 0
				dd 0
	.obsolete1		dw 0
	.firmware_revision:	times 8 db 0
	.model:			times 40 db 0
	.maximum_block_transfer	db 0
				db 0
				dw 0

				db 0
	.dma_support		db 0
	.lba_support		db 0
	.iordy_disable		db 0
	.iordy_support		db 0
				db 0
	.standyby_timer_support	db 0
				db 0
				dw 0

				dd 0
	.translation_fields	dw 0
				dw 0
	.current_cylinders	dw 0
	.current_heads		dw 0
	.current_spt		dw 0
	.current_sectors	dd 0
				db 0
				db 0
				db 0
	.user_addressable_secs	dd 0
				dw 0
	times 512 - ($-ata_identify_slave) db 0


align 16
ata_identify_master2:
	.device_type		dw 0		; 0

	.cylinders		dw 0		; 1
	.reserved_word2		dw 0		; 2
	.heads			dw 0		; 3
				dd 0		; 4
	.sectors_per_track	dw 0		; 6
	.vendor_unique:		times 3 dw 0	; 7
	.serial_number:		times 20 db 0	; 10
				dd 0		; 11
	.obsolete1		dw 0		; 13
	.firmware_revision:	times 8 db 0	; 14
	.model:			times 40 db 0	; 18
	.maximum_block_transfer	db 0
				db 0
				dw 0

				db 0
	.dma_support		db 0
	.lba_support		db 0
	.iordy_disable		db 0
	.iordy_support		db 0
				db 0
	.standyby_timer_support	db 0
				db 0
				dw 0

				dd 0
	.translation_fields	dw 0
				dw 0
	.current_cylinders	dw 0
	.current_heads		dw 0
	.current_spt		dw 0
	.current_sectors	dd 0
				db 0
				db 0
				db 0
	.user_addressable_secs	dd 0
				dw 0
	times 512 - ($-ata_identify_master2) db 0

align 16
ata_identify_slave2:
	.device_type		dw 0

	.cylinders		dw 0
	.reserved_word2		dw 0
	.heads			dw 0
				dd 0
	.sectors_per_track	dw 0
	.vendor_unique:		times 3 dw 0
	.serial_number:		times 20 db 0
				dd 0
	.obsolete1		dw 0
	.firmware_revision:	times 8 db 0
	.model:			times 40 db 0
	.maximum_block_transfer	db 0
				db 0
				dw 0

				db 0
	.dma_support		db 0
	.lba_support		db 0
	.iordy_disable		db 0
	.iordy_support		db 0
				db 0
	.standyby_timer_support	db 0
				db 0
				dw 0

				dd 0
	.translation_fields	dw 0
				dw 0
	.current_cylinders	dw 0
	.current_heads		dw 0
	.current_spt		dw 0
	.current_sectors	dd 0
				db 0
				db 0
				db 0
	.user_addressable_secs	dd 0
				dw 0
	times 512 - ($-ata_identify_slave2) db 0






