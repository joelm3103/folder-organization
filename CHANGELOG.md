# Changelog

All notable changes to Folder Organization are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this repo has no release cadence, so
**sections are dated rather than versioned** - newest first, one section per day the work landed,
instead of everything accumulating in one unreleased block.

Two conventions, so an entry is never read as more than it is:

- An entry stays under the date the work **landed**, even where the artifact was revised later;
  any later measurement or rewrite is named inside the entry.
- An entry recorded after the fact **says so**, so a retrospective note cannot be mistaken for a
  same-day record.

## [2026-11-06]

**In short:**

- The organiser exists in the shape it is published in: extension-routed sorting with a preview
  table, hash-checked collisions, a log, and a double-click launcher.
- Two defects that only a real folder exposes are fixed: the tool sorted the folder *above* the one
  it was placed in, and its subfolder scan silently skipped every OneDrive folder.
- Long plans gained a full-list export, so a 1000-row decision is never made from a 60-row screen.
- A subfolder sort no longer leaves an empty skeleton behind: the run offers to delete the folders
  it emptied, and `-PruneEmpty` does that unattended.
- A plain run also tidies the inside of the category folders, and treats a folder found there as a
  project that moves whole — or not at all.
- Every bucket gives up all its files, project folders collect under `Projects\<bucket>\`, the eight
  category folders are scaffolded on any real run, and empty folders are offered for deletion every time.

- The level-1 sweep now covers **every immediate subfolder**, not only folders named after a category, so
  loose files in `Media Assets\`, `Work\` or `Others\` are filed instead of ignored. On a live staging
  folder that turned 1 move into 20 without touching the internal structure of a single project.
- ~~A file only leaves a subfolder that is not a category when the tool knows where it belongs: if the
  routed destination would be the fallback `Other\`, the file stays and is reported.~~ **Superseded
  later the same day** - see "every bucket gives up all its files" under Changed.
- ~~`Retained in place` report~~: **superseded** with the rule it described; the console block, the
  `RETAINED` log line and the export section were all removed in the same pass.
- Tooling folders are never swept: dotted names, `node_modules`, `__pycache__`, `System Volume
  Information`, `$RECYCLE.BIN`, and anything reporting a `LinkType` (junctions, symlinks, OneDrive).

- `Projects\` bucket: a folder found inside a bucket that is not a category is a project and moves whole
  to `Projects\<bucket>\<name>`, keeping the bucket it came from so two unrelated `Scripts` folders stay
  apart instead of becoming `Scripts` and `Scripts (2)`. Contents are never entered, and a folder already
  inside `Projects\` is left alone.
- Category scaffolding: `Archives`, `Documents`, `Music`, `Other`, `Pictures`, `Projects`, `Software` and
  `Videos` all exist after any real run, whether or not anything was filed into them. The preview names
  the ones it will create before the prompt; `-WhatIf` creates nothing.
- Empty-folder pruning on every run, not just under `-Recurse`: every folder holding no files at any
  depth is listed and offered for deletion, deepest first. Never the target itself, the eight category
  folders, dotted folders, tooling trees or links. Each folder is re-checked immediately before a
  non-recursive removal, `-PruneEmpty` prunes unattended, and `-Force` alone deletes nothing.

### Added

- `organize-downloads.ps1` and `organize-downloads.bat`: extension-based sorting into `Archives`,
  `Documents`, `Pictures`, `Software`, `Videos`, `Music` and `Other`, driven by one ordered hashtable
  in the script.
  - Windows PowerShell 5.1 built-ins only. No install, no admin rights, no dependencies.
  - Dry-run preview by default with a `[y/N]` prompt; `-WhatIf` prints and exits; `-Force` runs
    unattended.
- SHA256 collision handling: identical bytes deletes the incoming copy as `DUPLICATE`, different
  bytes renames it `name (2).ext` as `RENAMED`. Nothing is ever overwritten.
- Per-run destination tracking, so two files from different subfolders cannot both claim one name —
  the same identical-or-rename rule decides, at planning time rather than mid-move.
- Action log `organize-log.txt` beside the scripts: one timestamped line per action
  (`MOVED`, `RENAMED`, `DUPLICATE`, `LOCK-DELETED`, `SKIPPED`, `CREATED-FOLDER`, `ERROR`), with the
  source folder of scanned files so a multi-folder run can be unwound from the log alone.
- Preview rendered as a five-column table (`#`, `File Name`, `File Type`, `Destination`, `Action`)
  with friendly type labels (`Excel`, `Web Shortcut`, `Remote Desktop`), width caps, ASCII `...`
  truncation, and a Notes block that keeps the full target and reason for every rename, duplicate
  and lock-file row.
