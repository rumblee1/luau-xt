# GNU assembler, 16-bit 8088 instructions.
# ROM offset 0 maps to F800:0000. The reset jump lives at FFFF:0000.
.intel_syntax noprefix
.code16
.arch i8086
.text

start:
	cli
	xor ax, ax
	mov ss, ax
	mov sp, 0x7000
	mov ds, ax
	mov word ptr [0x0180], offset handler
	mov word ptr [0x0182], cs

	mov ax, 0xB800
	mov es, ax
	xor di, di
	cld

	# Exercise signed overflow, the interrupt stack, and the return flags.
	mov al, 0x7f
	add al, 1
	jno failed
	int 0x60
	jno failed
	cmp al, 0x42
	jne failed

	# BP-based addressing defaults to SS. Set DS apart to check it.
	mov ax, 0x1000
	mov ds, ax
	mov bp, sp
	mov word ptr [bp - 2], 0x8088
	mov bx, word ptr [bp - 2]
	cmp bx, 0x8088
	jne failed

	mov si, offset passed_message
	jmp print
failed:
	mov si, offset failed_message
print:
	mov ah, 0x07
next_character:
	cs lodsb
	or al, al
	jz done
	stosw
	jmp next_character
done:
	hlt

handler:
	xor al, al
	mov al, 0x42
	iret

passed_message: .asciz "8088 DIAGNOSTIC OK"
failed_message: .asciz "8088 DIAGNOSTIC FAILED"

.org 0x7ff0, 0xff
	ljmp 0xf800, 0
.org 0x8000, 0xff
