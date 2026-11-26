param(
    [Parameter(Mandatory = $true)]
    [string]$NuSMVExe
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$exe = (Resolve-Path -LiteralPath $NuSMVExe).Path
$modelPath = Join-Path $PSScriptRoot 'middleware_detallado.smv'
$commandsPath = Join-Path $PSScriptRoot 'verificar.nusmv'
$evidence = Join-Path $PSScriptRoot 'evidencias'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null

$expected = [ordered]@{}
$definitions = Get-Content -LiteralPath $modelPath -Raw
foreach ($match in [regex]::Matches($definitions, '(?m)^(?<kind>LTL|CTL)SPEC\s+NAME\s+(?<name>[A-Za-z0-9_]+)\s*:=')) {
    $expected.Add($match.Groups['name'].Value, $match.Groups['kind'].Value)
}
if (@($expected.Values | Where-Object { $_ -eq 'LTL' }).Count -lt 2) {
    throw 'El modelo requiere al menos dos propiedades LTL.'
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $lines = & $exe -s -source $commandsPath 2>&1
    $exit = $LASTEXITCODE
} finally {
    Pop-Location
}
$log = $lines -join "`n"
$logPath = Join-Path $evidence 'verificacion.txt'
$log | Set-Content -LiteralPath $logPath -Encoding utf8
if ($exit -ne 0 -or $log -notmatch 'The transition relation is total: No deadlock state exists' -or
    $log -match '(?im)(?:syntax error|error in parsing|type error|cannot open)') {
    throw "NuSMV no pudo confirmar un modelo ejecutable sin bloqueos. Lea $logPath"
}

$results = @{}
foreach ($entry in [regex]::Matches($log, '(?m)^\s*\[(?<kind>LTL|CTL)\s+(?<status>True|False|Unchecked)\s+\S+\s+(?<name>[A-Za-z0-9_]+)\]\s*$')) {
    $name = $entry.Groups['name'].Value
    $results.Add($name, [ordered]@{
        nombre = $name
        logica = $entry.Groups['kind'].Value
        resultado = $entry.Groups['status'].Value.ToLowerInvariant()
    })
}
if ($results.Count -ne $expected.Count) {
    throw "La salida reporta $($results.Count) propiedades de $($expected.Count) declaradas. Lea $logPath"
}
foreach ($name in $expected.Keys) {
    if (!$results.ContainsKey($name) -or $results[$name].logica -ne $expected[$name] -or $results[$name].resultado -ne 'true') {
        throw "La propiedad $name no fue confirmada. Lea $logPath"
    }
}

$reach = [regex]::Match($log, '(?m)^reachable states: (?<reached>\d+) .*? out of (?<possible>\d+) ')
$diameter = [regex]::Match($log, '(?m)^system diameter: (?<diameter>\d+)')
$version = [regex]::Match($log, '(?m)^\*\*\* This is (?<version>NuSMV [^\s]+)')
if (!$reach.Success -or !$diameter.Success -or !$version.Success) {
    throw "NuSMV no informó la versión y las métricas de alcanzabilidad. Lea $logPath"
}

$ltl = @($results.Values | Where-Object { $_.logica -eq 'LTL' }).Count
$ctl = @($results.Values | Where-Object { $_.logica -eq 'CTL' }).Count
[ordered]@{
    herramienta = $version.Groups['version'].Value
    modelo = 'middleware_detallado.smv'
    sha256Modelo = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sha256Ejecutable = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    relacionTotal = $true
    estadosAlcanzables = [int64]$reach.Groups['reached'].Value
    combinacionesDeEstado = [int64]$reach.Groups['possible'].Value
    diametro = [int]$diameter.Groups['diameter'].Value
    ltlVerdaderas = $ltl
    ctlVerdaderas = $ctl
    propiedades = @($expected.Keys | ForEach-Object { $results[$_] })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'resumen.json') -Encoding utf8

Write-Output "Verificación correcta: $ltl LTL y $ctl CTL verdaderas. Relación total."
Write-Output "$($reach.Groups['reached'].Value) estados alcanzables. Evidencias: $evidence"
