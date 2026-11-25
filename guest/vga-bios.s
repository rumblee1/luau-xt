# VGA video option ROM at C000:0000. GLaBIOS supplies the text services.
.intel_syntax noprefix
.code16
.arch i386
.text
.byte 0x55, 0xaa, 2

init:
	pushf
	cli
	push ax
	push ds
	xor ax, ax
	mov ds, ax
	# INT 42h is the conventional saved system video vector.
	mov ax, [0x40]
	mov [0x108], ax
	mov ax, [0x42]
	mov [0x10a], ax
	mov word ptr [0x40], offset video_service
	mov [0x42], cs
	pop ds
	pop ax
	popf
	retf

video_service:
	cmp ax, 0x1a00
	je display_combination
	cmp ah, 0
	je select_mode
	cmp ah, 0x0f
	je query_mode
	jmp system_video

display_combination:
	mov al, 0x1a
	mov bx, 8             # VGA with a color display.
	iret

query_mode:
	push ds
	push ax
	xor ax, ax
	mov ds, ax
	mov al, [0x449]
	cmp al, 0x12
	je return_mode
	cmp al, 0x13
	jne query_text
return_mode:
	pop ax
	mov al, [0x449]
	mov ah, [0x44a]
	mov bh, [0x462]
	pop ds
	iret
query_text:
	pop ax
	pop ds
	jmp system_video

select_mode:
	push ax
	and al, 0x7f
	cmp al, 0x12
	jb select_text
	cmp al, 0x13
	ja select_text
	pop ax

	pusha
	push ds
	push es
	mov bl, al
	and al, 0x7f
	mov bh, al
	mov dx, 0x3c4
	mov ax, 0x0f02        # Enable writes to all planes.
	out dx, ax
	mov ax, 0x0604        # Planar access in mode 12h.
	cmp bh, 0x12
	je sequencer_memory
	or ah, 8             # Chain-4 in mode 13h.
sequencer_memory:
	out dx, ax
	mov dx, 0x3ce
	xor ax, ax
reset_graphics:
	out dx, ax          # Clear set/reset, compare, rotate and read plane.
	inc al
	cmp al, 5
	jb reset_graphics
	cmp bh, 0x12
	je graphics_shift
	mov ah, 0x40        # 256-color shift in mode 13h.
graphics_shift:
	out dx, ax
	mov ax, 0x0f07
	out dx, ax
	mov ax, 0xff08        # Write all eight bits.
	out dx, ax
	mov ax, 0x0506        # Graphics, A0000h–AFFFFh aperture.
	out dx, ax

	mov dx, 0x3d4
	mov ax, 0x000c
	out dx, ax
	inc al
	out dx, ax
	mov ax, 0x2813        # 80 bytes per plane per scanline.
	out dx, ax
	mov ax, 0x0014
	cmp bh, 0x12
	je crtc_address
	mov ah, 0x40
crtc_address:
	out dx, ax
	mov dx, 0x3c6
	mov al, 0xff
	out dx, al
	cmp bh, 0x12
	jne clear_video
	call planar_palette

clear_video:
	test bl, 0x80         # Bit 7 requests that video memory be preserved.
	jnz mode_data
	mov ax, 0xa000
	mov es, ax
	xor di, di
	xor ax, ax
	mov cx, 0x8000
	cld
	rep stosw

mode_data:
	xor ax, ax
	mov ds, ax
	mov [0x449], bh
	mov ax, 40
	mov cx, 64000
	cmp bh, 0x13
	je store_geometry
	mov ax, 80
	mov cx, 38400
store_geometry:
	mov [0x44a], ax
	mov [0x44c], cx
	mov word ptr [0x44e], 0
	mov byte ptr [0x462], 0
	pop es
	pop ds
	popa
	mov al, 0x20
	iret

select_text:
	pop ax

text_mode:
	push ax
	push dx
	mov dx, 0x3ce
	mov ax, 0x0e06        # Text, B8000h aperture.
	out dx, ax
	mov dx, 0x3c4
	mov ax, 0x0204        # Disable chain-4.
	out dx, ax
	pop dx
	pop ax
	jmp system_video

planar_palette:
	mov dx, 0x3c8
	xor al, al
	out dx, al
	inc dx
	xor cx, cx
ega_color:
	mov al, cl
	and al, 4
	shr al, 1
	mov ah, cl
	and ah, 0x20
	shr ah, 5
	or al, ah
	imul ax, ax, 21
	out dx, al
	mov al, cl
	and al, 2
	mov ah, cl
	and ah, 0x10
	shr ah, 4
	or al, ah
	imul ax, ax, 21
	out dx, al
	mov al, cl
	and al, 1
	shl al, 1
	mov ah, cl
	and ah, 8
	shr ah, 3
	or al, ah
	imul ax, ax, 21
	out dx, al
	inc cl
	cmp cl, 64
	jb ega_color

	mov dx, 0x3da
	in al, dx
	mov dx, 0x3c0
	xor cx, cx
	mov si, offset ega_palette
attribute_color:
	mov al, cl
	out dx, al
	mov al, cs:[si]
	out dx, al
	inc si
	inc cl
	cmp cl, 0x15
	jb attribute_color
	mov al, 0x20
	out dx, al
	ret

ega_palette:
	.byte 0, 1, 2, 3, 4, 5, 0x14, 7, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f
	.byte 0x01, 0, 0x0f, 0, 0

system_video:
	# Push the original target below the interrupt frame for a far tail call.
	push bp
	mov bp, sp
	push bp
	push word ptr [bp]
	push ax
	push ds
	xor ax, ax
	mov ds, ax
	mov ax, [0x108]
	mov [bp - 2], ax
	mov ax, [0x10a]
	mov [bp], ax
	pop ds
	pop ax
	pop bp
	retf

.org 1023, 0
.byte 0