- Optional subfolder scan via `-Recurse`, or `-MaxDepth N` for a bounded pass.
  - No run asks about subfolders: `-Recurse` or `-MaxDepth` is the only way in, so a double-click can
    never flatten the tree it was dropped into.
  - Files at any depth are filed into the target's top-level category folders. Folders named after a
    category are never descended, and junctions and symbolic links are never followed.
  - Subfolders left with no files are reported, and the run then offers once to delete them; answering
    No, or running without `-PruneEmpty`, leaves every folder in place.
- Self-protection: `organize-downloads.ps1`, `organize-downloads.bat`, `organize-log.txt` and
  `organize-preview.txt` are reported as `SKIP` and never moved or duplicated by a run.
- Post-sort pruning of the folders the scan emptied, as one question after the moves:
  `Delete these N empty subfolders? [y/N]`, defaulting to No.
  - Candidates are only folders the scan visited that hold no file at any depth beneath them: never
    the target itself, never a folder named after a category, never a junction or link.
  - Deepest-first, and each folder is re-checked immediately before the delete, so anything that
    appeared since the plan is kept and logged `PRUNE-SKIPPED`. `Remove-Item` runs without
    `-Recurse`, so a non-empty directory cannot be removed even if that check were bypassed.
  - `-Force` never prompts and never prunes; `-Force -PruneEmpty` prunes unattended; `-WhatIf` exits
    before execution, so a dry run asks nothing and deletes nothing.
  - One `PRUNED-FOLDER` line per removal, and a prune failure counts as a run failure and exits 1.
  - Verified on disposable trees: the yes and no answers, `-Force` with and without the switch,
    `-WhatIf`, the still-holds-content guard, a category-named folder left alone, and a delete
    refused by access rights leaving that folder intact while the run exited 1.
- Full-list export: when the plan exceeds the 60-row screen cap, every row, note and the summary are
  written to `organize-preview.txt` before the prompt, with the path announced.
  - Written on `-WhatIf` too, because the report describes the folder and changes nothing in it.
  - Wider column caps apply in the file (name 80, source 60) since there is no screen to fit.
  - Verified at 1004 rows on a real 1000-file tree; a 73-row run produced 73 numbered rows plus its
    duplicate note.
- `-Path`, `-LogFile` and `-PreviewFile` overrides.

