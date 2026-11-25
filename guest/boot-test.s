.intel_syntax noprefix
.code16
.arch i8086
.text

	xor ax, ax
	mov ds, ax
	mov si, offset message + 0x7c00
	cld
print:
	lodsb
	test al, al
	jz done
	mov ah, 0x0e
	mov bx, 0x0007
	int 0x10
	jmp print
done:
	cli
	hlt
	jmp done

message: .asciz "BOOT OK"
.org 510, 0
.word 0xaa55
