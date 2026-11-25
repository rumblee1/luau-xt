# Play a monochrome VGA clip streamed from DOS.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.set MAX_FRAME, 128 * 80 * 4
.set PCM_BYTES_V2, 879
.set PCM_BYTES_V3, 2197
.text

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
	lea dx, [si - 1]
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
	jc open_error
	mov [handle + ORIGIN], ax

	mov cx, 6
	call read
	jc invalid_header
	cmp ax, 6
	jne invalid_header
	cmp dword ptr [frame_data], 0x314c4356  # VCL1
	je read_interval
	cmp dword ptr [frame_data], 0x324c4356  # VCL2
	je pcm_v2
	cmp dword ptr [frame_data], 0x334c4356  # VCL3
	jne invalid_header
	mov word ptr [pcm_bytes + ORIGIN], PCM_BYTES_V3
	mov byte ptr [time_constant + ORIGIN], 206  # 20 kHz
	jmp check_pcm_header
pcm_v2:
	mov word ptr [pcm_bytes + ORIGIN], PCM_BYTES_V2
	mov byte ptr [time_constant + ORIGIN], 131  # 8 kHz
check_pcm_header:
	mov byte ptr [has_pcm + ORIGIN], 1
	cmp word ptr [frame_data + 4], 2
	jne invalid_header
read_interval:
	mov ax, [frame_data + 4]
	test ax, ax
	jz invalid_header
	cmp ax, 18
	ja invalid_header
	mov [interval + ORIGIN], ax
	cmp byte ptr [has_pcm + ORIGIN], 0
	je set_mode
	call prepare_pcm
set_mode:
	mov ax, 0x0013
	int 0x10
	mov dx, 0x3c8
	xor al, al
	out dx, al
	inc dx
	out dx, al
	out dx, al
	out dx, al
	mov al, 63
	out dx, al
	out dx, al
	out dx, al
	xor ax, ax
	mov fs, ax
	mov ax, fs:[0x046c]
	mov [frame_start + ORIGIN], ax

next_frame:
	mov cx, 2
	call read
	jc invalid_frame
	test ax, ax
	jz end_of_file
	cmp ax, 2
	jne invalid_frame
	mov cx, [frame_data]
	test cx, 3
	jnz invalid_frame
	cmp cx, MAX_FRAME
	ja invalid_frame
	mov [span_bytes + ORIGIN], cx
	jcxz read_pcm
	push cx
	call read
	pop cx
	jc invalid_frame
	cmp ax, cx
	jne invalid_frame
read_pcm:
	cmp byte ptr [has_pcm + ORIGIN], 0
	je begin_spans
	mov dx, [pcm_slot + ORIGIN]
	mov bx, [handle + ORIGIN]
	mov cx, [pcm_bytes + ORIGIN]
	mov ah, 0x3f
	int 0x21
	jc invalid_frame
	cmp ax, [pcm_bytes + ORIGIN]
	jne invalid_frame
	call wait_for_pcm
begin_spans:
	mov cx, [span_bytes + ORIGIN]
	jcxz display_frame
	mov ax, 0xa000
	mov es, ax
	mov si, offset frame_data
	mov bx, si
	add bx, cx
	cld

draw_span:
	lodsw
	mov di, ax
	test di, 1
	jnz invalid_frame
	lodsw
	mov dx, ax
	and ax, 0x7fff
	jz invalid_frame
	cmp ax, 128
	ja invalid_frame
	mov cx, ax
	shl ax, 1
	add ax, di
	jc invalid_frame
	cmp ax, 64000 - 320
	ja invalid_frame
	shl dx, 1
	sbb ax, ax
	and ax, 0x0101
	push di
	mov dx, cx
	rep stosw
	pop di
	add di, 320
	mov cx, dx
	rep stosw
	cmp si, bx
	jb draw_span

display_frame:
	cmp byte ptr [dsp_found + ORIGIN], 0
	je wait_frame
	cmp byte ptr [pcm_started + ORIGIN], 0
	jne pcm_ready
	call start_pcm
pcm_ready:
	inc word ptr [shown_frames + ORIGIN]
	mov ax, [pcm_base + ORIGIN]
	add ax, [pcm_bytes + ORIGIN]
	cmp [pcm_slot + ORIGIN], ax
	jne select_pcm_slot
	sub ax, [pcm_bytes + ORIGIN]
select_pcm_slot:
	mov [pcm_slot + ORIGIN], ax
	jmp next_frame

wait_frame:
	call check_escape
	mov ax, fs:[0x046c]
	sub ax, [frame_start + ORIGIN]
	cmp ax, [interval + ORIGIN]
	jae advance_frame
	hlt
	jmp wait_frame
advance_frame:
	mov ax, fs:[0x046c]
	mov [frame_start + ORIGIN], ax
	jmp next_frame

end_of_file:
	call wait_for_pcm
finish:
	call restore_text
	mov ax, 0x4c00
	int 0x21
invalid_frame:
	call restore_text
	jmp clip_error
invalid_header:
	call close_file
clip_error:
	mov dx, offset invalid + ORIGIN
	jmp fail
open_error:
	mov dx, offset usage + ORIGIN
	jmp fail
needs_vga:
	mov dx, offset requires_vga + ORIGIN
fail:
	mov ah, 9
	int 0x21
	mov ax, 0x4c01
	int 0x21

restore_text:
	call stop_pcm
	mov ax, 0x0003
	int 0x10
close_file:
	mov bx, [handle + ORIGIN]
	mov ah, 0x3e
	int 0x21
	ret
read:
	mov dx, offset frame_data
	mov bx, [handle + ORIGIN]
	mov ah, 0x3f
	int 0x21
	ret

wait_for_pcm:
	cmp byte ptr [pcm_started + ORIGIN], 0
	je ready
	mov bp, fs:[0x046c]
wait_for_irq:
	call check_escape
	cli
	mov ax, [completed_blocks + ORIGIN]
	cmp ax, [shown_frames + ORIGIN]
	jae irq_ready
	mov ax, fs:[0x046c]
	sub ax, bp
	cmp ax, 18
	jae no_sound_irq
	sti
	hlt
	jmp wait_for_irq
no_sound_irq:
	sti
	call stop_pcm
	mov byte ptr [dsp_found + ORIGIN], 0
	mov ax, fs:[0x046c]
	mov [frame_start + ORIGIN], ax
	ret
irq_ready:
	sti
ready:
	ret

check_escape:
	mov ah, 1
	int 0x16
	jz keep_playing
	xor ah, ah
	int 0x16
	cmp al, 27
	je finish
keep_playing:
	ret

.include "vgaclip-audio.inc"

default_name: .asciz "DEMO.VCL"
usage: .ascii "Cannot open clip. Usage: VGACLIP [file.vcl]\r\n$"
invalid: .ascii "Invalid or truncated VGA clip.\r\n$"
requires_vga: .ascii "VGACLIP requires VGA.\r\n$"
handle: .word 0
interval: .word 0
frame_start: .word 0
span_bytes: .word 0
has_pcm: .byte 0
.set frame_data, . + ORIGIN   # DOS allocates the rest of the COM segment.
