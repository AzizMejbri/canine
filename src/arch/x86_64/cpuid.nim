import arch/arch_specific


proc cpuid*(leaf: uint64): tuple[rax, rbx, rcx, rdx: uint64] {.x86_64.} =
  asm """
    cpuid 
    :"=a"(`result.rax`), "=b"(`result.rbx`), "=c"(`result.rcx`), "=d"(`result.rdx`)
    :"a"(`leaf`)
  """
proc cpuid*(leaf, subleaf: uint64): tuple[rax, rbx, rcx, rdx: uint64] {.x86_64.} =
  asm """
    cpuid 
    :"=a"(`result.rax`), "=b"(`result.rbx`), "=c"(`result.rcx`), "=d"(`result.dx`)
    :"a"(`leaf`), "b"(`subleaf`)
  """
