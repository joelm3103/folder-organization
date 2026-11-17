# Verification

This repository has **no test runner** — no Pester suite, no `test-results/`, no CI configuration. The
script is one ~1240-line file whose observable behaviour is console output, a log file and the state of
a directory tree, and its questions are interactive. There is therefore no runner summary to read a
count from.

What exists instead, and what this file is for: every claim in `CHANGELOG.md` under `### Verified` was
produced by an actual run against a throwaway fixture, and the commands below rebuild that fixture so
the run can be repeated. Nothing here is reconstructed from memory — the figures quoted are the ones the
runs printed.

- Recorded: 2026-11-17, on branch `feature/root-folders-as-projects`.
- Environment: Windows, **Windows PowerShell 5.1** (`powershell -NoProfile -ExecutionPolicy Bypass`).

## Reproduce the fixture

Paste into Windows PowerShell 5.1. Byte content is written with `WriteAllText`, not `Set-Content`, so
the hashes below are stable — `Set-Content` would add a line ending and change every one of them.

```powershell
$fx = Join-Path $env:TEMP 'fo-verify'
Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in 'Work\Clients','Work\Logs','Scratch','Documents\Sub3') {
    [void](New-Item -ItemType Directory -Path (Join-Path $fx $d) -Force)
}
[System.IO.File]::WriteAllText((Join-Path $fx 'archive.zip'), 'z')
[System.IO.File]::WriteAllText((Join-Path $fx 'invoice.pdf'), 'i')
[System.IO.File]::WriteAllText((Join-Path $fx 'Documents\stray.png'), 's')
[System.IO.File]::WriteAllText((Join-Path $fx 'Work\a.pdf'), 'a')
[System.IO.File]::WriteAllText((Join-Path $fx 'Work\Clients\x.pdf'), 'c')
1..3 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $fx "Documents\Sub3\p$_.png"), "p$_") }
Copy-Item .\organize-downloads.ps1, .\organize-downloads.bat $fx
```

The tree it builds, before anything runs:

```
fo-verify\
  archive.zip  invoice.pdf          (loose at the root)
  Documents\stray.png               (mis-filed: belongs in Pictures)
  Documents\Sub3\p1..p3.png         (a project inside a category folder)
  Work\a.pdf  Work\Clients\x.pdf    (a root project: opaque, moves whole)
  Work\Logs\                        (empty, inside the project)
  Scratch\                          (empty, at the root)
```

## Checks and what they printed

