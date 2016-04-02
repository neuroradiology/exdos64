
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Virtual/heap memory manager",0

;; Functions:
; vmm_map_memory
; vmm_unmap_memory
; vmm_set_pat
; flush_caches
; vmm_is_page_free
; vmm_get_free_page
; vmm_get_physical_address
; free_unused_memory
; kmalloc
; kfree
; init_heap

use64

;; 
;; PAGING TABLES
;; 

pml4					= 0x70000
pdpt					= 0x100000
page_table				= 0x101000

HEAP_BASE				= 0x400000000
heap_physical				dq 0

; vmm_map_memory:
; Maps physical memory to virtual memory
; In\	RAX = Physical address
; In\	RBX = Virtual address
; In\	RCX = Pages to map
; In\	DL = Flags
; Out\	Nothing

vmm_map_memory:
	pushaq
	pushfq
	call disable_interrupts
	mov [.physical], rax
	mov [.virtual], rbx
	mov [.count], rcx
	mov [.flags], dl

	mov rdi, [.virtual]
	shr rdi, 18
	add rdi, page_table
	mov rcx, [.count]
	mov rbx, [.physical]
	movzx rdx, [.flags]

.loop:
	mov rax, rbx
	or rax, rdx
	or rax, 0x80		; 2 MB page
	stosq
	add rbx, 0x200000
	loop .loop

.flush_tlb:
	mov rax, [.virtual]
	mov rcx, [.count]

.flush_tlb_loop:
	invlpg [rax]
	add rax, 0x200000
	loop .flush_tlb_loop

	call flush_caches
	popfq
	popaq
	ret


.physical			dq 0
.virtual			dq 0
.count				dq 0
.flags				db 0

; vmm_unmap_memory:
; Unmaps virtual memory
; In\	RAX = Virtual address
; In\	RCX = Number of pages to unmap
; Out\	Nothing

vmm_unmap_memory:
	pushaq
	pushfq
	call disable_interrupts
	mov [.virtual], rax
	mov [.count], rcx

	mov rdi, [.virtual]
	shr rdi, 18
	add rdi, page_table
	mov rcx, [.count]
	mov rax, 0
	rep stosq

.flush_tlb:
	mov rax, [.virtual]
	mov rcx, [.count]

.flush_tlb_loop:
	invlpg [rax]
	add rax, 0x200000
	loop .flush_tlb_loop

	call flush_caches
	popfq
	popaq
	ret

.virtual			dq 0
.count				dq 0

; vmm_set_pat:
; Sets the PAT type
; In\	RAX = Virtual address
; In\	RCX = Number of pages
; In\	DL = PAT entry
; Out\	Nothing

vmm_set_pat:
	pushaq

	mov [.virtual], rax
	mov [.count], rcx
	mov [.pat], dl

	mov al, [.pat]
	and al, 3
	mov byte[.pat_type], al
	shl [.pat_type], 3
	movzx rax, [.pat]
	and rax, 4
	shr rax, 2
	shl rax, 12
	or [.pat_type], eax

	mov rdi, [.virtual]
	shr rdi, 18
	add rdi, page_table
	mov rcx, [.count]

.loop:
	and dword[rdi], 0xFFFFEFE7
	mov eax, [.pat_type]
	or dword[rdi], eax

	add rdi, 8
	loop .loop

	call flush_caches
	popaq
	ret

.virtual			dq 0
.count				dq 0
.pat				db 0
.pat_type			dd 0

; flush_caches:
; Flushes caches

flush_caches:
	pushaq

	mov rax, cr0
	and eax, 0x9FFEFFFF	; re-enable caching
	mov cr0, rax

	mov rax, cr3		; this flushes caches
	mov cr3, rax

	mov rax, cr4		; this too
	mov cr4, rax

	wbinvd

	popaq
	ret

; vmm_is_page_free:
; Checks if a page is free
; In\	RAX = Virtual address
; Out\	RAX = 0 if free, 1 if not

vmm_is_page_free:
	pushaq
	mov [.virtual], rax

	mov rdi, [.virtual]
	shr rdi, 18
	add rdi, page_table
	mov rax, [rdi]
	cmp rax, 0
	je .free

	popaq
	mov rax, 1
	ret

.free:
	popaq
	mov rax, 0
	ret

.virtual			dq 0

; vmm_get_free_page:
; Gets free pages
; In\	RAX = Starting address
; In\	RCX = Required pages
; Out\	RAX = Free page address, 0 on error

vmm_get_free_page:
	pushaq
	mov [.base], rax
	mov [.count], rcx
	mov [.current_count], 0

.start:
	mov rbx, [.base]

.loop:
	mov rcx, [.count]
	cmp [.current_count], rcx
	jge .done
	mov rax, rbx
	call vmm_is_page_free
	cmp rax, 1
	je .not_free

	inc [.current_count]
	add rbx, 0x200000
	jmp .loop

