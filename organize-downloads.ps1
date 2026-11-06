<#
.SYNOPSIS
    Sorts loose files in a folder into extension-based category folders.

.DESCRIPTION
    Extension-only ruleset. It does NOT reason about projects or topics: anything it does not
    recognise goes to Other\ and you re-file it by hand.

    The folder it organises is the folder it lives in - drop this script and its .bat into the
    folder you want sorted and run it there. -Path overrides that.

    By default only files sitting directly in that folder are touched: no subfolders, no existing
    category contents, never a directory. -Recurse (or -MaxDepth N) also scans subfolders and files
    everything into the top-level category folders; the subfolder structure is NOT preserved.
    Interactive runs are asked first, with the file and folder counts, so the answer is informed.

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

    Default is a preview plus a [y/N] prompt. -WhatIf previews and exits. -Force runs unattended,
    and neither -WhatIf nor -Force will ever ask about subfolders: they stay root-only unless the
    switch is passed, so scheduled runs are deterministic.

.PARAMETER Path
    Folder to organise. Defaults to the folder this script lives in.

.PARAMETER Recurse
    Also sort files found in subfolders, into this folder's category folders.

.PARAMETER MaxDepth
    Limit how deep the scan goes, counting immediate subfolders as depth 1. Implies -Recurse.

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

.NOTES
    Windows PowerShell 5.1 built-ins only. No admin rights required.
#>

param(
    [string]$Path,
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$Recurse,
    [int]$MaxDepth = 0,
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

if ($explicitScan -or $interactive) {
    $scanDirs = @(Get-ScanTargets -Root $Path -MaxDepth $MaxDepth)
}

if ($explicitScan) {
    $useSubfolders = $true
}
elseif ($interactive -and $scanDirs.Count -gt 0) {
    $candidateFiles = 0
    foreach ($dir in $scanDirs) {
        $candidateFiles += @(Get-ChildItem -LiteralPath $dir.Dir -File -Force -ErrorAction SilentlyContinue).Count
    }
    if ($candidateFiles -gt 0) {
        Write-Host ('Also sort the {0} files inside {1} subfolders? Their folder structure is not preserved.' -f $candidateFiles, $scanDirs.Count) -ForegroundColor Yellow
        $scanAnswer = Read-Host '[y/N]'
        if ($scanAnswer -match '^(y|yes)$') { $useSubfolders = $true }
        Write-Host ''
    }
}

# ---------------------------------------------------------------- plan
$entries = New-Object System.Collections.ArrayList
foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Force)) {
    [void]$entries.Add([pscustomobject]@{ File = $file; Rel = '.' })
}
if ($useSubfolders) {
    foreach ($dir in $scanDirs) {
        foreach ($file in @(Get-ChildItem -LiteralPath $dir.Dir -File -Force -ErrorAction SilentlyContinue)) {
            [void]$entries.Add([pscustomobject]@{ File = $file; Rel = $dir.Relative })
        }
    }
}
$entries = @($entries | Sort-Object { $_.Rel }, { $_.File.Name })

$plan    = New-Object System.Collections.ArrayList
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

    if ($Map.ContainsKey($ext)) { $category = $Map[$ext] } else { $category = $Fallback }

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

