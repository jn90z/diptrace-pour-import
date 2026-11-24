#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$TargetPath,
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath,
  [ValidateSet('Auto','Pours','Shapes')][string]$SourceMode = 'Auto',
  [ValidateSet('Skip','Allow')][string]$DuplicateMode = 'Skip',
  [int]$TargetLayer = 0,
  [double]$Clearance = 0.33,
  [double]$BoardClearance = 0.33,
  [double]$LineWidth = 0.1,
  [double]$LineSpacing = 0.1,
  [double]$MinimumArea = 0,
  [double]$SpokeWidth = 0.33,
  [int]$Priority = 0,
  [switch]$AllowUnitConversion,
  [switch]$AnalyzeOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$culture = [System.Globalization.CultureInfo]::InvariantCulture
function Read-DipXml([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
  $settings = New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver = $null
  $reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $Path).ProviderPath, $settings)
  try {
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.PreserveWhitespace = $true
    $doc.Load($reader)
  } finally { $reader.Dispose() }
  if ($doc.DocumentElement.LocalName -ne 'Source' -or $doc.DocumentElement.GetAttribute('Type') -ne 'DipTrace-PCB') { throw "Not a DipTrace PCB XML document: $Path" }
  if ($null -eq $doc.SelectSingleNode('/Source/Board')) { throw "Missing /Source/Board: $Path" }
  return $doc
}
function Get-Units([System.Xml.XmlDocument]$Doc) {
  $u = $Doc.DocumentElement.GetAttribute('Units').ToLowerInvariant()
  if ($u -eq 'in') { $u = 'inch' }
  if ($u -notin @('mm','inch','mil')) { throw "Unsupported or missing Units='$u'" }
  return $u
}
function Get-Factor([string]$From,[string]$To) {
  $mm = @{mm=1.0; inch=25.4; mil=0.0254}
  return $mm[$From] / $mm[$To]
}
function Num([double]$n) { return $n.ToString('G17',$culture) }
function Get-PolygonSignature([System.Xml.XmlElement]$Pour) {
  $points = @($Pour.SelectNodes('./Points/Point'))
  if ($points.Count -lt 3) { throw 'A pour has fewer than three vertices.' }
  $coords = New-Object 'System.Collections.Generic.List[string]'
  foreach ($p in $points) {
    $x = [double]::Parse($p.GetAttribute('X'),$culture)
    $y = [double]::Parse($p.GetAttribute('Y'),$culture)
    $coords.Add(('{0:F6},{1:F6}' -f $x,$y))
  }
  if ($coords.Count -gt 3 -and $coords[0] -eq $coords[$coords.Count-1]) { $coords.RemoveAt($coords.Count-1) }
  $a = $coords.ToArray()
  $alternatives = New-Object 'System.Collections.Generic.List[string]'
  for ($i=0;$i -lt $a.Length;$i++) {
    $cw = for($j=0;$j -lt $a.Length;$j++) { $a[($i+$j)%$a.Length] }
    $ccw = for($j=0;$j -lt $a.Length;$j++) { $a[(($i-$j+$a.Length)%$a.Length)] }
    $alternatives.Add(($cw -join ';'))
    $alternatives.Add(($ccw -join ';'))
  }
  $sorted = $alternatives.ToArray(); [array]::Sort($sorted,[System.StringComparer]::Ordinal)
  return ($Pour.GetAttribute('Lay') + '|' + $sorted[0])
}
function Check-Ids([System.Xml.XmlElement]$Pours) {
  $i=0
  foreach ($p in @($Pours.SelectNodes('./CopperPour'))) {
    $id = -1
    if (-not [int]::TryParse($p.GetAttribute('Id'),[ref]$id) -or $id -ne $i) { throw "Existing copper pours do not have dense sequential Ids (expected $i). Refusing to reorder existing pours." }
    $i++
  }
  return $i
}
function Convert-Shape([System.Xml.XmlElement]$Shape,[System.Xml.XmlDocument]$Doc,[int]$Lay) {
  $type = $Shape.GetAttribute('Type')
  if ($type -notin @('Polygon','FillRect','9','3')) { throw "Unsupported shape type '$type'. Only Polygon and FillRect are accepted." }
  $pts = @($Shape.SelectNodes('./Points/Point'))
  if ($type -in @('FillRect','3')) {
    if ($pts.Count -ne 2) { throw 'FillRect requires exactly 2 points.' }
    $x1=[double]::Parse($pts[0].GetAttribute('X'),$culture);$x2=[double]::Parse($pts[1].GetAttribute('X'),$culture)
    $y1=[double]::Parse($pts[0].GetAttribute('Y'),$culture);$y2=[double]::Parse($pts[1].GetAttribute('Y'),$culture)
    $coords = @(@($x1,$y1),@($x2,$y1),@($x2,$y2),@($x1,$y2))
  } else {
    if ($pts.Count -lt 3) { throw 'Polygon requires at least three points.' }
    $coords = @($pts | ForEach-Object { ,@([double]::Parse($_.GetAttribute('X'),$culture),[double]::Parse($_.GetAttribute('Y'),$culture)) })
  }
  $p=$Doc.CreateElement('CopperPour')
  $settings=[ordered]@{NetId='-1';Lay=[string]$Lay;Priority=[string]$Priority;Type='Solid';Clearance=(Num $Clearance);UseNetClearance='Y';BoardClearance=(Num $BoardClearance);LineWidth=(Num $LineWidth);LineSpacing=(Num $LineSpacing);MinimumArea=(Num $MinimumArea);Spoke='Direct';SpokeWidth=(Num $SpokeWidth);ViaDirect='Y';SMD_Separate='N';SMD_Spoke='4 spoke';SMD_SpokeWidth=(Num $SpokeWidth);RatlineMode='Automaticaly';SnapToBoard='N';IslandRegion='N';IslandInternal='N';IslandConnection='Y';RegionsDone='N'}
  foreach ($key in $settings.Keys) { $p.SetAttribute($key,$settings[$key]) }
  $list=$Doc.CreateElement('Points')
  foreach ($xy in $coords) { $point=$Doc.CreateElement('Point');$point.SetAttribute('X',(Num $xy[0]));$point.SetAttribute('Y',(Num $xy[1]));[void]$list.AppendChild($point) }
  [void]$p.AppendChild($list)
  return $p
}
$timer=[Diagnostics.Stopwatch]::StartNew()
$logPath=$null
function Report([string]$Message) {
  $line=('{0:HH:mm:ss} {1}' -f (Get-Date),$Message)
  if ($logPath) { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 }
  Write-Host $line
}
try {
$targetFull=[System.IO.Path]::GetFullPath($TargetPath)
$sourceFull=[System.IO.Path]::GetFullPath($SourcePath)
$outputFull=[System.IO.Path]::GetFullPath($OutputPath)
if ($outputFull -ieq $targetFull -or $outputFull -ieq $sourceFull) { throw 'Output must be a new file and cannot overwrite either input.' }
if (Test-Path -LiteralPath $outputFull) { throw 'Output already exists. Choose a new filename to avoid overwriting prior work.' }
$logPath=Join-Path ([IO.Path]::GetDirectoryName($outputFull)) (([IO.Path]::GetFileName($outputFull))+'.'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.'+[guid]::NewGuid().ToString('N')+'.log')
Report "Target: $targetFull"
Report "Source: $sourceFull"
Report "Output: $outputFull"
Report "Log: $logPath"
$target=Read-DipXml $targetFull
$baseline=$target.CloneNode($true)
$source=Read-DipXml $sourceFull
$targetUnit=Get-Units $target
$sourceUnit=Get-Units $source
$factor=Get-Factor $sourceUnit $targetUnit
if ($factor -ne 1 -and -not $AllowUnitConversion) { throw "Units differ ($sourceUnit -> $targetUnit). Re-run with -AllowUnitConversion after checking coordinate origins." }
$targetPours=$target.SelectSingleNode('/Source/Board/CopperPours')
if ($null -eq $targetPours) { $targetPours=$target.CreateElement('CopperPours'); [void]$target.SelectSingleNode('/Source/Board').AppendChild($targetPours) }
$nextId=Check-Ids $targetPours
$existing=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($p in @($targetPours.SelectNodes('./CopperPour'))) { [void]$existing.Add((Get-PolygonSignature $p)) }
$sourcePours=@($source.SelectNodes('/Source/Board/CopperPours/CopperPour'))
$sourceShapes=@($source.SelectNodes('/Source/Board/Shapes/Shape'))
if ($SourceMode -eq 'Auto') { if ($sourcePours.Count -gt 0) { $SourceMode='Pours' } else { $SourceMode='Shapes' } }
$items=@(if ($SourceMode -eq 'Pours') { $sourcePours } else { $sourceShapes })
Report "Source mode: $SourceMode; source units: $sourceUnit; target units: $targetUnit; scale: $factor"
Report "Shapes detected: $($sourceShapes.Count); source pours detected: $($sourcePours.Count); existing destination pours: $nextId"
foreach ($group in @($sourceShapes | Group-Object -Property { $_.GetAttribute('Type') })) { Report "Shape type $($group.Name): $($group.Count)" }
$initialCount=$nextId
if ($items.Count -eq 0) { throw "No $SourceMode found in source XML." }
$added=0;$skipped=0;$invalid=0;$processed=0;$converted=0
foreach ($item in $items) {
  $processed++
  if ($processed -eq 1 -or $processed % 25 -eq 0 -or $processed -eq $items.Count) { Report "PROGRESS $processed/$($items.Count)" }
  try {
  if ($SourceMode -eq 'Pours') {
    $new=[System.Xml.XmlElement]$target.ImportNode($item,$true)
    $new.RemoveAttribute('Poured');$new.RemoveAttribute('Selected');$new.RemoveAttribute('Group');$new.RemoveAttribute('ShieldGroup');$new.RemoveAttribute('TraceShieldGroup')
    $new.SetAttribute('NetId','-1');$new.SetAttribute('RegionsDone','N')
    foreach ($n in @($new.SelectNodes('./Lines|./Polygons|./SpokeLine|./Regions'))) { [void]$new.RemoveChild($n) }
  } else {
    try {
      if ($item.GetAttribute('Layer') -notin @('Signal/Plane','3')) { throw 'Not a signal-plane shape' }
      $new=Convert-Shape $item $target $TargetLayer
    } catch { throw }
  }
  $pts=@($new.SelectNodes('./Points/Point'))
  if ($pts.Count -lt 3) { throw 'Fewer than three vertices' }
  foreach ($pt in $pts) {
    if ($factor -ne 1) {
      foreach ($axis in @('X','Y')) {
        $v=[double]::Parse($pt.GetAttribute($axis),$culture)
        $pt.SetAttribute($axis,(Num ($v*$factor)))
      }
    }
  }
  $new.SetAttribute('Id',[string]$nextId)
  $signature=Get-PolygonSignature $new
  $converted++
  if ($VerbosePreference -eq 'Continue') { Report "Item $processed prepared: $($pts.Count) vertices" }
  if ($DuplicateMode -eq 'Skip' -and $existing.Contains($signature)) { $skipped++;Report "Item $processed skipped: duplicate outline";continue }
  [void]$existing.Add($signature)
  [void]$targetPours.AppendChild($new)
  $nextId++;$added++
  } catch { $invalid++;Report "WARNING item ${processed}: $($_.Exception.Message)" }
}
Report "SUMMARY detected=$($items.Count); prepared=$converted; shapesConverted=$(if ($SourceMode -eq 'Shapes') {$converted} else {0}); duplicates=$skipped; invalid=$invalid; plannedMerge=$added; existing=$initialCount; plannedTotal=$nextId"
if ($AnalyzeOnly) { Report "ANALYSIS COMPLETE: no PCB exported; elapsed=$($timer.Elapsed.TotalSeconds) seconds"; return }
if ($added -eq 0) { throw "Nothing to merge (duplicates=$skipped; unsupported=$invalid). No output created." }
$folder=[System.IO.Path]::GetDirectoryName($outputFull)
if (-not (Test-Path -LiteralPath $folder)) { throw "Output folder does not exist: $folder" }
$writeSettings=New-Object System.Xml.XmlWriterSettings
$writeSettings.Indent=$true
$writeSettings.Encoding=New-Object System.Text.UTF8Encoding($false)
$writeSettings.CloseOutput=$true
$writer=[System.Xml.XmlWriter]::Create($outputFull,$writeSettings)
try { $target.Save($writer) } finally { $writer.Dispose() }
$check=Read-DipXml $outputFull
$finalCount=@($check.SelectNodes('/Source/Board/CopperPours/CopperPour')).Count
if ($finalCount -ne $nextId) { Remove-Item -LiteralPath $outputFull -Force;throw 'Verification failed: output pour count mismatch.' }
# Compare non-pour XML and existing pour nodes after normalizing formatting.
function Canonical([System.Xml.XmlNode]$Node) {
  $copy=New-Object System.Xml.XmlDocument
  $copy.PreserveWhitespace=$false
  $copy.LoadXml($Node.OuterXml)
  return $copy.DocumentElement.OuterXml
}
try {
  $oldPours=@($baseline.SelectNodes('/Source/Board/CopperPours/CopperPour'))
  $newPours=@($check.SelectNodes('/Source/Board/CopperPours/CopperPour'))
  for($i=0;$i -lt $oldPours.Count;$i++) {
    if ((Canonical $oldPours[$i]) -cne (Canonical $newPours[$i])) { throw "Existing pour $i changed" }
  }
  foreach ($doc in @($baseline,$check)) {
    $node=$doc.SelectSingleNode('/Source/Board/CopperPours')
    if ($node) { [void]$node.ParentNode.RemoveChild($node) }
  }
  if ((Canonical $baseline.DocumentElement) -cne (Canonical $check.DocumentElement)) { throw 'Non-pour XML changed' }
} catch { Remove-Item -LiteralPath $outputFull -Force;throw }
Report "Verification passed: XML readable, existing pours and non-pour XML retained"
$status=if ($invalid -gt 0 -or $skipped -gt 0) {'SUCCESS WITH WARNINGS'} else {'SUCCESS'}
Report "$status : Merged=$added; ExportedTotal=$finalCount; Elapsed=$($timer.Elapsed.TotalSeconds) seconds; Output=$outputFull"
} catch {
  Report "FAILED: $($_.Exception.Message); elapsed=$($timer.Elapsed.TotalSeconds) seconds"
  throw
}