.not_free:
	add [.base], 0x200000
	jmp .start

.done:
	popaq
	mov rax, [.base]
	ret

.base				dq 0
.count				dq 0
.current_count			dq 0

; vmm_get_physical_address
; Gets the physical address of a page
; In\	RAX = Virtual address
; Out\	RAX = Physical address

vmm_get_physical_address:
	pushaq
	mov [.virtual], rax

	mov rdi, [.virtual]
	shr rdi, 18
	add rdi, page_table
	mov rax, [rdi]
	and ax, 0xF000
	mov [.physical], rax

	popaq
	mov rax, [.physical]
	ret

.virtual			dq 0
.physical			dq 0

; free_unused_memory:
; Frees unused memory

free_unused_memory:
	mov rsi, .starting_msg
	call kprint

	cli

	mov rax, 0x800000
	mov rcx, 8188
	call vmm_unmap_memory

	mov rax, [local_apic]			; keep the local APIC mapped
	mov rbx, [local_apic]
	mov rcx, 1
	mov dl, 3				; of course only the kernel can access the local APIC
	call vmm_map_memory

	; if PCI-E is present, keep the configuration space mapped as well
	cmp [is_there_pcie], 1
	jne .check_hpet

	mov rax, [pcie_base]
	and eax, 0xFFE00000
	mov rbx, PCIE_BASE_VIRTUAL
	mov rcx, 16			; 32 MB
	mov dl, 3
	call vmm_map_memory

.check_hpet:
	cmp [hpet_base], 0
	je .quit

	mov rax, [hpet_table.address]
	and eax, 0xFFE00000
	mov rbx, HPET_MEMORY
	mov rcx, 2
	mov dl, 3
	call vmm_map_memory

.quit:
	ret

.starting_msg			db "[vmm] freeing unused kernel memory...",10,0

; kmalloc:
; Allocates kernel memory
; In\	RAX = Starting address
; In\	RBX = Number of bytes to allocate
; In\	DL = Page flags
; Out\	RAX = Memory address, 0 on error

kmalloc:
	pushaq
	mov [.start], rax
	mov [.bytes], rbx
	mov [.flags], dl

	mov rax, [.bytes]
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [.pages], rax

	mov rsi, .starting_msg
	call kprint
	mov rax, [.bytes]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint
	movzx rax, [.flags]
	call int_to_string
	call kprint
	mov rsi, .starting_msg3
	call kprint

	; find free virtual memory
	mov rax, [.start]
	mov rcx, [.pages]
	call vmm_get_free_page
	mov [.virtual], rax

	; allocate physical memory
	mov rax, 0
	mov rcx, [.bytes]
	call pmm_malloc
	jc .too_little_memory

	; map the physical memory into the virtual address space
	mov rbx, [.virtual]
	mov rcx, [.pages]
	mov dl, [.flags]
	call vmm_map_memory

	; clear all the memory
	mov rdi, [.virtual]
	mov rax, 0
	mov rcx, [.bytes]
	rep stosb

	popaq
	mov rax, [.virtual]
	ret

.too_little_memory:
	mov rsi, .fail_msg
	call kprint

	popaq
	mov rax, 0
	ret

.starting_msg			db "[kmalloc] allocating ",0
.starting_msg2			db " bytes of memory with flags ",0
.starting_msg3			db "...",10,0
.fail_msg			db "[kmalloc] failed to allocate memory.",10,0
.start				dq 0
.bytes				dq 0
.flags				db 0
.pages				dq 0
.virtual			dq 0
.physical			dq 0

; kfree:
; Frees kernel memory
; In\	RAX = Memory location
; In\	RBX = Number of bytes to free
; Out\	RAX = -1 on error

kfree:
	pushaq
	mov [.address], rax
	mov [.bytes], rbx

	mov rax, [.bytes]
	shr rax, 20
	mov rbx, 2
	call round_forward
	shr rax, 1
	mov [.pages], rax

	mov rax, [.address]
	call vmm_get_physical_address
	cmp rax, 0
	je .error
	mov [.physical], rax

	mov rsi, .starting_msg
	call kprint
	mov rax, [.bytes]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint
	mov rax, [.address]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov rax, [.address]
	mov rcx, [.pages]
	call vmm_unmap_memory			; free virtual memory

	mov rax, [.physical]
	mov rcx, [.pages]
	call pmm_mark_free			; free physical memory too

	popaq
	mov rax, 0
	ret

.error:
	popaq
	mov rax, -1
	ret

.address			dq 0
.physical			dq 0
.bytes				dq 0
.pages				dq 0
.starting_msg			db "[kfree] freeing ",0
.starting_msg2			db " bytes of memory at address 0x",0


