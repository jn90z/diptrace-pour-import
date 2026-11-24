<#
.SYNOPSIS
  Extracts (Points ...) from each (Shape ...) inside the first (Shapes ...) block
  of a DipTrace .asc file and wraps them in a (CopperPour ...) template.
.EXAMPLE
  .\Export-CopperPours.ps1 -InputPath .\points.asc -OutputPath .\copper_pours.txt
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$InputPath,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [int]$Layer = 0,[double]$LineWidth = 0.6,[double]$Clearance = 0.6,
  [double]$MinimumArea = 2.41,[double]$LineSpacing = 0.9,[double]$SpokeWidth = 0.75,
  [double]$BoardClearance = 1.936,[int]$Priority = 0
)
Set-StrictMode -Version Latest
function Get-BalancedBlock {
 param([Parameter(Mandatory = $true)][string]$Text,[Parameter(Mandatory = $true)][int]$StartIndex)
 $depth=0;$inString=$false;$escape=$false
 for($i=$StartIndex;$i -lt $Text.Length;$i++){
  $ch=$Text[$i]
  if($escape){$escape=$false;continue}
  if($ch -eq '\'){$escape=$true;continue}
  if($ch -eq '"'){$inString=-not $inString;continue}
  if($inString){continue}
  if($ch -eq '('){$depth++;continue}
  if($ch -eq ')'){$depth--;if($depth -eq 0 -and $i -gt $StartIndex){return $Text.Substring($StartIndex,($i-$StartIndex+1))}}
 }
 return $Text.Substring($StartIndex)
}
function Find-TokenIndex {
 param([Parameter(Mandatory = $true)][string]$Text,[Parameter(Mandatory = $true)][string]$Token,[int]$StartAt=0)
 return $Text.IndexOf($Token,$StartAt,[System.StringComparison]::Ordinal)
}
if(-not(Test-Path -LiteralPath $InputPath)){throw "InputPath not found: $InputPath"}
$raw=Get-Content -LiteralPath $InputPath -Raw -ErrorAction Stop
$shapesStart=Find-TokenIndex -Text $raw -Token '(Shapes' -StartAt 0
if($shapesStart -lt 0){throw "Could not find '(Shapes' in file."}
$shapesBlock=Get-BalancedBlock -Text $raw -StartIndex $shapesStart
$shapeMatches=[regex]::Matches($shapesBlock,"\((?i:Shape)(?=\s)")
if($shapeMatches.Count -eq 0){throw "Found '(Shapes' but no '(Shape ...)' blocks inside it."}
function Build-CopperPour {
 param([Parameter(Mandatory = $true)][string]$PointsBlock,[Parameter(Mandatory = $true)][int]$OldNumber)
 $pointsIndented=($PointsBlock -split "`r?`n" | ForEach-Object { "      "+$_ }) -join "`r`n"
 return @"
(CopperPour
      (Enabled "Y")
      (Selected "N")
      (Poured "N")
      (LineWidth $LineWidth)
      (Clearance $Clearance)
      (MinimumArea $MinimumArea)
      (Group -1)
      (Layer $Layer)
      (NetNumber -1)
$pointsIndented
      (Lines
      )
      (Polygons
      )
      (Type 0)
      (Spoke 0)
      (LineSpacing $LineSpacing)
      (SpokeWidth $SpokeWidth)
      (SpokeLine
      )
      (UseNetClearance "Y")
      (Locked "N")
      (SnapToBoard "N")
      (BoardClearance $BoardClearance)
      (IslandRegion "N")
      (IslandInternal "N")
      (IslandConnection "Y")
      (OldNumber $OldNumber)
      (ViaDirect "Y")
      (SMD_Separate "N")
      (SMD_Spoke 4)
      (SMD_SpokeWidth $SpokeWidth)
      (PanelExclude "N")
      (Regions_Counted "N")
      (Priority $Priority)
    )
"@
}
$pours=New-Object System.Collections.Generic.List[string]
$old=0
foreach($m in $shapeMatches){
 $shapeBlock=Get-BalancedBlock -Text $shapesBlock -StartIndex $m.Index
 $pStart=Find-TokenIndex -Text $shapeBlock -Token '(Points' -StartAt 0
 if($pStart -lt 0){continue}
 $pointsBlock=Get-BalancedBlock -Text $shapeBlock -StartIndex $pStart
 $pours.Add((Build-CopperPour -PointsBlock $pointsBlock -OldNumber $old))
 $old++
}
if($pours.Count -eq 0){throw "No (Points ...) blocks found inside (Shape ...) blocks."}
$outText=($pours -join "`r`n")
Set-Content -LiteralPath $OutputPath -Value $outText -Encoding UTF8
Write-Host "Wrote $($pours.Count) copper pours to: $OutputPath"
