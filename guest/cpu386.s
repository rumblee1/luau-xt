.intel_syntax noprefix
.code16
.arch i386
.text
	mov eax, 0x12345678
	mov ax, 0xffff
	add eax, 1
	cmp eax, 0x12350000
	jne failure

	xor ebx, ebx
	mov bx, offset words + 0x100
	mov ecx, 1
	mov dword ptr [ebx + ecx * 4], eax
	push eax
	xor eax, eax
	pop eax
	cmp eax, dword ptr [ebx + ecx * 4]
	jne failure

	mov eax, 0xffffffff
	mul eax
	cmp eax, 1
	jne failure
	cmp edx, 0xfffffffe
	jne failure
	mov ecx, 0xffffffff
	div ecx
	cmp eax, ecx
	jne failure
	test edx, edx
	jnz failure

	mov dx, offset passed + 0x100
	xor bl, bl
	jmp report
failure:
	mov dx, offset failed + 0x100
	mov bl, 1
report:
	mov ah, 9
	int 0x21
	mov al, bl
	mov ah, 0x4c
	int 0x21
words: .long 0, 0
passed: .ascii "386 REAL MODE PASS\r\n$"
failed: .ascii "386 REAL MODE FAIL\r\n$"
