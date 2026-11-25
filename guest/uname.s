# Small Linux/i386 uname for the 386 demo disk. Uses the kernel's UTS data.
.intel_syntax noprefix
.code32
.text
.global _start
_start:
	cld
	mov ecx, 1
	cmp dword ptr [esp], 1
	je inspect
	cmp dword ptr [esp], 2
	jne failure
	mov eax, [esp + 8]
	cmp word ptr [eax], 0x612d  # -a
	jne failure
	cmp byte ptr [eax + 2], 0
	jne failure
	mov ecx, 5

inspect:
	push ecx
	mov eax, 122                 # uname
	lea ebx, [utsname]
	int 0x80
	test eax, eax
	jnz failure
	pop ebp
	lea esi, [utsname]

print_field:
	mov edi, esi
	xor eax, eax
	mov ecx, 65
	repne scasb
	mov edx, edi
	sub edx, esi
	dec edx
	mov ecx, esi
	call write_stdout
	add esi, 65
	dec ebp
	jz print_newline
	lea ecx, [space]
	mov edx, 1
	call write_stdout
	jmp print_field

print_newline:
	lea ecx, [newline]
	mov edx, 1
	call write_stdout
	xor ebx, ebx
exit:
	mov eax, 1
	int 0x80

failure:
	mov ebx, 1
	jmp exit

write_stdout:
	mov eax, 4
	mov ebx, 1
	int 0x80
	ret

.section .rodata
space: .byte ' '
newline: .byte 10

.bss
.lcomm utsname, 6 * 65
