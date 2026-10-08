; SPDX-License-Identifier: MIT
; Assembled with `nasm -f bin`; the bytes are in scripts/smoke_test_system.sh (balloon boot sector).
; Boot sector: inflate 1 MiB of guest RAM through a legacy virtio-balloon (PCI, I/O BAR)
        bits 16
        org 0x7c00
        cli
        xor ax, ax
        mov ds, ax
        mov ss, ax
        mov sp, 0x7000
        ; find the balloon (1af4:1002) on bus 0
        xor bx, bx                      ; bx = device number
find:   mov eax, ebx
        shl eax, 11
        or eax, 0x80000000
        mov dx, 0xcf8
        out dx, eax
        mov dx, 0xcfc
        in eax, dx
        cmp eax, 0x10021af4
        je found
        inc bx
        cmp bx, 32
        jb find
        hlt
found:  mov eax, ebx
        shl eax, 11
        or eax, 0x80000010              ; BAR0
        mov dx, 0xcf8
        out dx, eax
        mov dx, 0xcfc
        in eax, dx
        and ax, 0xfffc
        mov si, ax                      ; si = I/O base
        mov eax, ebx
        shl eax, 11
        or eax, 0x80000004              ; command: I/O, memory, bus master
        mov dx, 0xcf8
        out dx, eax
        mov dx, 0xcfc
        mov ax, 7
        out dx, ax
        ; queue 0 (inflate) at 0x20000: descriptors, available ring, used ring at +0x1000
        mov ax, 0x2000
        mov es, ax
        xor di, di
        xor ax, ax
        mov cx, 0x1800
        cld
        rep stosw                       ; zero 0x20000-0x22fff
        mov dword [es:0], 0x22000       ; descriptor 0: buffer address
        mov dword [es:8], 1024          ; 256 page numbers
        mov word [es:0x802], 1          ; available ring: one entry (descriptor 0)
        ; page numbers 0x400-0x4ff (4-5 MiB)
        mov di, 0x2000
        mov eax, 0x400
fill:   mov [es:di], eax
        add di, 4
        inc eax
        cmp eax, 0x500
        jb fill
        lea dx, [si + 0x0e]
        xor ax, ax
        out dx, ax                      ; queue select 0
        lea dx, [si + 0x08]
        mov eax, 0x20
        out dx, eax                     ; queue page frame number
        lea dx, [si + 0x12]
        mov al, 7                       ; acknowledge, driver, driver ok
        out dx, al
        lea dx, [si + 0x10]
        xor ax, ax
        out dx, ax                      ; notify queue 0
poll:   cmp word [es:0x1002], 0         ; used ring index
        je poll
        lea dx, [si + 0x18]
        mov eax, 0x100
        out dx, eax                     ; config: 256 pages are now in the balloon
        mov si, msg
say:    lodsb
        test al, al
        jz done
        mov ah, al
        mov dx, 0x3fd
spin:   in al, dx
        test al, 0x20
        jz spin
        mov dx, 0x3f8
        mov al, ah
        out dx, al
        jmp say
done:   hlt
        jmp done
msg:    db 'BALLOON-INFLATED', 13, 10, 0
        times 510 - ($ - $$) db 0
        dw 0xaa55
