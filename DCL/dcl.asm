SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60
STDIN equ 0
STDOUT equ 1

section .bss

L: resb 42
R: resb 42
T: resb 42
revL: resb 42
revR: resb 42
appeared: resb 42
input:    resb 7000
posL: resb 1
posR: resb 1

section .text
global _start

; DESCRIPTION
; Checks if a letter is correct and has never appeared.
; ARGUMENTS
; %1 - an address to the letter
; MODIFIES REGISTERS:
; r10, r11, r12
%macro checkChar 1
  mov       r10, %1                     ; Check if a letter is 0 or in the interval [49, 90]
  mov       r12, 1
  call      _checkASCII

  cmp       byte [%1], 0                ; Ignore 0
  je        %%end
  mov       r11b, 1
  cmp       byte [appeared + r10], r11b ; Check if a letter has already appeared
  je        _error
  mov       byte [appeared + r10], r11b ; Remember that the letter has appeared
%%end:
%endmacro


; DESCRIPTION:
; Creates reversed permutation.
; ARGUMENTS:
; %1 - an address to the original permutation
; %2 - an address where the reversed permutation should be stored
; MODIFIES REGISTERS:
; rcx, r8
%macro getRev 2
  xor       rcx, rcx                    ; Set counter to 0
%%loop:
  movzx     r8, byte [%1 + rcx]         ; Save the next letter in r8
  sub       r8, 49
  add       rcx, 49
  mov       byte [%2 + r8], cl          ; Save that letter
  sub       rcx, 48
  cmp       rcx, 42                     ; Exit the loop if all 42 letters has been visited
  jne       %%loop
%endmacro


; DESCRIPTION:
; Changes a letter according to a Q permutation and saves it in rax.
; ARGUMENTS:
; %1 - if set to -1, Q is reversed. If set to 1, Q is not reversed
; %2 - an address to the argument of Q
; %3 - the letter
; MODIFIES REGISTERS:
; rax, r8
%macro Q 3
  movzx     r8, byte [%2]
  sub       r8, 49
  imul      r8, %1
  mov       rax, %3
  add       rax, r8
  cmp       rax, 90
  jg        %%too_big
  cmp       rax, 49
  jl        %%too_small
  jmp       %%end

%%too_big:
  sub       rax, 42
  jmp       %%end

%%too_small:
  add       rax, 42

%%end:
%endmacro


; DESCRIPTION:
; Changes a letter according to a permutation and saves it in rax.
; ARGUMENTS:
; %1 - an address to the permutation
; %2 - the letter
; MODIFIES REGISTERS:
; rax, r9
%macro perm 2
  mov       r9, %2
  sub       r9, 49
  movzx     rax, byte [%1 + r9]
%endmacro


; DESCRIPTION:
; Get L and R positions.
; ARGUMENTS:
; None
; MODIFIES REGISTERS:
; r8, r9, r10, r12
%macro getPos 0
  pop       r8                          ; Get the argument

  mov       r10, r8                     ; Check if the first letter is correct
  mov       r12, 0
  call      _checkASCII

  mov       r9, [r8]                    ; Save the first letter to posL
  mov       byte [posL], r9b

  add       r8, 1                       ; Move to the next letter

  mov       r10, r8                     ; Check if the second letter is correct
  mov       r12, 0
  call      _checkASCII

  mov       r9, [r8]                    ; Save the second letter to posR
  mov       byte [posR], r9b

  add       r8, 1                       ; Move to the next letter
  cmp       byte [r8], 0                ; Error if it's not 0
  jne       _error
%endmacro


; DESCRIPTION
; Checks if T consists of cycles of length 2.
; ARGUMENTS
; None
; MODIFIES REGISTERS:
; rax, r9, r10
%macro checkT 0
  mov       rcx, 49
%%loop:
  perm      T, rcx
  cmp       rax, rcx
  je        _error

  mov       r9, T
  mov       r10, 0
  perm      T, rax
  cmp       rcx, rax
  jne       _error

  add       rcx, 1
  cmp       rcx, 90
  jle       %%loop
%endmacro


; DESCRIPTION
; Checks if a letter's ASCII number is in the interval [49, 90].
; ARGUMENTS
; r10 - an address to the letter
; r12 - if set to 1, letter 0 is allowed
; MODIFIES REGISTERS:
; r10
_checkASCII:
  mov       r10, [r10]
  movzx     r10, r10b
  cmp       r10, 0                      ; Check if r10 == 0
  je        _checkASCII_zero
  sub       r10, 49
  cmp       r10, 0                      ; Check if r10 >= 49
  jl        _error
  cmp       r10, 41                     ; Check if r10 <= 90
  jg        _error
  jmp       _checkASCII_done
_checkASCII_zero:
  cmp       r12, 0                      ; If r12 == 0, exit with error
  je        _error
_checkASCII_done:
  ret       


