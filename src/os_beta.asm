; Demo OS Beta
BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov ax, 0x0003
    int 0x10

    mov si, banner
    call print

.hang:
    hlt
    jmp .hang

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

banner:
    db 13, 10
    db "################################", 13, 10
    db "#   DEMO OS BETA is running    #", 13, 10
    db "#   Selected from boot menu    #", 13, 10
    db "################################", 13, 10
    db 0

times 510-($-$$) db 0
dw 0xAA55
