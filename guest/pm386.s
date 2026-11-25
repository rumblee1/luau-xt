# DOS COM diagnostic. Uses conventional scratch below the PSP and extended RAM.
.intel_syntax noprefix
.code16
.arch i386
.text
	cli
	in al, 0x92
	or al, 2
	out 0x92, al

	# Rebase the copied protected-mode diagnostic at physical 0x500.
	push cs
	pop ds
	xor ax, ax
	mov es, ax
	mov si, offset payload + 0x100
	mov di, 0x500
	mov cx, offset payload_end - offset payload
	cld
	rep movsb
	push es
	pop ds
	ljmp 0, 0x500

payload:
	lgdt [0x500 + gdtr - payload]
	lidt [0x500 + idtr - payload]
	mov eax, cr0
	or eax, 1
	mov cr0, eax
	ljmp 8, 0x500 + protected - payload

.code32
protected:
	mov ax, 16
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov esp, 0x8000

	# POP resolves an ESP-relative destination after advancing the stack.
	mov dword ptr [esp], 0
	push 0x12345678
	pop dword ptr [esp]
	cmp dword ptr [esp], 0x12345678
	jne failed

	# 0–4 MiB identity map plus an alias of physical 1 MiB at virtual 4 MiB.
	mov edi, 0x10000
	xor eax, eax
	mov ecx, 3072
	rep stosd
	mov dword ptr [0x10000], 0x11007
	mov dword ptr [0x10004], 0x12003
	mov edi, 0x11000
	mov eax, 7
	mov ecx, 1024
fill_identity:
	stosd
	add eax, 4096
	loop fill_identity
	mov dword ptr [0x12000], 0x100003
	mov dword ptr [0x100000], 0x12345678
	mov eax, 0x10000
	mov cr3, eax
	mov eax, cr0
	or eax, 0x80000000
	mov cr0, eax
	cmp dword ptr [0x400000], 0x12345678
	jne failed

	# Install a page fault gate at IDT vector 14.
	mov eax, 0x500 + handle_page_fault - payload
	mov word ptr [0x2000 + 14 * 8], ax
	mov word ptr [0x2000 + 14 * 8 + 2], 8
	mov word ptr [0x2000 + 14 * 8 + 4], 0x8e00
	shr eax, 16
	mov word ptr [0x2000 + 14 * 8 + 6], ax
	mov dword ptr [0x401000], 1  # Intentionally absent, supervisor write.
	jmp failed

after_fault:
	# Install the ring-0 stack descriptor and a ring-3-callable interrupt.
	mov word ptr [0x3000 + 8], 16
	mov dword ptr [0x3000 + 4], 0x9000
	mov word ptr [0x3000 + 102], 104
	mov ax, 40
	ltr ax
	mov eax, 0x500 + handle_user - payload
	mov word ptr [0x2000 + 0x30 * 8], ax
	mov word ptr [0x2000 + 0x30 * 8 + 2], 8
	mov word ptr [0x2000 + 0x30 * 8 + 4], 0xee00
	shr eax, 16
	mov word ptr [0x2000 + 0x30 * 8 + 6], ax
	push 0x23
	push 0xa000
	push 2
	push 0x1b
	push 0x500 + user_entry - payload
	iret

user_entry:
	mov ax, 0x23
	mov ds, ax
	mov es, ax
	mov ebx, 0x1234
	int 0x30
	cmp eax, 0x3412
	jne user_fail
	cmp esp, 0xa000
	jne user_fail
	mov ebx, 0x5678
	int 0x30
user_fail:
	xor ebx, ebx
	int 0x30

handle_user:
	cmp word ptr [esp + 4], 0x1b
	jne failed
	cmp word ptr [esp + 16], 0x23
	jne failed
	cmp ebx, 0x1234
	jne user_finished
	mov eax, 0x3412
	iret
user_finished:
	cmp ebx, 0x5678
	jne failed
	mov esi, 0x500 + pass_message - payload
	jmp print
failed:
	mov esi, 0x500 + fail_message - payload
print:
	mov edi, 0xb8000
	mov ah, 7
print_next:
	lodsb
	test al, al
	jz halt
	stosw
	jmp print_next
halt:
	hlt
	jmp halt

handle_page_fault:
	cmp dword ptr [esp], 2
	jne failed
	mov eax, cr2
	cmp eax, 0x401000
	jne failed
	add esp, 4
	mov dword ptr [esp], 0x500 + after_fault - payload
	iret

.align 8, 0
gdt:
	.quad 0
	.quad 0x00cf9a000000ffff
	.quad 0x00cf92000000ffff
	.quad 0x00cffa000000ffff
	.quad 0x00cff2000000ffff
	.quad 0x0000890030000067
gdt_end:
gdtr:
	.word gdt_end - gdt - 1
	.long 0x500 + gdt - payload
idtr:
	.word 0x7ff
	.long 0x2000
pass_message: .asciz "386 PROTECTED MODE AND PAGING PASS"
fail_message: .asciz "386 PROTECTED MODE OR PAGING FAIL"
payload_end:
