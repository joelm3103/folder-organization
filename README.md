# Folder Organization

**Sorts loose files in a folder into extension-based category folders — preview first, one confirmation, and every action written to a log you can reverse from.**

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell_5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white)

A pair of files: `organize-downloads.ps1` does the work, `organize-downloads.bat` is the double-click launcher. Windows PowerShell 5.1 built-ins only — no installation, no admin rights, no dependencies.

It is deliberately dumb about meaning. Routing is by file extension and nothing else, so anything it does not recognise goes to `Other\` for you to re-file by hand. It will not guess that four PDFs belong to one client.

It tidies two levels, and only ever loose files: the root, and the inside of each category folder. A screenshot left behind in `Documents\` finds its way to `Pictures\`. A **folder** inside a category folder is treated as a project — nothing inside it is touched, and only the folder as a whole can be relocated, when its contents clearly belong somewhere else.

## Quick start

1. Copy both files into the folder you want sorted.
2. Double-click `organize-downloads.bat`.
3. Read the preview, answer `y`.

The folder the two files sit in is the folder that gets organised. The window stays open at the end so the result is readable.

```
Organising: C:\Users\you\Downloads

  #  File Name          File Type       Destination  Action
  -  -----------------  --------------  -----------  ------
  1  Budget.xlsx        Excel           Documents    MOVE
  2  Invoice 2360.pdf   PDF             Documents    MOVE
  3  Port Listener.exe  Executable      Software     MOVE
  4  Server.rdp         Remote Desktop  Other        MOVE

