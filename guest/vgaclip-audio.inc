# Sound Blaster 2.0 mono DMA at 220h, IRQ 5, channel 1.
.set DSP_IRQ_VECTOR, 0x0d

prepare_pcm:
	# Use the next DMA page when the double buffer would cross a 64 KiB boundary.
	mov ax, ds
	movzx ecx, ax
	shl ecx, 4
	lea eax, [ecx + frame_data + MAX_FRAME]
	movzx edx, ax
	movzx ebx, word ptr [pcm_bytes + ORIGIN]
	lea edx, [edx + ebx * 2]
	cmp edx, 0x10000
	jbe dma_address_ready
	add eax, 0xffff
	and eax, 0xffff0000
dma_address_ready:
	mov [dma_address + ORIGIN], ax
	sub eax, ecx
	mov [pcm_base + ORIGIN], ax
	mov [pcm_slot + ORIGIN], ax
	add eax, ecx
	shr eax, 16
	mov [dma_page + ORIGIN], al
	push es
	push ds
	pop es
	mov di, [pcm_base + ORIGIN]
	mov cx, [pcm_bytes + ORIGIN]
	shl cx, 1
	mov al, 0x80
	cld
	rep stosb
	pop es

	mov dx, 0x226
	mov al, 1
	out dx, al
	# Allow the original card time to assert reset before removing it.
	.rept 8
		in al, dx
	.endr
	xor al, al
	out dx, al
	mov dx, 0x22e
	mov cx, 0x2000
probe_status:
	in al, dx
	test al, 0x80
	jnz probe_response
	loop probe_status
	ret
probe_response:
	mov dx, 0x22a
	in al, dx
	cmp al, 0xaa
	jne prepare_done
	mov byte ptr [dsp_found + ORIGIN], 1
prepare_done:
	ret

start_pcm:
	mov ax, 0x3500 + DSP_IRQ_VECTOR
	int 0x21
	mov [old_irq + ORIGIN], bx
	mov [old_irq + ORIGIN + 2], es
	mov ax, 0x2500 + DSP_IRQ_VECTOR
	mov dx, offset dsp_interrupt + ORIGIN
	int 0x21
	in al, 0x21
	mov [old_mask + ORIGIN], al
	and al, 0xdf
	out 0x21, al

	mov al, 5
	out 0x0a, al             # Mask channel 1 during programming.
	out 0x0c, al             # Reset the address/count byte selector.
	mov ax, [dma_address + ORIGIN]
	out 0x02, al
	mov al, ah
	out 0x02, al
	mov al, [dma_page + ORIGIN]
	out 0x83, al
	mov ax, [pcm_bytes + ORIGIN]
	shl ax, 1
	dec ax
	out 0x03, al
	mov al, ah
	out 0x03, al
	mov al, 0x59             # Single transfer, auto-init, memory to device, channel 1.
	out 0x0b, al
	mov al, 1
	out 0x0a, al

	mov al, 0xd1
	call dsp_write
	mov al, 0x40
	call dsp_write
	mov al, [time_constant + ORIGIN]
	call dsp_write
	mov al, 0x48
	call dsp_write
	mov ax, [pcm_bytes + ORIGIN]
	dec ax
	call dsp_write
	mov al, ah
	call dsp_write
	mov byte ptr [pcm_started + ORIGIN], 1
	mov al, 0x1c             # Each DMA block raises IRQ 5.
	call dsp_write
	ret

stop_pcm:
	cmp byte ptr [pcm_started + ORIGIN], 0
	je pcm_stopped
	mov al, 0xd0
	call dsp_write
	mov al, 0xd3
	call dsp_write
	mov dx, 0x22e
	in al, dx
	mov al, 5
	out 0x0a, al
	in al, 0x21
	and al, 0xdf
	mov ah, [old_mask + ORIGIN]
	and ah, 0x20
	or al, ah
	out 0x21, al
	push ds
	lds dx, [old_irq + ORIGIN]
	mov ax, 0x2500 + DSP_IRQ_VECTOR
	int 0x21
	pop ds
	mov byte ptr [pcm_started + ORIGIN], 0
pcm_stopped:
	ret

dsp_interrupt:
	push ax
	push dx
	push ds
	push cs
	pop ds
	mov dx, 0x22e
	in al, dx
	inc word ptr [completed_blocks + ORIGIN]
	mov al, 0x20
	out 0x20, al
	pop ds
	pop dx
	pop ax
	iret

dsp_write:
	push ax
	push dx
	mov ah, al
	mov dx, 0x22c
dsp_busy:
	in al, dx
	test al, 0x80
	jnz dsp_busy
	mov al, ah
	out dx, al
	pop dx
	pop ax
	ret

pcm_bytes: .word 0
time_constant: .byte 0
pcm_base: .word 0
pcm_slot: .word 0
dma_address: .word 0
dma_page: .byte 0
old_irq: .long 0
old_mask: .byte 0
pcm_started: .byte 0
dsp_found: .byte 0
completed_blocks: .word 0
shown_frames: .word 0
