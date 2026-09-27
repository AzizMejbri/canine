.set MAGIC, 0x1BADB002
.set MAGIC2, 0xE85250D6 
.set FLAGS, 0

.set MAGIC2, 0xE85250D6
.set ARCHITECTURE, 0
.set STACK_SIZE, 0x4000

.section .multiboot2, "a"
.align 8
multiboot_header_start:
  .long MAGIC2
  .long ARCHITECTURE
  .long (multiboot_header_end - multiboot_header_start)
  .long -(MAGIC2 + ARCHITECTURE + (multiboot_header_end - multiboot_header_start))
  .align 8
  .word 0
  .word 0
  .long 8
multiboot_header_end:

.section .bss
.align 16
.kernel_stack:
  .skip STACK_SIZE

# Page tables (must be aligned to 4096)
.align 4096
pml4_table:   .skip 4096
pdp_table:    .skip 4096
pd_table:     .skip 4096

.section .text
.code32                          # CRITICAL: we enter in 32-bit mode
.global _start
.extern kernel_main

_start:
  movl $(.kernel_stack + STACK_SIZE), %esp

  # 1. Disable interrupts
  cli

  # 2. Set up identity-mapped page tables (map first 1GB)
  # PML4[0] -> PDP
  movl $pdp_table, %eax
  orl  $0x3, %eax               # present + writable
  movl %eax, pml4_table
  # PDP[0] -> PD
  movl $pd_table, %eax

  orl  $0x3, %eax
  movl %eax, pdp_table

  # PD: map 512 x 2MB pages (identity map first 1GB)
  movl $0, %ecx
.fill_pd:
  movl %ecx, %eax
  shll $21, %eax                # each entry covers 2MB
  orl  $0x83, %eax              # present + writable + huge page
  movl %eax, pd_table(, %ecx, 8)
  incl %ecx
  cmpl $512, %ecx
  jne  .fill_pd

  # 3. Load PML4 into CR3
  movl $pml4_table, %eax
  movl %eax, %cr3

  # 4. Enable PAE (CR4.PAE)
  movl %cr4, %eax
  orl  $0x20, %eax
  movl %eax, %cr4

  # 5. Set EFER.LME (long mode enable)
  movl $0xC0000080, %ecx
  rdmsr
  orl  $0x100, %eax
  wrmsr

  # 6. Enable paging (CR0.PG) — this activates long mode
  movl %cr0, %eax
  orl  $0x80000001, %eax
  movl %eax, %cr0

  # 7. Load a 64-bit GDT and far jump to 64-bit code
  lgdt gdt64_pointer
  ljmp $0x8, $_start64          # far jump flushes pipeline into 64-bit mode

# --- 64-bit GDT ---
.align 16
.global gdt64
.global gdt64_end
.global gdt64_pointer
gdt64:
  .quad 0x0000000000000000      # null descriptor
  .quad 0x00AF9A000000FFFF      # 64-bit code segment
  .quad 0x00AF92000000FFFF      # 64-bit data segment
gdt64_tss:
  .word 0                       # limit[15:0]      ← fill at runtime
  .word 0                       # base[15:0]       ← fill at runtime
  .byte 0                       # base[23:16]      ← fill at runtime
  .byte 0x89                    # access: present, DPL=0, 64-bit TSS available
  .byte 0x00                    # flags + limit[19:16]
  .byte 0                       # base[31:24]      ← fill at runtime
  .long 0                       # base[63:32]      ← fill at runtime
  .long 0                       # reserved
gdt64_end:

gdt64_pointer:
  .word (gdt64_end - gdt64 - 1)
  .quad gdt64

.code64
_start64:
  # Set up segment registers
  movw $0x10, %ax
  movw %ax, %ds
  movw %ax, %es
  movw %ax, %ss
  xorw %ax, %ax
  movw %ax, %fs
  movw %ax, %gs

  # --- Patch the TSS descriptor in the GDT ---
  # base = &tss64
  lea tss64(%rip), %rax
  # low 16 bits of base -> gdt64_tss+2
  movw %ax, gdt64_tss+2
  # bits 16-23 of base -> gdt64_tss+4
  shrq $16, %rax
  movb %al, gdt64_tss+4
  # bits 24-31 of base -> gdt64_tss+7
  shrq $8, %rax
  movb %al, gdt64_tss+7
  # bits 32-63 of base -> gdt64_tss+8 (4 bytes)
  shrq $8, %rax
  movl %eax, gdt64_tss+8

  # limit = tss64_end - tss64 - 1 = 112 - 1 = 111 (0x6F)
  movw $0x6F, gdt64_tss+0

  # --- Load the TSS ---
  movw $0x18, %ax
  ltr %ax

  # --- Fill in IST1 ---
  lea df_stack_top(%rip), %rax
  movq %rax, tss64+36          # offsetof(tss64, ist1) = 36

  # --- Enable SSE ---
  movq %cr4, %rax
  orq  $(1 << 9), %rax        # CR4.OSFXSR    = 1
  orq  $(1 << 10), %rax       # CR4.OSXMMEXCPT = 1
  movq %rax, %cr4

  # Also clear CR0.EM (bit 2) and CR0.TS (bit 3), just in case.
  movq %cr0, %rax
  andq $~((1 << 2) | (1 << 3)), %rax
  movq %rax, %cr0

  

  call kernel_main

  cli
hang:
  hlt
  jmp hang

.section .note.GNU-stack,"",@progbits

# Reserving a stack for #DF handling 
# While encountring a #DF exception, there is no garantee that 
# RSP is in a healthy state, we cant rely on that so we will use
# a custom stack for handling #DF exceptions
.section .bss
.align 16
.global df_stack_top
df_stack_bottom:
    .skip 0x4000          # 16 KiB
df_stack_top:


.section .data
.align 16
.global tss64
tss64:
  .long 0                # reserved
  .quad 0                # rsp0  (kernel stack for ring0 on int from ring3 — unused now)
  .quad 0                # rsp1
  .quad 0                # rsp2
  .quad 0                # reserved
  .quad 0                # ist1 <- df_stack_top here
  .quad 0                # ist2
  .quad 0                # ist3
  .quad 0                # ist4
  .quad 0                # ist5
  .quad 0                # ist6
  .quad 0                # ist7
  .quad 0                # reserved
  .quad 0                # reserved
  .word 0                # reserved
  .word tss64_end - tss64   # I/O map base (offset)
tss64_end:
