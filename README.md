# Folder Organization

**Sorts loose files in a folder into extension-based category folders — preview first, one confirmation, and every action written to a log you can reverse from.**

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell_5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white)

A pair of files: `organize-downloads.ps1` does the work, `organize-downloads.bat` is the double-click launcher. Windows PowerShell 5.1 built-ins only — no installation, no admin rights, no dependencies.

It is deliberately dumb about meaning. Routing is by file extension and nothing else, so anything it does not recognise goes to `Other\` for you to re-file by hand. It will not guess that four PDFs belong to one client.

It tidies two levels, and only ever loose files: the root, and the inside of **every** subfolder. A screenshot left behind in `Documents\` finds its way to `Pictures\`, and the sixteen loose images in a `Media Assets\` folder reach `Pictures\` too. Nothing is held back for being unrecognisable — an unknown file goes to `Other\` like any other. A **folder** inside a subfolder is a project: nothing inside it is touched, and it moves whole to `Projects\`.

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
| `-PruneEmpty` | Delete the empty folders left after the moves, without asking. Interactive runs are asked once, deepest first. |
| `-MoveProjects` | Move the project folders the preview lists, without asking. Interactive runs are asked after the preview instead. |
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
| `Projects` | nothing — a project folder gets there by being moved, never by a file being filed into it |

The whole table lives in one ordered hashtable at the top of the `.ps1`. Edit it there; nothing else needs to know.

## Safety rules

These are implemented, not aspirational:

- **Nothing is overwritten.** A name clash is resolved by comparing SHA256: identical bytes means the incoming copy is deleted and logged as `DUPLICATE`; different bytes means the incoming file is renamed `name (2).ext` and logged as `RENAMED`. The hash is compared again at deletion time, so a file edited after the preview is kept and logged `DUPLICATE-SKIPPED` instead of being removed.
- **Two files can never claim one destination** within a single run, including across subfolders. The same identical-or-rename rule applies.
- **Directories are never taken apart, and never deleted without a yes.** A project folder moves only as a whole, and only when you approve it; empty folders are reported on every run and deleted only on your answer, or with `-PruneEmpty`. The target folder itself and the eight category folders are never candidates, and `-Force` alone never deletes anything.
- **A project folder is opaque to files.** Not one file inside a folder that lives in a bucket is moved, renamed or deleted, at any depth, and a root folder is never relocated. Empty *directories* inside it are still fair game for the delete question — say No if a project's skeleton matters to you. The folder itself moves to `Projects\` as one piece, keeping its bucket (`Projects\Work\Clients`), so two unrelated folders called `Scripts` stay apart instead of becoming `Scripts` and `Scripts (2)`.
- **Unknown files are not special.** A `.dwg`, a `.py` or a `.bak` has no better home than `Other\`, and that is where it goes — the same rule as a screenshot. `Other\` is a category, not a scrap heap you have to sort out.
- **Tooling folders are never entered** — dotted names, `node_modules`, `__pycache__`, `System Volume Information`, `$RECYCLE.BIN` — and neither are junctions or symbolic links.
- **The tool never moves itself.** `organize-downloads.ps1`, `organize-downloads.bat`, `organize-log.txt` and `organize-preview.txt` are reported as `SKIP` and left where they are.
- **Partial downloads are left alone** — `.crdownload`, `.part`, `.partial`, `.tmp`, `.download` — as are `desktop.ini` and `thumbs.db`.
- **No input is a no.** Every confirmation is cast to a string and trimmed before it is tested, so an absent, blank or unrecognised answer aborts. `Read-Host` returns `$null` at end of input and `$null -notmatch 'pattern'` evaluates to nothing rather than `$true`, which once let a run with no input available proceed and move files.
- **Only `~$` lock files are deleted**, which is what Office leaves behind when a document closes badly.
- **A file already in its destination is never judged a duplicate of itself.**
- **Every action is logged** with a timestamp, so a run can be unwound by hand from the log.

## Buckets, projects and empty folders

A plain run does three things, and nothing else:

1. **Loose files at the root** are sorted into the category folders.
2. **Loose files inside every immediate subfolder** are sorted out of them, so `Documents\screenshot.png` becomes `Pictures\screenshot.png` and `Media Assets\background.jpg` becomes `Pictures\background.jpg`. A file already sitting in its own category folder is left alone without a row of its own.
3. **Folders left holding no files** are reported, and offered for deletion.

Level one is **buckets**, level two is **projects**. A bucket is any immediate subfolder, category or not. A folder inside a bucket is a project: it is never entered, and it can only ever move as a whole.

| Where a folder sits | What happens to it |
|---|---|
| Inside a category bucket (`Documents\Sub3`) | relocated by contents: any real document type pins it to `Documents`, otherwise the majority category wins, and a tie or a text-only folder leaves it alone |
| Inside any other bucket (`05_Admin\06_Engine`) | relocated whole to `Projects\<bucket>\<name>`, contents untouched |
| Inside `Projects\` already | left alone — that is where it belongs |

The contents rule only applies to category buckets, and it is deliberately narrow:

| What is in the folder | Where it belongs |
|---|---|
| Any real document type (`doc docx xls xlsx xlsm ppt pptx ppsx pdf rtf`) | `Documents` |
| Otherwise, one category holds most of the files | that category |
| Otherwise — a tie at the top | stays exactly where it is |
| Empty, or nothing but text-ish files and in-progress downloads | stays |

Text-ish files (`txt md log csv json xml html htm chm ini`) neither pin nor vote: a readme plus a help file must not drag a tool folder out of `Software`. Routed as individual files they still go to `Documents`.

Here is a real render from a test folder, with `-WhatIf`:

```
Organising: C:\Users\you\Downloads\Unsorted

