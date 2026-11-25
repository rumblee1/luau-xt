# Load the active partition boot sector at 9000:0000, outside the kernel load area.
.intel_syntax noprefix
.code16
.arch i8086
.text
	xor ax, ax
	mov ds, ax
	mov si, 0x7dbe
	mov ax, 0x9000
	mov es, ax
	xor bx, bx
	mov cx, [si + 2]  # Starting sector and cylinder from the partition entry.
	mov dh, [si + 1]
	mov ax, 0x0201
	int 0x13
	jc failed
	cmp word ptr es:[510], 0xaa55
	jne failed
	ljmp 0x9000, 0
failed:
	int 0x18
	cli
	hlt
