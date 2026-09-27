import macros

# macro x86_64*(p: untyped): untyped =
#   expectKind(p, nnkProcDef)
#
#   let procName = $p[0]              # "triggerDE"
#   let body     = p[6]               # the proc's StmtList
#
#   let msg = "proc `" & procName & "` is {.x86_64.} but target is " & $hostCPU
#
#   # Replace the body with: when defined(amd64): <body> else: {.error.}
#   p[6] = quote do:
#     when defined(amd64):
# `body`
#     else:
#       {.error: `msg`.}
#
#   result = p
template x86_64*(body: untyped) =
  when defined(amd64):
    body
  else:
    static:
      const info = instantiationInfo(fullPaths = true)
      {.error: "x86_64 block used on target " & $hostCPU &
               " at " & info.filename & "(" & $info.line & ", " &
               $info.column & ")".}
