; =============================================================================
; Stage 1 — MBR (512 байт). Загружает Stage 2 с диска и передаёт управление.
; =============================================================================
BITS 16
ORG 0x7C00

STAGE2_SEG      equ 0x0000
STAGE2_OFF      equ 0x8000
STAGE2_LBA      equ 1
STAGE2_SECTORS  equ 64          ; 32 КБ

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Сохранить номер загрузочного диска (BIOS передаёт в DL)
    mov [boot_drive], dl

    mov si, msg_loading
    call print

    ; Читаем Stage 2 через INT 13h Extended Read (LBA)
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, dap
    int 0x13
    jc disk_error

    mov dl, [boot_drive]
    jmp STAGE2_SEG:STAGE2_OFF

disk_error:
    mov si, msg_disk_err
    call print
.hang:
    hlt
    jmp .hang

; -----------------------------------------------------------------------------
print:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0
    int 0x10
    jmp print
.done:
    ret

; -----------------------------------------------------------------------------
boot_drive: db 0

align 4
dap:
    db 0x10                 ; размер DAP
    db 0
    dw STAGE2_SECTORS       ; число секторов
    dw STAGE2_OFF           ; offset буфера
    dw STAGE2_SEG           ; segment буфера
    dq STAGE2_LBA           ; LBA начала Stage 2

msg_loading:  db "Loader: reading stage2...", 13, 10, 0
msg_disk_err: db "Disk read error!", 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55
