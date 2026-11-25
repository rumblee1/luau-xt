# Shared mode 13h drawing and keyboard routines for the VGA disk programs.
.macro fill x, y, width, height, color
	mov di, (\y) * 320 + (\x)
	mov cx, \width
	mov bx, \height
	mov al, \color
	call rectangle
.endm

vga_start:
	mov ax, 0x1a00
	int 0x10
	cmp al, 0x1a
	jne vga_required
	mov ax, 0x0013
	int 0x10
	mov ax, 0xa000
	mov es, ax
	xor ax, ax
	mov fs, ax
	cld
	mov dx, 0x3c8
	out dx, al
	inc dx
	mov si, offset ui_colors + ORIGIN
	mov cx, 48
	rep outsb
	ret

vga_required:
	mov dx, offset requires_vga + ORIGIN
	mov ah, 9
	int 0x21
	mov ax, 0x4c01
	int 0x21

vga_exit:
	call text_mode
	mov ax, 0x4c00
	int 0x21

vga_result:
	push dx
	call text_mode
	pop dx
	mov ah, 9
	int 0x21
	mov ax, 0x4c00
	int 0x21

text_mode:
	mov ax, 3
	int 0x10
	ret

get_key:
	xor ah, ah
	int 0x16
	ret

# Draw AL at ES:DI, CX pixels wide and BX rows tall.
rectangle:
	pusha
	mov dx, 320
	sub dx, cx
	mov bp, cx
rectangle_row:
	rep stosb
	add di, dx
	mov cx, bp
	dec bx
	jnz rectangle_row
	popa
	ret

requires_vga: .ascii "This program requires a VGA display.\r\n$"
ui_colors:
	.byte 3, 5, 9,     9, 15, 24,   15, 26, 38,  51, 56, 62
	.byte 12, 46, 60,  26, 58, 38,  62, 49, 17,  61, 21, 25
	.byte 44, 29, 60,  58, 30, 48,  18, 32, 62,  62, 37, 17
	.byte 35, 46, 50,  17, 38, 28,  29, 23, 44,  63, 63, 63