if ($plan.Count -eq 0) {
    if ($useSubfolders) {
        Write-Host 'Nothing to organise - no files found here or in the subfolders scanned.' -ForegroundColor Green
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
if ($useSubfolders) {
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
        'MOVE'      { 'Gray' }
        'RENAME'    { 'Yellow' }
        'DUPLICATE' { 'DarkYellow' }
        'LOCK'      { 'DarkYellow' }
        'SKIP'      { 'DarkGray' }
        default     { 'Gray' }
    }
    $line = $gap + ([string]$index).PadLeft($idxWidth) + $gap + (Format-Cell $row.Name $nameWidth) + $gap
    if ($useSubfolders) { $line = $line + (Format-CellTail $row.Src $srcWidth) + $gap }
    $line = $line + (Format-Cell $row.Type $typeWidth) + $gap +
            (Format-Cell $row.Dest $destWidth) + $gap +
            (Format-Cell $row.Act  $actWidth).TrimEnd()
    Write-Host $line -ForegroundColor $colour
}
if ($rows.Count -gt $shown) {
    Write-Host ('  ... {0} more not shown' -f ($rows.Count - $shown)) -ForegroundColor DarkGray
}

# Anything that is not a plain move keeps its real target and reason visible.
$notes = @($rows | Where-Object { $_.Act -in @('RENAME', 'DUPLICATE', 'LOCK') })
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
        $item = $row.Item
        $where = if ($item.Rel -eq '.') { $row.Name } else { $item.Rel + '\' + $row.Name }
        switch ($row.Act) {
            'RENAME'    { $text = '{0} -> {1} (name clash, different content)' -f $where, (Split-Path -Leaf $item.Target) }
            'DUPLICATE' { $text = '{0} -> identical copy at {1}; this one is removed' -f $where, $item.Target }
            'LOCK'      { $text = '{0} -> lock file, removed' -f $where }
        }
        Write-Host ('  ' + $text) -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host ('Summary: {0} move, {1} rename, {2} duplicate-remove, {3} lock-remove, {4} skip' -f `
    $toMove.Count, $toRename.Count, $toDup.Count, $toLock.Count, $toSkip.Count)

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
    if ($useSubfolders) {
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
    [void]$lines.Add('')
    [void]$lines.Add($fHeader)
    [void]$lines.Add($fRule)

    $fileIndex = 0
    foreach ($row in $rows) {
        $fileIndex++
        $line = $gap + ([string]$fileIndex).PadLeft($fIdxWidth) + $gap + (Format-Cell $row.Name $fNameWidth) + $gap
        if ($useSubfolders) { $line = $line + (Format-CellTail $row.Src $fSrcWidth) + $gap }
        $line = $line + (Format-Cell $row.Type $fTypeWidth) + $gap +
                (Format-Cell $row.Dest $fDestWidth) + $gap +
                (Format-Cell $row.Act  $fActWidth).TrimEnd()
        [void]$lines.Add($line)
    }

    if ($notes.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Notes')
        foreach ($row in $notes) {
            $item = $row.Item
            $where = if ($item.Rel -eq '.') { $row.Name } else { $item.Rel + '\' + $row.Name }
            switch ($row.Act) {
                'RENAME'    { $text = '{0} -> {1} (name clash, different content)' -f $where, (Split-Path -Leaf $item.Target) }
                'DUPLICATE' { $text = '{0} -> identical copy at {1}; this one is removed' -f $where, $item.Target }
                'LOCK'      { $text = '{0} -> lock file, removed' -f $where }
            }
            [void]$lines.Add('  ' + $text)
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add(('Summary: {0} move, {1} rename, {2} duplicate-remove, {3} lock-remove, {4} skip' -f `
        $toMove.Count, $toRename.Count, $toDup.Count, $toLock.Count, $toSkip.Count))

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

if (-not $Force) {
    $answer = Read-Host 'Proceed? [y/N]'
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'Aborted. Nothing changed.' -ForegroundColor Yellow
        exit 0
    }
}

# ---------------------------------------------------------------- execute
$failures = 0

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

# Subfolders are never deleted; just say which ones no longer hold any files at all, counting what
# is nested beneath them (a folder holding only a category folder with content is not empty).
if ($useSubfolders) {
    $emptied = @()
    foreach ($dir in $scanDirs) {
        if (-not (Test-Path -LiteralPath $dir.Dir)) { continue }
        $remaining = @(Get-ChildItem -LiteralPath $dir.Dir -File -Force -Recurse -ErrorAction SilentlyContinue).Count
        if ($remaining -eq 0) { $emptied += $dir.Relative }
    }
    if ($emptied.Count -gt 0) {
        $sample = ($emptied | Select-Object -First 3) -join ', '
        Write-Host ('Subfolders with no files left: {0} ({1}{2})' -f $emptied.Count, $sample, $(if ($emptied.Count -gt 3) { ', ...' } else { '' })) -ForegroundColor DarkGray
    }
}

if ($failures -gt 0) {
    Write-Host ('Finished with {0} error(s). Log: {1}' -f $failures, $LogFile) -ForegroundColor Red
    exit 1
}

Write-Host ('Done. Log: {0}' -f $LogFile) -ForegroundColor Green
exit 0
