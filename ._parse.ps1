Continue=''Stop''
foreach ( in @(''own_lib.ps1'',''tg_report.ps1'')) {
  =; =
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ), [ref], [ref])
  if ( -and .Count -gt 0) {  | ForEach-Object { .ToString() }; exit 1 }
  Write-Output (''PARSE OK ''+)
}
