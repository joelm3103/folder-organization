# Folder Organization

**Sorts loose files in a folder into extension-based category folders — preview first, one confirmation, and every action written to a log you can reverse from.**

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell_5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white)

A pair of files: `organize-downloads.ps1` does the work, `organize-downloads.bat` is the double-click launcher. Windows PowerShell 5.1 built-ins only — no installation, no admin rights, no dependencies.

It is deliberately dumb about meaning. Routing is by file extension and nothing else, so anything it does not recognise goes to `Other\` for you to re-file by hand. It will not guess that four PDFs belong to one client.

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
- **Directories are never moved, and only ever deleted with your explicit yes.** A subfolder scan reports the folders it emptied and offers to delete them at the end; nothing is removed without that answer or `-PruneEmpty`, and the target folder itself and every category folder are never candidates.
- **The tool never moves itself.** `organize-downloads.ps1`, `organize-downloads.bat`, `organize-log.txt` and `organize-preview.txt` are reported as `SKIP` and left where they are.
- **Partial downloads are left alone** — `.crdownload`, `.part`, `.partial`, `.tmp`, `.download` — as are `desktop.ini` and `thumbs.db`.
- **Only `~$` lock files are deleted**, which is what Office leaves behind when a document closes badly.
- **A file already in its destination is never judged a duplicate of itself.**
- **Every action is logged** with a timestamp, so a run can be unwound by hand from the log.

## Subfolder scan

Off by default. `-Recurse` (or `-MaxDepth N`) files everything, at any depth, into the target's *top-level* category folders — the subfolder structure is not preserved. Interactive runs are asked first, with both counts, and the default is No:

```
Also sort the 1000 files inside 90 subfolders? Their folder structure is not preserved.
```

- Folders named after a category are never descended, so an existing `Documents\` is left intact.
- Junctions and symbolic links are never followed.
- `-WhatIf` and `-Force` never ask, so unattended runs stay deterministic and root-only unless the switch is passed.
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

Action verbs: `MOVED`, `RENAMED`, `DUPLICATE`, `LOCK-DELETED`, `SKIPPED`, `CREATED-FOLDER`, `PRUNED-FOLDER`, `PRUNE-SKIPPED`, `ERROR`. Scanned files carry their source folder in the log line, so a multi-folder run can be reconstructed from the log alone.

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
