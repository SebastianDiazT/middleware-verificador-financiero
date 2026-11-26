[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $VdmjJar,
    [Parameter(Mandatory)][string] $NuSMVExe,
    [string] $JavaExe = 'java'
)

$ErrorActionPreference = 'Stop'

Write-Output 'VDM++ - demostracion y pruebas de contratos'
& (Join-Path $PSScriptRoot 'vdm/ejecutar-pruebas.ps1') -VdmjJar $VdmjJar -JavaExe $JavaExe

Write-Output 'NuSMV - propiedades temporales y alcanzabilidad'
& (Join-Path $PSScriptRoot 'nusmv/ejecutar-verificacion.ps1') -NuSMVExe $NuSMVExe
