# Ring the motherboard speaker for about a quarter of a second.
.intel_syntax noprefix
.code16
.arch i8086
.text
	mov al, 0xb6
	out 0x43, al
	mov ax, 1356
	out 0x42, al
	mov al, ah
	out 0x42, al
	in al, 0x61
	mov bl, al
	or al, 3
	out 0x61, al
	xor ax, ax
	mov es, ax
	mov dx, es:[0x046c]
wait:
	hlt
	mov ax, es:[0x046c]
	sub ax, dx
	cmp ax, 5
	jb wait
	mov al, bl
	out 0x61, al
	mov ax, 0x4c00
	int 0x21
