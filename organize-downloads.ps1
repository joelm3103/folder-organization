<#
.SYNOPSIS
    Sorts loose files in a folder into extension-based category folders.

.DESCRIPTION
    Extension-only ruleset. It does NOT reason about projects or topics: anything it does not
    recognise goes to Other\ and you re-file it by hand.

    The folder it organises is the folder it lives in - drop this script and its .bat into the
    folder you want sorted and run it there. -Path overrides that.

    By default only loose files are touched, at two levels: files sitting directly in the folder, and
    files sitting directly inside each of its subfolders - every subfolder, category or not. That is
    what lets a screenshot left in Documents\ reach Pictures\, and the sixteen loose images in a
    Media Assets\ folder reach Pictures\ too. A file already sitting in its own category folder is
    left alone without being listed.

    A file only leaves a subfolder that is not a category when the tool knows what it is. Category
    folders are machine-owned, so a stray file inside them is routed in full, Other\ included. Any
    other subfolder belongs to you: its recognised files are filed out, and anything that would land
    in Other\ is left where it is and reported at the end, so you can decide whether to move it by
    hand. Mobile VPN\ therefore keeps its certificates, and Sync Configs\ its shortcuts.

    A folder inside a subfolder is treated as a project: nothing inside it is ever moved or deleted,
    and a root folder is never relocated. Only the children of a category folder are considered for
    a whole-folder move, and only when the contents clearly belong elsewhere. Real document types
    (doc, docx, xls, xlsx, ppt, pptx, ppsx, pdf, rtf) pin such a folder to Documents; otherwise the
    single largest category among its files decides, and a tie leaves the folder where it is.
    Interactive runs are asked before any folder moves; -MoveProjects does it unattended, and -Force
    alone never moves one.

    -Recurse (or -MaxDepth N) additionally scans subfolders outside the category folders and files
    everything into the top-level category folders; that structure is NOT preserved. This is the only
    way to flatten a tree: a double-click never asks, so a plain run can only ever tidy loose files at
    the two levels below. Pass the switch deliberately when you mean it.
    When a scan leaves subfolders with no files in them, the run ends by offering to delete those
    folders too; -PruneEmpty does it without asking. No directory is ever removed without one of
    those two - a plain run, and any -Force run without the switch, leaves every folder in place.

    When the plan is longer than the on-screen table (60 rows), the complete list is written to
    organize-preview.txt before the confirmation prompt, so every row - and every rename, duplicate
    or lock-file decision - can be read without losing any of them to the row cap. A dry run writes
    that report too; it is a report, not a change to the folder being sorted.

    Collisions are handled, not overwritten:
      * destination already holds the same name with identical bytes  -> incoming copy deleted
      * destination already holds the same name with different bytes -> incoming copy renamed "(2)"
      * two files in the same run claiming one destination            -> same rules, tracked up front

    The script never moves or deletes its own files: organize-downloads.ps1, organize-downloads.bat
    and organize-log.txt are listed as SKIP rows.

    Default is a preview plus a [y/N] prompt. -WhatIf previews and exits. -Force runs unattended.
    Nothing asks about subfolders any more: only -Recurse or -MaxDepth reaches them, so a double-click
    can never flatten the tree it was dropped into.

.PARAMETER Path
    Folder to organise. Defaults to the folder this script lives in.

.PARAMETER Recurse
    Also sort files found in subfolders, into this folder's category folders. Subfolder structure is
    not preserved, so this flattens a project tree - it is the only way to do that, and no run ever
    asks you. Use -WhatIf first.

.PARAMETER MaxDepth
    Limit how deep the scan goes, counting immediate subfolders as depth 1. Implies -Recurse.

.PARAMETER PruneEmpty
    Delete the subfolders the scan emptied, without asking. Interactive runs are asked after the
    sort instead; -Force never prompts, so this switch is how an unattended run prunes.

.PARAMETER MoveProjects
    Move the project folders whose contents belong in another category, without asking.
    Interactive runs are asked after the preview instead; -Force never prompts, so this switch is
    how an unattended run relocates a folder.

.PARAMETER WhatIf
    Print the planned actions and exit without changing anything.

.PARAMETER Force
    Execute without the confirmation prompt (for Task Scheduler).

.PARAMETER LogFile
    Override the action log path. Defaults to organize-log.txt next to this script.

.PARAMETER PreviewFile
    Override the full-list report path. Defaults to organize-preview.txt next to the log.

.EXAMPLE
    .\organize-downloads.bat
    Sort the folder the launcher sits in, after showing a preview.

.EXAMPLE
    .\organize-downloads.bat -WhatIf
    Preview only, change nothing.

.EXAMPLE
    .\organize-downloads.bat -Recurse -WhatIf
    Preview a subfolder scan without changing anything.

.EXAMPLE
    .\organize-downloads.bat -MaxDepth 1
    Sort this folder and its immediate subfolders, leaving deeper trees alone.

.EXAMPLE
    .\organize-downloads.bat -MoveProjects -Force
    Tidy the category folders and relocate any project folder that clearly belongs elsewhere,
    without asking anything.

.NOTES
    Windows PowerShell 5.1 built-ins only. No admin rights required.
#>

param(
    [string]$Path,
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$Recurse,
    [int]$MaxDepth = 0,
    [switch]$PruneEmpty,
    [switch]$MoveProjects,
    [string]$LogFile,
    [string]$PreviewFile
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# The folder to organise is the folder this script lives in. Never its parent: a copy dropped into
# a working folder must sort that folder, not whatever happens to be above it.
if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = $ScriptDir
}
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $ScriptDir 'organize-log.txt'
}
if ([string]::IsNullOrWhiteSpace($PreviewFile)) {
    $PreviewFile = Join-Path (Split-Path -Parent $LogFile) 'organize-preview.txt'
}
if ($MaxDepth -lt 0) {
    Write-Host 'ERROR: -MaxDepth must be zero or greater.' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Host "ERROR: folder not found: $Path" -ForegroundColor Red
    exit 1
}
$Path = (Resolve-Path -LiteralPath $Path).ProviderPath

# ---------------------------------------------------------------- ruleset
$Rules = [ordered]@{
    'Archives'  = @('zip','tar','gz','tgz','rar','7z')
    'Documents' = @('pdf','doc','docx','xls','xlsx','xlsm','ppt','pptx','ppsx','csv','eml','msg',
                    'txt','rtf','html','htm','xml','json','md','chm')
    'Pictures'  = @('png','jpg','jpeg','gif','bmp','webp','svg','tif','tiff','ico','psd')
    'Software'  = @('exe','msi','msix','msixbundle','bin','iso','apk')
    'Videos'    = @('mp4','avi','mkv','mov','wmv','webm','m4v','flv','mpg','mpeg')
    'Music'     = @('mp3','wav','m4a','aac','flac','ogg','gsm','wma')
}
$Fallback = 'Other'

