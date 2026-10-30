; =============================================================================
; Stage 2 — Space Invaders (60 сек) → пароль → меню ОС → chainload
; Загружается по адресу 0x8000, размер до 64 секторов.
; =============================================================================
BITS 16
ORG 0x8000

PASSWORD_LBA    equ 65
PASSWORD_MAX    equ 16
OS1_LBA         equ 100
OS2_LBA         equ 200
OS3_LBA         equ 300
TICKS_PER_SEC   equ 18          ; ≈18.2, округляем
GAME_SECONDS    equ 60

; --- layout экрана игры (текст 80x25) ---
INV_ROWS        equ 4
INV_COLS        equ 8
INV_START_ROW   equ 2
INV_START_COL   equ 10
PLAYER_ROW      equ 22
BULLET_NONE     equ 0xFF

start:
    ; DL = boot drive (передан из Stage 1)
    mov [boot_drive], dl

    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    call set_text_mode
    call play_invaders
    call ask_password
    call show_os_menu
    ; не возвращаемся

; =============================================================================
; Видео / вывод
; =============================================================================
set_text_mode:
    mov ax, 0x0003
    int 0x10
    ret

cls:
    pusha
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    xor dx, dx
    call set_cursor
    popa
    ret

set_cursor:
    ; DH=row, DL=col
    mov ah, 0x02
    mov bh, 0
    int 0x10
    ret

putchar:
    ; AL = char, BL = attr (ignored in teletype except page)
    mov ah, 0x0E
    mov bh, 0
    int 0x10
    ret

print:
    lodsb
    test al, al
    jz .done
    call putchar
    jmp print
.done:
    ret

print_at:
    ; SI=string, DH=row, DL=col
    push dx
    call set_cursor
    pop dx
    call print
    ret

; Пишет символ в видеопамять напрямую (быстрее для игры)
; DH=row, DL=col, AL=char, BL=attr
poke_char:
    push es
    push ax
    push bx
    push dx
    mov ax, 0xB800
    mov es, ax
    ; offset = (row*80 + col) * 2
    xor ax, ax
    mov al, dh
    mov bh, 80
    mul bh              ; AX = row*80
    xor bh, bh
    mov bl, dl
    add ax, bx
    shl ax, 1
    mov di, ax
    pop dx
    pop bx
    pop ax
    mov [es:di], al
    mov [es:di+1], bl
    pop es
    ret

; Читает символ из видеопамяти → AL
peek_char:
    push es
    push bx
    push dx
    mov ax, 0xB800
    mov es, ax
    xor ax, ax
    mov al, dh
    mov bh, 80
    mul bh
    xor bh, bh
    mov bl, dl
    add ax, bx
    shl ax, 1
    mov di, ax
    mov al, [es:di]
    pop dx
    pop bx
    pop es
    ret

; =============================================================================
; Таймер BIOS (тики ≈18.2 Гц)
; =============================================================================
get_ticks:
    ; → DX:AX = ticks (берём младшие 32 бита через CX:DX)
    push cx
    xor ah, ah
    int 0x1A
    mov ax, dx
    mov dx, cx
    pop cx
    ret

; =============================================================================
; SPACE INVADERS (упрощённая текстовая версия, ровно ~60 секунд)
; =============================================================================
play_invaders:
    call cls
    call init_game

    call get_ticks
    mov [game_start], ax
    mov [game_start+2], dx

.game_loop:
    call check_time_up
    jc .game_done

    call draw_hud
    call handle_input
    call update_bullet
    call update_invaders
    call draw_player
    call short_delay

    cmp byte [inv_alive], 0
    jne .game_loop

    ; все убиты — ждём оставшееся время или выходим
    jmp .game_loop

.game_done:
    call cls
    mov si, msg_game_over
    mov dh, 10
    mov dl, 20
    call print_at
    call wait_key
    ret

init_game:
    mov byte [player_col], 40
    mov byte [bullet_row], BULLET_NONE
    mov byte [inv_dir], 1
    mov byte [inv_anim], 0
    mov word [score], 0
    mov byte [inv_move_div], 0

    ; заполнить массив захватчиков: 1 = жив
    mov cx, INV_ROWS * INV_COLS
    mov di, invaders
    mov al, 1
    rep stosb
    mov byte [inv_alive], INV_ROWS * INV_COLS

    ; стартовая позиция блока
    mov byte [inv_base_row], INV_START_ROW
    mov byte [inv_base_col], INV_START_COL
    call draw_all_invaders
    ret

