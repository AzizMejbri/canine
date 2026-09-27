import arch/arch_specific
import arch/x86_64/debug

proc triggerDE*(): cint {.inline, x86_64.} =
  asm """
    xor %%rcx, %%rcx
    mov $10, %%rax
    xor %%rdx, %%rdx
    div %%rcx
    ::: "rax", "rcx", "rdx", "memory"
  """
    
proc triggerPF*(): cint {.inline, x86_64.} =
  ## Trigger #PF (vector 14): read from an unmapped address.
  ## 0xdeadbeef000 is not mapped in any sane kernel page table.
  asm """
    mov $0xdeadbeef000, %%rax
    mov (%%rax), %%rax
    ::: "rax", "memory"
  """

proc triggerUD*(): cint {.inline, x86_64.} =
  asm """
    ud2
  """

proc triggerDF*() {.inline, x86_64, noreturn, asmNoStackFrame.} =
  # trigger a #BP with a bad stack pointer
  asm """
    xorq %rax, %rax
    movq %rax, %rsp
    int3                
  """

proc triggerGP*() {.inline, x86_64.} =
  asm """
    mov $0x18, %ax      # TSS selector, index 3 — but loaded into DS
    mov %ax, %ds        # TSS is not a data segment → #GP
  """


proc triggerGP2*() {.inline, x86_64.} =
  asm """
    mov $0x1337, %ax      # TSS selector, index 3 — but loaded into DS
    mov %ax, %ds        # TSS is not a data segment → #GP
  """