# Friendly type labels for the preview table. Anything unlisted falls back to its upper-cased
# extension, and a file with no extension is just "File".
$FileTypes = @{
    'pdf'  = 'PDF';        'doc'  = 'Word';         'docx' = 'Word';       'rtf'  = 'Rich Text'
    'xls'  = 'Excel';      'xlsx' = 'Excel';        'xlsm' = 'Excel';      'csv'  = 'CSV'
    'ppt'  = 'PowerPoint'; 'pptx' = 'PowerPoint';   'ppsx' = 'Slide Show'
    'txt'  = 'Text';       'md'   = 'Markdown';     'log'  = 'Log'
    'url'  = 'Web Shortcut'; 'lnk' = 'Shortcut';     'rdp'  = 'Remote Desktop'
    'ini'  = 'Config';     'cfg'  = 'Config';       'conf' = 'Config'
    'reg'  = 'Registry';   'bat'  = 'Batch';        'cmd'  = 'Batch'
    'ps1'  = 'PowerShell'; 'py'   = 'Python';       'js'   = 'JavaScript'
    'json' = 'JSON';       'xml'  = 'XML';          'html' = 'Web Page';   'htm'  = 'Web Page'
    'eml'  = 'Email';      'msg'  = 'Email';        'ics'  = 'Calendar'
    'zip'  = 'Archive';    '7z'   = 'Archive';      'rar'  = 'Archive'
    'tar'  = 'Archive';    'gz'   = 'Archive';      'tgz'  = 'Archive'
    'exe'  = 'Executable'; 'msi'  = 'Installer';    'msix' = 'Installer'
    'iso'  = 'Disk Image'; 'apk'  = 'Android App'
    'png'  = 'Image';      'jpg'  = 'Image';        'jpeg' = 'Image'
    'gif'  = 'Image';      'bmp'  = 'Image';        'webp' = 'Image'
    'tif'  = 'Image';      'tiff' = 'Image';        'ico'  = 'Icon'
    'svg'  = 'Vector Image'; 'psd' = 'Photoshop'
    'mp4'  = 'Video';      'mkv'  = 'Video';        'mov'  = 'Video'
    'avi'  = 'Video';      'wmv'  = 'Video';        'webm' = 'Video'
    'mp3'  = 'Audio';      'wav'  = 'Audio';        'm4a'  = 'Audio'
    'drawio' = 'Diagram';  'chm'  = 'Help File';    'bkp'  = 'Backup'
}

# Explicitly unroutable: never moved, never deleted.
$SkipExtensions = @('crdownload','part','partial','tmp','download')
$SkipNames      = @('desktop.ini','thumbs.db')

# The organiser's own files: always left exactly where they are.
$ToolFiles = @('organize-downloads.ps1','organize-downloads.bat','organize-log.txt','organize-preview.txt')

$Map = @{}
foreach ($cat in $Rules.Keys) {
    foreach ($ext in $Rules[$cat]) { $Map[$ext] = $cat }
}
$Categories = @($Rules.Keys) + @($Fallback)

# Extensions that pin a project folder to Documents. Deliberately narrow: a readme.txt or a licence
# file must not drag a tool folder out of Software, so text-ish formats are not in this list.
$PinTypes = @('doc','docx','xls','xlsx','xlsm','ppt','pptx','ppsx','pdf','rtf')

# Text-ish files neither pin a folder nor vote on where it belongs: a readme plus a help file must
# not outvote the two executables a tool folder is actually made of. They are still routed to
# Documents like any other file - this list only governs the project-folder decision.
$WeakDocTypes = @('txt','md','log','csv','json','xml','html','htm','chm','ini')

# ---------------------------------------------------------------- helpers
# Hashing goes through .NET, not Get-FileHash: on this machine PSModulePath lists the PowerShell 7
# module tree first, so Windows PowerShell 5.1 cannot autoload Microsoft.PowerShell.Utility and
# Get-FileHash is not a recognised cmdlet.
function Get-Hash([string]$file) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($file)
        try {
            $bytes = $sha.ComputeHash($stream)
        }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '')
}