| # | Check | Command (from the fixture) | Observed |
|---|---|---|---|
| 1 | A root folder is planned as a project; empty folders are predicted at their **future** path | `.\organize-downloads.ps1 -Path $fx -WhatIf` | Row `Work  (root)  Folder  Projects  MOVE FOLDER`; note `Work (2 file(s), kept together) -> Projects\Work`; row `Sub3  Documents  Folder  Pictures  MOVE FOLDER`; `Empty folders after this run: 2 (Projects\Work\Logs, Scratch)`; `Summary: 3 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 2 skip, 2 folder move`; `Dry run (-WhatIf): nothing changed.`; exit 0 |
| 2 | The project folder is never entered — its files move untouched | `.\organize-downloads.ps1 -Path $fx -Force -MoveProjects -PruneEmpty` | `Scaffolded 4 category folder(s).` then `Empty folders: 2 (Projects\Work\Logs, Scratch)`, `pruned Projects\Work\Logs`, `pruned Scratch`, `Removed 2 empty folder(s).`; exit 0 |
| 3 | Contents survived byte-for-byte | `sha256sum` either side of check 2 | `a.pdf` `ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb`, `Clients/x.pdf` `2e7d2c03a9507ae265ecf5b5356885a53393a2029d241394997265a1a25aefc6` — identical under `Work\` and under `Projects\Work\` |
| 4 | The log never names a file inside the project | `grep -cE '\ba\.pdf\b\|x\.pdf' $fx\organize-log.txt` | `0` — only `MOVED-FOLDER Work -> Projects\Work`; the two project files have no line at all |
| 5 | Preview count equals the prune report | checks 1 and 2 | Both `2 (Projects\Work\Logs, Scratch)`. The preview predicted the post-move path, and execution removed exactly those two |
| 6 | A second run is a no-op | `.\organize-downloads.ps1 -Path $fx -Force -MoveProjects -PruneEmpty` again | `Already filed: 3 file(s) inside category folders left alone.`, `Summary: 0 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 3 skip`; exit 0 |
| 7 | The scan enters root projects only when typed, and says so | `-Recurse -WhatIf` on a tree holding `Big\notes.txt` and `Big\Sub\deep.pdf` | `WARNING: the subfolder scan will enter 1 root project folder(s) and flatten their contents.` / `Only a plain run moves them whole to Projects\.`; **no** `MOVE FOLDER` row for `Big`; `Empty folders after this run: 2 (Big\Sub, Big)` |
| 8 | The depth limit and the emptiness test interact correctly | `-MaxDepth 1 -WhatIf` on the same tree | Same warning; no `MOVE FOLDER`; no row for `Big\Sub\deep.pdf`; no empty-folder prediction, because `Big` still holds a file at depth 2 |
| 9 | A missing target fails closed | `.\organize-downloads.ps1 -Path 'Z:\does-not-exist' -WhatIf` | `ERROR: folder not found: Z:\does-not-exist`; exit 1 |
| 10 | An 8.3 short name no longer corrupts relative paths | Same fixture reached through `$env:TEMP` (`C:\Users\JOEL~1.MAN\...`) | `Empty folders after this run: 2 (Projects\Work\Logs, Scratch)` — previously `2 (y\Work\Logs, y\Scratch)`, and execution listed six candidates including the scaffolded `Music\`, `Other\`, `Software\`, `Videos\` |

Check 10 is the regression for a defect found while writing this file, so it is worth naming the
mechanism: `Resolve-Path` returns an 8.3 short name **unchanged** (`C:\Users\JOEL~1.MAN\...`, 49 chars)
while `Get-ChildItem` reports every child as a long path (`C:\Users\joel.manick\...`). Every
`Substring($Root.Length)` relative path then slices mid-name, which produced `y\Work\Logs`. Two
consequences, both silent: the top-level category-folder exemption in `Get-EmptyFolders` stopped
recognising `Music\` (it tests the relative path for a backslash), so scaffolded category folders were
offered for deletion; and the project-rewrite prefix match never fired, so a relocating project was
judged at its old path again. Fixed by resolving the target with `Get-Item` (`FullName`, long form)
instead of `Resolve-Path`, and by normalising the root at the top of `Get-EmptyFolders` so no caller can
reintroduce the mismatch.

## Not covered by this transcript

- The launcher (`organize-downloads.bat`) end to end: the double-click pause, the `-Force` token walk and
  the exit-code echo were verified in earlier passes and are unchanged by this work; the `.bat` was not
  modified.
- The interactive path: declining the folder move (`Project folders left in place.`), answering the
  prune question `y`/`n`, and the "no input is a no" matrix. All exercised in earlier passes; none of
  those code paths changed here.
- Real user data. Every run above used a `%TEMP%` fixture; no live folder was touched.
- OneDrive placeholder trees under `-Recurse` and paths longer than `MAX_PATH`.

## Note on running from a synced folder

A run whose log file lives in a folder being watched by a sync client can abort mid-way: with
`$ErrorActionPreference = 'Stop'`, a locked `organize-log.txt` throws on the first `Add-Content` and the
run stops after whatever it had already moved. Observed once during this session (Syncthing watching the
repo folder); the re-run from an untouched location passed. This is a pre-existing property of writing
the log with `Add-Content` per line, not a defect introduced by the changes above.