#  File Name    Source     File Type  Destination     Action
-  -----------  ---------  ---------  --------------  -----------
1  archive.zip  .          Archive    Archives        MOVE
2  invoice.pdf  .          PDF        Documents       MOVE
3  build.log    05_Admin   Log        Other           MOVE
4  notes.txt    05_Admin   Text       Documents       MOVE
5  stray.png    Documents  Image      Pictures        MOVE
6  06_Engine    05_Admin   Folder     Projects\05...  MOVE FOLDER
7  Sub3         Documents  Folder     Pictures        MOVE FOLDER

Notes
05_Admin\06_Engine (2 file(s), kept together) -> Projects\05_Admin\06_Engine
Documents\Sub3 (10 pictures) -> Pictures\Sub3

Category folders to create: Archives, Music, Other, Pictures, Projects, Software, Videos
Empty folders after this run: 1 (05_Admin)
You will be asked whether to delete them.

Summary: 5 move, 0 rename, 0 duplicate-remove, 0 lock-remove, 0 skip, 2 folder move
```

Note rows 3 and 4: `05_Admin` is not a category bucket, so its loose files are filed like any others — the `.log` to `Other`, the `.txt` to `Documents` — and the folder is then empty.

Whole-folder moves are asked about separately from the file moves, because they are a bigger decision: `Move these 2 project folders to their matching category? [y/N]`, default No. `-MoveProjects` moves them without asking; `-Force` alone never moves one. A name clash renames the incoming folder `Sub3 (2)` — nothing is ever merged.

### Every run leaves the structure

All eight category folders — `Archives`, `Documents`, `Music`, `Other`, `Pictures`, `Projects`, `Software`, `Videos` — exist after any real run, whether or not anything was filed into them. A folder that is already tidy is still a folder that should be ready for the next file, so the preview names the ones that will be created before you answer. `-WhatIf` creates nothing.

### Empty folders

After the moves, everything left holding no files at any depth is reported and offered for deletion — on a normal run, not only under `-Recurse`:

```
Empty folders: 3 (05_Admin, Media Assets, Projects\06_Engine\Logs)
Delete these 3 empty folders? [y/N]
```

- Candidates are evaluated *after* the moves, so a bucket that handed over its files is judged empty and a folder that has since gained a file is not.
- Never candidates: the target folder itself, the eight category folders (they are structure, not debris), dotted folders, tooling trees, and any link.
- Deepest first, so a parent that held only emptied children goes too. Each folder is re-checked immediately before the delete — anything that appeared is kept and logged `PRUNE-SKIPPED`.
- A file arriving in the instant between that check and the removal makes the removal *fail*, never the file disappear: `Remove-Item` runs without `-Recurse`, so a directory that holds anything cannot be taken.
- `Remove-Item` is used without `-Recurse`, so a directory that still holds anything cannot be removed even if that check were bypassed.
- `-Force` never prunes; `-Force -PruneEmpty` prunes without asking.

Because this reaches inside project folders, an empty `Projects\06_Engine\Logs` is a candidate too. Files are never touched, but a project's empty scaffolding can disappear — answer No if that structure matters.

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
- Empty folders are offered for deletion exactly as in a plain run — the same question, the same guards, the same candidates. The switch adds flattening, not pruning.

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