function Write-Log([string]$action, [string]$detail) {
    $line = '{0}  {1,-16} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $action, $detail
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Get-TypeLabel([string]$ext) {
    if ([string]::IsNullOrEmpty($ext)) { return 'File' }
    if ($FileTypes.ContainsKey($ext)) { return $FileTypes[$ext] }
    return $ext.ToUpperInvariant()
}

# Pad to the column width, trimming an over-long value with an ASCII ellipsis so the table never
# wraps and the alignment of every later column survives.
function Format-Cell([string]$text, [int]$width) {
    if ($null -eq $text) { $text = '' }
    if ($text.Length -le $width) { return $text.PadRight($width) }
    if ($width -le 3) { return $text.Substring(0, $width) }
    return $text.Substring(0, $width - 3) + '...'
}

# Same idea, but the tail is kept: a folder path is only useful if its end survives.
function Format-CellTail([string]$text, [int]$width) {
    if ($null -eq $text) { $text = '' }
    if ($text.Length -le $width) { return $text.PadRight($width) }
    if ($width -le 3) { return $text.Substring($text.Length - $width) }
    return ('...' + $text.Substring($text.Length - ($width - 3))).PadRight($width)
}

# The reason a row is not a plain move, as one line. Shared by the screen table and the export so
# the two can never drift apart.
function Get-NoteText($row) {
    $item = $row.Item
    if ($row.Act -eq 'MOVE FOLDER' -or $row.Act -eq 'RENAME FOLDER') {
        $tail = Split-Path -Leaf $item.Target
        if ($row.Act -eq 'RENAME FOLDER') {
            return ('{0}\{1} ({2}) -> {3} (name clash, folder renamed)' -f $item.Rel, $item.Name, $item.Detail, $tail)
        }
        return ('{0}\{1} ({2}) -> {3}' -f $item.Rel, $item.Name, $item.Detail, $tail)
    }
    $where = if ($item.Rel -eq '.') { $row.Name } else { $item.Rel + '\' + $row.Name }
    switch ($row.Act) {
        'RENAME'    { return ('{0} -> {1} (name clash, different content)' -f $where, (Split-Path -Leaf $item.Target)) }
        'DUPLICATE' { return ('{0} -> identical copy at {1}; this one is removed' -f $where, $item.Target) }
        'LOCK'      { return ('{0} -> lock file, removed' -f $where) }
    }
    return $where
}

# The files the sweep deliberately walked past, grouped by the folder that keeps them. This is the
# part a person acts on by hand, so it is shown on screen (capped) and in full in the exported report.
function Show-RetainedReport($retained) {
    if ($retained.Count -eq 0) { return }
    Write-Host ''
    Write-Host ('Retained in place - not recognised, so their folder keeps them: {0}' -f $retained.Count) -ForegroundColor DarkYellow
    $nameCap = 6
    foreach ($group in @($retained | Group-Object Rel | Sort-Object Name)) {
        $names = @($group.Group | ForEach-Object { $_.File.Name })
        $line = '  {0,-16} {1,4}  ' -f $group.Name, $names.Count
        if ($names.Count -gt $nameCap) {
            $line = $line + ($names[0..($nameCap - 1)] -join ', ') + ('  ... {0} more' -f ($names.Count - $nameCap))
        }
        else {
            $line = $line + ($names -join ', ')
        }
        Write-Host $line -ForegroundColor DarkGray
    }
}

# A destination name that is free both on disk and in this run's plan.
function Get-UniquePath([string]$dir, [string]$name, [hashtable]$Reserved) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext  = [System.IO.Path]::GetExtension($name)
    $i = 2
    do {
        $candidate = Join-Path $dir ('{0} ({1}){2}' -f $base, $i, $ext)
        $taken = (Test-Path -LiteralPath $candidate) -or ($null -ne $Reserved -and $Reserved.ContainsKey($candidate.ToLowerInvariant()))
        if (-not $taken) { return $candidate }
        $i++
    } while ($i -lt 1000)
    return $candidate
}

# Subfolders a scan would visit: never a category folder, never a link (junction / symbolic link -
# the only reparse points that can loop), never deeper than -MaxDepth. Note: OneDrive marks every
# synced folder ReparsePoint with an empty LinkType, so filtering on the attribute alone would skip
# the entire tree; LinkType is what distinguishes a genuine link from a cloud placeholder.
function Get-ScanTargets([string]$Root, [int]$MaxDepth) {
    $found = New-Object System.Collections.ArrayList
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Dir = $Root; Depth = 0; Relative = '.' })

    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        foreach ($child in @(Get-ChildItem -LiteralPath $node.Dir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($Categories -contains $child.Name) { continue }
            if ($child.LinkType) { continue }

            $depth = $node.Depth + 1
            if ($MaxDepth -gt 0 -and $depth -gt $MaxDepth) { continue }

            if ($node.Relative -eq '.') { $relative = $child.Name }
            else { $relative = $node.Relative + '\' + $child.Name }

            [void]$found.Add([pscustomobject]@{ Dir = $child.FullName; Depth = $depth; Relative = $relative })
            $queue.Enqueue([pscustomobject]@{ Dir = $child.FullName; Depth = $depth; Relative = $relative })
        }
    }
    return @($found | Sort-Object Relative)
}

# A destination name that is free on disk and in this run's plan, for a FOLDER. Kept separate from
# Get-UniquePath because a folder name may contain dots ("Aug & Jul'26.v2") and has no extension.
function Get-UniqueFolder([string]$dir, [string]$name, [hashtable]$Reserved) {
    $candidate = Join-Path $dir $name
    $taken = (Test-Path -LiteralPath $candidate) -or ($null -ne $Reserved -and $Reserved.ContainsKey($candidate.ToLowerInvariant()))
    if (-not $taken) { return $candidate }
    $i = 2
    do {
        $candidate = Join-Path $dir ('{0} ({1})' -f $name, $i)
        $taken = (Test-Path -LiteralPath $candidate) -or ($null -ne $Reserved -and $Reserved.ContainsKey($candidate.ToLowerInvariant()))
        if (-not $taken) { return $candidate }
        $i++
    } while ($i -lt 1000)
    return $candidate
}

# Project folders: the immediate subfolders of each category folder. Anything deeper is part of a
# project, so it is never a candidate on its own.
function Get-ProjectFolders([string]$Root) {
    $out = New-Object System.Collections.ArrayList
    foreach ($category in $Categories) {
        $catDir = Join-Path $Root $category
        if (-not (Test-Path -LiteralPath $catDir -PathType Container)) { continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $catDir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($child.LinkType) { continue }
            [void]$out.Add([pscustomobject]@{ Dir = $child.FullName; Name = $child.Name; Parent = $category })
        }
    }
    return @($out | Sort-Object Parent, Name)
}

# What a project folder is made of, at any depth beneath it. In-progress downloads and OS clutter are
# not evidence of anything, so they are not counted; a folder made only of those counts as empty.
function Get-FolderComposition([string]$Folder) {
    $counts = @{}
    $total = 0
    $pinned = $false
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -File -Force -Recurse -ErrorAction SilentlyContinue)) {
        if ($SkipNames -contains $file.Name.ToLowerInvariant()) { continue }
        $ext = $file.Extension.TrimStart('.').ToLowerInvariant()
        if ($SkipExtensions -contains $ext) { continue }
        if ($WeakDocTypes -contains $ext) { continue }
        $category = if ($Map.ContainsKey($ext)) { $Map[$ext] } else { $Fallback }
        if ($counts.ContainsKey($category)) { $counts[$category] = $counts[$category] + 1 }
        else { $counts[$category] = 1 }
        $total++
        if ($PinTypes -contains $ext) { $pinned = $true }
    }
    $parts = @($counts.GetEnumerator() | Sort-Object -Property Value -Descending |
               ForEach-Object { '{0} {1}' -f $_.Value, $_.Key.ToLowerInvariant() })
    return [pscustomobject]@{ Total = $total; Counts = $counts; Pinned = $pinned; Summary = ($parts -join ', ') }
}

# ---------------------------------------------------------------- target
Write-Host ''
Write-Host "Organising: $Path" -ForegroundColor Cyan

$targetLeaf = Split-Path -Leaf $Path
if ($Categories -contains $targetLeaf) {
    Write-Host ''
    Write-Host ("WARNING: this launcher sits in '{0}', which is one of the category folders it manages." -f $targetLeaf) -ForegroundColor Yellow
    Write-Host '         Its files would be sorted into a nested category folder inside it.' -ForegroundColor Yellow
    Write-Host '         Pass -Path <folder> if you meant to organise something else.' -ForegroundColor Yellow
}
Write-Host ''

