#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$merge = Join-Path $base 'Merge-DipTracePours.ps1'
$form=New-Object Windows.Forms.Form
$form.Text='DipTrace Copper Pour Importer'
$form.Size=New-Object Drawing.Size(790,800)
$form.StartPosition='CenterScreen'
$form.MinimumSize=New-Object Drawing.Size(790,650)
$form.Font=New-Object Drawing.Font('Segoe UI',9)
$fields=@{}
function Add-FileRow([string]$caption,[int]$y,[string]$key,[string]$filter) {
 $label=New-Object Windows.Forms.Label;$label.Text=$caption;$label.Location=New-Object Drawing.Point(18,$y);$label.AutoSize=$true;$form.Controls.Add($label)
 $tb=New-Object Windows.Forms.TextBox;$tb.Location=New-Object Drawing.Point(18,($y+23));$tb.Size=New-Object Drawing.Size(625,25);$form.Controls.Add($tb)
 $btn=New-Object Windows.Forms.Button;$btn.Text='Browse...';$btn.Location=New-Object Drawing.Point(655,($y+20));$btn.Size=New-Object Drawing.Size(100,29);$form.Controls.Add($btn)
 $btn.Add_Click({
   if ($key -eq 'Output') { $dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Filter=$filter;$dialog.FileName='merged_pours.dipxml' }
   else {$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter=$filter}
   if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $tb.Text=$dialog.FileName }
   $dialog.Dispose()
 }.GetNewClosure())
 $fields[$key]=$tb
}
Add-FileRow '1. Existing PCB layout (.dipxml)' 16 'Target' 'DipTrace XML (*.dipxml)|*.dipxml|XML (*.xml)|*.xml|All files (*.*)|*.*'
Add-FileRow '2. Source pours or DXF-converted shapes (.dipxml)' 94 'Source' 'DipTrace XML (*.dipxml)|*.dipxml|XML (*.xml)|*.xml|All files (*.*)|*.*'
Add-FileRow '3. New merged board output (.dipxml)' 172 'Output' 'DipTrace XML (*.dipxml)|*.dipxml|XML (*.xml)|*.xml'
$settingsLabel=New-Object Windows.Forms.Label;$settingsLabel.Text='Import settings';$settingsLabel.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$settingsLabel.Location=New-Object Drawing.Point(18,259);$settingsLabel.AutoSize=$true;$form.Controls.Add($settingsLabel)
$modeLabel=New-Object Windows.Forms.Label;$modeLabel.Text='Source type';$modeLabel.Location=New-Object Drawing.Point(18,292);$modeLabel.AutoSize=$true;$form.Controls.Add($modeLabel)
$mode=New-Object Windows.Forms.ComboBox;$mode.DropDownStyle='DropDownList';[void]$mode.Items.AddRange(@('Auto','Pours','Shapes'));$mode.SelectedIndex=0;$mode.Location=New-Object Drawing.Point(130,289);$mode.Width=160;$form.Controls.Add($mode)
$dup=New-Object Windows.Forms.CheckBox;$dup.Text='Skip existing matching pour outlines';$dup.Checked=$true;$dup.Location=New-Object Drawing.Point(325,290);$dup.AutoSize=$true;$form.Controls.Add($dup)
$convert=New-Object Windows.Forms.CheckBox;$convert.Text='Convert source units to target units when different';$convert.Checked=$false;$convert.Location=New-Object Drawing.Point(18,330);$convert.AutoSize=$true;$form.Controls.Add($convert)
$layerLabel=New-Object Windows.Forms.Label;$layerLabel.Text='Layer ID for source shapes';$layerLabel.Location=New-Object Drawing.Point(18,366);$layerLabel.AutoSize=$true;$form.Controls.Add($layerLabel)
$layer=New-Object Windows.Forms.NumericUpDown;$layer.Location=New-Object Drawing.Point(190,363);$layer.Maximum=100;$layer.Width=75;$form.Controls.Add($layer)
$note=New-Object Windows.Forms.Label;$note.Text='Source shapes: only closed Polygon and FillRect shapes are converted. New pours are unassigned (NetId=-1) and unpoured; confirm layer, net and fill rules inside DipTrace.';$note.Location=New-Object Drawing.Point(18,401);$note.Size=New-Object Drawing.Size(735,43);$form.Controls.Add($note)
$run=New-Object Windows.Forms.Button;$run.Text='Merge copper pours';$run.Location=New-Object Drawing.Point(18,458);$run.Size=New-Object Drawing.Size(180,36);$run.BackColor=[Drawing.Color]::FromArgb(35,106,177);$run.ForeColor=[Drawing.Color]::White;$form.Controls.Add($run)
$preview=New-Object Windows.Forms.CheckBox;$preview.Text='Analyze only (no PCB output)';$preview.Location=New-Object Drawing.Point(215,460);$preview.AutoSize=$true;$form.Controls.Add($preview)
$verboseBox=New-Object Windows.Forms.CheckBox;$verboseBox.Text='Verbose logging';$verboseBox.Location=New-Object Drawing.Point(480,460);$verboseBox.AutoSize=$true;$form.Controls.Add($verboseBox)
$progress=New-Object Windows.Forms.ProgressBar;$progress.Location=New-Object Drawing.Point(18,500);$progress.Size=New-Object Drawing.Size(737,18);$form.Controls.Add($progress)
$log=New-Object Windows.Forms.TextBox;$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical';$log.Location=New-Object Drawing.Point(18,530);$log.Size=New-Object Drawing.Size(737,215);$log.Anchor='Top,Left,Right,Bottom';$form.Controls.Add($log)
$run.Add_Click({
  $run.Enabled=$false
  try {
    foreach ($key in @('Target','Source','Output')) { if ([string]::IsNullOrWhiteSpace($fields[$key].Text)) { throw "Select $key file first." } }
    $log.AppendText("Starting merge...`r`n")
    $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$merge,'-TargetPath',$fields['Target'].Text,'-SourcePath',$fields['Source'].Text,'-OutputPath',$fields['Output'].Text,'-SourceMode',$mode.SelectedItem.ToString(),'-TargetLayer',$layer.Value.ToString())
    if (-not $dup.Checked) {$argsList+=@('-DuplicateMode','Allow')}
    if ($convert.Checked) {$argsList+='-AllowUnitConversion'}
    if ($preview.Checked) {$argsList+='-AnalyzeOnly'}
    if ($verboseBox.Checked) {$argsList+='-Verbose'}
    $progress.Value=0
    $script:hasWarnings=$false
    & powershell.exe @argsList 2>&1 | ForEach-Object {
      $line=$_.ToString()
      $log.AppendText($line+"`r`n")
      if ($line -match 'PROGRESS (\d+)/(\d+)') { $progress.Value=[int][Math]::Min(100,100*[double]$Matches[1]/[double]$Matches[2]) }
      if ($line -match 'WARNING|duplicates=[1-9]|invalid=[1-9]') {$script:hasWarnings=$true}
      [Windows.Forms.Application]::DoEvents()
    }
    if ($LASTEXITCODE -ne 0) { throw 'Merge failed. Review the log for details.' }
    $progress.Value=100
    $message=if ($preview.Checked) {'Analysis complete. No PCB exported.'} else {'Merge complete. Verify the new board in DipTrace and run DRC.'}
    $status=if ($script:hasWarnings) {'Completed with warnings'} else {'Success'}
    [Windows.Forms.MessageBox]::Show($message,$status) | Out-Null
  } catch { $log.AppendText("ERROR: $($_.Exception.Message)`r`n");[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Merge error') | Out-Null }
  finally { $run.Enabled=$true }
})
[void]$form.ShowDialog()
