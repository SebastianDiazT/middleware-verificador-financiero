# Middleware Verificador de Operaciones Financieras

Especificación formal de un control previo al débito para pagos instantáneos. El middleware admite una sola autorización por ID de transacción y exige una observación vigente que indique que el banco de destino está operativo. El proyecto estudia el caso de los envíos interoperables desde Yape con datos simulados.

## Inicio rápido en Windows

1. Descarga el repositorio desde **Code → Download ZIP** y extrae los archivos, o clónalo con Git.
2. Abre PowerShell 7 en la carpeta que contiene `README.md` y `ejecutar-validacion.ps1`. La ejecución de referencia usa Java 27, [VDMJ 4.7.0](https://repo.maven.apache.org/maven2/dk/au/ece/vdmj/vdmj/4.7.0/vdmj-4.7.0.jar) y [NuSMV 2.7.1 para Windows](https://nusmv.fbk.eu/downloads.html). Extrae el archivo de NuSMV antes de usarlo.
3. Ejecuta el comando con las rutas de las herramientas en tu equipo.

```powershell
.\ejecutar-validacion.ps1 -VdmjJar 'C:\ruta\vdmj-4.7.0.jar' -NuSMVExe 'C:\ruta\NuSMV.exe'
```

Si Java no está en `PATH`, añade `-JavaExe 'C:\ruta\jdk\bin\java.exe'`. El siguiente comando ejecuta únicamente la traza de `TX001` con VDMJ.

```powershell
.\vdm\ejecutar-pruebas.ps1 -VdmjJar 'C:\ruta\vdmj-4.7.0.jar' -SoloDemo
```

Los scripts guardan cada ejecución en `vdm/evidencias/` y `nusmv/evidencias/`. Las salidas de referencia están en [`resultados/`](resultados/). Se reemplazaron las rutas absolutas del equipo en los registros VDMJ archivados por rutas relativas o nombres de archivo.

## Programa y diagramas

| Dónde empezar | Contenido |
| --- | --- |
| [Diagramas en PDF](diagramas/diagramas_middleware_financiero.pdf) | Ocho estados, 14 transiciones con sus condiciones y asignaciones, variables iniciales, traza de `TX001` y diagrama de clases. |
| [Diagrama de estados editable](diagramas/estados_admision.mmd) · [Diagrama de clases editable](diagramas/clases_middleware.mmd) | Fuentes Mermaid. Las etiquetas T00–T13 del diagrama de estados corresponden a las de la tabla y a los predicados `t00`–`t13` en NuSMV. |
| [Programa VDM++ y pruebas](vdm/README.md) | Clases `MiddlewareVerificador` y `Banco`, contratos, pruebas y demostración ejecutable. |
| [Modelo de estados y verificación NuSMV](nusmv/README.md) | Autómata, propiedades temporales, consultas de alcanzabilidad y resultados reproducibles. |

El punto de entrada de la especificación es la operación `procesar` en [`MiddlewareVerificador.vdmpp`](vdm/modelo/MiddlewareVerificador.vdmpp). La clase [`Banco.vdmpp`](vdm/modelo/Banco.vdmpp) conserva el estado y el instante de la observación. Las fórmulas temporales están en [`middleware_detallado.smv`](nusmv/middleware_detallado.smv).

## Cómo se toma la decisión

El programa recibe un valor `Solicitud` con monto positivo. Aplica las reglas de arriba abajo y devuelve la primera respuesta correspondiente.

| Qué encuentra el middleware | Respuesta | Efecto sobre el historial de autorizaciones |
| --- | --- | --- |
| ID registrado con los mismos datos. | `DUPLICADA` | Conserva la autorización original. |
| ID registrado con datos diferentes. | `CONFLICTO` | Conserva la solicitud y la autorización originales. |
| ID nuevo y banco ausente del directorio. | `SIN_DIRECTORIO` | Mantiene el ID disponible para reintentar. |
| ID nuevo y banco en mantenimiento o fuera de servicio. | `BANCO_NO_DISPONIBLE` | Mantiene el ID disponible para reintentar. |
| ID nuevo y observación operativa vencida. | `DESACTUALIZADO` | Mantiene el ID disponible para reintentar. |
| ID nuevo y observación operativa vigente. | `VALIDA` | Registra la solicitud, el ID y la evidencia en un paso atómico. |

La observación tiene una vigencia de hasta **cinco unidades de reloj lógico**, incluyendo el límite. Por ejemplo, en la demostración una observación de edad 6 se rechaza y una de edad 5 se acepta. Al repetirse la solicitud autorizada, la respuesta `DUPLICADA` tiene prioridad incluso si para entonces la observación está vencida.

El diagrama separa la fase de un intento de la memoria por ID. El intento repetido termina en `FINALIZADA` con respuesta `DUPLICADA`. La autorización original del ID permanece en `AUTORIZADA` en VDM++. En NuSMV se conserva `idRegistrado`, el contador y la evidencia.

## Resultados y alcance

- **VDM++** obtuvo 29 escenarios conformes y ocho rechazos esperados por contrato. La demostración de las seis respuestas termina con una autorización para `TX001`. Se generaron 88 obligaciones de prueba, pendientes de demostración. [Resumen](resultados/vdm/resumen-validacion.json) · [Traza](resultados/vdm/demostracion-vdmj.txt).
- **NuSMV** comprobó 21 propiedades LTL y 10 consultas CTL en un autómata con 209 estados alcanzables. La verificación cubre la unicidad de la autorización por ID, la exigencia de evidencia operativa y vigente y la llegada a una respuesta. [Resumen](resultados/nusmv/resumen.json) · [Salida de verificación](resultados/nusmv/verificacion.txt).

VDM++ admite varios bancos y varios IDs. NuSMV sigue un solo ID, un banco y dos contenidos posibles de solicitud, con envíos secuenciales. Al aceptar un nuevo intento, captura la entrada para representar una observación estable durante esa decisión. La verificación se refiere a esta abstracción de admisión. El débito, la liquidación bancaria y la coordinación entre réplicas pertenecen a la implementación financiera posterior.

Referencias de las herramientas: [manual de NuSMV](https://nusmv.fbk.eu/userman/v27/nusmv.pdf) y [manual de VDM-10 en Overture](https://www.overturetool.org/documentation/manuals.html).