# ---------------------------------------------------------------- subfolder decision
$interactive = (-not $WhatIf) -and (-not $Force)
$explicitScan = $Recurse -or ($MaxDepth -gt 0)
$useSubfolders = $false
$scanDirs = @()

if ($explicitScan) {
    $scanDirs = @(Get-ScanTargets -Root $Path -MaxDepth $MaxDepth)
    $useSubfolders = $true
}

# There is deliberately no prompt here. Asking "sort the subfolders too?" put every project folder
# one keystroke from being scattered, and a folder in the tree is a project by design. Flattening is
# a switch you type, never an answer you give at a prompt.

# ---------------------------------------------------------------- plan
# ---------------------------------------------------------------- gather
# Two levels by default: loose files at the root, then loose files sitting directly inside each
# category folder. That second pass is what lets a screenshot left in Documents\ reach Pictures\.
# Nothing is ever taken out of a folder that lives inside a category folder - that is a project.
$entries = New-Object System.Collections.ArrayList
$sweepFiles = 0     # loose files found directly inside an immediate subfolder
$sweptFolders = 0   # ...in this many folders
$inPlaceCount = 0   # ...of which these were already in the right category folder

foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Force)) {
    [void]$entries.Add([pscustomobject]@{ File = $file; Rel = '.'; InPlace = $false; Bucket = $null; IsCategory = $false })
}

# Every immediate subfolder is a bucket, category or not: a loose screenshot in Media Assets needs the
# same treatment as one left in Documents. A bucket named after a category is machine-owned, so it is
# swept in full; any other bucket is the user's, so only files the tool recognises leave it (see the
# retained branch in the plan pass). Never entered: links, dotted folders and tooling trees.
# Only when the scan is not recursive: -Recurse walks these same folders itself, and enumerating them
# twice would turn every depth-1 file into a duplicate of itself.
$NeverSweep = @('node_modules', '__pycache__', 'system volume information', '$recycle.bin', '.git', '.svn')

$bucketDirs = if ($useSubfolders) {
    @()
}
else {
    @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)
}

foreach ($dir in $bucketDirs) {
    if ($dir.LinkType) { continue }
    if ($dir.Name.StartsWith('.')) { continue }
    if ($NeverSweep -contains $dir.Name.ToLowerInvariant()) { continue }

    $isCategory = $Categories -contains $dir.Name
    $sweptFolders++

    foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -File -Force -ErrorAction SilentlyContinue)) {
        $sweepFiles++
        $ext = $file.Extension.TrimStart('.').ToLowerInvariant()
        $belongs = if ($Map.ContainsKey($ext)) { $Map[$ext] } else { $Fallback }
        # Only a category folder can hold a file that is already where it belongs. Media Assets\a.pdf is
        # not "already filed" just because the name matched - it still belongs in Documents.
        $inPlace = $isCategory -and ($belongs -eq $dir.Name)
        if ($inPlace) { $inPlaceCount++ }
        [void]$entries.Add([pscustomobject]@{
            File = $file; Rel = $dir.Name; InPlace = $inPlace; Bucket = $dir.Name; IsCategory = $isCategory
        })
    }
}

if ($useSubfolders) {
    foreach ($dir in $scanDirs) {
        foreach ($file in @(Get-ChildItem -LiteralPath $dir.Dir -File -Force -ErrorAction SilentlyContinue)) {
            [void]$entries.Add([pscustomobject]@{
                File = $file; Rel = $dir.Relative; InPlace = $false; Bucket = $null; IsCategory = $false
            })
        }
    }
}
$entries = @($entries | Sort-Object { $_.Rel }, { $_.File.Name })
# The Source column earns its width as soon as anything comes from somewhere other than the root.
$showSource = $useSubfolders -or ($sweepFiles -gt 0)

$plan    = New-Object System.Collections.ArrayList
# Files left where they are because the tool could not classify them: reported, never moved.
$retained = New-Object System.Collections.ArrayList
# Destinations claimed so far in this run: lower-cased path -> source file that will occupy it.
$planned = @{}

foreach ($entry in $entries) {

    $file = $entry.File

    if ($SkipNames -contains $file.Name.ToLowerInvariant()) { continue }

    if ($ToolFiles -contains $file.Name.ToLowerInvariant()) {
        [void]$plan.Add([pscustomobject]@{
            Action = 'SKIPS'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = '(left in place)'; Detail = 'organiser file'
        })
        continue
    }

    if ($file.Name -like '~$*') {
        [void]$plan.Add([pscustomobject]@{
            Action = 'LOCK-DELETE'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = '(removed)'; Detail = 'Office/Office lock file'
        })
        continue
    }

    $ext = $file.Extension.TrimStart('.').ToLowerInvariant()

    if ($SkipExtensions -contains $ext) {
        [void]$plan.Add([pscustomobject]@{
            Action = 'SKIPS'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = '(left in place)'; Detail = 'in-progress download'
        })
        continue
    }

    # Already filed correctly inside its own category folder: nothing to do, and no row to read.
    if ($entry.InPlace) { continue }

    if ($Map.ContainsKey($ext)) { $category = $Map[$ext] } else { $category = $Fallback }

    # A file only leaves a folder that is not machine-owned when the tool knows where it belongs. The
    # fallback bucket means "unknown", and an unknown file is better left in the folder that holds it -
    # it is reported instead, so it can be moved by hand if that is what you want.
    if ($entry.Bucket -and -not $entry.IsCategory -and $category -eq $Fallback) {
        [void]$retained.Add([pscustomobject]@{ File = $file; Rel = $entry.Rel })
        continue
    }

    $destDir  = Join-Path $Path $category
    $destPath = Join-Path $destDir $file.Name

    # A file already sitting where it would go is not a duplicate of itself - never delete it.
    if ($destPath -ieq $file.FullName) {
        [void]$plan.Add([pscustomobject]@{
            Action = 'SKIPS'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = '(left in place)'; Detail = 'already in place'
        })
        continue
    }

    $destKey = $destPath.ToLowerInvariant()

    if ($planned.ContainsKey($destKey)) {
        $other = $planned[$destKey]
        if ((Get-Hash $file.FullName) -eq (Get-Hash $other)) {
            [void]$plan.Add([pscustomobject]@{
                Action = 'DUPLICATE'; File = $file; Source = $file.FullName; Rel = $entry.Rel
                Target = $destPath; Detail = 'identical copy claimed earlier in this run -> remove this one'
            })
            continue
        }
        $unique = Get-UniquePath $destDir $file.Name $planned
        $planned[$unique.ToLowerInvariant()] = $file.FullName
        [void]$plan.Add([pscustomobject]@{
            Action = 'RENAME'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = $unique; Detail = 'name clash within this run, different content'
        })
        continue
    }

    if (Test-Path -LiteralPath $destPath) {
        if ((Get-Hash $file.FullName) -eq (Get-Hash $destPath)) {
            [void]$plan.Add([pscustomobject]@{
                Action = 'DUPLICATE'; File = $file; Source = $file.FullName; Rel = $entry.Rel
                Target = $destPath; Detail = 'identical copy already filed -> remove this one'
            })
            continue
        }
        $unique = Get-UniquePath $destDir $file.Name $planned
        $planned[$unique.ToLowerInvariant()] = $file.FullName
        [void]$plan.Add([pscustomobject]@{
            Action = 'RENAME'; File = $file; Source = $file.FullName; Rel = $entry.Rel
            Target = $unique; Detail = 'name clash, different content'
        })
        continue
    }

    $planned[$destKey] = $file.FullName
    [void]$plan.Add([pscustomobject]@{
        Action = 'MOVE'; File = $file; Source = $file.FullName; Rel = $entry.Rel
        Target = $destPath; Detail = $category
    })
}

