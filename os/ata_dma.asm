
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
; ata_identify_master

pci_ide_bus			db 0
pci_ide_slot			db 0
pci_ide_function		db 0
ide_dma_port			dw 0
ata_io_port			dw 0x1F0

; ata_detect:
; Detects ATA drives

ata_detect:
	mov rsi, .starting_msg
	call kprint

	; look for PCI IDE controller
	mov ax, 0x0101
	call pci_get_device_class

	cmp ax, 0xFFFF
	je .no

	mov [pci_ide_bus], al
	mov [pci_ide_slot], ah
	mov [pci_ide_function], bl

	mov rsi, .found_msg
	call kprint

	mov al, [pci_ide_bus]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ide_slot]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ide_function]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	; read the DMA base I/O port
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_slot]
	mov bl, [pci_ide_function]
	mov bh, 0x20
	call pci_read_dword

	and ax, 0xFFFC
	mov [ide_dma_port],ax

	mov rsi, .dma_base_msg
	call kprint
	mov ax, [ide_dma_port]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

	; disable PRDT execution
	mov dx, [ide_dma_port]
	add dx, 4
	mov eax, ata_prdt
	out dx, eax

	mov dx, [ide_dma_port]
	mov al, 1
	out dx, al

	; enable PCI busmaster DMA
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_slot]
	mov bl, [pci_ide_function]
	mov bh, 4
	call pci_read_dword

	mov edx, eax
	or edx, 4
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_slot]
	mov bl, [pci_ide_function]
	mov bh, 0x20
	call pci_write_dword

	; detect the ATA base I/O port
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_slot]
	mov bl, [pci_ide_function]
	mov bh, 0x10
	call pci_read_dword

	cmp ax, 1
	jle .got_io

	and ax, 0xFFFC
	mov [ata_io_port], ax

.got_io:
	mov rsi, .base_io_msg
	call kprint
	mov ax, [ata_io_port]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

.identify_drives:
	; identify the master drive
	

	jmp $

.no:
	mov rsi, .no_msg
	call kprint

	ret

.starting_msg			db "[ata] detecting PCI IDE controller...",10,0
.no_msg				db "[ata] no PCI IDE controllers found.",10,0
.found_msg			db "[ata] found PCI IDE controller at PCI slot ",0
.colon				db ":",0
.dma_base_msg			db "[ata] DMA base port is 0x",0
.base_io_msg			db "[ata] channel 0 I/O port is 0x",0

ata_read:
ata_write:
	stc
	ret

; ata_prdt:
; ATA PRDT structure for DMA
align 32
ata_prdt:
	.memory			dd mbr_tmp
	.bytes			dw 0
	.last_prd		dw 0x8000


	
