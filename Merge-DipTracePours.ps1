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
  [switch]$AllowUnitConversion
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
$targetFull=[System.IO.Path]::GetFullPath($TargetPath)
$sourceFull=[System.IO.Path]::GetFullPath($SourcePath)
$outputFull=[System.IO.Path]::GetFullPath($OutputPath)
if ($outputFull -ieq $targetFull -or $outputFull -ieq $sourceFull) { throw 'Output must be a new file and cannot overwrite either input.' }
if (Test-Path -LiteralPath $outputFull) { throw 'Output already exists. Choose a new filename to avoid overwriting prior work.' }
$target=Read-DipXml $targetFull
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
$items=if ($SourceMode -eq 'Pours') { $sourcePours } else { $sourceShapes }
if ($items.Count -eq 0) { throw "No $SourceMode found in source XML." }
$added=0;$skipped=0;$invalid=0
foreach ($item in $items) {
  if ($SourceMode -eq 'Pours') {
    $new=[System.Xml.XmlElement]$target.ImportNode($item,$true)
    $new.RemoveAttribute('Poured');$new.RemoveAttribute('Selected');$new.RemoveAttribute('Group');$new.RemoveAttribute('ShieldGroup');$new.RemoveAttribute('TraceShieldGroup')
    $new.SetAttribute('NetId','-1');$new.SetAttribute('RegionsDone','N')
    foreach ($n in @($new.SelectNodes('./Lines|./Polygons|./SpokeLine|./Regions'))) { [void]$new.RemoveChild($n) }
  } else {
    try {
      if ($item.GetAttribute('Layer') -notin @('Signal/Plane','3')) { $invalid++;continue }
      $new=Convert-Shape $item $target $TargetLayer
    } catch { Write-Warning "Shape skipped: $($_.Exception.Message)";$invalid++;continue }
  }
  $pts=@($new.SelectNodes('./Points/Point'))
  if ($pts.Count -lt 3) { $invalid++; continue }
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
  if ($DuplicateMode -eq 'Skip' -and $existing.Contains($signature)) { $skipped++;continue }
  [void]$existing.Add($signature)
  [void]$targetPours.AppendChild($new)
  $nextId++;$added++
}
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
Write-Output "SUCCESS: Added=$added; DuplicatesSkipped=$skipped; UnsupportedSkipped=$invalid; TotalPours=$finalCount; Output=$outputFull"
