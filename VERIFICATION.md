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
- Recorded: 2026-11-23, on branch `feat/exclude-folders` — the excluded-folder checks (11–17) below.
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

## Category-folder scaffolding

Same fixture builder as above, with three variations: one loose `note.pdf` (fixture A), a genuinely
empty folder (fixture B), and fixture A answered interactively with stdin piped (fixture C). For B the
script is kept **outside** the target — a copied script inside the folder is itself a `SKIP` row, so the
plan is never empty and the "nothing to organise" path is never reached.

| # | Check | Command | Observed |
|---|---|---|---|
| 11 | Unattended run creates only what it files into | `-Force` on fixture A | `Category folders missing: 8 - only the ones this run files into will be created.`; afterwards `Documents\` holds `note.pdf` and the seven other categories do not exist; no `Scaffolded` line; the log's only `CREATED-FOLDER` names `…\Documents` |
| 12 | The switch restores the full structure | `-Force -Scaffold` on the same folder | `Category folders to create: Archives, Music, Other, Pictures, Projects, Software, Videos` then `Scaffolded 7 category folder(s).`; all eight exist |
| 13 | An empty folder with `-Force` does nothing | `-Force` on fixture B | `Nothing to organise - no loose files at this folder's root.`; exit 0; still no subfolder |
| 14 | A dry run still names what a yes would add | `-WhatIf` on fixture B | `Category folders missing: 8 (Archives, Documents, Music, Other, Pictures, Projects, Software, Videos) - pass -Scaffold to create all of them; otherwise only the ones this run files into.` then `Dry run (-WhatIf): nothing changed.`; exit 0; nothing created |
| 15 | An empty folder with `-Scaffold` builds the structure | `-Force -Scaffold` on fixture B | `Scaffolded 8 category folder(s).`; all eight exist |
| 16 | Enter at the question means minimal | `printf '
y
'` piped into fixture A | The question prints with `Missing: …` and `No creates only the folders this run files into.`; afterwards only `Documents\` exists and holds `note.pdf` |
| 17 | `y` at the question builds all eight | `printf 'y
y
'` piped into fixture A | `Scaffolded 7 category folder(s).` plus the eighth created by the move; all eight exist |
| 18 | Enter is not a yes for either question | `printf '

'` piped into fixture A | Scaffold answered No, `Proceed?` answered No → `Aborted. Nothing changed.`; `note.pdf` still at the root and no category folder created |
| 19 | An unattended run never asks | `-Force` on fixture A, output searched for `Create all eight category folders` | 0 matches |

The prompt block itself, as printed:

```
Create all eight category folders? [y/N]
  Missing: Archives, Documents, Music, Other, Pictures, Projects, Software, Videos
  No creates only the folders this run files into.
```

The other interactive paths — declining a folder move, the prune question, the no-input matrix — are
still covered only by earlier passes, not by this transcript.

## Excluded folders

The exclusion feature gets its own fixture rather than perturbing the one above, because what has to be
proved is an absence: a protected tree must not appear in the plan, in the prune list or in the log.

```powershell
$fx = Join-Path $env:TEMP 'fo-exclude'
Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in 'Work\Clients','Keep\sub','Keep\EmptyDir','Move Me','Documents') {
    [void](New-Item -ItemType Directory -Path (Join-Path $fx $d) -Force)
}
[System.IO.File]::WriteAllText((Join-Path $fx 'Work\a.pdf'), 'a')
[System.IO.File]::WriteAllText((Join-Path $fx 'Work\Clients\x.pdf'), 'c')
[System.IO.File]::WriteAllText((Join-Path $fx 'Keep\b.txt'), 'b')
[System.IO.File]::WriteAllText((Join-Path $fx 'Keep\sub\c.png'), 'p')
[System.IO.File]::WriteAllText((Join-Path $fx 'Move Me\d.pdf'), 'd')
[System.IO.File]::WriteAllText((Join-Path $fx 'Documents\shot.png'), 's')
Copy-Item .\organize-downloads.ps1, .\organize-downloads.bat $fx
[System.IO.File]::WriteAllText((Join-Path $fx 'organize-exclude.txt'), "# standing exclusions`r`nKeep`r`nWork\Clients`r`n")
```

The script is copied into the fixture so the default `organize-exclude.txt` resolves there rather than
to this repository. `Keep` is a name rule; `Work\Clients` is a path rule.

