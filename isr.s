.section .text
.extern fault_handler
.extern canine_panic
.code64

.macro ISR_NOERR num
.global isr\num
isr\num:
  pushq $0                # fake error code for uniformity
  pushq $\num             # vector number
  jmp isr_common
.endm

.macro ISR_ERR num
.global isr\num
isr\num:
  # CPU already pushed the error code
  pushq $\num
  jmp isr_common
.endm


# Vectors 0-31
ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR   8        # #DF always has an error code (0)
ISR_NOERR 9
ISR_ERR   10
ISR_ERR   11
ISR_ERR   12
ISR_ERR   13
ISR_ERR   14       # #PF
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR   17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_ERR   21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_ERR   29
ISR_ERR   30
ISR_NOERR 31

.global
isr_common:
  # Save all GP registers so the Nim handler can't clobber them.
  pushq %rax
  pushq %rcx
  pushq %rdx
  pushq %rbx
  pushq %rbp
  pushq %rsi
  pushq %rdi
  pushq %r8
  pushq %r9
  pushq %r10
  pushq %r11
  pushq %r12
  pushq %r13
  pushq %r14
  pushq %r15

  # Call Nim handler with pointer to the saved frame in %rdi.
  movq %rsp, %rdi
  call fault_handler # returns 0 = resume, non-zero = panic

  testq %rax, %rax
  jnz   .hang

  popq %r15
  popq %r14
  popq %r13
  popq %r12
  popq %r11
  popq %r10
  popq %r9
  popq %r8
  popq %rdi
  popq %rsi
  popq %rbp
  popq %rbx
  popq %rdx
  popq %rcx
  popq %rax

  addq $16, %rsp  
  iretq

.hang:
  leaq err_msg(%rip), %rdi
  call canine_panic
  cli
  hlt

.section .rodata
err_msg: .asciz "Irrecoverable error when handling an exception ..."

.section .note.GNU-stack,"",@progbits

