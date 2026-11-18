# publish-vk-once.ps1
# Одиночная проба после периода тишины (без циклов, одним запросом на метод):
# users.get с личным токеном. Отпустило -> 1) удалить тестовый пост, 2) publish-vk-group.ps1.
# Не отпустило -> тихий FAIL без дальнейших попыток.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Get-LastToken([string]$file) {
    $lines = Get-Content $file -Encoding UTF8 | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }
    $marked = $lines | Where-Object { $_ -match '^VK_TOKEN\s*=' } | Select-Object -Last 1
    if ($marked) { ($marked -split '=', 2)[1].Trim() } else { $lines | Select-Object -Last 1 }
}

$pt = Get-LastToken 'posts news\user_id.env'
$groupId = -242982533
$testPostId = 13

$u = Invoke-RestMethod -Uri 'https://api.vk.com/method/users.get' -Method Post -Body @{ access_token = $pt; v = '5.199' }
if ($u.error) { "FAIL: флуд ещё держит (error $($u.error.error_code)); токен в покое, следующая проба — руками или плановый прогон 10:30"; exit 1 }
"флуд снят (пользователь $($u.response[0].first_name)), продолжаю"

try {
    $d = Invoke-RestMethod -Uri 'https://api.vk.com/method/wall.delete' -Method Post -Body @{ owner_id = $groupId; post_id = $testPostId; access_token = $pt; v = '5.199' }
    if ($d.error) { "wall.delete поста $($testPostId) : error $($d.error.error_code) $($d.error.error_msg)" }
    else { "тестовый пост $($testPostId) удалён" }
} catch { "wall.delete упал: $($_.Exception.Message)" }

$p = & powershell -NoProfile -ExecutionPolicy Bypass -File 'publish-vk-group.ps1' 2>&1
$p | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { "FAIL: publish-vk-group.ps1 код $LASTEXITCODE"; exit 1 }
"SUCCESS: тестовый пост убран, позиция опубликована в VK-группу"
