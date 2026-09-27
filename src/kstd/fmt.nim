import macros


# ---------------------------------------------------------------------
# Compile-time {} formatting
# ---------------------------------------------------------------------

proc buildFmt(fmt: string, argStrs: seq[string]): string =
  var output = ""
  var argIdx = 0
  var i = 0
  while i < fmt.len:
    let c = fmt[i]
    if c == '{' and i + 1 < fmt.len:
      if fmt[i + 1] == '{':
        output.add '{'
        i += 2
        continue
      elif fmt[i + 1] == '}':
        if argIdx < argStrs.len:
          output.add argStrs[argIdx]
          inc argIdx
        i += 2
        continue
    elif c == '}' and i + 1 < fmt.len and fmt[i + 1] == '}':
      output.add '}'
      i += 2
      continue
    output.add c
    inc i
  output

macro staticFmt*(fmt: static[string], args: varargs[untyped]): untyped =
  ## Compile-time `{}` string formatting.
  ##
  ##   const banner = staticFmt("canine v{}  port={}\n", "0.0.1", 0x3F8)
  ##
  ## Literal braces via `{{` and `}}`. All args must be compile-time constants.
  var arr = nnkBracket.newTree()
  for a in args:
    arr.add newCall(bindSym "$", a)
  let argSeq = arr.prefix("@")
  let call = newCall(bindSym "buildFmt", newLit fmt, argSeq)
  let constIdent = nskConst.genSym("staticFmtResult")
  result = newStmtList(
    newConstStmt(constIdent, call),
    constIdent
  )

