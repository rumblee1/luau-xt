# CPU probe for the GLaBIOS 0.4.2 XT POST, at F000:DE00.
# SI already points to the CPU name selected by the original 8088/V20 check.
.intel_syntax noprefix
.code16
.arch i386
.set HOOK_OFFSET, 0xde00
.set GLA_OUT_SZ, 0xf79e
.text
post_cpu:
	pushf
	cli
	push ax
	xor ax, ax
	push ax
	popf
	pushf
	pop ax
	test ah, 0x80           # The 8086/8088 cannot clear this bit.
	jnz display

	mov ah, 0x30            # Try setting IOPL in real mode.
	push ax
	popf
	pushf
	pop ax
	test ah, 0x30
	jz is_286

	# The 386 cannot set EFLAGS.AC. Only use 32-bit instructions after
	# ruling out the older CPUs.
	push eax
	push edx
	pushfd
	pop edx
	mov eax, edx
	xor eax, 0x40000
	push eax
	popfd
	pushfd
	pop eax
	xor eax, edx
	mov si, HOOK_OFFSET + cpu_386 - post_cpu
	test eax, 0x40000
	jz restore
	mov si, HOOK_OFFSET + cpu_486_plus - post_cpu
restore:
	push edx
	popfd
	pop edx
	pop eax
	jmp display
is_286:
	mov si, HOOK_OFFSET + cpu_286 - post_cpu
display:
	pop ax
	popf
	.byte 0xe9              # Tail-call the original near string printer.
	.word GLA_OUT_SZ - (HOOK_OFFSET + (. - post_cpu) + 2)

cpu_286: .asciz "286"
cpu_386: .asciz "i386"
cpu_486_plus: .asciz "486+"
.org 512, 0
