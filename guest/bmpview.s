# FreeDOS viewer for uncompressed, indexed 8-bit BMP files.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.text

start:
	mov dx, offset default_name + ORIGIN
	mov si, 0x81
	cld
skip_spaces:
	lodsb
	cmp al, ' '
	je skip_spaces
	cmp al, 9
	je skip_spaces
	cmp al, 13
	je open_file
	mov dx, si
	dec dx
scan_name:
	lodsb
	cmp al, 13
	je end_name
	cmp al, ' '
	je end_name
	cmp al, 9
	jne scan_name
end_name:
	mov byte ptr [si - 1], 0

open_file:
	push dx
	mov ax, 0x1a00
	int 0x10
	pop dx
	cmp al, 0x1a
	jne needs_vga

	mov ax, 0x3d00
	int 0x21
	jc open_failed
	mov [file_handle + ORIGIN], ax

	mov dx, offset header + ORIGIN
	mov cx, 54
	call read_exact
	jc invalid_image
	cmp word ptr [header + ORIGIN], 0x4d42
	jne invalid_image
	mov eax, [header + ORIGIN + 14]
	cmp eax, 40
	jb invalid_image
	cmp eax, 124
	ja invalid_image
	add ax, 14
	mov [palette_offset + ORIGIN], ax
	cmp word ptr [header + ORIGIN + 26], 1
	jne invalid_image
	cmp word ptr [header + ORIGIN + 28], 8
	jne invalid_image
	cmp dword ptr [header + ORIGIN + 30], 0
	jne invalid_image

	mov eax, [header + ORIGIN + 18]
	test eax, eax
	jz invalid_image
	cmp eax, 320
	ja invalid_image
	mov [image_width + ORIGIN], ax
	add ax, 3
	and ax, 0xfffc
	mov [row_size + ORIGIN], ax

	mov word ptr [row_step + ORIGIN], -320
	mov eax, [header + ORIGIN + 22]
	test eax, eax
	jz invalid_image
	jns check_height
	neg eax
	mov word ptr [row_step + ORIGIN], 320
check_height:
	cmp eax, 200
	ja invalid_image
	mov [rows_left + ORIGIN], ax

	# Center the image. Positive BMP height stores the bottom row first.
	mov cx, ax
	mov ax, 200
	sub ax, cx
	shr ax, 1
	cmp word ptr [row_step + ORIGIN], 320
	je center_x
	add ax, cx
	dec ax
center_x:
	imul ax, ax, 320
	mov dx, 320
	sub dx, [image_width + ORIGIN]
	shr dx, 1
	add ax, dx
	mov [video_offset + ORIGIN], ax

	mov eax, [header + ORIGIN + 46]
	test eax, eax
	jnz check_colors
	mov ax, 256
check_colors:
	cmp eax, 256
	ja invalid_image
	shl ax, 2
	mov [palette_size + ORIGIN], ax
	add ax, [palette_offset + ORIGIN]
	movzx eax, ax
	cmp [header + ORIGIN + 10], eax
	jb invalid_image

	xor cx, cx
	mov dx, [palette_offset + ORIGIN]
	call seek
	jc invalid_image
	mov dx, offset palette + ORIGIN
	mov cx, [palette_size + ORIGIN]
	call read_exact
	jc invalid_image
	mov dx, [header + ORIGIN + 10]
	mov cx, [header + ORIGIN + 12]
	test cx, 0x8000
	jnz invalid_image
	call seek
	jc invalid_image

	# All data is loaded through DOS, then sent through real VGA ports and VRAM.
	mov ax, 0x0013
	int 0x10
	mov dx, 0x3c8
	xor al, al
	out dx, al
	inc dx
	mov si, offset palette + ORIGIN
	mov cx, 256
load_palette:
	mov al, [si + 2]
	shr al, 2
	out dx, al
	mov al, [si + 1]
	shr al, 2
	out dx, al
	mov al, [si]
	shr al, 2
	out dx, al
	add si, 4
	loop load_palette

draw_row:
	mov dx, offset row + ORIGIN
	mov cx, [row_size + ORIGIN]
	call read_exact
	jc truncated_image
	mov ax, 0xa000
	mov es, ax
	mov di, [video_offset + ORIGIN]
	mov si, offset row + ORIGIN
	mov cx, [image_width + ORIGIN]
	cld
	rep movsb
	mov ax, [row_step + ORIGIN]
	add [video_offset + ORIGIN], ax
	dec word ptr [rows_left + ORIGIN]
	jnz draw_row

	call close_file
	xor ah, ah
	int 0x16
	mov ax, 0x0003
	int 0x10
	mov ax, 0x4c00
	int 0x21

truncated_image:
	mov ax, 0x0003
	int 0x10
invalid_image:
	call close_file
	mov dx, offset image_error + ORIGIN
	jmp fail
open_failed:
	mov dx, offset open_error + ORIGIN
	jmp fail
needs_vga:
	mov dx, offset vga_error + ORIGIN
fail:
	mov ah, 9
	int 0x21
	mov ax, 0x4c01
	int 0x21

seek:
	mov bx, [file_handle + ORIGIN]
	mov ax, 0x4200
	int 0x21
	ret

read_exact:
	push cx
	mov bx, [file_handle + ORIGIN]
	mov ah, 0x3f
	int 0x21
	pop cx
	jc read_failed
	cmp ax, cx
	je read_done
	stc
read_failed:
	ret
read_done:
	clc
	ret

close_file:
	mov bx, [file_handle + ORIGIN]
	mov ah, 0x3e
	int 0x21
	ret

default_name: .asciz "SAMPLE.BMP"
open_error: .ascii "Cannot open BMP file. Usage: BMPVIEW [file.bmp]\r\n$"
image_error: .ascii "Expected an uncompressed 8-bit BMP up to 320x200.\r\n$"
vga_error: .ascii "BMPVIEW requires VGA.\r\n$"

file_handle: .word 0
palette_offset: .word 0
palette_size: .word 0
image_width: .word 0
rows_left: .word 0
row_size: .word 0
row_step: .word 0
video_offset: .word 0
header: .space 54
palette: .space 1024
row: .space 320
