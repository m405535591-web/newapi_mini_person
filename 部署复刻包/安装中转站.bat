@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "RELAY_SCRIPT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $text=[IO.File]::ReadAllText($env:RELAY_SCRIPT,[Text.Encoding]::UTF8); $body=($text -split '(?m)^# POWERSHELL\r?$',2)[1]; if (!$body) { throw '脚本内容缺失' }; & ([ScriptBlock]::Create($body)) } catch { Write-Host ('操作失败：' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "RELAY_RESULT=%errorlevel%"
echo.
if not "%RELAY_RESULT%"=="0" echo 操作未完成，请查看上方提示。
if /i not "%~1"=="--no-pause" pause
exit /b %RELAY_RESULT%
# POWERSHELL
$ErrorActionPreference = 'Stop'
$root = Split-Path $env:RELAY_SCRIPT -Parent
Set-Location -LiteralPath $root
$template = Get-Content -LiteralPath (Join-Path $root '部署配置.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$db = Join-Path $root 'data\new-api.db'
$settings = Join-Path $root 'config\settings.json'
if ((Test-Path -LiteralPath $db) -or (Test-Path -LiteralPath $settings)) {
    throw '检测到已有部署，已停止安装，避免覆盖数据。请用现有启动脚本或换一个空目录。'
}
if (Get-NetTCPConnection -LocalPort $template.port -State Listen -ErrorAction SilentlyContinue) { throw '18327 端口已被占用。请先修改部署配置.json 的 port。' }
foreach ($name in @('bin','config','data','logs','cache','temp','downloads','backups')) {
    New-Item -ItemType Directory -Path (Join-Path $root $name) -Force | Out-Null
}
$binary = Join-Path $root 'bin\new-api.exe'
$download = Join-Path $root ('downloads\new-api-' + $template.version + '.exe')
$uri = 'https://github.com/QuantumNous/new-api/releases/download/' + $template.version + '/new-api-' + $template.version + '.exe'
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
try {
    $env:TEMP = Join-Path $root 'temp'
    $env:TMP = $env:TEMP
    if (!(Test-Path -LiteralPath $binary)) {
        Write-Host '下载官方 Windows x64 程序。支持把校验通过的程序提前放到 bin\new-api.exe 进行离线安装。'
        $arguments = @('--fail','--location','--retry','2','--connect-timeout','20','--max-time','600','--output',$download,$uri)
        if ($template.download_proxy) { $arguments = @('--proxy', $template.download_proxy) + $arguments }
        & curl.exe @arguments
        if ($LASTEXITCODE -ne 0) { throw '下载失败。请检查本机 7890 代理，或将 download_proxy 置空后在干净目录重试。已创建目录不含用户数据库。' }
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLower() -ne $template.sha256) { throw '官方程序 SHA256 不匹配，禁止执行。' }
        Move-Item -LiteralPath $download -Destination $binary
    }
    if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLower() -ne $template.sha256) { throw 'bin/new-api.exe 校验不通过，禁止启动。' }
    @{version=$template.version;sha256=$template.sha256;source=$uri} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'bin\version.json') -Encoding UTF8
    function New-RandomSecret {
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        return -join ($bytes | ForEach-Object { $_.ToString('x2') })
    }
    $password = 'Aa9!' + (New-RandomSecret).Substring(0,32)
    @{port=$template.port;session_secret=(New-RandomSecret);crypto_secret=(New-RandomSecret);upstream_proxy='';no_proxy=$template.no_proxy} | ConvertTo-Json | Set-Content -LiteralPath $settings -Encoding UTF8
    $utf8 = New-Object Text.UTF8Encoding($false)
    $startFile = Join-Path $root '启动中转站.bat'
    $start = [IO.File]::ReadAllText($startFile, [Text.Encoding]::UTF8)
    $start = [regex]::Replace($start, "USER_SESSION_ACTIVE_LIMIT\s*=\s*'[^']*'", "USER_SESSION_ACTIVE_LIMIT = '$($template.session_active_limit)'")
    $start = [regex]::Replace($start, "USER_SESSION_ISSUANCE_LIMIT\s*=\s*'[^']*'", "USER_SESSION_ISSUANCE_LIMIT = '$($template.session_issuance_limit)'")
    $start = $start.Replace('18327', [string]$template.port)
    [IO.File]::WriteAllText($startFile,$start,$utf8)
    $openFile = Join-Path $root '打开管理页面.bat'
    [IO.File]::WriteAllText($openFile,[IO.File]::ReadAllText($openFile,[Text.Encoding]::UTF8).Replace('18327',[string]$template.port),$utf8)
    $local = 'http://127.0.0.1:' + $template.port
    $public = $template.public_base_url
    if (!$public) {
        $lan = Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1
        if ($lan) { $public = 'http://' + $lan.IPv4Address[0].IPAddress + ':' + $template.port } else { $public = $local }
    }
    "Username: $($template.admin_username)`r`nPassword: $password`r`nURL: $public`r`n" | Set-Content -LiteralPath (Join-Path $root 'config\admin-credentials.txt') -Encoding UTF8
    # Keep the service console open while installation continues separately.
    $launcher = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ""' + $startFile + '" --no-pause"') -WorkingDirectory $root -WindowStyle Normal -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        if ($launcher.HasExited) { throw '启动窗口已关闭，请检查启动提示和日志。' }
        try {
            $status = Invoke-RestMethod -Uri ($local + '/api/status') -TimeoutSec 2
            if ($status.success) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (!$ready) { throw '服务启动超时，请检查启动窗口和日志。' }
    $web = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    function Invoke-LocalApi($path, $body, $headers) {
        $args = @{Uri=($local+$path);WebSession=$web;TimeoutSec=30;ErrorAction='Stop'}
        if ($headers) { $args.Headers = $headers }
        if ($null -ne $body) {
            $args.Method = 'POST'
            $args.ContentType = 'application/json; charset=utf-8'
            $args.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 15 -Compress))
        }
        $result = Invoke-RestMethod @args
        if (!$result.success) { throw ('接口调用失败：' + $path + ' ' + $result.message) }
        return $result
    }
    Invoke-LocalApi '/api/setup' @{username=$template.admin_username;password=$password;confirmPassword=$password;SelfUseModeEnabled=$true;DemoSiteEnabled=$false} $null | Out-Null
    $login = Invoke-LocalApi '/api/user/login' @{username=$template.admin_username;password=$password} $null
    $headers = @{Authorization=('Bearer ' + $login.data.access_token);'New-Api-User'=[string]$login.data.user.id}
    $options = @{
        RegisterEnabled='true';PasswordRegisterEnabled='true';EmailVerificationEnabled='false';PasswordResetEnabled='false'
        ServerAddress=$public
        'performance_setting.disk_cache_enabled'='false'
        'performance_setting.disk_cache_path'=(Join-Path $root 'cache')
        'performance_setting.disk_cache_max_size_mb'='256'
    }
    foreach ($key in $options.Keys) {
        $body = @{key=$key;value=$options[$key]} | ConvertTo-Json -Compress
        $result = Invoke-RestMethod -Uri ($local+'/api/option/') -Method Put -Headers $headers -WebSession $web -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 15
        if (!$result.success) { throw ('配置失败：' + $key) }
    }
    $scopes = @('channel:read','channel:operate','channel:write','channel:sensitive_write')
    $proof = Invoke-LocalApi '/api/verify' @{method='password';scope='access_token.generate';context=@{scopes=$scopes;expires_at=0};password=$password} $headers
    $proofHeaders = @{Authorization=$headers.Authorization;'New-Api-User'=$headers['New-Api-User'];'X-Security-Proof'=$proof.data.proof_token}
    $token = Invoke-LocalApi '/api/user/access_tokens' @{name='NEWAPI_ADMIN_TOKEN项目对接';scopes=$scopes;expires_at=0} $proofHeaders
    $credential = @{base_url=$public;import_api=($public+'/api/channel/');NEWAPI_ADMIN_TOKEN=$token.data.token;api_key=$token.data.token;headers=@{Authorization=('Bearer '+$token.data.token);'New-Api-User'=$headers['New-Api-User'];'Content-Type'='application/json'};scopes=$scopes;token_id=$token.data.item.id;expires_at=0}
    $credential | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'config\newapi-admin-token.json') -Encoding UTF8
    $credential | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'config\oauth-import-api.json') -Encoding UTF8
    Invoke-LocalApi '/api/channel/?p=0&page_size=1' $null $credential.headers | Out-Null
    Invoke-LocalApi '/api/user/auth/logout' @{} $headers | Out-Null
    Write-Host ('部署完成：' + $public)
    Write-Host '账号密码：config/admin-credentials.txt；管理 API Key：config/newapi-admin-token.json。'
    Write-Host '请保持服务 CMD 窗口打开，关闭该窗口将停止服务。'
    Write-Host '无开机自启。访问账号是否走代理，在每个渠道内单独配置。'
} catch {
    throw ('部署未完成：' + $_.Exception.Message + '；如已生成数据库，不要重复覆盖，交给 Codex 检查并续做。')
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
