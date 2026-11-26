# Programa VDM++ del middleware financiero

El programa simula la decisión de autorizar una solicitud antes del débito. Cada `idTransaccion` identifica una única operación en el middleware, incluso cuando hay varios bancos en el directorio.

## Ejecutar

Requisitos de la validación: PowerShell 7, Java y [VDMJ 4.7.0](https://repo.maven.apache.org/maven2/dk/au/ece/vdmj/vdmj/4.7.0/vdmj-4.7.0.jar). El ejecutor comprueba el SHA-256 del JAR. La ejecución registrada usó Java 27.

Desde esta carpeta, prueba el programa con el comando siguiente.

```powershell
.\ejecutar-pruebas.ps1 -VdmjJar 'C:\ruta\vdmj-4.7.0.jar'
```

Añade `-SoloDemo` para mostrar únicamente la traza de `TX001`. Si Java no está en el PATH, añade `-JavaExe 'C:\ruta\jdk\bin\java.exe'`.

## Orden de evaluación

Para cada solicitud, aplica la primera fila que corresponda. `MAX_EDAD = 5` se mide en unidades de reloj lógico.

| Condición | Respuesta | Efecto |
|---|---|---|
| El ID ya está registrado y los datos coinciden. | `DUPLICADA` | Conserva la autorización. |
| El ID ya está registrado y algún dato difiere. | `CONFLICTO` | Conserva la autorización. |
| El ID está sin registrar y el banco no figura en el directorio. | `SIN_DIRECTORIO` | Rechaza el intento sin consumir el ID. |
| El banco figura en el directorio y está en mantenimiento o fuera de servicio. | `BANCO_NO_DISPONIBLE` | Rechaza el intento sin consumir el ID. |
| El banco figura como operativo y la observación supera las cinco unidades. | `DESACTUALIZADO` | Rechaza el intento sin consumir el ID. |
| El ID está sin registrar y la observación operativa tiene hasta cinco unidades. | `VALIDA` | Registra el ID, la solicitud y la observación usada al autorizar. |

`procesar` define la respuesta en su postcondición y el efecto sobre el estado. `registrarId` es privado e incorpora la autorización al conjunto de IDs, el historial y la secuencia de autorizaciones en un paso atómico. El banco cambia su observación por `registrarBanco` o `actualizarBanco`, y `avanzarTiempo` incrementa el reloj del middleware.

## Demostración

La traza usa `TX001` en todos los pasos. En el paso 4 se acepta una observación con edad exactamente igual a 5 (`11 - 6`). En los pasos 5 y 6, la decisión se toma por el ID antes de consultar el directorio. El estado de la autorización original permanece en `AUTORIZADA` y el contador continúa en 1.

| Paso | Situación | Respuesta | Autorizaciones |
|---|---|---|---:|
| 1 | Banco ausente | `SIN_DIRECTORIO` | 0 |
| 2 | Banco en mantenimiento | `BANCO_NO_DISPONIBLE` | 0 |
| 3 | Banco operativo con observación de edad 6 | `DESACTUALIZADO` | 0 |
| 4 | Banco operativo con observación de edad 5 | `VALIDA` | 1 |
| 5 | Mismo ID y datos, observación vencida | `DUPLICADA` | 1 |
| 6 | Mismo ID con otro banco ausente | `CONFLICTO` | 1 |

## Evidencia

El ejecutor guarda en `evidencias/` la traza de seis decisiones, las pruebas de comportamiento, los rechazos esperados por contrato y la generación de obligaciones. Las obligaciones generadas quedan pendientes de demostración. La ejecución cubre decisiones secuenciales en el intérprete VDMJ.