; DESCRIPTION:
; Saves a permutation and checks if it's correct.
; ARGUMENTS:
; r13 - an address where the argument ahould be stored
; MODIFIES REGISTERS:
; rcx, r8, r9, r10, r11, r12
_getArg:
  xor       rcx, rcx                    ; Set counter to 0
_getArg_zero:                           ; Fill appeared with 0
  mov       byte [appeared + rcx], 0    ; Save 0 in an address
  add       rcx, 1
  cmp       rcx, 43                     ; Exit the loop if rcx == 43
  jne       _getArg_zero

  pop       rcx                         ; Save top of the stack and set string beginning in r8
  pop       r8
  push      rcx
  xor       rcx, rcx                    ; Set counter to 0
_getArg_loop:
  checkChar r8                          ; Check if the letter is correct and has never appeared
  mov       r9, [r8]

  cmp       r9b, 0                      ; Exit the loop if the letter is 0
  je        _getArg_end

  mov       byte [r13 + rcx], r9b       ; Save the letter

  add       rcx, 1                      ; Move to the next letter
  add       r8, 1
  jmp       _getArg_loop
_getArg_end:
  cmp       rcx, 42                     ; Error if the permutation doesn't have 42 letters
  jne       _error
  ret       


; DESCRIPTION:
; Updates posL and posR.
; ARGUMENTS:
; r10 - an address to the current position
; r8 - the current position
; r9 - if set to 1, the posR is rotated, otherwise posL is rotated
; MODIFIES REGISTERS:
; r8, r9
_rotate:
  add       r8b, 1                      ; Update the letter
  cmp       r8b, 90                     ; If the letter is greater than 90 then substract 42 from it
  jle       _rotate_endif
  sub       r8b, 42
_rotate_endif:
  mov       byte [r10], r8b             ; Save the updated letter
  cmp       r9, 1                       ; End if posL is rotated
  jne       _rotate_end
  cmp       r8b, 76                     ; Otherwise if the letter is equal to 'L', 'R' or 'T', rotate posL
  je        _rotate_rotateL
  cmp       r8b, 82
  je        _rotate_rotateL
  cmp       r8b, 84
  je        _rotate_rotateL
  jmp       _rotate_end

_rotate_rotateL:
  mov       r10, posL                   ; Rotate posL
  mov       r8b, byte [posL]
  mov       r9, 0
  call      _rotate
_rotate_end:
  ret       


_start:
  pop       rax                         ; Check the number of arguments
  cmp       rax, 5
  jl        _error
  pop       rax

  mov       r13, L                      ; Get the permutations
  call      _getArg

  mov       r13, R
  call      _getArg

  mov       r13, T
  call      _getArg

  checkT    

  getRev    L, revL                     ; Create reversed permutations
  getRev    R, revR

  checkT    

  getPos                                ; Get posL and posR

  jmp       _loop1                      ; Start reading from stdin

_out:
  mov       rax, SYS_WRITE              ; Write the encrypted part of input
  mov       rdi, STDOUT
  mov       rsi, input
  mov       rdx, r14
  syscall   

_loop1:
  mov       rax, SYS_READ               ; Read the next 7000 letters
  mov       rdi, STDIN
  mov       rsi, input
  mov       rdx, 7000
  syscall   

  mov       r15, input                  ; Set r15 to the beginning of input
  mov       r14, 0                      ; Set the counter to 0

_loop2:
  cmp       byte [r15], 0               ; End successfully if the letter is 0
  je        _ok

  mov       r10, r15                    ; Check if the letter is correct
  mov       r12, 0
  call      _checkASCII

  movzx     rax, byte [r15]             ; Set rax to the current letter

  mov       r10, posR                   ; Update posR and posL
  mov       r8b, byte [posR]
  mov       r9, 1
  call      _rotate

  Q         1, posR, rax                ; Make permutations
  perm      R, rax
  Q         -1, posR, rax
  Q         1, posL, rax
  perm      L, rax
  Q         -1, posL, rax
  perm      T, rax
  Q         1, posL, rax
  perm      revL, rax
  Q         -1, posL, rax
  Q         1, posR, rax
  perm      revR, rax
  Q         -1, posR, rax

  mov       byte [r15], al              ; Save the letter
  add       r15, 1
  add       r14, 1

  cmp       r14, 7000                   ; If all 7000 letters has been visited, write the result
                                        ; and read another 100 letters
  je        _out

  jmp       _loop2                      ; Otherwise move to the next letter

  mov       edi, 0                      ; Exit successfully
  call      _exit

_error:
  mov       edi, 1
  jmp       _exit

_ok:
  mov       rax, SYS_WRITE              ; Write the remaining results
  mov       rdi, STDOUT
  mov       rsi, input
  mov       rdx, r14
  syscall   

  mov       edi, 0                      ; Exit successfully

_exit:
  mov       eax, SYS_EXIT
  syscall   