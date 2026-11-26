param(
    [Parameter(Mandatory = $true)]
    [string]$VdmjJar,
    [string]$JavaExe = 'java',
    [switch]$SoloDemo
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$taskJar = (Resolve-Path -LiteralPath $VdmjJar).Path
$taskJava = (Get-Command -Name $JavaExe -ErrorAction Stop).Source
$taskModels = @(
    (Join-Path $PSScriptRoot 'modelo/Banco.vdmpp'),
    (Join-Path $PSScriptRoot 'modelo/MiddlewareVerificador.vdmpp')
)
$taskTests = Join-Path $PSScriptRoot 'pruebas/PruebasMiddleware.vdmpp'
$taskDemo = Join-Path $PSScriptRoot 'pruebas/DemostracionMiddleware.vdmpp'
$taskFiles = @($taskModels) + @($taskTests)
$taskScenarioCount = 29
$taskExpectedHash = 'CB512AA62AE5870FB0B5E12DBA1EE9019A55CC77E61C3B5257564289E964236F'
if ((Get-FileHash -LiteralPath $taskJar -Algorithm SHA256).Hash -ne $taskExpectedHash) {
    throw 'El JAR no coincide con la version VDMJ 4.7.0 utilizada en esta entrega.'
}
$taskEvidence = Join-Path $PSScriptRoot 'evidencias'
New-Item -ItemType Directory -Force -Path $taskEvidence | Out-Null

function Invoke-TaskVdmj {
    param([string[]]$Files, [string[]]$VdmArguments)
    $taskLines = & $taskJava -jar $taskJar -vdmpp -c UTF-8 @Files @VdmArguments 2>&1
    $taskExit = $LASTEXITCODE
    return [pscustomobject]@{ ExitCode = $taskExit; Text = ($taskLines -join "`n") }
}

$demo = Invoke-TaskVdmj -Files (@($taskModels) + @($taskDemo)) -VdmArguments @('-e', 'DemostracionMiddleware`Ejecutar()')
$demo.Text | Set-Content -LiteralPath (Join-Path $taskEvidence 'demostracion-vdmj.txt') -Encoding utf8
$demoPattern = 'mk_Paso\("([^"]+)",\s*(\d+),\s*<([A-Z_]+)>,\s*<([A-Z_]+)>,\s*(\d+),\s*(nil|\d+)\)'
$demoRows = @([regex]::Matches($demo.Text, $demoPattern) | ForEach-Object {
    [pscustomobject]@{
        Escenario = $_.Groups[1].Value
        Reloj = [int]$_.Groups[2].Value
        Respuesta = $_.Groups[3].Value
        EstadoDelID = $_.Groups[4].Value
        Autorizaciones = [int]$_.Groups[5].Value
        EvidenciaEn = $_.Groups[6].Value
    }
})
$demoExpected = @(
    '0/SIN_DIRECTORIO/RECHAZADA/0/nil'
    '0/BANCO_NO_DISPONIBLE/RECHAZADA/0/nil'
    '6/DESACTUALIZADO/RECHAZADA/0/nil'
    '11/VALIDA/AUTORIZADA/1/6'
    '12/DUPLICADA/AUTORIZADA/1/6'
    '12/CONFLICTO/AUTORIZADA/1/6'
)
$demoActual = @($demoRows | ForEach-Object {
    "$($_.Reloj)/$($_.Respuesta)/$($_.EstadoDelID)/$($_.Autorizaciones)/$($_.EvidenciaEn)"
})
if ($demo.ExitCode -ne 0 -or $demo.Text -match 'EXCEPTION:|Error [0-9]+:' -or
    ($demoActual -join '|') -cne ($demoExpected -join '|')) {
    throw 'La demostracion no produjo la traza esperada. Revise evidencias/demostracion-vdmj.txt.'
}
Write-Output 'Demostracion para TX001. EvidenciaEn es el instante de observacion guardado.'
$demoRows | Format-Table -AutoSize
if ($SoloDemo) { return }

$taskRun = Invoke-TaskVdmj -Files $taskFiles -VdmArguments @('-e', 'PruebasMiddleware`EjecutarTodas()')
$taskRun.Text | Set-Content -LiteralPath (Join-Path $taskEvidence 'pruebas-vdmj.txt') -Encoding utf8
$taskTrueList = '(?m)^\[' + ((@('true') * $taskScenarioCount) -join ', ') + '\]\r?$'
if ($taskRun.ExitCode -ne 0 -or $taskRun.Text -notmatch $taskTrueList -or
    $taskRun.Text -match 'EXCEPTION:|Error [0-9]+:' -or
    $taskRun.Text -notmatch 'Type checked 3 classes.*No type errors') {
    throw "Los $taskScenarioCount escenarios no finalizaron correctamente. Revise evidencias/pruebas-vdmj.txt."
}

$taskCases = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $PSScriptRoot 'pruebas/casos-negativos.json') | ConvertFrom-Json
$taskNegativeLog = [System.Collections.Generic.List[string]]::new()
foreach ($taskCase in $taskCases) {
    $taskResult = Invoke-TaskVdmj -Files $taskModels -VdmArguments @('-e', $taskCase.expresion)
    $taskNegativeLog.Add("CASO: $($taskCase.nombre)`nEXPRESION: $($taskCase.expresion)`n$($taskResult.Text)`n")
    $taskNegativeLog | Set-Content -LiteralPath (Join-Path $taskEvidence 'pruebas-negativas-vdmj.txt') -Encoding utf8
    if ($taskResult.Text -notmatch [regex]::Escape($taskCase.errorEsperado) -or
        $taskResult.Text -notmatch 'Type checked 2 classes.*No type errors' -or
        $taskResult.Text -notmatch 'Initialized 2 classes.*No init errors') {
        throw "No se obtuvo el rechazo esperado para $($taskCase.nombre)."
    }
}

$taskPo = Invoke-TaskVdmj -Files $taskFiles -VdmArguments @('-p')
$taskPo.Text | Set-Content -LiteralPath (Join-Path $taskEvidence 'obligaciones-vdmj.txt') -Encoding utf8
if ($taskPo.ExitCode -ne 0 -or $taskPo.Text -notmatch 'Generated [0-9]+ proof obligations' -or
    $taskPo.Text -notmatch 'No POG errors' -or $taskPo.Text -match 'EXCEPTION:|Error [0-9]+:') {
    throw 'Fallo la generacion de obligaciones. Revise evidencias/obligaciones-vdmj.txt.'
}
$taskPoCount = [regex]::Match($taskPo.Text, 'Generated ([0-9]+) proof obligations').Groups[1].Value
@{
    fecha = (Get-Date).ToString('o')
    herramienta = 'VDMJ 4.7.0'
    escenariosConformes = $taskScenarioCount
    rechazosEsperados = $taskCases.Count
    decisionesDemostradas = $demoRows.Count
    obligacionesGeneradas = [int]$taskPoCount
    demostracionMecanizada = $false
    pruebasConcurrentes = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskEvidence 'resumen-validacion.json') -Encoding utf8
Write-Output "Correcto: $taskScenarioCount/$taskScenarioCount escenarios y $($taskCases.Count)/$($taskCases.Count) rechazos esperados por contrato."
Write-Output "$taskPoCount obligaciones generadas; no se presentan como demostradas. Pruebas secuenciales."
