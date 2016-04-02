
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "PCI bus scanner",0

;; Functions:
; init_pci
; pci_get_buses
; pci_read_dword
; pci_write_dword
; pci_get_device_class
; pci_get_device_class_progif
; pci_get_device_vendor

total_pci_buses				db 0

; init_pci:
; Initializes the PCI bus

init_pci:
	mov rsi, .starting_msg
	call kprint

.loop:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, 0
	mov bh, 0
	call pci_read_dword

	cmp eax, 0xFFFFFFFF
	je .done

	inc [.device]
	cmp [.device], 0xFF
	je .next_bus
	jmp .loop

.next_bus:
	inc [.bus]
	mov [.device], 0
	jmp .loop

.done:
	mov al, [.bus]
	mov [total_pci_buses], al

	mov rsi, .done_msg
	call kprint
	mov al, [total_pci_buses]
	inc al
	and rax, 0xFF
	call int_to_string
	call kprint
	mov rsi, .done_msg2
	call kprint

	ret

.bus				db 0
.device				db 0
.starting_msg			db "[pci] initializing PCI...",10,0
.done_msg			db "[pci] done, found ",0
.done_msg2			db " buses.",10,0

; pci_get_buses:
; Returns the number of PCI buses present
; In\	Nothing
; Out\	RAX = Number of PCI buses onboard

pci_get_buses:
	movzx rax, [total_pci_buses]
	inc rax
	ret

; pci_read_dword:
; Reads a DWORD from the PCI bus
; In\	AL = Bus number
; In\	AH = Device number
; In\	BL = Function
; In\	BH = Offset
; Out\	EAX = DWORD from PCI bus

pci_read_dword:
	cmp [is_there_pcie], 1		; use PCI-E when available, transparently to the user ;)
	je pcie_read_dword

	pushaq
	mov [.bus], al
	mov [.slot], ah
	mov [.function], bl
	mov [.offset], bh

	mov eax, 0
	movzx ebx, [.bus]
	shl ebx, 16
	or eax, ebx
	movzx ebx, [.slot]
	shl ebx, 11
	or eax, ebx
	movzx ebx, [.function]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.offset]
	and ebx, 0xFC
	or eax, ebx
	or eax, 0x80000000

	mov edx, 0xCF8
	out dx, eax

	call iowait
	mov edx, 0xCFC
	in eax, dx
	mov [.tmp], eax
	popaq
	mov eax, [.tmp]
	ret

.tmp				dd 0
.bus				db 0
.function			db 0
.slot				db 0
.offset				db 0

; pci_write_dword:
; Writes a DWORD to the PCI bus
; In\	AL = Bus number
; In\	AH = Device number
; In\	BL = Function
; In\	BH = Offset
; In\	EDX = DWORD to write
; Out\	Nothing

pci_write_dword:
	cmp [is_there_pcie], 1		; use PCI-E when available, transparently to the user ;)
	je pcie_write_dword

	pushaq
	mov [.bus], al
	mov [.slot], ah
	mov [.func], bl
	mov [.offset], bh
	mov [.dword], edx

	mov eax, 0
	mov ebx, 0
	mov al, [.bus]
	shl eax, 16
	mov bl, [.slot]
	shl ebx, 11
	or eax, ebx
	mov ebx, 0
	mov bl, [.func]
	shl ebx, 8
	or eax, ebx
	mov ebx, 0
	mov bl, [.offset]
	and ebx, 0xFC
	or eax, ebx
	mov ebx, 0x80000000
	or eax, ebx

	mov edx, 0xCF8
	out dx, eax

	call iowait
	mov eax, [.dword]
	mov edx, 0xCFC
	out dx, eax

	call iowait
	popaq
	ret

.dword				dd 0
.tmp				dd 0
.bus				db 0
.func				db 0
.slot				db 0
.offset				db 0

; pci_get_device_class:
; Gets the bus and device number of a PCI device from the class codes
; In\	AH = Class code
; In\	AL = Subclass code
; Out\	AL = Bus number (0xFF if invalid)
; Out\	AH = Device number (0xFF if invalid)
; Out\	BL = Function number (0xFF if invalid)

pci_get_device_class:
	mov [.class], ax
	mov [.bus], 0
	mov [.device], 0
	mov [.function], 0

.find_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 8
	call pci_read_dword

	shr eax, 16
	cmp ax, [.class]
	je .found_device

.next:

.next_function:
	inc [.function]
	cmp [.function], 8
	je .next_device
	jmp .find_device

.next_device:
	mov [.function], 0
	inc [.device]
	cmp [.device], 32
	je .next_bus
	jmp .find_device

.next_bus:
	mov [.device], 0
	inc [.bus]
	mov al, [total_pci_buses]
	cmp [.bus], al
	jle .find_device

.not_found:
	mov ax, 0xFFFF
	mov bl, 0xFF
	ret

.found_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]

	ret

.class				dw 0
.bus				db 0
.device				db 0
.function			db 0

; pci_get_device_class_progif:
; Gets the bus and device number of a PCI device from the class codes and Prog IF code
; In\	AH = Class code
; In\	AL = Subclass code
; In\	BL = Prog IF
; Out\	AL = Bus number (0xFF if invalid)
; Out\	AH = Device number (0xFF if invalid)
; Out\	BL = Function number (0xFF if invalid)

pci_get_device_class_progif:
	mov [.class], ax
	mov [.progif], bl
	mov [.bus], 0
	mov [.device], 0
	mov [.function], 0

.find_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 8
	call pci_read_dword

	shr eax, 8
	cmp al, [.progif]
	jne .next

	shr eax, 8
	cmp ax, [.class]
	jne .next
	jmp .found_device

.next:

.next_function:
	inc [.function]
	cmp [.function], 8
	je .next_device
	jmp .find_device

.next_device:
	mov [.function], 0
	inc [.device]
	cmp [.device], 32
	je .next_bus
	jmp .find_device

.next_bus:
	mov [.device], 0
	inc [.bus]
	mov al, [total_pci_buses]
	cmp [.bus], al
	jle .find_device

.not_found:
	mov ax, 0xFFFF
	mov bl, 0xFF
	ret

.found_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]

	ret

.class				dw 0
.bus				db 0
.device				db 0
.function			db 0
.progif				db 0

; pci_get_device_vendor:
; Gets the bus and device and function of a PCI device from the vendor and device ID
; In\	EAX = Vendor/device combination (low word vendor ID, high word device ID)
; Out\	AL = Bus number (0xFF if invalid)
; Out\	AH = Device number (0xFF if invalid)
; Out\	BL = Function number (0xFF if invalid)

pci_get_device_vendor:
	mov [.dword], eax
	mov [.bus], 0
	mov [.device], 0
	mov [.function], 0

.find_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 0
	call pci_read_dword

	cmp eax, [.dword]
	je .found_device

.next:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 0xC
	call pci_read_dword
	shr eax, 16
	test al, 0x80		; is multifunction?
	jz .next_device

.next_function:
	inc [.function]
	cmp [.function], 7
	jle .find_device

.next_device:
	mov [.function], 0
	inc [.device]
	cmp [.device], 32
	jle .find_device

.next_bus:
	mov [.device], 0
	inc [.bus]
	mov al, [total_pci_buses]
	cmp [.bus], al
	jle .find_device

.no_device:
	mov ax, 0xFFFF
	mov bl, 0xFF
	ret

.found_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]

	ret

.dword				dd 0
.bus				db 0
.device				db 0
.function			db 0





