# PowerShell Script para Sincronização de Logs Windows -> Linux com Interface Amigável e Segurança

# Configurações iniciais
$PscpPathDefault = "C:\Program Files\PuTTY\pscp.exe"
$LogFileDefault = "C:\Scripts\log_envio_logs.txt"

function Show-Menu {
    Clear-Host
    Write-Host "=== Sincronização de Logs Windows -> Linux ===" -ForegroundColor Cyan
    Write-Host "1 - Configurar caminhos e credenciais"
    Write-Host "2 - Iniciar sincronização de logs"
    Write-Host "3 - Visualizar log da última execução"
    Write-Host "0 - Sair"
}

function LogWrite {
    param([string]$message, [string]$logFile)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append
}

function Verify-PSCP {
    param([string]$pscpPath)
    if (-Not (Test-Path $pscpPath)) {
        Write-Host "pscp.exe não encontrado. Deseja baixar e instalar automaticamente? (S/N)" -NoNewline
        $resp = Read-Host
        if ($resp.ToUpper() -eq "S") {
            $url = "https://the.earth.li/~sgtatham/putty/latest/w64/pscp.exe"
            $tempPath = "$env:TEMP\pscp.exe"
            try {
                Write-Host "Baixando pscp.exe..."
                Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
                $puttyDir = Split-Path $pscpPath
                if (-Not (Test-Path $puttyDir)) {
                    New-Item -ItemType Directory -Path $puttyDir -Force | Out-Null
                }
                Move-Item -Path $tempPath -Destination $pscpPath -Force
                Write-Host "pscp.exe instalado em $pscpPath"
                return $true
            }
            catch {
                Write-Host "Erro ao baixar/installar pscp.exe: $_" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "pscp.exe é necessário para continuar." -ForegroundColor Red
            return $false
        }
    } else {
        return $true
    }
}

function Test-SSHConnection {
    param([string]$user, [string]$host)
    $check = Test-Connection -ComputerName $host -Count 1 -Quiet
    if (-not $check) {
        Write-Host "Host $host inacessível. Verifique rede e DNS." -ForegroundColor Red
        return $false
    }
    try {
        ssh -o BatchMode=yes "$user@$host" "echo ok" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Falha na autenticação SSH. Verifique chave e permissões." -ForegroundColor Red
            return $false
        }
        return $true
    }
    catch {
        Write-Host "Erro ao testar conexão SSH: $_" -ForegroundColor Red
        return $false
    }
}

