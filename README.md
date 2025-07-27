AnalyzerSysPro
AnalyzerSysPro es una utilidad de línea de comandos creada en PowerShell, diseñada para realizar un análisis completo de sistemas operativos Windows. La herramienta recopila, procesa y presenta información clave sobre el rendimiento del sistema, la configuración de seguridad y la actividad reciente, todo desde un único script.

El objetivo principal de esta herramienta es ofrecer una "radiografía" detallada del estado de un sistema para facilitar el diagnóstico de problemas y la revisión de su configuración de seguridad.

Capacidades Principales
Análisis de Rendimiento: Mide el uso de CPU y memoria.

Gestión de Procesos: Lista y detalla los procesos en ejecución y sus hilos.

Actividad de Red: Monitorea conexiones de red y puertos abiertos.

Mecanismos de Persistencia: Revisa servicios y tareas programadas que se inician automáticamente.

Análisis Forense Básico: Calcula hashes SHA256 de los archivos de procesos para su verificación en bases de datos de malware (como VirusTotal).

Historial de Estabilidad: Registra el historial de apagados y reinicios del sistema.

Requisitos
Sistema Operativo: Windows 10, Windows 11 o Windows Server 2016 y superior.

PowerShell: Versión 5.1 o superior (instalado por defecto en los sistemas soportados).

Privilegios: Se requieren permisos de Administrador para su correcta ejecución.

Instrucciones de Uso
Existen dos versiones del script para diferentes escenarios.

Opción 1: Script Completo (Recomendado)
Esta es la versión robusta que ofrece todas las funcionalidades, incluyendo diferentes modos de ejecución y la capacidad de auto-elevar sus privilegios si no se ejecuta como administrador.

Guarda el código en un archivo llamado AnalyzerSysPro_v3.ps1.

Abre una consola de PowerShell.

Navega hasta la carpeta donde guardaste el archivo (ej. cd C:\Users\TuUsuario\Desktop).

Ejecuta uno de los siguientes comandos según lo que necesites:

Análisis Completo en Pantalla:

.\AnalyzerSysPro_v3.ps1

Análisis Resumido (solo lo esencial):

.\AnalyzerSysPro_v3.ps1 -Resumen

Guardar el Reporte Completo en un Archivo:

.\AnalyzerSysPro_v3.ps1 -Archivo "C:\Ruta\Deseada\Reporte.txt"

Monitor en Tiempo Real (incluye actividad de red):

.\AnalyzerSysPro_v3.ps1 -TiempoReal

(Para detener el monitoreo, presiona la tecla q).

Opción 2: Versión de Copiar y Pegar (Uso Rápido)
Esta es una versión simplificada, diseñada para ser copiada y pegada directamente en una terminal. No admite parámetros y requiere que la consola ya tenga privilegios elevados.

Importante: Abre una consola de PowerShell como Administrador.

Copia todo el contenido del script VerCopiarPegar.

Pega el código directamente en la ventana de PowerShell y presiona Enter. El script se ejecutará inmediatamente en el modo de análisis completo.