check_time_up:
    ; CF=1 если прошло >= 60 сек
    call get_ticks
    ; DX:AX = now
    mov bx, [game_start]
    mov cx, [game_start+2]
    sub ax, bx
    sbb dx, cx
    ; AX ≈ elapsed ticks (младшие 16 достаточно для 60 сек)
    cmp ax, GAME_SECONDS * TICKS_PER_SEC
    jae .up
    clc
    ret
.up:
    stc
    ret

seconds_left:
    ; → AX = секунд осталось
    call get_ticks
    mov bx, [game_start]
    mov cx, [game_start+2]
    sub ax, bx
    sbb dx, cx
    mov bx, TICKS_PER_SEC
    xor dx, dx
    div bx              ; AX = elapsed seconds
    mov bx, GAME_SECONDS
    sub bx, ax
    jnc .ok
    xor bx, bx
.ok:
    mov ax, bx
    ret

draw_hud:
    pusha
    mov si, msg_hud
    mov dh, 0
    mov dl, 0
    call print_at

    call seconds_left
    ; напечатать число в AH/AL просто через деление
    mov bl, 10
    div bl              ; AL=десятки, AH=единицы
    add al, '0'
    add ah, '0'
    mov [time_buf], al
    mov [time_buf+1], ah
    mov byte [time_buf+2], 0
    mov si, time_buf
    mov dh, 0
    mov dl, 14
    call print_at

    ; score
    mov ax, [score]
    call print_num_at_score
    popa
    ret

print_num_at_score:
    ; AX = score, печатаем в (0, 30)
    pusha
    mov cx, 0
    mov bx, 10
.cnv:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .cnv
    mov dh, 0
    mov dl, 30
    call set_cursor
.out:
    pop ax
    add al, '0'
    call putchar
    loop .out
    popa
    ret

handle_input:
    mov ah, 0x01
    int 0x16
    jz .none
    xor ah, ah
    int 0x16
    cmp al, 27          ; ESC — пропуск (для отладки оставляем запрещённым)
    ; движение
    cmp ah, 0x4B        ; Left
    je .left
    cmp ah, 0x4D        ; Right
    je .right
    cmp al, 'a'
    je .left
    cmp al, 'A'
    je .left
    cmp al, 'd'
    je .right
    cmp al, 'D'
    je .right
    cmp al, ' '
    je .shoot
    jmp .none
.left:
    cmp byte [player_col], 1
    jbe .none
    ; стереть старую позицию
    mov dh, PLAYER_ROW
    mov dl, [player_col]
    mov al, ' '
    mov bl, 0x07
    call poke_char
    dec byte [player_col]
    jmp .none
.right:
    cmp byte [player_col], 78
    jae .none
    mov dh, PLAYER_ROW
    mov dl, [player_col]
    mov al, ' '
    mov bl, 0x07
    call poke_char
    inc byte [player_col]
    jmp .none
.shoot:
    cmp byte [bullet_row], BULLET_NONE
    jne .none
    mov al, [player_col]
    mov [bullet_col], al
    mov byte [bullet_row], PLAYER_ROW - 1
.none:
    ret

draw_player:
    mov dh, PLAYER_ROW
    mov dl, [player_col]
    mov al, '^'
    mov bl, 0x0A
    call poke_char
    ret

update_bullet:
    cmp byte [bullet_row], BULLET_NONE
    je .done

    ; стереть
    mov dh, [bullet_row]
    mov dl, [bullet_col]
    mov al, ' '
    mov bl, 0x07
    call poke_char

    dec byte [bullet_row]
    cmp byte [bullet_row], 1
    jb .miss

    ; проверить попадание в захватчика
    call bullet_hit_test
    jc .hit

    ; нарисовать
    mov dh, [bullet_row]
    mov dl, [bullet_col]
    mov al, '|'
    mov bl, 0x0E
    call poke_char
    jmp .done
.hit:
.miss:
    mov byte [bullet_row], BULLET_NONE
.done:
    ret

bullet_hit_test:
    ; CF=1 если попали
    pusha
    mov cx, INV_ROWS * INV_COLS
    xor si, si
.check:
    cmp byte [invaders+si], 0
    je .next

    call inv_index_to_pos   ; → DH,DL позиция si-го
    cmp dh, [bullet_row]
    jne .next
    cmp dl, [bullet_col]
    jne .next

    ; попадание
    mov byte [invaders+si], 0
    dec byte [inv_alive]
    add word [score], 10
    mov al, ' '
    mov bl, 0x07
    call poke_char
    popa
    stc
    ret
