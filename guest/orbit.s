# Fly through eight beacons while avoiding a moving sweeper.
.intel_syntax noprefix
.code16
.arch i386
.set ORIGIN, 0x100
.text
	jmp start
.include "vga-ui.inc"

start:
	call vga_start
	fill 8, 24, 304, 168, 1
	fill 10, 26, 300, 164, 0
	fill 12, 8, 124, 10, 1
	call draw_beacon
	call draw_ship
	call draw_sweeper

poll:
	mov ah, 1
	int 0x16
	jz timer
	call get_key
	cmp al, 27
	je vga_exit
	xor bx, bx
	xor dx, dx
	cmp ah, 0x4b
	je left
	cmp ah, 0x4d
	je right
	cmp ah, 0x48
	je up
	cmp ah, 0x50
	je down
	cmp al, ' '
	je set_heading
	jmp timer
left:
	mov bx, -3
	jmp set_heading
right:
	mov bx, 3
	jmp set_heading
up:
	mov dx, -3
	jmp set_heading
down:
	mov dx, 3
set_heading:
	mov [ship_dx + ORIGIN], bx
	mov [ship_dy + ORIGIN], dx

timer:
	mov ax, fs:[0x046c]
	cmp ax, [last_tick + ORIGIN]
	je sleep
	mov [last_tick + ORIGIN], ax
	call move_ship
	xor al, al
	call sweeper_rectangle
	add word ptr [sweeper_y + ORIGIN], 3
	cmp word ptr [sweeper_y + ORIGIN], 170
	jb check_collisions
	mov word ptr [sweeper_y + ORIGIN], 30

check_collisions:
	mov ax, [ship_x + ORIGIN]
	sub ax, 150
	add ax, 5
	cmp ax, 15
	ja check_beacon
	mov ax, [ship_y + ORIGIN]
	sub ax, [sweeper_y + ORIGIN]
	add ax, 5
	cmp ax, 21
	ja check_beacon
	mov dx, offset crashed + ORIGIN
	jmp vga_result

check_beacon:
	mov si, [beacon + ORIGIN]
	mov ax, [ship_x + ORIGIN]
	sub ax, [beacons + ORIGIN + si]
	add ax, 6
	cmp ax, 12
	ja draw_scene
	mov ax, [ship_y + ORIGIN]
	sub ax, [beacons + ORIGIN + si + 2]
	add ax, 6
	cmp ax, 12
	ja draw_scene
	xor al, al
	call beacon_rectangle
	shr si, 2
	imul di, si, 15
	add di, 10 * 320 + 14
	mov cx, 12
	mov bx, 6
	mov al, 5
	call rectangle
	add word ptr [beacon + ORIGIN], 4
	cmp word ptr [beacon + ORIGIN], beacons_end - beacons
	jb draw_scene
	mov dx, offset victory + ORIGIN
	jmp vga_result
draw_scene:
	call draw_beacon
	call draw_sweeper
	call draw_ship
sleep:
	hlt
	jmp poll

move_ship:
	mov bx, [ship_x + ORIGIN]
	add bx, [ship_dx + ORIGIN]
	cmp bx, 14
	jae check_right
	mov bx, 14
check_right:
	cmp bx, 299
	jbe next_y
	mov bx, 299
next_y:
	mov dx, [ship_y + ORIGIN]
	add dx, [ship_dy + ORIGIN]
	cmp dx, 28
	jae check_bottom
	mov dx, 28
check_bottom:
	cmp dx, 181
	jbe store_ship
	mov dx, 181
store_ship:
	xor al, al
	call ship_rectangle
	mov [ship_x + ORIGIN], bx
	mov [ship_y + ORIGIN], dx
	ret

draw_ship:
	mov al, 4
ship_rectangle:
	pusha
	imul di, [ship_y + ORIGIN], 320
	add di, [ship_x + ORIGIN]
	mov cx, 7
	mov bx, 7
	call rectangle
	popa
	ret

draw_beacon:
	mov al, 6
beacon_rectangle:
	pusha
	mov si, [beacon + ORIGIN]
	imul di, [beacons + ORIGIN + si + 2], 320
	add di, [beacons + ORIGIN + si]
	mov cx, 7
	mov bx, 7
	call rectangle
	popa
	ret

draw_sweeper:
	mov al, 7
sweeper_rectangle:
	pusha
	imul di, [sweeper_y + ORIGIN], 320
	add di, 150
	mov cx, 11
	mov bx, 17
	call rectangle
	popa
	ret

ship_x: .word 36
ship_y: .word 100
ship_dx: .word 0
ship_dy: .word 0
sweeper_y: .word 46
last_tick: .word 0
beacon: .word 0
beacons: .word 66, 100, 92, 48, 125, 128, 200, 132, 268, 158, 270, 58, 214, 86, 58, 148
beacons_end:
victory: .ascii "Orbit Relay: all eight beacons recovered.\r\n$"
crashed: .ascii "Orbit Relay: sweeper collision. Run GAMES\\ORBIT to retry.\r\n$"