function Sync-Logs {
    param (
        [string]$logSource,
        [string]$linuxUser,
        [string]$linuxHost,
        [string]$linuxPath,
        [string]$pscpPath,
        [string]$logFile
    )

    $maxRetries = 3
    $logFiles = Get-ChildItem -Path $logSource -Filter *.log -Recurse
    if ($logFiles.Count -eq 0) {
        Write-Host "Nenhum arquivo de log encontrado no diretório $logSource" -ForegroundColor Yellow
        return
    }

    foreach ($file in $logFiles) {
        $sourceFile = $file.FullName
        $retries = 0
        $success = $false
        $fileHash = (Get-FileHash -Path $sourceFile -Algorithm SHA256).Hash
        $remoteFile = "$linuxUser@$linuxHost:`"$linuxPath\$($file.Name)`""

        Write-Host "Enviando $sourceFile (SHA256: $fileHash)..."
        LogWrite "Iniciando envio do arquivo $sourceFile (SHA256: $fileHash)" $logFile

        while (-not $success -and $retries -lt $maxRetries) {
            $cmd = "& `"$pscpPath`" -batch `"$sourceFile`" $remoteFile"
            Invoke-Expression $cmd

            if ($LASTEXITCODE -eq 0) {
                # Verificação de hash remoto (requer ssh e comando sha256sum)
                $remoteHash = ssh "$linuxUser@$linuxHost" "sha256sum `"$linuxPath/$($file.Name)`" | cut -d ' ' -f1" 2>$null
                if ($remoteHash -eq $fileHash) {
                    Write-Host "Arquivo $($file.Name) enviado e verificado com sucesso."
                    LogWrite "Arquivo $($file.Name) enviado e verificado com sucesso." $logFile
                    $success = $true
                } else {
                    Write-Host "Falha na verificação do hash remoto. Tentando novamente..." -ForegroundColor Red
                    LogWrite "Falha na verificação do hash remoto para $($file.Name)." $logFile
                    $retries++
                    Start-Sleep -Seconds 5
                }
            } else {
                Write-Host "Erro no envio do arquivo. Tentativa $($retries+1) de $maxRetries." -ForegroundColor Red
                LogWrite "Erro no envio do arquivo $($file.Name). Tentativa $($retries+1) de $maxRetries." $logFile
                $retries++
                Start-Sleep -Seconds 5
            }
        }
        if (-not $success) {
            Write-Host "Falha definitiva ao enviar o arquivo $($file.Name)." -ForegroundColor Red
            LogWrite "Falha definitiva ao enviar o arquivo $($file.Name)." $logFile
        }
    }
    Write-Host "Sincronização finalizada." -ForegroundColor Green
    LogWrite "Sincronização finalizada." $logFile
}

# Valores padrão configuráveis
$logSource = Read-Host "Informe o caminho da pasta de logs no Windows (exemplo: C:\Logs)"
$linuxUser = Read-Host "Informe o usuário Linux para conexão SSH"
$linuxHost = Read-Host "Informe o hostname ou IP do servidor Linux"
$linuxPath = Read-Host "Informe o caminho da pasta destino no Linux (exemplo: /var/logs_centralizados/windows)"
$pscpPath = $PscpPathDefault
$logFile = $LogFileDefault

# Loop da interface
do {
    Show-Menu
    $option = Read-Host "Escolha uma opção"

    switch ($option) {
        "1" {
            Write-Host "Configuração atual:" -ForegroundColor Cyan
            Write-Host "Pasta logs Windows: $logSource"
            Write-Host "Usuário Linux: $linuxUser"
            Write-Host "Host Linux: $linuxHost"
            Write-Host "Pasta destino Linux: $linuxPath"
            Write-Host "Caminho pscp.exe: $pscpPath"
            Write-Host "Arquivo de log: $logFile"
            Write-Host "Deseja alterar algum desses valores? (S/N)" -NoNewline
            $resp = Read-Host
            if ($resp.ToUpper() -eq "S") {
                $logSource = Read-Host "Informe o caminho da pasta de logs no Windows"
                $linuxUser = Read-Host "Informe o usuário Linux"
                $linuxHost = Read-Host "Informe o hostname/IP Linux"
                $linuxPath = Read-Host "Informe a pasta destino no Linux"
                $pscpPath = Read-Host "Informe o caminho do pscp.exe (deixe vazio para padrão: $PscpPathDefault)"
                if ([string]::IsNullOrEmpty($pscpPath)) { $pscpPath = $PscpPathDefault }
                $logFile = Read-Host "Informe o caminho do arquivo de log"
                if ([string]::IsNullOrEmpty($logFile)) { $logFile = $LogFileDefault }
            }
            Write-Host "Configurações atualizadas."
            Pause
        }
        "2" {
            if (-not (Verify-PSCP -pscpPath $pscpPath)) {
                Write-Host "pscp.exe não disponível. Execute a opção 1 para configurar." -ForegroundColor Red
                Pause
                continue
            }
            if (-not (Test-SSHConnection -user $linuxUser -host $linuxHost)) {
                Write-Host "Conexão SSH falhou. Verifique as configurações." -ForegroundColor Red
                Pause
                continue
            }
            Sync-Logs -logSource $logSource -linuxUser $linuxUser -linuxHost $linuxHost -linuxPath $linuxPath -pscpPath $pscpPath -logFile $logFile
            Pause
        }
        "3" {
            if (Test-Path $logFile) {
                Get-Content $logFile -Tail 20 | Out-Host
            } else {
                Write-Host "Arquivo de log não encontrado."
            }
            Pause
        }
        "0" {
            Write-Host "Saindo..." -ForegroundColor Green
        }
        default {
            Write-Host "Opção inválida. Tente novamente." -ForegroundColor Yellow
            Pause
        }
    }
} while ($option -ne "0")