$toMove = @($plan | Where-Object { $_.Action -eq 'MOVE' })
$toRename = @($plan | Where-Object { $_.Action -eq 'RENAME' })
$toDup = @($plan | Where-Object { $_.Action -eq 'DUPLICATE' })
$toLock = @($plan | Where-Object { $_.Action -eq 'LOCK-DELETE' })
$toSkip = @($plan | Where-Object { $_.Action -eq 'SKIPS' })

# ---------------------------------------------------------------- project folders
# A folder inside a category folder is a project: its insides are never touched, only the folder as
# a whole can move. Documents win outright; otherwise the single largest category has to win
# outright, so a folder that is evenly mixed stays exactly where it is.
$folderPlan = New-Object System.Collections.ArrayList
$reservedFolders = @{}

foreach ($project in @(Get-ProjectFolders $Path)) {
    $composition = Get-FolderComposition $project.Dir
    if ($composition.Total -eq 0) { continue }

    if ($composition.Pinned) {
        $wanted = 'Documents'
    }
    else {
        $wanted = $null
        $bestCount = 0
        $tied = $false
        foreach ($category in $composition.Counts.Keys) {
            $count = $composition.Counts[$category]
            if ($count -gt $bestCount) { $wanted = $category; $bestCount = $count; $tied = $false }
            elseif ($count -eq $bestCount) { $tied = $true }
        }
        if ($tied) { $wanted = $null }
    }

    if (-not $wanted) { continue }
    if ($wanted -eq $project.Parent) { continue }

    $destDir = Join-Path $Path $wanted
    $dest = Get-UniqueFolder $destDir $project.Name $reservedFolders
    $reservedFolders[$dest.ToLowerInvariant()] = $project.Dir
    $action = if ((Split-Path -Leaf $dest) -eq $project.Name) { 'MOVE-FOLDER' } else { 'RENAME-FOLDER' }

    [void]$folderPlan.Add([pscustomobject]@{
        Action = $action
        Name   = $project.Name
        Source = $project.Dir
        Target = $dest
        Rel    = $project.Parent
        Detail = $composition.Summary
    })
}

if ($plan.Count -eq 0 -and $folderPlan.Count -eq 0) {
    if ($retained.Count -gt 0) {
        # Nothing to do, but there is something to read: say what was kept and why, then stop.
        Show-RetainedReport $retained
        Write-Host ''
        Write-Host 'Nothing to organise - none of the files found are recognised, so they stayed put.' -ForegroundColor Green
        exit 0
    }
    if ($useSubfolders) {
        Write-Host 'Nothing to organise - no files found here or in the subfolders scanned.' -ForegroundColor Green
    }
    elseif ($sweepFiles -gt 0) {
        Write-Host 'Nothing to organise - everything is already filed, and no project folder belongs elsewhere.' -ForegroundColor Green
    }
    else {
        Write-Host 'Nothing to organise - no loose files at this folder''s root.' -ForegroundColor Green
    }
    exit 0
}

# ---------------------------------------------------------------- preview table
# One row per file, plus a Source column only when subfolders are in play. Long names are capped so
# a single oversized file cannot push the other columns out of alignment.
$NameCap = 46
$TypeCap = 16
$DestCap = 14
$SrcCap  = 22
$RowCap  = 60

$rows = New-Object System.Collections.ArrayList
foreach ($item in $plan) {
    $ext = $item.File.Extension.TrimStart('.').ToLowerInvariant()

    if ($item.Action -eq 'SKIPS') {
        $dest = '(in place)'; $act = 'SKIP'
    }
    elseif ($item.Action -eq 'LOCK-DELETE') {
        $dest = '(removed)'; $act = 'LOCK'
    }
    else {
        $dest = Split-Path -Leaf (Split-Path -Parent $item.Target)
        $act  = $item.Action
    }

    [void]$rows.Add([pscustomobject]@{
        Name  = $item.File.Name
        Src   = $item.Rel
        Type  = (Get-TypeLabel $ext)
        Dest  = $dest
        Act   = $act
        Item  = $item
    })
}

# Project folders get a row each too: one whole-folder decision is worth seeing next to the files.
foreach ($item in $folderPlan) {
    [void]$rows.Add([pscustomobject]@{
        Name = $item.Name
        Src  = $item.Rel
        Type = 'Folder'
        Dest = (Split-Path -Leaf (Split-Path -Parent $item.Target))
        Act  = if ($item.Action -eq 'RENAME-FOLDER') { 'RENAME FOLDER' } else { 'MOVE FOLDER' }
        Item = $item
    })
}