Summary: 4 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 0 skip
Proceed? [y/N]
```

`desktop.ini` is skipped without a row of its own. The preview above is a verbatim render from a five-file test folder with `-WhatIf`.

## Options

| Option | Effect |
|---|---|
| `-WhatIf` | Print the preview and exit. Creates no category folders, writes no log. |
| `-Force` | Run without the confirmation prompt, for Task Scheduler. Also suppresses the launcher's closing pause. |
| `-Recurse` | Also sort files found in subfolders, into this folder's category folders. |
| `-MaxDepth N` | Limit the scan depth (immediate subfolders are depth 1). Implies `-Recurse`. |
| `-PruneEmpty` | Delete the subfolders the scan emptied, without asking. Interactive runs are asked after sorting instead. |
| `-MoveProjects` | Move the project folders whose contents belong in another category, without asking. Interactive runs are asked after the preview instead. |
| `-Path <folder>` | Organise a different folder. Defaults to the launcher's own folder. |
| `-LogFile <path>` | Override the action log. Defaults to `organize-log.txt` beside the scripts. |
| `-PreviewFile <path>` | Override the long-plan report. Defaults to `organize-preview.txt` beside the log. |

```bat
organize-downloads.bat -WhatIf
organize-downloads.bat -MaxDepth 1
organize-downloads.bat -Recurse -PruneEmpty -Force
organize-downloads.bat "D:\Unsorted Stuff" -Force
```

## Where files go

| Category | Extensions |
|---|---|
| `Archives` | zip, tar, gz, tgz, rar, 7z |
| `Documents` | pdf, doc(x), xls(x/m), ppt(x), ppsx, csv, eml, msg, txt, rtf, html, htm, xml, json, md, chm |
| `Pictures` | png, jpg, jpeg, gif, bmp, webp, svg, tif, tiff, ico, psd |
| `Software` | exe, msi, msix, msixbundle, bin, iso, apk |
| `Videos` | mp4, avi, mkv, mov, wmv, webm, m4v, flv, mpg, mpeg |
| `Music` | mp3, wav, m4a, aac, flac, ogg, gsm, wma |
| `Other` | py, ps1, bat, sh, js, jar, dll, cfg, conf, ini, pem, crt, lic, drawio, and anything unrecognised |

The whole table lives in one ordered hashtable at the top of the `.ps1`. Edit it there; nothing else needs to know.

## Safety rules

These are implemented, not aspirational:

- **Nothing is overwritten.** A name clash is resolved by comparing SHA256: identical bytes means the incoming copy is deleted and logged as `DUPLICATE`; different bytes means the incoming file is renamed `name (2).ext` and logged as `RENAMED`.
- **Two files can never claim one destination** within a single run, including across subfolders. The same identical-or-rename rule applies.
- **Directories are never taken apart, and never deleted without a yes.** A project folder moves only as a whole, and only when you approve it; a subfolder scan reports the folders it emptied and offers to delete them; nothing is removed without that answer or `-PruneEmpty`, and the target folder itself and every category folder are never candidates.
- **A project folder is opaque.** Nothing inside a folder that lives in a category folder is moved, renamed or deleted — not one file, at any depth. Only the folder itself can move.
- **The tool never moves itself.** `organize-downloads.ps1`, `organize-downloads.bat`, `organize-log.txt` and `organize-preview.txt` are reported as `SKIP` and left where they are.
- **Partial downloads are left alone** — `.crdownload`, `.part`, `.partial`, `.tmp`, `.download` — as are `desktop.ini` and `thumbs.db`.
- **No input is a no.** Every confirmation is cast to a string and trimmed before it is tested, so an absent, blank or unrecognised answer aborts. `Read-Host` returns `$null` at end of input and `$null -notmatch 'pattern'` evaluates to nothing rather than `$true`, which once let a run with no input available proceed and move files.
- **Only `~$` lock files are deleted**, which is what Office leaves behind when a document closes badly.
- **A file already in its destination is never judged a duplicate of itself.**
- **Every action is logged** with a timestamp, so a run can be unwound by hand from the log.

## Category folders and project folders

A plain run does two things, and nothing else:

1. **Loose files at the root** are sorted into the category folders.
2. **Loose files inside the category folders** are sorted out of them, so `Documents\screenshot.png` becomes `Pictures\screenshot.png`. A file already sitting in its own category folder is left alone without a row of its own.

A folder inside a category folder is a **project**. Nothing inside it is ever touched — not one file, at any depth. The only thing the run will consider is moving the folder as a whole, and only when its contents clearly belong in another category:

| What is in the folder | Where it belongs |
|---|---|
| Any real document type (`doc docx xls xlsx xlsm ppt pptx ppsx pdf rtf`) | `Documents` |
| Otherwise, one category holds most of the files | that category |
| Otherwise — a tie at the top | stays exactly where it is |
| Empty, or nothing but text-ish files and in-progress downloads | stays |

Text-ish files (`txt md log csv json xml html htm chm ini`) neither pin nor vote: a readme plus a help file must not drag a tool folder out of `Software`. Routed as individual files they still go to `Documents`.

A real render, from the folder that prompted this rule:

```
Organising: C:\Users\you\Downloads\Unsorted

  #  File Name  Source     File Type  Destination  Action
  -  ---------  ---------  ---------  -----------  -----------
  1  Sub3       Documents  Folder     Pictures     MOVE FOLDER

Notes
  Documents\Sub3 (10 pictures) -> Sub3

Already filed: 1 file(s) inside category folders left alone.