.next:
    inc si
    loop .check
    popa
    clc
    ret

inv_index_to_pos:
    ; SI = index → DH=row, DL=col
    push ax
    push bx
    mov ax, si
    mov bl, INV_COLS
    div bl                  ; AL=row_idx, AH=col_idx
    mov bh, al
    mov bl, ah
    mov al, [inv_base_row]
    add al, bh
    add al, bh              ; row spacing = 2
    mov dh, al
    mov al, [inv_base_col]
    mov ah, bl
    shl ah, 2               ; col spacing = 4
    add al, ah
    mov dl, al
    pop bx
    pop ax
    ret

draw_all_invaders:
    pusha
    mov cx, INV_ROWS * INV_COLS
    xor si, si
.lp:
    call inv_index_to_pos
    cmp byte [invaders+si], 0
    je .erase
    mov al, 'W'
    mov bl, 0x0C
    jmp .put
.erase:
    mov al, ' '
    mov bl, 0x07
.put:
    call poke_char
    inc si
    loop .lp
    popa
    ret

update_invaders:
    ; замедленное движение
    inc byte [inv_move_div]
    cmp byte [inv_move_div], 8
    jb .done
    mov byte [inv_move_div], 0

    call erase_all_invaders

    mov al, [inv_dir]
    add [inv_base_col], al

    ; границы
    cmp byte [inv_base_col], 2
    ja .chk_right
    mov byte [inv_dir], 1
    inc byte [inv_base_row]
    jmp .redraw
.chk_right:
    ; правая граница ≈ start + cols*4
    mov al, [inv_base_col]
    add al, INV_COLS * 4
    cmp al, 76
    jb .redraw
    mov byte [inv_dir], -1
    inc byte [inv_base_row]
.redraw:
    ; если дошли до игрока — просто продолжаем (время всё равно кончится)
    call draw_all_invaders
.done:
    ret

erase_all_invaders:
    pusha
    mov cx, INV_ROWS * INV_COLS
    xor si, si
.lp:
    call inv_index_to_pos
    mov al, ' '
    mov bl, 0x07
    call poke_char
    inc si
    loop .lp
    popa
    ret

short_delay:
    pusha
    mov cx, 1
    mov dx, 0x5000
    mov ah, 0x86
    int 0x15            ; wait CX:DX микросекунд
    popa
    ret

wait_key:
    xor ah, ah
    int 0x16
    ret

; =============================================================================
; ПАРОЛЬ
; =============================================================================
ask_password:
.retry:
    call cls
    mov si, msg_pass_title
    mov dh, 8
    mov dl, 20
    call print_at
    mov si, msg_pass_prompt
    mov dh, 10
    mov dl, 20
    call print_at

    call load_password
    call read_password_input

    call compare_password
    jnc .ok

    mov si, msg_pass_bad
    mov dh, 12
    mov dl, 20
    call print_at
    call wait_key
    jmp .retry
.ok:
    mov si, msg_pass_ok
    mov dh, 12
    mov dl, 20
    call print_at
    call wait_key
    ret

load_password:
    ; читаем сектор PASSWORD_LBA в password_stored
    mov word [dap_pass+2], 1
    mov word [dap_pass+4], password_stored
    mov word [dap_pass+6], 0
    mov dword [dap_pass+8], PASSWORD_LBA
    mov dword [dap_pass+12], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, dap_pass
    int 0x13
    jc .use_default
    ; если сектор пуст (первый байт 0 или 0xFF) — дефолт
    mov al, [password_stored]
    test al, al
    jz .use_default
    cmp al, 0xFF
    je .use_default
    ret
.use_default:
    mov si, default_password
    mov di, password_stored
    mov cx, PASSWORD_MAX + 1
    rep movsb
    ret

read_password_input:
    mov di, password_input
    mov cx, PASSWORD_MAX
    xor bx, bx              ; длина
    mov dh, 10
    mov dl, 38
    call set_cursor
.read:
    xor ah, ah
    int 0x16
    cmp al, 13              ; Enter
    je .done
    cmp al, 8               ; Backspace
    je .bksp
    cmp al, 27
    je .done
    ; печатный?
    cmp al, 32
    jb .read
    cmp al, 126
    ja .read
    cmp bx, PASSWORD_MAX
    jae .read
    mov [di], al
    inc di
    inc bx
    mov al, '*'
    call putchar
    jmp .read