| # | Check | Command | Observed |
|---|---|---|---|
| 11 | A name rule and a path rule are read, applied and stated | `.\organize-downloads.ps1 -Path $fx -WhatIf` | `Excluded: 2 rule(s) (Keep, Work\Clients)`, `Never entered, moved or pruned. Source: organize-exclude.txt`, `Left in place because it holds one: Work`; rows only `shot.png Documents Image Pictures MOVE` and `Move Me (root) Folder Projects MOVE FOLDER`; `Summary: 1 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 3 skip, 1 folder move`; exit 0 |
| 12 | `-Recurse` does not enter an excluded path, and a path rule protects only that copy | `-Recurse -WhatIf -ExcludeFile $fx\path-only.txt` (file contains only `Work\Clients`) | `Excluded: 1 rule(s) (Work\Clients)`; `WARNING: the subfolder scan will enter 3 root project folder(s)`; rows include `b.txt Keep Text Documents MOVE` and `c.png Keep\sub Image Pictures MOVE`; **no** row for `Clients\x.pdf`; `Empty folders after this run: 4 (Keep\EmptyDir, Keep\sub, Keep, Move Me)` — `Work\Clients` is not a candidate |
| 13 | `-Exclude` merges with the file, and splits a quoted comma list | `-WhatIf -ExcludeFile $fx\empty.txt -Exclude 'Work\Clients,Keep'` | `Excluded: 2 rule(s) (Work\Clients, Keep)`, `Source: empty.txt, -Exclude`; `MOVE FOLDER` only for `Move Me`; exit 0 |
| 14 | A missing explicitly-passed file fails closed | `-WhatIf -ExcludeFile $fx\nope.txt` | `ERROR: exclusion file not found: …\nope.txt`; exit 1 |
| 15 | Execution leaves every protected tree byte-intact | `-Force -MoveProjects -PruneEmpty`, then `Get-ChildItem $fx -Recurse -Force` | `Keep\b.txt`, `Keep\sub\c.png`, `Keep\EmptyDir`, `Work\a.pdf`, `Work\Clients\x.pdf` all still present; `Projects\Move Me\d.pdf` moved; only `Pictures\shot.png` was filed |
| 16 | The log never names a protected file | `grep -cE 'b\.txt\|c\.png\|x\.pdf' $fx\organize-log.txt` | `0`. The log holds `SKIPPED organize-*.{ps1,bat,txt}`, `CREATED-FOLDER …\Pictures`, `MOVED Documents\shot.png -> …\Pictures`, `CREATED-FOLDER …\Projects`, `MOVED-FOLDER Move Me -> Projects\Move Me` |
| 17 | Excluding a category folder stops that sweep | Fixture `fo-exclude-cat` holding only `Documents\shot.png`; control `-ExcludeFile none.txt`, then `-ExcludeFile cat.txt` (`Documents`) | Control: row `shot.png Documents Image Pictures MOVE`. Excluded: no `shot.png` row at all, `Excluded: 1 rule(s) (Documents)`, and the Source column disappears with the sweep |
| 18 | The long report states the active rules | 61-file fixture plus `organize-exclude.txt` containing `Keep`; `-WhatIf`, then read `organize-preview.txt` | Header reads `Files      : 64` … `Exclude    : 1 rule(s) (Keep) from organize-exclude.txt` |

Two results are worth naming because they are the design, not side effects:

- `Work` is **not** relocated in check 11, even though `Work` itself is not excluded. `Work\Clients`
is, and moving the parent would move the protected folder with it; the preview says so under
`Left in place because it holds one:`. Under `-Recurse` (check 12) `Work` *is* entered and flattened —
an exclusion governs what the tool does to a tree, and a scan that was typed deliberately still files
`Work\a.pdf`.
- `Keep\EmptyDir` survives check 15 with `-PruneEmpty`. The prune walk enumerates the whole tree itself
and never passed through `Keep`, so it reaches the child directly; `Test-ExcludedTree` refuses it by
segment. Without that, exclusion would only protect a folder from the passes that happened to visit
its parent.

## Note on a pre-existing gap this change did not close

`Get-ScanTargets` does not consult `$NeverSweep` (confirmed by reading the function at `c6dc171`), so
`-Recurse` enters `node_modules`, `.git`, `__pycache__` and the rest — contradicting the README's "tooling
folders are never entered". It is visible in check 12's control run, where `node_modules\m.js` appears as
a flattenable row. User exclusions *are* applied in that function; the hardcoded list is not. Left as a
separate fix rather than folded into this pass.

## Not covered by this transcript

- The launcher (`organize-downloads.bat`) end to end: the double-click pause, the `-Force` token walk and
  the exit-code echo were verified in earlier passes and are unchanged by this work. The `.bat` gained
  usage documentation only — no executable line changed, so there is nothing new to exercise there.
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
