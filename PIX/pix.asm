extern pixtime

global pix

section .text

; DESCRIPTION
; Computes a / b, where a is 128-bit and b is 64-bit. Remainder is ignored. Result is saved in rdx:rax.
; ARGUMENTS (on the stack):
; first 32 bits of a, last 32 bits of a, b
; MODIFIES REGISTERS:
; rax, rdx, rcx
div128: 
  xor     rax, rax
  mov     rax, qword [rsp + 8]
  xor     rdx, rdx
  div     qword [rsp + 24]
  mov     rcx, rax

  mov     rax, qword [rsp + 16]
  div     qword [rsp + 24]
  mov     rdx, rcx
  ret     


; DESCRIPTION
; Computes (16 ^ pow) % mod in O(log(pow)). Result is saved in rax.
; ARGUMENTS (on the stack):
; pow, mod
; MODIFIES REGISTERS:
; rdx, rax
get16Pow:
  cmp     qword [rsp + 8], 0         ; If pow == 0, return 1
  je      _get16Pow_ret1

  mov     rdx, qword [rsp + 8]       ; Save pow / 2 in rdx
  shr     rdx, 1

  push    qword [rsp + 16]           ; Save (16 ^ (pow / 2)) % mod in rax
  push    rdx
  call    get16Pow
  add     rsp, 16

  xor     rdx, rdx                   ; Save (rax ^ 2) % mod in rax
  mul     rax
  div     qword [rsp + 16]
  mov     rax, rdx

  mov     rdx, qword [rsp + 8]       ; If pow % 2 == 0, then end
  and     rdx, 1
  je      _get16Pow_end
  mov     rdx, rax                   ; Otherwise multiply by 16 and get modulo
  shr     rdx, 28
  shl     rax, 4
  div     qword [rsp + 16]
  mov     rax, rdx                   ; Save the result in rax
  ret     

_get16Pow_ret1:
  mov     rax, 1                     ; Return 1
_get16Pow_end:
  ret     


; DESCRIPTION
; Computes Sj for some n. Result is saved in rax.
; ARGUMENTS (on the stack):
; n, j
; MODIFIES REGISTERS:
; r8, rcx, rdi, rsi, rdx, rax
getSj:
  xor     r8, r8                     ; Set the result to 0
  mov     rcx, 0                     ; Set rcx as k = 0
_getSj_loop1:
  mov     rax, rcx                   ; Save 8k + j in rdi
  mov     rdi, 8
  mul     rdi
  mov     rdi, rax
  add     rdi, qword [rsp + 16]

  mov     rsi, qword [rsp + 8]       ; Save n - k in rsi
  sub     rsi, rcx

  push    rdi                        ; Get 16^(n - k) mod (8k + j)
  push    rsi
  call    get16Pow
  mov     rdx, rax                   ; Save result in rdx
  add     rsp, 16


  push    rcx                        ; Divide the result by (8k + j)
  push    rdi
  push    qword 0
  push    rdx
  call    div128
  add     rsp, 24
  pop     rcx

  add     r8, rax                    ; Add the result to r8

  add     rcx, 1
  cmp     rcx, qword [rsp + 8]       ; Repeat if k <= n
  jle     _getSj_loop1


  mov     rsi, 1                     ; Save {16 ^ (-1)} in rsi
  shl     rsi, 60
  mov     rcx, qword [rsp + 8]       ; Set rcx as k = n + 1
  add     rcx, 1

_getSj_loop2:
  mov     rax, rcx                   ; Save 8k + j in rdi
  mov     edi, 8
  mul     edi
  mov     rdi, rax
  add     rdi, qword [rsp + 16]

  xor     rdx, rdx                   ; Save {16 ^ (n - k) / (8k + j)} in rax
  mov     rax, rsi
  div     rdi

  add     r8, rax                    ; Add rax to the result
  cmp     rax, 0                     ; If added 0, then end
  je      _getSj_loop2_end

  mov     rdi, 16                    ; Save {16 ^ (n - k - 1)} in rsi
  xor     rdx, rdx
  mov     rax, rsi
  div     rdi
  mov     rsi, rax

  add     rcx, 1                     ; Increment k and repeat
  jmp     _getSj_loop2

_getSj_loop2_end:
  mov     rax, r8                    ; Save the result in rax
  ret     


; DESCRIPTION
; Computes digits of pi. Result is saved in rax.
; ARGUMENTS (on the stack):
; n
; MODIFIES REGISTERS:
; r8, rcx, rdi, rsi, rdx, rax
getPi:
  push    qword 1                    ; Get Sj for j = 1
  push    qword [rsp + 16]
  call    getSj
  xor     rdx, rdx
  mov     rdi, 4
  mul     rdi
  mov     r9, rax

  mov     qword [rsp + 8], 4         ; Get Sj for j = 4
  call    getSj
  xor     rdx, rdx
  mov     rdi, 2
  mul     rdi
  sub     r9, rax

  mov     qword [rsp + 8], 5         ; Get Sj for j = 5
  call    getSj
  sub     r9, rax

  mov     qword [rsp + 8], 6         ; Get Sj for j = 6
  call    getSj
  sub     r9, rax
  add     rsp, 16
  mov     rax, r9
  ret     


; DESCRIPTION
; Calls pixtime.
; ARGUMENTS
; None
; MODIFIES REGISTERS:
; rax
%macro time 0
  push    rdi
  push    rsi
  push    rdx
  xor     rax, rax
  rdtsc   
  shl     rdx, 32
  add     rax, rdx
  mov     rdi, rax
  call    pixtime

  pop     rdx
  pop     rsi
  pop     rdi
%endmacro


pix:
  time                               ; Call pixtime

_main_loop:
  mov     rax, 1                     ; Get next index
  lock \
  xadd    qword [rsi], rax
  cmp     rax, rdx
  jge     _pix_end

  push    rax
  push    rdi
  push    rsi
  push    rdx

  xor     rdx, rdx                   ; Get a value for the index
  mov     rdi, 8
  mul     rdi
  push    rax
  call    getPi
  shr     rax, 32
  mov     r8, rax
  add     rsp, 8

  pop     rdx
  pop     rsi
  pop     rdi
  pop     rax

  mov     dword [rdi + rax * 4], r8d ; Save the result

  jmp     _main_loop

_pix_end:
  time                               ; Call pixtime
  ret     