# A standalone i386 Multiboot payload used to verify GRUB's real handoff.
.intel_syntax noprefix
.code32
.arch i386
.text
.align 4
.long 0x1badb002
.long 3
.long -0x1badb005
.global _start
_start:
	cli
	cld
	cmp eax, 0x2badb002
	jne failed
	mov esi, offset passed
	jmp print
failed:
	mov esi, offset failure
print:
	mov edi, 0xb8000
	mov ah, 7
next:
	lodsb
	test al, al
	jz stop
	stosw
	jmp next
stop:
	hlt
	jmp stop

passed: .asciz "GRUB MULTIBOOT HANDOFF PASS"
failure: .asciz "GRUB MULTIBOOT HANDOFF FAIL"
