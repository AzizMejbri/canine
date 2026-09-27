import arch/x86_64/[port, ctrl]
import kstd/hooks
import kstd/opt

const
  MasterCmd*  = 0x20'u8
  MasterData* = 0x21'u8

  SlaveCmd*   = 0xA0'u8
  SlaveData*  = 0xA1'u8
  
  EOI*        = 0x20'u8
  READ_ISR    = 0x0A'u8 # OCW3 IRQ ready next CMD read
  READ_IRR    = 0x0B'u8 # OCW3 IRQ service next CMD read


type
  # ICW1 (Initialization Command Word) bits
  ICW1 {.pure.} = enum
    Init        = 0x11'u8 # ICW1: Initialize + ICW4 required
    SendIcw4    = 0x01'u8 # ICW4 will be sent
    Single      = 0x02'u8 # Single (Cascade) mode
    Interval4   = 0x04'u8 # Call address interval 4                
    Level       = 0x08'u8 # Level triggered mode                     

  # ICW2 - Vector offsets
  ICW2 {.pure.} = enum
      MasterOffset = 0x20, # Master PIC offset = IRQ[0-7] -> INT [0x20-0x27]
      SlaveOffset  = 0x28, # Slave  PIC offset = IRQ[8-15] -> INT [0x28-0x2F]
  
  # ICW3 - cascade configuration
  ICW3 {.pure.} = enum
      MasterCascade = 0x4, # Master: slave at IRQ2 (00000100)
      SlaveCascade  = 0x2, # Slave: cascade Identity (00000010)
  
  # ICW4 - Environment configuration
  ICW4 {.pure.} = enum
      x86Mode         = 0x01, # 8086/88 (x86) mode
      Auto            = 0x02, # Auto EOI
      BufSlave        = 0x08, # Buffered mode : slave                            
      BufMaster       = 0x0C, # Buffered mode : master
      SFNM            = 0x10, # Special Fully nested mode
  
  # Interrupt masks
  InterruptMask {.pure.} = enum
    MaskAll      = 0xFF, # Mask all interrupts
    UnmaskAll    = 0x00, # unmask all interrupts

converter toU8(w: Icw1): uint8 = uint8(ord w)
converter toU8(w: Icw2): uint8 = uint8(ord w)
converter toU8(w: Icw3): uint8 = uint8(ord w)
converter toU8(w: Icw4): uint8 = uint8(ord w)
converter toU8(mask: InterruptMask): uint8 = uint8(ord mask)

proc remap() =
  let mask1 = inb MasterData
  let mask2 = inb SlaveData

  outb MasterCmd,  ICW1.Init
  outb SlaveCmd,   ICW1.Init
  ioWait()

  outb MasterData, ICW2.MasterOffset
  outb SlaveData,  ICW2.SlaveOffset
  ioWait()

  outb MasterData, ICW3.MasterCascade
  outb SlaveData,  ICW3.SlaveCascade
  ioWait()

  outb MasterData, ICW4.x86Mode
  outb SlaveData,  ICW4.x86Mode
  ioWait()

  outb MasterData, mask1
  outb SlaveData,  mask2
  ioWait()

proc setMask*(irq: uint8, masked: bool = true) {.inline.} =
  let cond = irq < 8
  let bit = if cond: irq else: irq - 8
  let port = if cond: MasterData else: SlaveData
  var mask = inb port
  mask = if masked: mask or (1'u8 shl bit)
    else: mask and not (1'u8 shl bit)
  outb port, mask

template clearMask*(irq: uint8) = setMask(irq, false)

# --- runtime: irq not known at compile time ---
template sendEOI*(irq: uint8) =
  asm """
    movb $0x20, %%al
    movw $0x20, %%dx
    cmpb $8,    %0
    jb 1f
    movw $0xA0, %%dx
  1:
    outb %%al,  %%dx
    :                      # no outputs
    : "r" (irq)            # single positional input, %0
  """

# --- compile time: irq is a static value ---
template sendEOI*(irq: static uint8) =
  when irq >= 8:
    asm """
      movb %[eoi],  %%al
      movw %[port], %%dx
      outb %%al,    %%dx
      :: [eoi] "i" (`EOI`), [port] "i" (`SlaveCmd`)
    """
  else:
    asm """
      movb %[eoi],  %%al
      movw %[port], %%dx
      outb %%al,    %%dx
      :: [eoi] "i" (`EOI`), [port] "i" (`MasterCmd`)
    """

proc disable*() {.inline.} =
    outb SlaveData,  InterruptMask.MaskAll
    outb MasterData, InterruptMask.MaskAll

initAppend 129:
  remap()
  disable()
