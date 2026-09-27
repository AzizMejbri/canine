import drivers/output/vga
import arch/x86_64/[ctrl, interrupts/common]
import kstd/option


# ---- ISR stubs, defined in isr.s ----
proc isr0*()  {.importc, cdecl, used.}
proc isr1*()  {.importc, cdecl, used.}
proc isr2*()  {.importc, cdecl, used.}
proc isr3*()  {.importc, cdecl, used.}
proc isr4*()  {.importc, cdecl, used.}
proc isr5*()  {.importc, cdecl, used.}
proc isr6*()  {.importc, cdecl, used.}
proc isr7*()  {.importc, cdecl, used.}
proc isr8*()  {.importc, cdecl, used.}
proc isr9*()  {.importc, cdecl, used.}
proc isr10*() {.importc, cdecl, used.}
proc isr11*() {.importc, cdecl, used.}
proc isr12*() {.importc, cdecl, used.}
proc isr13*() {.importc, cdecl, used.}
proc isr14*() {.importc, cdecl, used.}
proc isr15*() {.importc, cdecl, used.}
proc isr16*() {.importc, cdecl, used.}
proc isr17*() {.importc, cdecl, used.}
proc isr18*() {.importc, cdecl, used.}
proc isr19*() {.importc, cdecl, used.}
proc isr20*() {.importc, cdecl, used.}
proc isr21*() {.importc, cdecl, used.}
proc isr22*() {.importc, cdecl, used.}
proc isr23*() {.importc, cdecl, used.}
proc isr24*() {.importc, cdecl, used.}
proc isr25*() {.importc, cdecl, used.}
proc isr26*() {.importc, cdecl, used.}
proc isr27*() {.importc, cdecl, used.}
proc isr28*() {.importc, cdecl, used.}
proc isr29*() {.importc, cdecl, used.}
proc isr30*() {.importc, cdecl, used.}
proc isr31*() {.importc, cdecl, used.}


const vecNames: array[32, string] = [
  "Divide Error (#DE)",
  "Debug (#DB)",
  "NMI",
  "Breakpoint (#BP)",
  "Overflow (#OF)",
  "BOUND Range (#BR)",
  "Invalid Opcode (#UD)",
  "Device Not Available (#NM)",
  "Double Fault (#DF)",
  "Coprocessor Segment Overrun",
  "Invalid TSS (#TS)",
  "Segment Not Present (#NP)",
  "Stack-Segment Fault (#SS)",
  "General Protection (#GP)",
  "Page Fault (#PF)",
  "Reserved",
  "x87 FPU Error (#MF)",
  "Alignment Check (#AC)",
  "Machine Check (#MC)",
  "SIMD FP Error (#XF)",
  "Reserved", "Reserved", "Reserved", "Reserved",
  "Reserved", "Reserved", "Reserved", "Reserved",
  "Reserved", "Reserved", "Reserved", "Reserved",
]


var handlers*: array[32, Option[FaultHandler]]

proc registerFaultHandler*(h: FaultHandler, vec: int) =
  doAssert vec in 0..31, "bad vector"
  if h != nil: handlers[vec] = some h
  else: handlers[vec] = none(FaultHandler)
  

proc registerFaultHandler*(h: Option[FaultHandler], vec: int) =
  doAssert vec in 0..31, "bad vector"
  handlers[vec] = h

proc defaultFaultHandler*(frame: ptr InterruptFrame): cint {.cdecl.} =
  let vec  = frame.vector
  let err  = frame.error
  let rip  = frame.rip

  chCol White, Blue
  put "\n\n=== EXCEPTION (handled by `faults::defaultFaultHandler()`) ===\n"
  if vec < 32:
    put "vector: "
    putHex uint8(vec)
    put "  "
    put vecNames[int(vec)]
  else:
    put "vector: "
    putHex uint8(vec)
  put "\nerror:  "
  putHex err
  put "\nrip:    "
  putHex rip
  if vec == 14:
    put "\ncr2:    "
    putHex readCr2()
  put "\n\n"
  
  resetCol()
  1

proc faultHandler*(frame: ptr InterruptFrame): cint
    {.exportc: "fault_handler", cdecl.} =
  let v = int frame.vector
  if v in 0..31 and handlers[v].isSome:
    return handlers[v].get()(frame)
  return defaultFaultHandler(frame)
