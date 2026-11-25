# Find eight matching signals on a shuffled, 4-by-4 board.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.text
	jmp start
.include "vga-ui.inc"

start:
	call vga_start
	mov bp, fs:[0x046c]
	mov bx, 16
shuffle:
	imul bp, bp, 25173
	add bp, 13849
	mov ax, bp
	xor dx, dx
	div bx
	mov si, dx
	dec bx
	mov al, [tiles + ORIGIN + bx]
	xchg al, [tiles + ORIGIN + si]
	mov [tiles + ORIGIN + bx], al
	cmp bx, 1
	ja shuffle
	fill 56, 14, 208, 172, 1
	fill 60, 18, 200, 164, 0
	xor al, al
draw_board:
	call tile
	inc al
	cmp al, 16
	jb draw_board

choose:
	call get_key
	cmp al, 27
	je vga_exit
	mov bl, [cursor + ORIGIN]
	cmp ah, 0x4b
	je left
	cmp ah, 0x4d
	je right
	cmp ah, 0x48
	je up
	cmp ah, 0x50
	je down
	cmp al, ' '
	je reveal
	cmp al, 13
	je reveal
	jmp choose
left:
	test bl, 3
	jz choose
	dec bl
	jmp move_cursor
right:
	mov al, bl
	and al, 3
	cmp al, 3
	je choose
	inc bl
	jmp move_cursor
up:
	cmp bl, 4
	jb choose
	sub bl, 4
	jmp move_cursor
down:
	cmp bl, 12
	jae choose
	add bl, 4
move_cursor:
	mov al, bl
	xchg al, [cursor + ORIGIN]
	call tile
	mov al, bl
	call tile
	jmp choose

reveal:
	movzx bx, bl
	cmp byte ptr [matched + ORIGIN + bx], 0
	jne choose
	mov al, bl
	cmp al, [first + ORIGIN]
	je choose
	cmp byte ptr [first + ORIGIN], 0xff
	jne second_tile
	mov [first + ORIGIN], al
	call tile
	jmp choose
second_tile:
	mov [second + ORIGIN], al
	call tile
	movzx si, byte ptr [first + ORIGIN]
	mov al, [tiles + ORIGIN + si]
	cmp al, [tiles + ORIGIN + bx]
	jne mismatch
	mov byte ptr [matched + ORIGIN + si], 1
	mov byte ptr [matched + ORIGIN + bx], 1
	dec byte ptr [pairs_left + ORIGIN]
	jnz hide
	mov dx, offset solved + ORIGIN
	jmp vga_result
mismatch:
	mov dx, fs:[0x046c]
wait:
	hlt
	mov ax, fs:[0x046c]
	sub ax, dx
	cmp ax, 12
	jb wait
hide:
	mov al, 0xff
	xchg al, [first + ORIGIN]
	call tile
	mov al, 0xff
	xchg al, [second + ORIGIN]
	call tile
	jmp choose

# Draw tile AL. The border shows the cursor and a color shows a revealed signal.
tile:
	pusha
	movzx si, al
	mov bx, si
	shl bx, 1
	mov di, [offsets + ORIGIN + bx]
	mov ax, si
	cmp [cursor + ORIGIN], al
	mov al, 1
	jne border
	mov al, 15
border:
	mov cx, 42
	mov bx, 32
	call rectangle
	add di, 642
	mov ax, si
	cmp [first + ORIGIN], al
	je face
	cmp [second + ORIGIN], al
	je face
	cmp byte ptr [matched + ORIGIN + si], 0
	jne face
	mov al, 2
	jmp interior
face:
	mov al, [tiles + ORIGIN + si]
	add al, 3
interior:
	mov cx, 38
	mov bx, 28
	call rectangle
	popa
	ret

offsets:
	.irp row, 24, 63, 102, 141
		.word \row*320+66, \row*320+114, \row*320+162, \row*320+210
	.endr
tiles: .byte 1, 4, 3, 5, 8, 2, 7, 6, 5, 8, 7, 4, 2, 3, 6, 1
matched: .zero 16
cursor: .byte 0
first: .byte 0xff
second: .byte 0xff
pairs_left: .byte 8
solved: .ascii "Signal Grid: all eight pairs found.\r\n$"
