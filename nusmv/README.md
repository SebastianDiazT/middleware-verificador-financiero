# Modelo de admisión en NuSMV

`middleware_detallado.smv` representa la decisión de admisión del middleware. Sigue un ID de transacción, un banco y una secuencia de intentos. `DATOS_A` y `DATOS_B` representan contenidos distintos para el mismo ID. Cualquiera puede ser el primero en autorizarse. La comparación de un reintento siempre usa el contenido que quedó autorizado.

## Ejecutar la verificación

Se necesita [NuSMV 2.7.1](https://nusmv.fbk.eu/downloads.html). Desde esta carpeta, con PowerShell 7:

```powershell
.\ejecutar-verificacion.ps1 -NuSMVExe 'C:\ruta\NuSMV.exe'
```

El script comprueba la relación de transición, valida todas las fórmulas declaradas, guarda la salida de NuSMV en `evidencias/verificacion.txt` y genera `evidencias/resumen.json` con cada nombre y resultado. También deja el SHA-256 del modelo y del ejecutable usado. Para ejecutar solo la comprobación directa con NuSMV:

```text
NuSMV -s -ctt middleware_detallado.smv
```

## Entradas y memoria

| Grupo | Variables | Significado |
| --- | --- | --- |
| Entradas | `enviar`, `datosEntrada`, `bancoEntrada`, `vigenciaEntrada` | El entorno puede elegir su valor en cada paso. El sistema acepta un envío cuando está en `ESPERA`. |
| Captura | `datosIntento`, `bancoConsultado`, `vigenciaConsultada` | T01 copia la entrada. Estos valores se mantienen durante la evaluación. Antes del primer envío, sus valores de arranque son `SIN_DATOS`, `AUSENTE` y `VENCIDA`. |
| Control | `fase`, `respuesta` | Inician en `ESPERA` y `SIN_RESPUESTA`. Una respuesta se hace visible en `FINALIZADA`. T13 la limpia al volver a la espera. |
| Memoria | `idRegistrado`, `datosRegistrados`, `autorizaciones`, `bancoAlAutorizar`, `vigenciaAlAutorizar` | Inician en falso, `SIN_DATOS`, cero y `SIN_EVIDENCIA` en ambos campos de evidencia. T12 es la única transición que modifica esta memoria. El valor 2 del contador representa dos o más autorizaciones. |

## Transiciones y acciones

Las guardas `t00_esperar` a `t13_rearmar` corresponden a las transiciones T00 a T13. Excepto donde se indica una asignación, las variables conservan su valor. Todas las asignaciones de una fila ocurren en el mismo paso.

| ID | Origen | Guarda | Destino y acción |
| --- | --- | --- | --- |
| T00 | ESPERA | `!enviar` | ESPERA. Conserva las variables. |
| T01 | ESPERA | `enviar` | VALIDAR_ID. Copia los datos de la solicitud, el estado observado del banco y la vigencia. |
| T02 | VALIDAR_ID | `idRegistrado` | COMPARAR_SOLICITUD. |
| T03 | VALIDAR_ID | `!idRegistrado` | CONSULTAR_DIRECTORIO. |
| T04 | COMPARAR_SOLICITUD | `datosIntento = datosRegistrados` | FINALIZADA. Responde DUPLICADA. |
| T05 | COMPARAR_SOLICITUD | `datosIntento != datosRegistrados` | FINALIZADA. Responde CONFLICTO. |
| T06 | CONSULTAR_DIRECTORIO | `bancoConsultado = AUSENTE` | FINALIZADA. Responde SIN_DIRECTORIO. |
| T07 | CONSULTAR_DIRECTORIO | `bancoConsultado != AUSENTE` | EVALUAR_ESTADO_BANCO. |
| T08 | EVALUAR_ESTADO_BANCO | MANTENIMIENTO o FUERA_SERVICIO | FINALIZADA. Responde BANCO_NO_DISPONIBLE. |
| T09 | EVALUAR_ESTADO_BANCO | `bancoConsultado = OPERATIVO` | VALIDAR_VIGENCIA. |
| T10 | VALIDAR_VIGENCIA | `vigenciaConsultada = VENCIDA` | FINALIZADA. Responde DESACTUALIZADO. |
| T11 | VALIDAR_VIGENCIA | `vigenciaConsultada = VIGENTE` | REGISTRAR_AUTORIZACION. |
| T12 | REGISTRAR_AUTORIZACION | La fase se alcanzó mediante T11 | FINALIZADA. Registra el ID, copia contenidos y evidencia, aumenta el contador hasta 2 y responde VALIDA. |
| T13 | FINALIZADA | Incondicional | ESPERA. Limpia la respuesta. Preserva la memoria de la autorización. |

El orden importa. Un ID registrado siempre va a comparación, incluso si la observación del banco está ausente. Para un ID todavía libre se comprueba primero la existencia de la observación, luego el estado operativo y finalmente la vigencia. Por ejemplo, si el banco está fuera de servicio y su observación está vencida, se responde `BANCO_NO_DISPONIBLE`.

## Resultados

NuSMV 2.7.1 comprobó **21 propiedades LTL y 10 CTL verdaderas**. La relación de transición es total y el modelo tiene **209 estados alcanzables**, de 362 880 combinaciones posibles de variables de estado. El diámetro que informa NuSMV es 12. No se impusieron fórmulas de seguridad ni condiciones de justicia como restricciones de la máquina.

| Propiedad | Fórmula o alcance |
| --- | --- |
| P01, unicidad | `G (autorizaciones <= 1)`. El dominio admite 2 para que el verificador pueda detectar una duplicación. |
| P02, evidencia | Toda respuesta `VALIDA` deja una sola autorización, el contenido registrado y evidencia operativa y vigente. |
| P03, decisión | `G (fase = VALIDAR_ID -> F (fase = FINALIZADA))`. Empieza a contar cuando se acepta el envío. |
| P04–P11, P13, P15–P17, P19–P21 | Comprueban el avance de las fases, la prioridad de guardas, las seis respuestas, la captura de entradas y la limpieza de la respuesta. |
| P12 | Fuera de T12, el ID, su contenido registrado, el contador y ambos campos de evidencia se conservan de un paso al siguiente. |
| P14, elegibilidad | La fase de registro exige un ID libre y una evidencia operativa y vigente. |
| P18 | La captura permanece estable durante la evaluación. |

A01–A06 demuestran que se puede obtener cada una de las seis respuestas. A07 confirma una secuencia con el mismo contenido: mantenimiento con cero autorizaciones, recuperación y autorización, y reintento duplicado con el total aún en uno. A08 comprueba que un reintento puede ser duplicado con el banco ausente. A09 comprueba un conflicto de contenido con el banco operativo y vigente. A10 alcanza un caso fuera de servicio con observación vencida y respuesta por indisponibilidad bancaria.

La verificación cubre la máquina finita previa al débito. La positividad del monto es una precondición de entrada de la abstracción. `VIGENTE` y `VENCIDA` resumen el cálculo de edad que realiza el programa VDM++; sus pasos internos se representan con una captura estable para reflejar la exclusión mutua de `procesar`. El modelo acepta un intento por vez y analiza decisiones, sin simular red, colas, contabilidad ni liquidación.

[Manual de NuSMV](https://nusmv.fbk.eu/userman/v27/nusmv.pdf)
