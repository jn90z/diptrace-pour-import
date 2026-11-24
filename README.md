# DipTrace Copper Pour Importer

A Windows PowerShell 5.1 GUI for merging DXF-derived copper shapes or already-created copper pours into an existing DipTrace PCB Layout **XML** (`.dipxml`) design. It replaces the former copy-and-paste step of the [DipTrace forum DXF-to-pour workaround](https://diptrace.com/forum/viewtopic.php?t=13968).

**Status: first implementation; not yet validated by opening a merged board in DipTrace 5.3.** Work on a copy and inspect the merged result before production.

## Manual DipTrace steps (still required)

1. Prepare **closed outlines** in AutoCAD/DXF. Check drawing units and clean overlapping segments before exporting DXF.
2. Launch a **new blank PCB Layout window** in DipTrace 5.3. Do not import into your production board.
3. Choose **File > Import > DXF**, select correct DXF units, **Import Mode: Add**, **Convert to: Top**, and enable **Fill closed areas** and **Embedded Polygons**. Inspect the Top copper results. This recreates the workflow in the forum discussion.
4. Choose **File > Export > DipTrace XML** (or File > Save As > DipTrace XML depending on your version) and save the temporary shapes-only project as `source_shapes.dipxml`. The GUI can convert supported XML `Polygon` and `FillRect` shapes directly into pours, so the intermediate ASCII export is not needed.
5. Export or save your **actual production board** separately as `original_board.dipxml`. Do not export only selected objects; use a complete board file.
6. Launch `Start-PourImporter.ps1`, select the production board, source shapes XML, and a **new** output path. Keep Source Type `Auto` (pours preferred if present, otherwise shapes). Use target layer ID **0** for typical top copper; verify the numeric layer in your board.
7. Click **Merge copper pours**. Open the resulting `.dipxml` in DipTrace, verify the count and alignment of new pours, assign required **nets and thermal/fill parameters**, **pour/re-pour** the copper, and run DRC. Save as a native `.dip` when satisfied.

### If your source already contains copper pours

You can also select a separate `.dipxml` with existing pours. Set Source Type `Pours` or `Auto`. The tool appends source pour outlines, resets them to *unpoured and unconnected*, and preserves most of their fill settings. It does not copy source net IDs because those IDs may refer to unrelated destination nets.

## Launch

Use Windows PowerShell 5.1 on a Windows desktop:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Start-PourImporter.ps1
```

Optional command-line use:

```powershell
.\Merge-DipTracePours.ps1 -TargetPath .\original_board.dipxml `
  -SourcePath .\source_shapes.dipxml -OutputPath .\merged_board.dipxml `
  -SourceMode Shapes -TargetLayer 0
```

The command-line script also provides `-Clearance`, `-BoardClearance`, `-LineWidth`, `-LineSpacing`, `-MinimumArea`, `-SpokeWidth`, `-Priority`, `-DuplicateMode Allow` and `-AllowUnitConversion` switches. Its default dimensions are in **destination file units**, so review these for your board.

## Safety and scope

- Only `/Source/Board/CopperPours` is modified. All other PCB design contents are retained by XML DOM processing (whitespace formatting can change).
- New pours receive sequential IDs. Existing pours are **not** renumbered. An existing nonsequential pour ID list causes an error.
- Matching outlines are skipped by default using normalized vertex sequences (rotation/reversal invariant, 6-decimal coordinate rounding). This is not a complete geometric-equivalence test: overlapping or geometrically equivalent polygons with different vertices may still both be added.
- XML input must be a full `Source Type="DipTrace-PCB"` board; DTDs are prohibited. Source and target units must match unless explicit conversion is allowed.
- Source shapes are limited to `Polygon` and `FillRect` with signal-plane layer designation. Lines, arcs, polylines and complex compound shapes are not automatically converted, because open or self-intersecting geometry may generate invalid pours.
- The source and target must be **aligned in their coordinate systems**. This tool can scale units but does not estimate or correct translation, rotation or mirroring.
- New pours default to `NetId=-1`. Do not assume they are electrically connected until nets and repouring are checked inside DipTrace.
- Existing output files are never overwritten, and neither input is modified.

## Related work and documentation

- [Original forum method and bulk ASCII script](https://diptrace.com/forum/viewtopic.php?t=13968)
- [DipTrace PCB XML format specification](https://www.diptrace.com/support/tutorials/xml_specs_PCB_html/), especially `<CopperPours>` and `<Shapes>`.
- `legacy/Export-CopperPours.ps1` is retained as a reference, not used by the XML GUI.

## Future improvements

Sample real DipTrace 5.3 `.dipxml` boards with complex copper fills should be used to verify serializer compatibility, group IDs, multiple layers, source polygon types, and DipTrace open/re-save behaviour. A future release can support an optional preview and per-pour net assignment.
