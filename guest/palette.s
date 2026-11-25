# Explore a 256-color VGA palette and print the selected palette index.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.text
	jmp start
.include "vga-ui.inc"

start:
	call vga_start
	mov dx, 0x3c8
	xor ax, ax
	out dx, al
	inc dx
	xor bx, bx
rgb:
	mov ax, bx
	shr al, 5
	imul ax, ax, 9
	out dx, al
	mov ax, bx
	shr al, 2
	and al, 7
	imul ax, ax, 9
	out dx, al
	mov ax, bx
	and al, 3
	imul ax, ax, 21
	out dx, al
	inc bx
	cmp bx, 256
	jb rgb

	fill 0, 0, 320, 200, 41
	xor al, al
draw_grid:
	call swatch
	inc al
	jnz draw_grid
	call highlight

choose:
	call get_key
	cmp al, 27
	je vga_exit
	cmp al, 13
	je report
	mov bl, [selected + ORIGIN]
	cmp ah, 0x4b
	je left
	cmp ah, 0x4d
	je right
	cmp ah, 0x48
	je up
	cmp ah, 0x50
	jne choose
	cmp bl, 240
	jae choose
	add bl, 16
	jmp move
left:
	test bl, 15
	jz choose
	dec bl
	jmp move
right:
	mov al, bl
	and al, 15
	cmp al, 15
	je choose
	inc bl
	jmp move
up:
	cmp bl, 16
	jb choose
	sub bl, 16
move:
	mov al, bl
	xchg al, [selected + ORIGIN]
	call clear_border
	call swatch
	call highlight
	jmp choose

report:
	mov al, [selected + ORIGIN]
	mov bl, al
	shr al, 4
	call hex_digit
	mov [digits + ORIGIN], al
	mov al, bl
	and al, 15
	call hex_digit
	mov [digits + ORIGIN + 1], al
	mov dx, offset result + ORIGIN
	jmp vga_result

hex_digit:
	add al, '0'
	cmp al, '9'
	jbe digit_ready
	add al, 'A' - '9' - 1
digit_ready:
	ret

highlight:
	mov al, [selected + ORIGIN]
	call location
	mov al, 255
	mov cx, 12
	mov bx, 9
	call rectangle
	mov al, [selected + ORIGIN]
	call swatch
	fill 242, 71, 54, 54, 255
	mov al, [selected + ORIGIN]
	mov di, 75 * 320 + 246
	mov cx, 46
	mov bx, 46
	jmp rectangle

clear_border:
	pusha
	call location
	mov al, 41
	mov cx, 12
	mov bx, 9
	call rectangle
	popa
	ret

swatch:
	pusha
	call location
	add di, 321
	mov cx, 10
	mov bx, 7
	call rectangle
	popa
	ret

location:
	push ax
	xor ah, ah
	mov di, ax
	and di, 15
	imul di, di, 12
	shr ax, 4
	imul ax, ax, 9 * 320
	add di, ax
	add di, 28 * 320 + 22
	pop ax
	ret

selected: .byte 0
result: .ascii "VGA palette index 0x"
digits: .ascii "00\r\n$"