$idxWidth  = ([string]$rows.Count).Length
$nameWidth = 9      # "File Name"
$typeWidth = 9      # "File Type"
$destWidth = 11     # "Destination"
$actWidth  = 6      # "Action"
$srcWidth  = 6      # "Source"
foreach ($row in $rows) {
    if ($row.Name.Length -gt $nameWidth) { $nameWidth = $row.Name.Length }
    if ($row.Type.Length -gt $typeWidth) { $typeWidth = $row.Type.Length }
    if ($row.Dest.Length -gt $destWidth) { $destWidth = $row.Dest.Length }
    if ($row.Act.Length  -gt $actWidth)  { $actWidth  = $row.Act.Length }
    if ($row.Src.Length  -gt $srcWidth)  { $srcWidth  = $row.Src.Length }
}
if ($nameWidth -gt $NameCap) { $nameWidth = $NameCap }
if ($typeWidth -gt $TypeCap) { $typeWidth = $TypeCap }
if ($destWidth -gt $DestCap) { $destWidth = $DestCap }
if ($srcWidth  -gt $SrcCap)  { $srcWidth  = $SrcCap }

$gap = '  '
$header = $gap + '#'.PadLeft($idxWidth) + $gap + 'File Name'.PadRight($nameWidth) + $gap
$rule   = $gap + ('-' * $idxWidth) + $gap + ('-' * $nameWidth) + $gap
if ($showSource) {
    $header = $header + 'Source'.PadRight($srcWidth) + $gap
    $rule   = $rule + ('-' * $srcWidth) + $gap
}
$header = $header + 'File Type'.PadRight($typeWidth) + $gap + 'Destination'.PadRight($destWidth) + $gap +
          'Action'.PadRight($actWidth)
$rule = $rule + ('-' * $typeWidth) + $gap + ('-' * $destWidth) + $gap + ('-' * $actWidth)

Write-Host $header -ForegroundColor Cyan
Write-Host $rule -ForegroundColor DarkGray

$shown = 0
$index = 0
foreach ($row in $rows) {
    $index++
    if ($index -gt $RowCap) { break }
    $shown++

    $colour = switch ($row.Act) {
        'MOVE'          { 'Gray' }
        'MOVE FOLDER'   { 'Magenta' }
        'RENAME'        { 'Yellow' }
        'RENAME FOLDER' { 'Yellow' }
        'DUPLICATE'     { 'DarkYellow' }
        'LOCK'          { 'DarkYellow' }
        'SKIP'          { 'DarkGray' }
        default         { 'Gray' }
    }
    $line = $gap + ([string]$index).PadLeft($idxWidth) + $gap + (Format-Cell $row.Name $nameWidth) + $gap
    if ($showSource) { $line = $line + (Format-CellTail $row.Src $srcWidth) + $gap }
    $line = $line + (Format-Cell $row.Type $typeWidth) + $gap +
            (Format-Cell $row.Dest $destWidth) + $gap +
            (Format-Cell $row.Act  $actWidth).TrimEnd()
    Write-Host $line -ForegroundColor $colour
}
if ($rows.Count -gt $shown) {
    Write-Host ('  ... {0} more not shown' -f ($rows.Count - $shown)) -ForegroundColor DarkGray
}

# Anything that is not a plain move keeps its real target and reason visible.
$notes = @($rows | Where-Object { $_.Act -in @('RENAME', 'DUPLICATE', 'LOCK', 'MOVE FOLDER', 'RENAME FOLDER') })
if ($notes.Count -gt 0) {
    Write-Host ''
    Write-Host 'Notes' -ForegroundColor Cyan
    $noteCap = 20
    $n = 0
    foreach ($row in $notes) {
        $n++
        if ($n -gt $noteCap) {
            Write-Host ('  ... {0} more not listed' -f ($notes.Count - $noteCap)) -ForegroundColor DarkGray
            break
        }
        Write-Host ('  ' + (Get-NoteText $row)) -ForegroundColor DarkGray
    }
}

Show-RetainedReport $retained

if ($inPlaceCount -gt 0) {
    Write-Host ''
    Write-Host ('Already filed: {0} file(s) inside category folders left alone.' -f $inPlaceCount) -ForegroundColor DarkGray
}