- Two-level tidy in a plain run: loose files at the root, then loose files sitting directly inside
  each category folder, so a screenshot left in `Documents\` reaches `Pictures\`. A file already
  sitting in its own category folder is left alone without a row of its own, and the count of those
  is reported instead.
- Project folders: a folder inside a category folder is opaque and is only ever considered as a
  whole. Real document types (`doc docx xls xlsx xlsm ppt pptx ppsx pdf rtf`) pin it to `Documents`;
  otherwise the largest category among its files decides; a tie, an empty folder, or a folder made
  only of text-ish files leaves it exactly where it is.
  - Text-ish files (`txt md log csv json xml html htm chm ini`) neither pin nor vote, so a readme
    plus a help file cannot drag a utility folder out of `Software`.
  - The decision is asked separately from the file moves (`Move these N project folders ...?`,
    default No); `-MoveProjects` does it unattended and `-Force` alone never moves a folder.
  - A name clash at the destination renames the incoming folder `Sub3 (2)`; existing folders are
    never merged into.
  - Logged as `MOVED-FOLDER`, `RENAMED-FOLDER` or `FOLDER-SKIPPED`, and the target is re-checked
    immediately before the move so a folder that appeared meanwhile is never silently absorbed.
  - Verified against the worked example: `Sub1` (5 docx, 3 jpg, 1 xlsx) and `Sub2` (2 docx, 5 jpg,
    1 xlsx) stay in `Documents`, `Sub3` (10 jpg) moves whole to `Pictures\Sub3`.

- The interactive `Also sort the N files inside M subfolders?` question is gone. It made flattening a
  keystroke away for anyone double-clicking, which is precisely what the level-2 tidy was introduced
  to stop: a folder in the tree is a project, and a project is not entered. `-Recurse` / `-MaxDepth`
  are now the only route, typed deliberately. Side effect: a plain run walks no directories at all,
  and the prompt sequence is down to one question.
- A root folder is never relocated. Whole-folder moves stay limited to the children of category folders, so
  `Media Assets` cannot be swept into `Pictures` as a folder just because it happens to hold images.
- The sweep is skipped entirely under `-Recurse`, which walks those same folders itself; enumerating them
  both ways made every depth-1 file a duplicate of itself.
- The export header now reads `Buckets : N folder(s) swept, M file(s), K already in place` plus
  `Retained : R file(s)`, replacing the category-only line.

- **The retention rule is retired.** A file whose only destination is `Other\` now leaves its bucket
  like every other file. `Mobile VPN\`'s certificates, `Sync Configs\` shortcuts and an `Others\` `.ps1`
  all move to `Other\`; the buckets are then empty and become deletion candidates. Reverses the rule
  added earlier the same day, deliberately: `Other\` is a category, not a scrap heap.
- The help text and the README no longer claim a project folder is wholly untouched: pruning has always
  reached inside one, so the promise is now stated as files — not one file is moved, renamed or
  deleted there — with empty directories named as the exception. A first real run proved the point by
  pruning five empty folders inside `Projects\Others\ADQRCODEV2TEST`.
- A project found inside a category bucket is still judged by its contents (`Documents\Sub3` with 10 jpg
  moves to `Pictures\Sub3`, a folder pinned by document types goes to `Documents`, a tie stays), while a
  project found inside any other bucket goes to `Projects\<bucket>\` regardless of contents. Two rules,
  one per kind of bucket.
- The early exit now needs more than "no files to move": it is silent only when there are also no
  project moves, no category folders to create and no empty folders to offer. A run that would only
  scaffold or only prune still asks first.
- Execution order is files, then project folders, then scaffolding, then pruning, so a bucket emptied by
  a folder move is judged empty in the same run.

### Changed

- Target resolution is now the launcher's own folder (`$ScriptDir`), never its parent. A copy placed
  in a subfolder sorts that subfolder.
- A warning is printed when the target folder name is itself a category name, since its files would
  then be sorted into a nested category folder inside it.
- `-Recurse` and `-MaxDepth` remain the way to flatten a tree *outside* the category folders; the
  level-2 tidy is separate and never flattens a project. A category folder is still never
  descended by the recursive scan.
- The launcher window now stays open at the end and prints the exit code, so a double-click result
  can actually be read. `-Force` skips the pause for scheduled runs.
- The console title reads `Folder Organization Script` rather than naming one specific folder, since
  the launcher is reused elsewhere.

### Fixed
- **Pruning looked inside tooling trees.** The empty-folder walk refused a candidate whose own name was
  in the skip list or started with a dot, but still enumerated its children — so an empty
  `bucket\.git\objects\tmp` was offered for deletion even though `.git` is never entered. Every path segment
  is now checked, not just the leaf, so a candidate inside a protected tree is refused too. Verified on a
  project holding `.git\objects\empty` and `node_modules\pkg\dist`: three genuine empties were pruned, both
  tooling trees survived.
- **A duplicate was deleted on a hash compared before the prompt.** The identical-bytes decision was made
  at planning time, then the file was removed minutes later without re-checking. A file edited while the
  preview sat on screen would have been deleted as a copy of something it no longer matched. The hash is
  now compared again immediately before the removal, and a mismatch keeps the file and logs
  `DUPLICATE-SKIPPED`. Verified by fault injection — a scripted edit to the source between planning and
  execution left the file in place with the log line `no longer identical to ...`.
- **The preview missed buckets emptied only by a lock file.** A `~$` file is deleted on execution, but
  its path was not counted as departing, so a bucket holding nothing else was not predicted empty. Added
  to the departing set; a bucket with one lock file and one stale document now reports `Empty folders
  after this run: 1`.

### Fixed

- A run whose confirmation prompt received no input at all **proceeded instead of aborting**, moving
  files without a yes. `Read-Host` returns `$null` at end of input and `$null -notmatch 'pattern'`
  evaluates to nothing, so `if ($answer -notmatch ...)` fell through. Every answer is now cast to a
  string and trimmed first, so absent, blank, whitespace and unrecognised answers are all a no.
  Found the hard way: an empty line piped into a live folder moved a file, and the action log named the
  run that did it. Regression matrix now covers no input, blank, spaces, `n`, junk, `y`, `Y`, `Yes`
  and ` y ` across the proceed, project-folder and prune prompts.

- The organiser sorted one folder *up* from where it lived: a line deriving the target as
  `Split-Path -Parent $ScriptDir`, correct only while the script sat in a category folder, meant a
  copy in a staging folder tidied the folder above it. Confirmed by a run that moved 27 files out of
  a desktop root instead of the staging folder it was launched from.
- The subfolder scan found nothing on OneDrive trees. OneDrive marks every synced folder with the
  reparse-point attribute and an empty `LinkType`, so the junction guard skip-matched the entire
  tree; the guard now tests `LinkType`, which is what actually distinguishes a link from a cloud
  placeholder.
- The preview header and its dashed rule ended at different columns once a `DUPLICATE` row widened
  the action column, because the header's action cell was not padded. Header and rule now end
  together.
- `Get-FileHash` is not used: on a machine whose `PSModulePath` lists the PowerShell 7 module tree
  first, Windows PowerShell 5.1 cannot autoload `Microsoft.PowerShell.Utility` and the cmdlet does
  not exist. Hashing goes through .NET `SHA256` instead, which needs no module.
- The launcher no longer relies on a pipe or `findstr` to detect `-Force`; it walks `%*` token by
  token, so a quoted path containing spaces, `&` or parentheses cannot break the check.
