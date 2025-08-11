# ForensicTimeScanner (FTS) v1.3.1
# Autores: Antonio Camelo (lordMadruga)

# Função para exibir o banner
function Show-Banner {
    $banner = @"
  _____                        _        
|  ___|__  _ __ ___ _ __  ___(_) ___   
| |_ / _ \| '__/ _ \ '_ \/ __| |/ __|  
|  _| (_) | | |  __/ | | \__ \ | (__   
|_|__\___/|_|  \___|_| |_|___/_|\___|  
|_   _(_)_ __ ___   ___                
  | | | | '_ ` _ \ / _ \               
  | | | | | | | | |  __/               
 _|_| |_|_| |_| |_|\___|               
/ ___|  ___ __ _ _ __  _ __   ___ _ __ 
\___ \ / __/ _` | '_ \| '_ \ / _ \ '__|
 ___) | (_| (_| | | | | | | |  __/ |   
|____/ \___\__,_|_| |_|_| |_|\___|_|   

FTS v1.3.1
Desenvolvido por Antonio Camelo

"@
    Write-Host $banner -ForegroundColor Cyan
}

# Exibir o banner
Show-Banner

# Diretório de saída
$outputDir = "$([Environment]::GetFolderPath('Desktop'))\ForensicsReport\Analise_$(Get-Date -Format 'ddMMyy_HHmm')"
New-Item -Path $outputDir -ItemType Directory -Force

# Capturar o nome do host
$hostName = $env:COMPUTERNAME

# Função para buscar arquivos e pastas modificados ou criados
function Get-FileEvents {
    param (
        [datetime]$startTime
    )
    Get-ChildItem -Path "C:\" -Recurse -ErrorAction SilentlyContinue -ErrorVariable errors | ForEach-Object {
        $event = if ($_.CreationTime -ge $startTime) {
            "Criado"
        } elseif ($_.LastWriteTime -ge $startTime) {
            "Modificado"
        } else {
            $null
        }

        if ($event) {
            [PSCustomObject]@{
                Evento = $event
                Tipo = if ($_.PSIsContainer) { "Pasta" } else { "Arquivo" }
                DataHora = if ($event -eq "Criado") { $_.CreationTime.ToString("dd/MM/yyyy HH:mm:ss") } else { $_.LastWriteTime.ToString("dd/MM/yyyy HH:mm:ss") }
                Nome = $_.Name
                CaminhoCompleto = $_.FullName
                Hash = if (-not $_.PSIsContainer) {
                    try {
                        (Get-FileHash -Path $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                    } catch {
                        $null
                    }
                } else {
                    ""
                }
            }
        }
    }
    # Registrar erros em um arquivo
    $errors | Out-File -FilePath "$outputDir\Errors.txt" -Append
}

# Função para buscar modificações no registro
function Get-RegistryEvents {
    param (
        [datetime]$startTime
    )
    $registryPaths = @(
        "HKLM:\Software",
        "HKCU:\Software"
    )

    $registryEvents = @()

    foreach ($path in $registryPaths) {
        Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.LastWriteTime -ge $startTime) {
                $eventType = "Modificado"  # Assumindo modificação se LastWriteTime for recente

                $registryEvents += [PSCustomObject]@{
                    Evento = $eventType
                    Tipo = "Registro"
                    DataHora = $_.LastWriteTime.ToString("dd/MM/yyyy HH:mm:ss")
                    Nome = $_.PSChildName
                    CaminhoCompleto = $_.PSPath
                    Hash = ""
                }
            }
        }
    }
    return $registryEvents
}

# Função para calcular o hash SHA-256
function Get-FileHashSHA256 {
    param (
        [string]$filePath
    )
    Get-FileHash -Path $filePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash
}

# Interação com o usuário
$choice = Read-Host "Você quer analisar por (D)ias, (H)oras ou (M)inutos? Digite D, H ou M"
$timeSpan = switch ($choice) {
    'D' { [int](Read-Host "Quantos dias você quer analisar?") }
    'H' { [int](Read-Host "Quantas horas você quer analisar?") }
    'M' { [int](Read-Host "Quantos minutos você quer analisar?") }
    default {
        Write-Host "Opção inválida. Encerrando o script."
        exit
    }
}

# Determinar o tempo de início da análise
$startTime = switch ($choice) {
    'D' { (Get-Date).AddDays(-$timeSpan) }
    'H' { (Get-Date).AddHours(-$timeSpan) }
    'M' { (Get-Date).AddMinutes(-$timeSpan) }
}



# Medir o tempo de execução da análise
$executionTime = Measure-Command {
    Write-Host " "
    Write-Host "Buscando arquivos e pastas criados, modificados ou deletados no diretório: C:\ após: $($startTime.ToString('dd/MM/yyyy HH:mm:ss'))"
    Write-Host " "
    Write-Host "Data e hora atual: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan
    Write-Host " "
    Write-Host "Diretório de saída: $outputDir"
    Write-Host " "
    Write-Host "Aguarde, o processo pode levar alguns minutos..." -ForegroundColor Yellow
    Write-Host " "
   
    # Executar busca de eventos de arquivos
    $fileEvents = Get-FileEvents -startTime $startTime

    # Executar busca de eventos no registro
    $registryEvents = Get-RegistryEvents -startTime $startTime

    # Combinar eventos de arquivos e registro
    $allEvents = $fileEvents + $registryEvents
}

# Contagem de eventos
$totalCriados = ($allEvents | Where-Object { $_.Evento -eq "Criado" }).Count
$totalModificados = ($allEvents | Where-Object { $_.Evento -eq "Modificado" }).Count

# Gerar relatório CSV
$csvPath = "$outputDir\Events_$hostName.csv"
$allEvents | Export-Csv -Path $csvPath -NoTypeInformation

# Calcular hash do arquivo CSV
$csvHash = Get-FileHashSHA256 -filePath $csvPath
Set-Content -Path "$outputDir\Hash.txt" -Value "CSV Hash: $csvHash"

# Criar resumo para o JSON
$periodoAnalisado = switch ($choice) {
    'D' { "Últimos $timeSpan dias" }
    'H' { "Últimas $timeSpan horas" }
    'M' { "Últimos $timeSpan minutos" }
}
$resumo = @{
    "ForensicTimeScanner (FTS) v1.3.1" = @{
        "Total de itens encontrados" = @{
            "Criados" = $totalCriados
            "Modificados" = $totalModificados
        }
        "Data e hora da análise" = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
        "Período analisado" = $periodoAnalisado
        "Host Analisado" = $hostName
        "Desenvolvido por" = "Antonio Camelo"
    }
}

# Gerar relatório JSON
$jsonPath = "$outputDir\Events_$hostName.json"
$resumo | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath

# Adicionar eventos ao JSON
$allEvents | ConvertTo-Json -Depth 3 | Add-Content -Path $jsonPath

# Calcular hash do arquivo JSON
$jsonHash = Get-FileHashSHA256 -filePath $jsonPath
Add-Content -Path "$outputDir\Hash.txt" -Value "JSON Hash: $jsonHash"

# Calcular tempo de execução em hh:mm:ss
$totalSeconds = [int]$executionTime.TotalSeconds
$hours = [math]::Floor($totalSeconds / 3600)
$minutes = [math]::Floor(($totalSeconds % 3600) / 60)
$seconds = $totalSeconds % 60

# Exibir resumo
Write-Host "Análise concluída. Relatórios gerados em $outputDir" -ForegroundColor Cyan
Write-Host " "
Write-Host "Total de eventos encontrados: $($allEvents.Count)"
Write-Host " "
Write-Host ("Tempo total de execução: {0:D2}:{1:D2}:{2:D2}" -f [int]$hours, [int]$minutes, [int]$seconds) -ForegroundColor Yellow