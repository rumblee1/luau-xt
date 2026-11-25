# Keyboard pixel editor. S exports a new SKETCH.BMP on the current disk.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.set COLS, 40
.set ROWS, 24
.set BMP_WIDTH, COLS * 4
.set BMP_HEIGHT, ROWS * 4
.text
	jmp start
.include "vga-ui.inc"

start:
	call vga_start
	fill 38, 28, 244, 148, 1
	call swatches
	call cursor_position
	call draw_cursor

edit:
	call get_key
	cmp al, 27
	je vga_exit
	cmp ah, 0x48
	jb shortcuts
	cmp ah, 0x50
	jbe movement
shortcuts:
	cmp al, 's'
	je save
	cmp al, 'S'
	je save
	cmp al, ' '
	je paint
	cmp al, '0'
	jb movement
	cmp al, '8'
	ja movement
	sub al, '0'
	mov [brush + ORIGIN], al
	call swatches
	call cursor_position
	call draw_cursor
	jmp edit
movement:
	call cursor_position
	mov bx, [cursor_x + ORIGIN]
	mov dx, [cursor_y + ORIGIN]
	cmp ah, 0x4b
	je left
	cmp ah, 0x4d
	je right
	cmp ah, 0x48
	je up
	cmp ah, 0x50
	jne edit
	cmp dx, ROWS - 1
	jae edit
	inc dx
	jmp move_cursor
left:
	test bx, bx
	jz edit
	dec bx
	jmp move_cursor
right:
	cmp bx, COLS - 1
	jae edit
	inc bx
	jmp move_cursor
up:
	test dx, dx
	jz edit
	dec dx
move_cursor:
	call draw_cell
	mov [cursor_x + ORIGIN], bx
	mov [cursor_y + ORIGIN], dx
	call cursor_position
	call draw_cursor
	jmp edit

paint:
	call cursor_position
	mov al, [brush + ORIGIN]
	mov [canvas + ORIGIN + si], al
	call draw_cursor
	jmp edit

cursor_position:
	imul si, [cursor_y + ORIGIN], COLS
	add si, [cursor_x + ORIGIN]
	imul di, [cursor_y + ORIGIN], 6 * 320
	imul bp, [cursor_x + ORIGIN], 6
	add di, bp
	add di, 30 * 320 + 40
	ret

draw_cell:
	pusha
	mov al, [canvas + ORIGIN + si]
	mov cx, 6
	mov bx, 6
	call rectangle
	popa
	ret

draw_cursor:
	call draw_cell
	mov al, 15
	mov cx, 6
	stosb
	add di, 4
	stosb
	add di, 5 * 320 - 6
	stosb
	add di, 4
	stosb
	ret

swatches:
	fill 40, 8, 211, 14, 0
	mov di, 8 * 320 + 40
	xor ax, ax
	mov cx, 20
	mov bx, 10
swatch:
	call rectangle
	cmp al, [brush + ORIGIN]
	jne next_swatch
	push ax
	push di
	add di, 11 * 320
	mov al, 15
	rep stosb
	mov cx, 20
	pop di
	pop ax
next_swatch:
	add di, 23
	inc al
	cmp al, 9
	jb swatch
	ret

save:
	# DOS create-new leaves an existing drawing intact.
	mov dx, offset filename + ORIGIN
	xor cx, cx
	mov ax, 0x5b00
	int 0x21
	jc save_failed
	mov [handle + ORIGIN], ax

	push es
	push ds
	pop es
	mov si, offset ui_colors + ORIGIN
	mov di, offset bmp_palette + ORIGIN
	mov cx, 16
encode_palette:
	mov al, [si + 2]
	shl al, 2
	stosb
	mov al, [si + 1]
	shl al, 2
	stosb
	lodsb
	shl al, 2
	stosb
	xor al, al
	stosb
	add si, 2
	loop encode_palette
	pop es

	mov dx, offset bmp_header + ORIGIN
	mov cx, bmp_pixels - bmp_header
	call write_file
	jc discard_file
	mov si, offset canvas + ORIGIN + COLS * ROWS
	mov bp, ROWS
save_row:
	sub si, COLS
	push si
	push es
	push ds
	pop es
	mov di, offset bmp_pixels + ORIGIN
	mov dx, COLS
scale_row:
	lodsb
	mov cx, 4
	rep stosb
	dec dx
	jnz scale_row
	pop es
	pop si
	mov di, 4
duplicate_row:
	mov dx, offset bmp_pixels + ORIGIN
	mov cx, BMP_WIDTH
	call write_file
	jc discard_file
	dec di
	jnz duplicate_row
	dec bp
	jnz save_row
	call close_file
	jc remove_file
	fill 270, 8, 12, 10, 5
	jmp edit
discard_file:
	call close_file
remove_file:
	mov dx, offset filename + ORIGIN
	mov ah, 0x41
	int 0x21
save_failed:
	fill 270, 8, 12, 10, 7
	jmp edit

close_file:
	mov bx, [handle + ORIGIN]
	mov ah, 0x3e
	int 0x21
	ret

write_file:
	pusha
	mov bx, [handle + ORIGIN]
	mov ah, 0x40
	int 0x21
	jc write_failed
	cmp ax, cx
	jne write_failed
	popa
	clc
	ret
write_failed:
	popa
	stc
	ret

cursor_x: .word 0
cursor_y: .word 0
brush: .byte 4
handle: .word 0
filename: .asciz "SKETCH.BMP"
canvas: .zero COLS * ROWS
bmp_header:
	.ascii "BM"
	.long bmp_pixels - bmp_header + BMP_WIDTH * BMP_HEIGHT, 0, bmp_pixels - bmp_header
	.long 40, BMP_WIDTH, BMP_HEIGHT
	.word 1, 8
	.long 0, BMP_WIDTH * BMP_HEIGHT, 0, 0, 16, 0
bmp_palette: .zero 64
bmp_pixels: .zero BMP_WIDTH