Write-Host ''
$summaryText = 'Summary: {0} move, {1} rename, {2} duplicate-remove, {3} lock-remove, {4} skip' -f `
    $toMove.Count, $toRename.Count, $toDup.Count, $toLock.Count, $toSkip.Count
if ($folderPlan.Count -gt 0) {
    $summaryText = $summaryText + (', {0} folder move' -f $folderPlan.Count)
}
Write-Host $summaryText

# ---------------------------------------------------------------- full-list export
# The screen table is capped so a long plan stays readable. When it is truncated, every row is
# written out first and the path announced before the prompt, so nothing is decided from a partial
# picture. Written on -WhatIf too: it is a report about the folder, not a change to it.
$previewWritten = $null
if ($rows.Count -gt $shown) {

    $fNameWidth = 9; $fTypeWidth = 9; $fDestWidth = 11; $fActWidth = 6; $fSrcWidth = 6
    foreach ($row in $rows) {
        if ($row.Name.Length -gt $fNameWidth) { $fNameWidth = $row.Name.Length }
        if ($row.Type.Length -gt $fTypeWidth) { $fTypeWidth = $row.Type.Length }
        if ($row.Dest.Length -gt $fDestWidth) { $fDestWidth = $row.Dest.Length }
        if ($row.Act.Length  -gt $fActWidth)  { $fActWidth  = $row.Act.Length }
        if ($row.Src.Length  -gt $fSrcWidth)  { $fSrcWidth  = $row.Src.Length }
    }
    # Generous caps: a file has no screen to fit on.
    if ($fNameWidth -gt 80) { $fNameWidth = 80 }
    if ($fTypeWidth -gt 20) { $fTypeWidth = 20 }
    if ($fDestWidth -gt 22) { $fDestWidth = 22 }
    if ($fSrcWidth  -gt 60) { $fSrcWidth  = 60 }

    $fIdxWidth = ([string]$rows.Count).Length
    $fHeader = $gap + '#'.PadLeft($fIdxWidth) + $gap + 'File Name'.PadRight($fNameWidth) + $gap
    $fRule   = $gap + ('-' * $fIdxWidth) + $gap + ('-' * $fNameWidth) + $gap
    if ($showSource) {
        $fHeader = $fHeader + 'Source'.PadRight($fSrcWidth) + $gap
        $fRule   = $fRule + ('-' * $fSrcWidth) + $gap
    }
    $fHeader = $fHeader + 'File Type'.PadRight($fTypeWidth) + $gap + 'Destination'.PadRight($fDestWidth) + $gap +
               'Action'.PadRight($fActWidth)
    $fRule = $fRule + ('-' * $fTypeWidth) + $gap + ('-' * $fDestWidth) + $gap + ('-' * $fActWidth)

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('Folder organisation preview')
    [void]$lines.Add('')
    [void]$lines.Add(('Generated  : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$lines.Add(('Target     : {0}' -f $Path))
    if ($useSubfolders) {
        [void]$lines.Add(('Subfolders : scanned ({0} folder(s))' -f $scanDirs.Count))
    }
    else {
        [void]$lines.Add('Subfolders : not scanned')
    }
    [void]$lines.Add(('Files      : {0}' -f $rows.Count))
    if ($sweptFolders -gt 0) {
        [void]$lines.Add(('Buckets    : {0} folder(s) swept, {1} file(s), {2} already in place' -f $sweptFolders, $sweepFiles, $inPlaceCount))
    }
    if ($retained.Count -gt 0) {
        [void]$lines.Add(('Retained   : {0} file(s) left in place (destination would be Other)' -f $retained.Count))
    }
    if ($folderPlan.Count -gt 0) {
        [void]$lines.Add(('Projects   : {0} folder move(s)' -f $folderPlan.Count))
    }
    [void]$lines.Add('')
    [void]$lines.Add($fHeader)
    [void]$lines.Add($fRule)

    $fileIndex = 0
    foreach ($row in $rows) {
        $fileIndex++
        $line = $gap + ([string]$fileIndex).PadLeft($fIdxWidth) + $gap + (Format-Cell $row.Name $fNameWidth) + $gap
        if ($showSource) { $line = $line + (Format-CellTail $row.Src $fSrcWidth) + $gap }
        $line = $line + (Format-Cell $row.Type $fTypeWidth) + $gap +
                (Format-Cell $row.Dest $fDestWidth) + $gap +
                (Format-Cell $row.Act  $fActWidth).TrimEnd()
        [void]$lines.Add($line)
    }

    if ($notes.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Notes')
        foreach ($row in $notes) {
            [void]$lines.Add('  ' + (Get-NoteText $row))
        }
    }

    if ($retained.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Retained in place (not recognised, destination would be Other):')
        foreach ($group in @($retained | Group-Object Rel | Sort-Object Name)) {
            [void]$lines.Add(('  {0} ({1}): {2}' -f $group.Name, $group.Count, (@($group.Group | ForEach-Object { $_.File.Name }) -join ', ')))
        }
    }

    $exportSummary = 'Summary: {0} move, {1} rename, {2} duplicate-remove, {3} lock-remove, {4} skip' -f `
        $toMove.Count, $toRename.Count, $toDup.Count, $toLock.Count, $toSkip.Count
    if ($inPlaceCount -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add(('Already filed: {0} file(s) inside category folders left alone.' -f $inPlaceCount))
    }
    if ($folderPlan.Count -gt 0) {
        $exportSummary = $exportSummary + (', {0} folder move' -f $folderPlan.Count)
    }
    [void]$lines.Add('')
    [void]$lines.Add($exportSummary)

    try {
        $previewDir = Split-Path -Parent $PreviewFile
        if ($previewDir -and -not (Test-Path -LiteralPath $previewDir)) {
            New-Item -ItemType Directory -Path $previewDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllLines($PreviewFile, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
        $previewWritten = $PreviewFile
    }
    catch {
        Write-Host ('WARNING: could not write the full list: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

if ($previewWritten) {
    Write-Host ''
    Write-Host ('Full list ({0} rows) written to: {1}' -f $rows.Count, $previewWritten) -ForegroundColor Cyan
}

if ($WhatIf) {
    Write-Host 'Dry run (-WhatIf): nothing changed.' -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------- project folder decision
# Moving a whole folder is a bigger decision than moving one file, so it is asked on its own and
# never folded into the Proceed answer below.
$moveFolders = $false
if ($folderPlan.Count -gt 0) {
    if ($MoveProjects) {
        $moveFolders = $true
    }
    elseif ($interactive) {
        Write-Host ''
        $folderQuestion = if ($folderPlan.Count -eq 1) {
            'Move this project folder to its matching category? [y/N]'
        }
        else {
            'Move these {0} project folders to their matching category? [y/N]' -f $folderPlan.Count
        }
        Write-Host $folderQuestion -ForegroundColor Yellow
        $folderAnswer = ([string](Read-Host)).Trim()
        if ($folderAnswer -match '^(?i)y(es)?$') { $moveFolders = $true }
    }
    if (-not $moveFolders) {
        $folderHint = if ($interactive) { '' } else { ' Pass -MoveProjects to move them without asking.' }
        Write-Host ('Project folders left in place.' + $folderHint) -ForegroundColor DarkGray
    }
    Write-Host ''
}

# Read-Host returns $null when stdin has run out, and "$null -notmatch 'pattern'" evaluates to
# nothing at all - so "if ($answer -notmatch ...)" fell through and a run with no input available
# proceeded to move files. Every answer is therefore cast to a string first, which makes an absent or
# blank answer an explicit 'no'. Confirmation must fail closed.
if (-not $Force) {
    Write-Host 'Proceed? [y/N]' -ForegroundColor Yellow
    $answer = ([string](Read-Host)).Trim()
    if ($answer -notmatch '^(?i)y(es)?$') {
        Write-Host 'Aborted. Nothing changed.' -ForegroundColor Yellow
        exit 0
    }
}

# ---------------------------------------------------------------- execute
$failures = 0

# One line records what the sweep deliberately walked past, so the decision is auditable later.
if ($retained.Count -gt 0) {
    try {
        $retainedSummary = @($retained | Group-Object Rel | Sort-Object Name |
                            ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count }) -join ', '
        Write-Log 'RETAINED' ('{0} file(s) left in place (destination would be {1}): {2}' -f `
                   $retained.Count, $Fallback, $retainedSummary)
    }
    catch { }
}

# A scanned file is logged with its source folder so a multi-folder run can be reconstructed.
function Get-Label($item) {
    if ($item.Rel -eq '.') { return $item.File.Name }
    return ($item.Rel + '\' + $item.File.Name)
}

foreach ($item in $plan) {
    $label = Get-Label $item
    try {
        switch ($item.Action) {

            'MOVE' {
                $destDir = Split-Path -Parent $item.Target
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    Write-Log 'CREATED-FOLDER' $destDir
                }
                Move-Item -LiteralPath $item.Source -Destination $item.Target
                Write-Log 'MOVED' ('{0} -> {1}' -f $label, (Split-Path -Parent $item.Target))
                Write-Host ('  moved    {0}' -f $label) -ForegroundColor Gray
            }

            'RENAME' {
                $destDir = Split-Path -Parent $item.Target
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Move-Item -LiteralPath $item.Source -Destination $item.Target
                Write-Log 'RENAMED' ('{0} -> {1}' -f $label, (Split-Path -Leaf $item.Target))
                Write-Host ('  renamed  {0} -> {1}' -f $label, (Split-Path -Leaf $item.Target)) -ForegroundColor Yellow
            }

            'DUPLICATE' {
                Remove-Item -LiteralPath $item.Source -Force
                Write-Log 'DUPLICATE' ('removed {0}; identical copy kept at {1}' -f $label, $item.Target)
                Write-Host ('  dup-rm   {0}' -f $label) -ForegroundColor DarkYellow
            }

            'LOCK-DELETE' {
                Remove-Item -LiteralPath $item.Source -Force
                Write-Log 'LOCK-DELETED' $label
                Write-Host ('  lock-rm  {0}' -f $label) -ForegroundColor DarkYellow
            }

            'SKIPS' {
                Write-Log 'SKIPPED' ('{0} ({1})' -f $label, $item.Detail)
            }
        }
    }
    catch {
        $failures++
        Write-Log 'ERROR' ('{0}: {1}' -f $label, $_.Exception.Message)
        Write-Host ('  ERROR    {0}: {1}' -f $label, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''

# ---------------------------------------------------------------- project folders
# Whole folders, after the files, and only when the move was approved. The target is re-checked
# immediately beforehand: a folder that appeared since the plan is never silently merged into.
if ($folderPlan.Count -gt 0 -and $moveFolders) {
    foreach ($item in $folderPlan) {
        $label = '{0}\{1}' -f $item.Rel, $item.Name
        try {
            if (-not (Test-Path -LiteralPath $item.Source)) { continue }
            if (Test-Path -LiteralPath $item.Target) {
                Write-Log 'FOLDER-SKIPPED' ('{0} (target appeared: {1})' -f $label, $item.Target)
                Write-Host ('  kept     {0} (target appeared)' -f $label) -ForegroundColor DarkGray
                continue
            }
            $destDir = Split-Path -Parent $item.Target
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Write-Log 'CREATED-FOLDER' $destDir
            }
            Move-Item -LiteralPath $item.Source -Destination $item.Target
            $verb = if ($item.Action -eq 'RENAME-FOLDER') { 'RENAMED-FOLDER' } else { 'MOVED-FOLDER' }
            Write-Log $verb ('{0} -> {1}\{2}' -f $label, (Split-Path -Leaf $destDir), (Split-Path -Leaf $item.Target))
            Write-Host ('  moved    {0} -> {1}' -f $label, $item.Target) -ForegroundColor Magenta
        }
        catch {
            $failures++
            Write-Log 'ERROR' ('{0}: {1}' -f $label, $_.Exception.Message)
            Write-Host ('  ERROR    {0}: {1}' -f $label, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------- emptied folders
# The folders the scan left with nothing in them, counted at any depth beneath: a folder holding
# only a category folder that still has content is not empty. Never the target itself, never a
# category folder (the scan does not visit those), never a link.
$emptied = @()
if ($useSubfolders) {
    foreach ($dir in $scanDirs) {
        if (-not (Test-Path -LiteralPath $dir.Dir)) { continue }
        $remaining = @(Get-ChildItem -LiteralPath $dir.Dir -File -Force -Recurse -ErrorAction SilentlyContinue).Count
        if ($remaining -eq 0) { $emptied += $dir }
    }
}

if ($emptied.Count -gt 0) {
    $sample = (@($emptied | Select-Object -First 3) | ForEach-Object { $_.Relative }) -join ', '
    Write-Host ('Subfolders with no files left: {0} ({1}{2})' -f $emptied.Count, $sample, $(if ($emptied.Count -gt 3) { ', ...' } else { '' })) -ForegroundColor DarkGray
}

# Removing directories is a separate, visible decision from the moves already approved, so it is
# asked here rather than folded into the sort - and never asked by an unattended run.
if ($emptied.Count -gt 0 -and (-not $WhatIf)) {

    $prune = $false
    if ($PruneEmpty) {
        $prune = $true
    }
    elseif ($interactive) {
        Write-Host ''
        Write-Host ('Delete these {0} empty subfolders? [y/N]' -f $emptied.Count) -ForegroundColor Yellow
        $pruneAnswer = ([string](Read-Host)).Trim()
        if ($pruneAnswer -match '^(?i)y(es)?$') { $prune = $true }
    }

    if ($prune) {
        # Deepest first, so a parent that only held emptied children can go too. Each folder is
        # re-checked immediately before the delete: anything that appeared since the plan is left
        # alone. Remove-Item is used without -Recurse, so a non-empty directory cannot be removed.
        $toPrune = @($emptied | Sort-Object -Property @{ Expression = { $_.Depth }; Descending = $true },
                                                 @{ Expression = { $_.Relative }; Descending = $false })
        $removed = 0
        foreach ($dir in $toPrune) {
            try {
                if (-not (Test-Path -LiteralPath $dir.Dir)) { continue }
                if ($Categories -contains (Split-Path -Leaf $dir.Dir)) { continue }
                if (@(Get-ChildItem -LiteralPath $dir.Dir -Force -ErrorAction SilentlyContinue).Count -gt 0) {
                    Write-Log 'PRUNE-SKIPPED' ('{0} (still holds content)' -f $dir.Relative)
                    Write-Host ('  kept     {0} (still holds content)' -f $dir.Relative) -ForegroundColor DarkGray
                    continue
                }
                Remove-Item -LiteralPath $dir.Dir -Force
                $removed++
                Write-Log 'PRUNED-FOLDER' $dir.Relative
                Write-Host ('  pruned   {0}' -f $dir.Relative) -ForegroundColor DarkGray
            }
            catch {
                $failures++
                Write-Log 'ERROR' ('{0}: {1}' -f $dir.Relative, $_.Exception.Message)
                Write-Host ('  ERROR    {0}: {1}' -f $dir.Relative, $_.Exception.Message) -ForegroundColor Red
            }
        }
        Write-Host ('Removed {0} empty folder(s).' -f $removed) -ForegroundColor Gray
    }
    elseif ($interactive) {
        Write-Host 'Empty folders left in place.' -ForegroundColor DarkGray
    }
}

if ($failures -gt 0) {
    Write-Host ('Finished with {0} error(s). Log: {1}' -f $failures, $LogFile) -ForegroundColor Red
    exit 1
}

Write-Host ('Done. Log: {0}' -f $LogFile) -ForegroundColor Green
exit 0