Summary: 0 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 0 skip, 1 folder move
```

`Documents\Sub1` (5 docx, 3 jpg, 1 xlsx) and `Documents\Sub2` (2 docx, 5 jpg, 1 xlsx) both stay where they are — they hold documents — while `Sub3` (10 jpg) moves whole to `Pictures\Sub3`.

Whole-folder moves are asked about separately from the file moves, because they are a bigger decision: `Move these 3 project folders to their matching category? [y/N]`, default No. `-MoveProjects` moves them without asking; `-Force` alone never moves one. A name clash at the destination renames the incoming folder to `Sub3 (2)` — nothing is ever merged.

## Subfolder scan

Off by default, and **only ever reached by typing the switch**. `-Recurse` (or `-MaxDepth N`) files everything, at any depth, into the target's *top-level* category folders — the subfolder structure is not preserved.

There is no prompt offering this. An early version asked `Also sort the 1003 files inside 90 subfolders?` in the double-click flow, which put every project folder one keystroke from being scattered — a folder in the tree is a project by design, so asking to flatten it contradicted the whole point. A plain run now cannot leave the two tidy levels, however many times you press Enter.

```
organize-downloads.bat -Recurse -WhatIf      # see what flattening would do, change nothing
organize-downloads.bat -MaxDepth 1           # one level down only
```

- Folders named after a category are never descended by this scan, so an existing `Documents\` is never flattened — its loose files are tidied by the level-2 pass instead, and the folders inside it are left as projects.
- Junctions and symbolic links are never followed.
- No run ever asks about subfolders, so a double-click and a scheduled run behave the same way: loose files only, unless the switch is passed.
- Subfolders are reported when they are left with no files, and the run then asks once: `Delete these N empty subfolders? [y/N]`, defaulting to No.
  - Only folders the scan visited are candidates: never the target itself, never a folder named after a category, never a link.
  - Deletion runs deepest-first so a parent that only held emptied children goes too, and each folder is re-checked immediately before the delete — anything that appeared since the plan is kept and logged `PRUNE-SKIPPED`.
  - `Remove-Item` is used without `-Recurse`, so a directory that still holds anything cannot be removed even if that check were bypassed.
  - `-Force` never asks and never prunes; `-Force -PruneEmpty` prunes without asking. `-WhatIf` exits long before this point.

Point this at a project tree and it will flatten it. That is the honest warning: on a 1000-file client folder a full-depth scan planned 843 moves, 126 renames and 32 duplicate deletions. Use `-MaxDepth 1` when you want a bounded pass.

## Long plans

The on-screen table caps at 60 rows so a long plan stays readable. Beyond that, the complete list is written to `organize-preview.txt` before the prompt and the path is announced — every row, every rename, duplicate and lock-file note, plus the summary. It is written on `-WhatIf` too, since a report about the folder changes nothing in it.

## Logging

`organize-log.txt` gets one line per action:

```
2026-11-06 10:59:38  MOVED            SubOne\a.pdf -> C:\Users\you\Downloads\Documents
2026-11-06 10:59:38  DUPLICATE        removed SubTwo\a.pdf; identical copy kept at ...\Documents\a.pdf
2026-11-06 10:59:38  SKIPPED          organize-downloads.ps1 (organiser file)
```

Action verbs: `MOVED`, `RENAMED`, `DUPLICATE`, `LOCK-DELETED`, `SKIPPED`, `CREATED-FOLDER`, `MOVED-FOLDER`, `RENAMED-FOLDER`, `FOLDER-SKIPPED`, `PRUNED-FOLDER`, `PRUNE-SKIPPED`, `ERROR`. Scanned files carry their source folder in the log line, so a multi-folder run can be reconstructed from the log alone.

Exit codes: `0` success or nothing to do, `1` an error occurred.

## Notes for anyone editing this

- **`Get-FileHash` is deliberately not used.** On machines where `PSModulePath` lists the PowerShell 7 module tree first, Windows PowerShell 5.1 cannot autoload `Microsoft.PowerShell.Utility` and the cmdlet does not exist. Hashing goes through `.NET` `SHA256` instead.
- **The `.bat` must stay CRLF.** Batch labels and `goto` misbehave on LF-only files.
- **`-Force` detection walks `%*` token by token** rather than piping through `findstr`, so a quoted path containing spaces, `&` or parentheses cannot break it or be mistaken for the switch.
- **OneDrive folders all report the reparse-point attribute** with an empty `LinkType`, so the subfolder scan filters on `LinkType` rather than the attribute — otherwise the entire tree is silently skipped.
- **Target resolution is the launcher's own folder, never its parent.** An early version sorted the parent, and a copy dropped into a subfolder tidied the folder above it instead.

## Repo layout

```
organize-downloads.ps1   the tool
organize-downloads.bat   double-click launcher
README.md
CHANGELOG.md
.gitattributes          pins CRLF for the .bat and .ps1 on checkout
.gitignore              keeps the runtime artefacts out of history
```

`organize-log.txt` and `organize-preview.txt` are runtime artefacts and are git-ignored; they are created beside the scripts when a run happens.

## Licence

Internal tooling. Not licensed for public reuse.
