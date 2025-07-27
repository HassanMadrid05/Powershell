# ==============================================================================
# DEFINICION DE FUNCIONES DE ANALISIS
# ==============================================================================

# --- FUNCIONES GETTER (Para obtener datos crudos) ---
function Get-ThirdPartyServices {
    return Get-CimInstance -ClassName Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -notlike "*C:\Windows*" }
}

function Get-ActiveScheduledTasks {
    return Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' -or $_.State -eq 'Running' }
}

# --- FUNCIONES SHOW (Para formatear y mostrar datos) ---
function Show-SystemInfo {
    param($compInfo)
    Write-Host "`n--- 1. Informacion General del Sistema ---" -ForegroundColor Green
    $procInfo = Get-CimInstance Win32_Processor
    $numSockets = ($procInfo | Measure-Object).Count
    $numCores = ($procInfo | Measure-Object -Property NumberOfCores -Sum).Sum
    $numLogicalProcessors = ($procInfo | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $compInfo | Select-Object CsDNSHostName, CsManufacturer, CsModel, @{N='CPUs (Sockets)';E={$numSockets}}, @{N='Nucleos Fisicos';E={$numCores}}, @{N='Nucleos Logicos (Hilos)';E={$numLogicalProcessors}}, CsTotalPhysicalMemory, OsName, OsVersion, OsLastBootUpTime | Format-List
}

function Show-SystemShutdownHistory {
    Write-Host "`n--- 2. Historial de Apagados y Reinicios (Ultimos 5 Dias) ---" -ForegroundColor Green
    try {
        $eventFilter = @{
            LogName   = 'System'
            Id        = 1074, 6006, 6005, 41
            StartTime = (Get-Date).AddDays(-5)
        }
        # 1074: Apagado/Reinicio iniciado por usuario/proceso.
        # 6006: Apagado limpio del sistema.
        # 6005: Encendido del sistema.
        # 41:   Reinicio inesperado (crash).
        $events = Get-WinEvent -FilterHashtable $eventFilter -ErrorAction Stop

        if ($events) {
            $eventData = foreach ($event in $events) {
                $description = switch ($event.Id) {
                    1074 { 
                        $processName = $event.Properties[0].Value
                        $reason = $event.Properties[4].Value
                        "Iniciado por Proceso/Usuario: '$processName' - Razon: $reason"
                    }
                    6006 { "Apagado limpio del sistema" }
                    6005 { "Encendido del sistema" }
                    41   { "CRITICO: El sistema se reinicio sin un apagado limpio (Crash / Corte de energia)" }
                    default { ($event.Message -split '(?:\r?\n)')[0] }
                }
                [PSCustomObject]@{
                    Fecha       = $event.TimeCreated
                    ID          = $event.Id
                    Nivel       = $event.LevelDisplayName
                    'Descripcion' = $description.Trim()
                }
            }
            $eventData | Sort-Object Fecha -Descending | Format-Table -AutoSize -Wrap
        } else {
            Write-Host "     No se encontraron eventos de apagado o reinicio en los ultimos 5 dias." -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "No se pudo obtener el historial de apagados desde el Visor de Eventos. Error: $($_.Exception.Message)"
    }
}


function Show-CpuPerCoreUsage {
    Write-Host "`n--- 3. Uso de CPU por Nucleo Logico ---" -ForegroundColor Green
    $cpuCores = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor | Where-Object {$_.Name -ne '_Total'}
    if ($cpuCores) { $cpuCores | Select-Object @{N="Nucleo Logico";E={$_.Name}}, @{N="Uso CPU (%)";E={$_.PercentProcessorTime}} | Sort-Object "Nucleo Logico" | Format-Table -AutoSize }
}

function Show-TopProcesses {
    param($sortedProcesses)
    Write-Host "`n--- 4. Procesos Principales (Top 20) ---" -ForegroundColor Green
    ($sortedProcesses | Select-Object -First 20) | Select-Object ProcessId, Name, @{N="CPU (s)";E={if ($_.CPU -ne $null) {($_.CPU / 10000000).ToString("N2")} else {"N/A"}}}, @{N="Memoria (MB)";E={($_.WS / 1MB).ToString("N2")}}, ThreadCount, CommandLine | Format-Table -AutoSize -Wrap
}

function Show-ThreadAnalysis {
    param($topProcesses)
    Write-Host "`n--- 5. Resumen de Hilos por Proceso (Top 10) ---" -ForegroundColor Green
    $threadStateMap = @{ 0='Inicializado'; 1='Listo'; 2='En Ejecucion'; 3='En Espera'; 4='Terminado'; 5='Bloqueado'; 6='Transicion'; 7='Desconocido' }
    foreach ($process in $topProcesses) {
        Write-Host "`n  >> Proceso: $($process.Name) (PID: $($process.ProcessId), Hilos Totales: $($process.ThreadCount))" -ForegroundColor Cyan
        try {
            $threads = Get-CimInstance -ClassName Win32_Thread -Filter "ProcessHandle = $($process.ProcessId)" -ErrorAction Stop
            if ($threads) { 
                $threads | Group-Object -Property ThreadState | 
                    Select-Object @{N="Estado del Hilo"; E={$threadStateMap[[int]$_.Name]}}, Count | 
                    Format-Table -AutoSize
            } else { Write-Host "    No se encontraron hilos." -ForegroundColor DarkGray }
        } catch { Write-Host "    Error al obtener hilos: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Show-ProcessHierarchy {
    param($allProcesses, $topProcesses)
    Write-Host "`n--- 6. Jerarquia de Subprocesos (Hijos) (Top 10) ---" -ForegroundColor Magenta
    foreach ($parentProcess in $topProcesses) {
        Write-Host "`n  >> Proceso Padre: $($parentProcess.Name) (PID: $($parentProcess.ProcessId))" -ForegroundColor Cyan
        $childProcesses = $allProcesses | Where-Object { $_.ParentProcessId -eq $parentProcess.ProcessId }
        if ($childProcesses) {
            Write-Host "    Se encontraron los siguientes procesos hijos:"
            $childProcesses | Select-Object ProcessId, Name, @{N="CPU (s)";E={if ($_.CPU -ne $null) {($_.CPU / 10000000).ToString("N2")} else {"N/A"}}}, @{N="Memoria (MB)";E={($_.WS / 1MB).ToString("N2")}}, CommandLine | Format-Table -AutoSize -Wrap
        } else { Write-Host "    No se encontraron subprocesos (hijos)." -ForegroundColor DarkGray }
    }
}

function Show-NetworkInfo {
    Write-Host "`n--- 7. Analisis de Red ---" -ForegroundColor Green
    try {
        Write-Host "`n  >> Conexiones TCP Establecidas" -ForegroundColor Cyan
        $tcpConnections = Get-NetTCPConnection -State Established -ErrorAction Stop
        if ($tcpConnections) { $tcpConnections | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,@{N="Proceso";E={(Get-Process -Id $_.OwningProcess -EA 0).ProcessName}} | Format-Table -AutoSize -Wrap }
        else { Write-Host "     No hay conexiones TCP establecidas." -ForegroundColor DarkGray }
        
        Write-Host "`n  >> Puertos en Escucha (Listeners)" -ForegroundColor Cyan
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop
        if ($listeners) { $listeners | Select-Object LocalAddress,LocalPort,@{N="Proceso";E={(Get-Process -Id $_.OwningProcess -EA 0).ProcessName}} | Sort-Object LocalPort | Format-Table -AutoSize -Wrap }
        else { Write-Host "     No hay puertos TCP en escucha." -ForegroundColor DarkGray }
    } catch { Write-Warning "No se pudo obtener la informacion de red." }
}

function Show-PersistenceInfo {
    param($services, $tasks)
    Write-Host "`n--- 8. Analisis de Persistencia ---" -ForegroundColor Green
    try {
        Write-Host "`n  >> Servicios de Terceros con Inicio Automatico" -ForegroundColor Cyan
        if ($services) { $services | Select-Object Name, DisplayName, State, PathName | Format-Table -AutoSize -Wrap }
        else { Write-Host "     No se encontraron servicios de terceros con inicio automatico." -ForegroundColor DarkGray }

        Write-Host "`n  >> Tareas Programadas Activas" -ForegroundColor Cyan
        if ($tasks) {
            foreach ($task in $tasks) {
                $action = if ($task.Actions) { $task.Actions.Execute } else { "N/A" }
                $actionArgs = if ($task.Actions) { $task.Actions.Arguments } else { "" }
                $fullAction = "$action $actionArgs".Trim()
                Write-Host "`n    - Tarea: " -NoNewline -ForegroundColor White; Write-Host $task.TaskName -ForegroundColor Yellow
                Write-Host "      Ruta:   $($task.TaskPath)"; Write-Host "      Estado: $($task.State)"; Write-Host "      Autor:  $($task.Principal.UserId)"; Write-Host "      Accion: $fullAction"
                Write-Host "    --------------------------------------------------" -ForegroundColor DarkGray
            }
        } else { Write-Host "`n     No se encontraron tareas programadas activas." -ForegroundColor DarkGray }
    } catch { Write-Warning "No se pudo obtener la informacion de persistencia." }
}

function Show-ForensicSummary {
    param($topProcesses, $compInfo, [switch]$CalcularHash)
    
    $procPerf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process
    $numLogicalProcessors = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $cpuPerfHashTable = $procPerf | Where-Object { $_.Name -ne "_Total" } | Group-Object -Property IDProcess -AsHashTable -AsString
    
    $reportData = [System.Collections.Generic.List[psobject]]::new()

    foreach ($process in $topProcesses) {
        $currentCpuUsage = 0
        if ($cpuPerfHashTable.ContainsKey($process.ProcessId.ToString())) { 
            $currentCpuUsage = ($cpuPerfHashTable[$process.ProcessId.ToString()].PercentProcessorTime / $numLogicalProcessors) 
        }
        
        $psObject = [PSCustomObject]@{ 
            Nombre = $process.Name; 
            PID = $process.ProcessId; 
            'Uso CPU Actual (%)' = $currentCpuUsage.ToString("N2"); 
            'Uso Memoria (%)' = (($process.WS / $compInfo.CsTotalPhysicalMemory) * 100).ToString("N2"); 
            'Ruta del Ejecutable' = $process.ExecutablePath
        }

        if ($CalcularHash) {
            $fileHash = if ($process.ExecutablePath -and (Test-Path $process.ExecutablePath -PathType Leaf)) {
                try { (Get-FileHash -Path $process.ExecutablePath -Algorithm SHA256 -ErrorAction Stop).Hash } catch { "Acceso Denegado" }
            } else { "N/A" }
            $psObject | Add-Member -MemberType NoteProperty -Name 'Hash SHA256' -Value $fileHash
        }
        
        $reportData.Add($psObject)
    }
    
    return $reportData
}

function Show-InterpretiveAnalysis {
    param($reportData, $allProcesses, $compInfo, $services, $tasks)
    Write-Host "`n--- 10. Analisis Interpretativo (Estilo Reporte) ---" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray
    $procInfo = Get-CimInstance Win32_Processor
    $numSockets = ($procInfo | Measure-Object).Count
    $numCores = ($procInfo | Measure-Object -Property NumberOfCores -Sum).Sum
    $numLogicalProcessors = ($procInfo | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    
    $totalPerf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor | Where-Object { $_.Name -eq '_Total' }
    $topProcessOverall = $reportData | Sort-Object 'Uso CPU Actual (%)' -Descending | Select-Object -First 1

    Write-Host "`nDe acuerdo con la revision del equipo '$($compInfo.CsDNSHostName)', se comenta lo siguiente:`n" -ForegroundColor White
    Write-Host " - El sistema cuenta con $($numSockets) CPU(s) fisica(s) con un total de $($numCores) nucleos y $($numLogicalProcessors) hilos logicos."
    Write-Host " - El uso de CPU general se desglosa en: $($totalPerf.PercentUserTime)% para actividad de usuario y $($totalPerf.PercentPrivilegedTime)% para actividad del sistema."
    Write-Host " - En el momento de la captura, el procesador se encontraba desocupado en un $($totalPerf.PercentIdleTime)% de su tiempo."

    if ($topProcessOverall -and $topProcessOverall.PID -eq 0) {
        Write-Host " - El 'proceso' con mayor actividad es 'System Idle Process', lo que indica que la CPU esta mayormente libre." -ForegroundColor Green
        $topRealProcess = $reportData | Where-Object { $_.PID -ne 0 } | Sort-Object 'Uso CPU Actual (%)' -Descending | Select-Object -First 1
        if ($topRealProcess) {
            $topRealProcessDetails = $allProcesses | Where-Object { $_.ProcessId -eq $topRealProcess.PID }
            $cpuPerCoreEquivalent = [double]$topRealProcess.'Uso CPU Actual (%)' * $numLogicalProcessors
            Write-Host " - El programa real mas activo es '$($topRealProcess.Nombre)' (PID: $($topRealProcess.PID)), consumiendo $(($topRealProcessDetails.WS / 1MB).ToString('N2')) MB de RAM y un $($cpuPerCoreEquivalent.ToString('N2'))% de un nucleo."
        }
    }
    elseif ($topProcessOverall) {
        $topProcessDetails = $allProcesses | Where-Object { $_.ProcessId -eq $topProcessOverall.PID }
        $cpuPerCoreEquivalent = [double]$topProcessOverall.'Uso CPU Actual (%)' * $numLogicalProcessors
        Write-Host " - El principal proceso activo es '$($topProcessOverall.Nombre)' (PID: $($topProcessOverall.PID)), consumiendo $(($topProcessDetails.WS / 1MB).ToString('N2')) MB de RAM y un $($cpuPerCoreEquivalent.ToString('N2'))% de un nucleo." -ForegroundColor Yellow
    }
    
    if ($null -ne $services -or $null -ne $tasks) {
        Write-Host "`nResumen de Persistencia:" -ForegroundColor Cyan
        $serviceCount = if($null -ne $services) { $services.Count } else { 0 }
        Write-Host " - Se encontraron $serviceCount servicios de terceros con inicio automatico."
        if ($null -ne $tasks) {
            $taskCount = $tasks.Count
            $systemPrincipals = @('S-1-5-18', 'SYSTEM', 'AUTORIDAD NT\SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'Servicio Local', 'Servicio de red')
            $systemTasksCount = ($tasks | Where-Object { $systemPrincipals -contains $_.Principal.UserId }).Count
            $userTasksCount = $taskCount - $systemTasksCount
            Write-Host " - Se encontraron $taskCount tareas programadas activas, de las cuales:"
            Write-Host "   - Tareas de Sistema: $systemTasksCount"
            Write-Host "   - Tareas de Usuario: $userTasksCount"
        }
    }
    Write-Host "`n`nNOTA IMPORTANTE: El % de CPU de un proceso puede superar el 100% si utiliza multiples nucleos." -ForegroundColor Gray
}

# ==============================================================================
# INICIO DEL SCRIPT DE ANALISIS
# ==============================================================================

# --- MODO SNAPSHOT (COMPLETO) ---
try {
    Clear-Host
     $banner = @"
                         _                           _____
    /\                  | |                         / ____|
   /  \    _ __    __ _ | | _   _  ____  ___  _ __ | (___   _   _  ___
  / /\ \  | '_ \  / _` || || | | ||_  / / _ \| '__| \___ \ | | | |/ __|
 / ____ \ | | | || (_| || || |_| | / / |  __/| |    ____) || |_| |\__ \
/_/    \_\|_| |_| \__,_||_| \__, |/___| \___||_|   |_____/  \__, ||___/
                             __/ |                           __/ |
                            |___/                           |___/

"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "                       by Hassan MAdrid (https://github.com/HassanMadrid05/Powershell)" -ForegroundColor White
    Write-Host

    Write-Host "Iniciando recopilacion de datos..." -ForegroundColor Yellow
    Write-Host "Fecha y Hora de Ejecucion: $(Get-Date)" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray

    $compInfo = Get-ComputerInfo | Select-Object CsDNSHostName,CsManufacturer,CsModel,CsTotalPhysicalMemory,OsName,OsVersion,OsLastBootUpTime
    $processes = Get-CimInstance -Class Win32_Process | Select-Object ProcessId,Name,ExecutablePath,CommandLine,ParentProcessId,@{N="CreationTime";E={$_.ConvertToDateTime($_.CreationDate)}},@{N="WS";E={$_.WorkingSetSize}},@{N="CPU";E={$_.UserModeTime + $_.KernelModeTime}},ThreadCount
    $sortedProcesses = $processes | Sort-Object -Property CPU, WS -Descending
    $top10ProcessesForAnalysis = $sortedProcesses | Select-Object -First 10
    
    $thirdPartyServices = $null
    $activeTasks = $null

    Show-SystemInfo -compInfo $compInfo
    
    Show-SystemShutdownHistory
    Show-CpuPerCoreUsage
    Show-TopProcesses -sortedProcesses $sortedProcesses
    Show-ThreadAnalysis -topProcesses $top10ProcessesForAnalysis
    Show-ProcessHierarchy -allProcesses $processes -topProcesses $top10ProcessesForAnalysis
    Show-NetworkInfo
    
    $thirdPartyServices = Get-ThirdPartyServices
    $activeTasks = Get-ActiveScheduledTasks
    Show-PersistenceInfo -services $thirdPartyServices -tasks $activeTasks
    
    Write-Host "`n--- 9. Resumen Ejecutivo y Analisis Forense ---" -ForegroundColor Yellow
    $forensicData = Show-ForensicSummary -topProcesses $top10ProcessesForAnalysis -compInfo $compInfo -CalcularHash
    
    $tablaFormateada = $forensicData | Format-Table -AutoSize -Wrap -Property Nombre, PID, 'Uso CPU Actual (%)', 'Uso Memoria (%)', 'Ruta del Ejecutable', 'Hash SHA256' | Out-String
    Write-Host $tablaFormateada

    Show-InterpretiveAnalysis -reportData $forensicData -allProcesses $processes -compInfo $compInfo -services $thirdPartyServices -tasks $activeTasks

    Write-Host "`n--- Analisis finalizado ---" -ForegroundColor Green
}
catch {
    Write-Error "Ocurrio un error inesperado durante la ejecucion del analisis."
    Write-Error $_.Exception.Message
}