.bksp:
    test bx, bx
    jz .read
    dec di
    dec bx
    mov al, 8
    call putchar
    mov al, ' '
    call putchar
    mov al, 8
    call putchar
    jmp .read
.done:
    mov byte [di], 0
    mov [password_input_len], bl
    ret

compare_password:
    ; CF=0 если совпало
    mov si, password_stored
    mov di, password_input
.lp:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .bad
    test al, al
    jz .good
    inc si
    inc di
    jmp .lp
.good:
    clc
    ret
.bad:
    stc
    ret

; =============================================================================
; МЕНЮ ОС
; =============================================================================
show_os_menu:
.menu:
    call cls
    mov si, msg_menu_title
    mov dh, 6
    mov dl, 22
    call print_at
    mov si, msg_os1
    mov dh, 10
    mov dl, 22
    call print_at
    mov si, msg_os2
    mov dh, 12
    mov dl, 22
    call print_at
    mov si, msg_os3
    mov dh, 14
    mov dl, 22
    call print_at
    mov si, msg_menu_hint
    mov dh, 18
    mov dl, 18
    call print_at

.wait:
    xor ah, ah
    int 0x16
    cmp al, '1'
    je .boot1
    cmp al, '2'
    je .boot2
    cmp al, '3'
    je .boot3
    jmp .wait

.boot1:
    mov eax, OS1_LBA
    mov si, name_os1
    jmp chainload
.boot2:
    mov eax, OS2_LBA
    mov si, name_os2
    jmp chainload
.boot3:
    mov eax, OS3_LBA
    mov si, name_os3
    jmp chainload

; EAX = LBA загрузочного сектора ОС, SI = имя
chainload:
    push eax
    call cls
    mov dh, 10
    mov dl, 20
    call print_at          ; SI уже имя
    mov si, msg_booting
    mov dh, 12
    mov dl, 20
    call print_at
    pop eax

    ; читаем 1 сектор ОС в 0x7C00
    mov dword [dap_os+8], eax
    mov dword [dap_os+12], 0
    mov word [dap_os+2], 1
    mov word [dap_os+4], 0x7C00
    mov word [dap_os+6], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, dap_os
    int 0x13
    jc .fail

    ; стандартный «прыжок» как BIOS: DL = drive
    mov dl, [boot_drive]
    jmp 0x0000:0x7C00

.fail:
    mov si, msg_boot_fail
    mov dh, 14
    mov dl, 20
    call print_at
    call wait_key
    jmp show_os_menu

; =============================================================================
; Данные
; =============================================================================
boot_drive:         db 0
player_col:         db 40
bullet_row:         db BULLET_NONE
bullet_col:         db 0
inv_dir:            db 1
inv_anim:           db 0
inv_base_row:       db INV_START_ROW
inv_base_col:       db INV_START_COL
inv_alive:          db 0
inv_move_div:       db 0
score:              dw 0
game_start:         dd 0
password_input_len: db 0

invaders:           times INV_ROWS * INV_COLS db 0
password_stored:    times PASSWORD_MAX + 1 db 0
password_input:     times PASSWORD_MAX + 1 db 0
time_buf:           times 4 db 0

default_password:   db "secret", 0

align 4
dap_pass:
    db 0x10, 0
    dw 1
    dw 0, 0
    dq 0

align 4
dap_os:
    db 0x10, 0
    dw 1
    dw 0, 0
    dq 0

msg_hud:        db "Time left:    Score: ", 0
msg_game_over:  db "Time is up! Press any key...", 0
msg_pass_title: db "=== ACCESS CONTROL ===", 0
msg_pass_prompt:db "Password: ", 0
msg_pass_bad:   db "Wrong password! Try again.", 0
msg_pass_ok:    db "Access granted.", 0
msg_menu_title: db "=== SELECT OPERATING SYSTEM ===", 0
msg_os1:        db "1. Demo OS Alpha", 0
msg_os2:        db "2. Demo OS Beta", 0
msg_os3:        db "3. Demo OS Gamma", 0
msg_menu_hint:  db "Press 1, 2 or 3 to boot", 0
msg_booting:    db "Booting...", 0
msg_boot_fail:  db "Boot failed! Press a key.", 0
name_os1:       db "Loading Demo OS Alpha", 0
name_os2:       db "Loading Demo OS Beta", 0
name_os3:       db "Loading Demo OS Gamma", 0

; добиваем до 64 секторов (32768 байт)
times 32768-($-$$) db 0
