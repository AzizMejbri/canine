import arch/arch_specific

proc cli*() {.inline, x86_64.} =
  asm "cli"

proc sti*() {.inline, x86_64.} =
  asm "sti"

proc halt*() {.inline, x86_64, noreturn.} =
  asm "cli; hlt"
  while true: discard

template pushAll*() {.x86_64.} =
    asm """
      pushfq
      pushq %%rax
      pushq %%rbx
      pushq %%rcx
      pushq %%rdx
      pushq %%rsi
      pushq %%rdi
      pushq %%rbp
      pushq %%r8
      pushq %%r9
      pushq %%r10
      pushq %%r11
      pushq %%r12
      pushq %%r13
      pushq %%r14
      pushq %%r15
      ::
    """

template popAll*() {.x86_64.} =
    asm """
      popq %%r15
      popq %%r14
      popq %%r13
      popq %%r12
      popq %%r11
      popq %%r10
      popq %%r9
      popq %%r8
      popq %%rbp
      popq %%rdi
      popq %%rsi
      popq %%rdx
      popq %%rcx
      popq %%rbx
      popq %%rax
      popfq
      ::
    """

proc readCr2*(): uint64 {.inline, x86_64.} =
  asm """
    mov %%cr2, %0
    : "=r"(result)
  """

const IO_DELAY_PORT* = 0x80'u8
proc ioWait*() {.inline, x86_64.} =
  asm """
    xor  %%al,  %%al
    out  %%al, %[io_dp]
    : 
    : [io_dp] "i" (`IO_DELAY_PORT`)
  """
