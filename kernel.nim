import drivers/output/[vga, serial as com]
import drivers/input/keyboard
import drivers/time/pit
import drivers/pic
import arch/x86_64/[idt, ctrl, cpuid]
import mm/pmm/[map, frame_alloc, heap]
import kstd/fmt
import kstd/mem
import kstd/hooks
import arch/x86_64/[debug, interrupts/triggers]
import arch/x86_64/interrupts/fault_handlers/[
  pf, de, db, ud, df, gp
]
import globals


proc NimMain() {.importc.}

proc kMain() {.exportc: "kernel_main", cdecl, noreturn.} =

  # every initialization procedure delegated to the constructor will be invoked here,
  # respecting its designated priority order, making the initialization process the 
  # responsibility of its respective module not of the kMain function
  clear()
  resetCol()
  initHere()
  sti()


  # singleStepTrap()
  # vga.println "about to div by zero\n"
  # {.push checks: off.}
  # singleStepTrap(dumpRegs and disasMany)
  # let _ {.volatile.} = triggerDE()
  # {.pop.}
  # singleStepTrap()
  # vga.println "survived div by zero\n"
  NimMain()
 
  # vga.println("about to page fault")
  # {.push checks: off.}
  # let _ {.volatile.} = triggerPF()
  # {.pop.}
  # vga.println("survived page fault")

  # vga.println("about to debug fault")
  # {.push checks: off.}
  # let _ {.volatile.} = triggerDB()
  # {.pop.}
  # vga.println("survived debug fault")

  while true:
    discard
