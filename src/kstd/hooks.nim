import macros
import std/strutils

const MAX_PRIO = 255

type
  InitEntry = object
    order: int
    sym:   NimNode
    origin: string
    repr:  string

var initBuckets {.compileTime.}: array[MAX_PRIO + 1, seq[InitEntry]]
var initCounter {.compileTime.}: int

proc doInitAppend(prio: int, body: NimNode): NimNode =
  doAssert prio in 0 .. MAX_PRIO, "init priority out of range: " & $prio
  let name = genSym(nskProc, "initBlock")
  let info = body.lineInfo
  let origin = if info.len > 0: info else: "<unknown>"

  initBuckets[prio].add InitEntry(
    order: initCounter, sym: name, origin: origin, repr: body.repr,
  )
  inc initCounter

  result = newStmtList()
  result.add quote do:
    proc `name`() {.used.} =
      `body`

macro initAppend*(prio: static[int], body: untyped): untyped =
  doInitAppend(prio, body)

macro initAppend*(body: untyped): untyped =
  doInitAppend(0, body)

# ---- log formatting -------------------------------------------------------

const
  Esc   = "\x1b["
  Reset = Esc & "m"
  Bold  = Esc & "1m"
  Dim   = Esc & "2m"

proc fg(n: int): string {.compileTime.} = Esc & $n & "m"

proc colorFor(prio: int): string {.compileTime.} =
  let r = prio.float / MAX_PRIO.float
  if prio == 0: return fg(36)   # cyan
  if r < 0.5:   return fg(32)   # green
  if r < 0.85:  return fg(33)   # yellow
  return fg(31)                 # red

proc fmtBody(body: string, indent: int): seq[string] {.compileTime.} =
  var lines = body.splitLines()
  # strip blank lines at both ends
  while lines.len > 0 and lines[0].strip.len == 0: lines.delete(0)
  while lines.len > 0 and lines[^1].strip.len == 0: lines.delete(lines.len - 1)
  # dedent by common leading whitespace
  var minIndent = high(int)
  for l in lines:
    if l.strip.len == 0: continue
    var n = 0
    while n < l.len and (l[n] == ' ' or l[n] == '\t'): inc n
    if n < minIndent: minIndent = n
  if minIndent == high(int): minIndent = 0
  for l in lines:
    let s = if l.len >= minIndent: l[minIndent .. ^1] else: ""
    result.add " ".repeat(indent) & s

proc shortOrigin(o: string): string {.compileTime.} =
  var s = o
  # "…/foo.nim(12, 3)" -> "…/foo.nim:12"
  let openParen = s.find('(')
  if openParen >= 0:
    let closeParen = s.find(')', openParen)
    if closeParen > openParen:
      let loc = s[openParen + 1 ..< closeParen]
      let comma = loc.find(',')
      let lineNo = if comma > 0: loc[0 ..< comma] else: loc
      s = s[0 ..< openParen] & ":" & lineNo
  # trim to last two path components
  let parts = s.split('/')
  if parts.len > 2:
    s = parts[^2] & "/" & parts[^1]
  return s

macro initHere*(): untyped =
  result = newStmtList()
  var total = 0

  var totalCount = 0
  for p in 0 .. MAX_PRIO: totalCount += initBuckets[p].len

  echo Bold & fg(35) & "── initHere " & Reset &
       Dim & "(" & $totalCount & " block" &
       (if totalCount == 1: "" else: "s") & ")" & Reset

  for p in 0 .. MAX_PRIO:
    if initBuckets[p].len == 0: continue
    let c = colorFor(p)
    let n = initBuckets[p].len
    echo c & "prio " & $p & Reset &
         Dim & " · " & $n & " block" & (if n == 1: "" else: "s") & Reset
    for e in initBuckets[p]:
      echo "  " & Dim & "▸ " & Reset & Bold & shortOrigin(e.origin) & Reset
      for line in fmtBody(e.repr, 0):
        echo "    " & Dim & "│ " & Reset & line
      result.add newCall(e.sym)
      inc total

  echo Bold & fg(32) & "✓ " & Reset & Bold & "emitted " &
      $total & " block" & (if total == 1: "" else: "s") & Reset
  doAssert total > 0,
    fg(31) & "initHere: found no registered init blocks" & Reset
