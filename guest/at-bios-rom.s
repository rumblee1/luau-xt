# 386 BIOS extension at D000:0000 for memory discovery and A20 control.
.intel_syntax noprefix
.code16
.arch i386
.text
.byte 0x55, 0xaa, 2

init:
	pushf
	cli
	pusha
	push ds
	xor ax, ax
	mov ds, ax
	mov word ptr [0x54], offset memory_service
	mov [0x56], cs

	# GLaBIOS measures conventional RAM. Read the extended range from CMOS.
	push cs
	pop ds
	cld
	mov si, offset post_message
	call print_string
	call read_extended_kib
	mov cx, ax
	xor dx, dx
	mov bx, 1024
	div bx
	mov si, offset units_mib
	test dx, dx
	jz print_capacity
	mov ax, cx
	mov si, offset units_kib
print_capacity:
	call print_number
	call print_string
	pop ds
	popa
	popf
	retf

print_string:
	lodsb
	test al, al
	jz string_done
	call print_character
	jmp print_string
string_done:
	ret

print_number:
	xor dx, dx
	mov bx, 10
	div bx
	push dx
	test ax, ax
	jz print_digit
	call print_number
print_digit:
	pop ax
	add al, '0'
print_character:
	mov ah, 0x0e
	mov bx, 7
	int 0x10
	ret

# AT CMOS registers 17h and 18h contain extended RAM in KiB.
read_extended_kib:
	mov al, 0x17
	out 0x70, al
	in al, 0x71
	mov ah, al
	mov al, 0x18
	out 0x70, al
	in al, 0x71
	xchg al, ah
	ret

memory_service:
	push bp
	mov bp, sp
	cmp ax, 0xe820
	je memory_map
	cmp ax, 0xe801
	je extended
	cmp ah, 0x88
	je legacy_size
	cmp ah, 0x24
	je a20_service
	jmp invalid

a20_service:
	cmp al, 1
	jbe a20_change
	cmp al, 2
	je a20_state
	cmp al, 3
	jne invalid
	mov bx, 3
	xor ax, ax
	jmp success
a20_change:
	shl al, 1
	out 0x92, al
	xor ax, ax
	jmp success
a20_state:
	in al, 0x92
	shr al, 1
	and ax, 1
	jmp success

legacy_size:
	call read_extended_kib
	jmp success
extended:
	call read_extended_kib
	xor bx, bx
	cmp ax, 15 * 1024
	jbe extended_done
	mov bx, ax
	sub bx, 15 * 1024
	shr bx, 6               # E801 reports memory above 16 MiB in 64 KiB blocks.
	mov ax, 15 * 1024
extended_done:
	mov cx, ax
	mov dx, bx
	jmp success

memory_map:
	cmp edx, 0x534d4150
	jne invalid
	cmp ecx, 20
	jb invalid
	cmp ebx, 2
	ja invalid
	push ax
	push cx
	push si
	mov ax, bx
	mov cl, 2
	shl ax, cl
	mov si, ax
	shl ax, cl
	add si, ax
	add si, offset map
	mov cx, 20
	push di
	pushf
	cld
	cs rep movsb
	popf
	pop di
	pop si
	pop cx
	pop ax
	cmp bx, 2
	jne next_region
	call read_extended_kib
	movzx eax, ax
	shl eax, 10
	mov dword ptr es:[di + 8], eax
next_region:
	inc ebx
	cmp ebx, 3
	jne map_return
	xor ebx, ebx
map_return:
	mov eax, 0x534d4150
	mov ecx, 20
success:
	and word ptr [bp + 6], 0xfffe
	pop bp
	iret
invalid:
	mov ah, 0x86
	or word ptr [bp + 6], 1
	pop bp
	iret

map:
	.long 0, 0, 0xa0000, 0, 1
	.long 0xa0000, 0, 0x60000, 0, 2
	.long 0x100000, 0, 0, 0, 1  # Size filled from CMOS.

post_message: .asciz "  Extended RAM: "
units_mib: .asciz " MiB\r\n"
units_kib: .asciz " KiB\r\n"

.org 1023, 0
.byte 0
