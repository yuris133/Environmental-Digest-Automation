# publish-vk-when-unblocked.ps1
# Ждёт, пока VK снимет flood control с личного токена (posts news\user_id.env):
# каждые 10 минут дешёвый users.get, до 24 попыток (~4 часа).
# Как только отпустило: 1) удаляет тестовый пост на стене сообщества (если жив),
# 2) публикует сегодняшнюю позицию через publish-vk-group.ps1 (текст+фото).
# Выход 0 = оба шага сделаны; 1 = флуд не отпустил за окно попыток.

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

$unblocked = $false
foreach ($i in 1..24) {
    "проверка $i/24 $(Get-Date -Format 'HH:mm:ss'):"
    try {
        $u = Invoke-RestMethod -Uri 'https://api.vk.com/method/users.get' -Method Post `
            -Body @{ access_token = $pt; v = '5.199' }
        if ($u.error) {
            "  flood ещё держит (error $($u.error.error_code))"
        } else {
            "  флуд снят, продолжаю ($($u.response[0].first_name))"
            $unblocked = $true
            break
        }
    } catch { "  запрос упал: $($_.Exception.Message)" }
    Start-Sleep -Seconds 600
}
if (-not $unblocked) { "FAIL: флуд не отпустил за 24 проверки"; exit 1 }

# 1) тестовый пост на стене — убрать, если ещё существует
try {
    $d = Invoke-RestMethod -Uri 'https://api.vk.com/method/wall.delete' -Method Post `
        -Body @{ owner_id = $groupId; post_id = $testPostId; access_token = $pt; v = '5.199' }
    if ($d.error) { "wall.delete поста $($testPostId) : error $($d.error.error_code) $($d.error.error_msg)" }
    else { "тестовый пост $($testPostId) удалён" }
} catch { "wall.delete упал: $($_.Exception.Message)" }

# 2) публикация сегодняшней позиции (publish-vk-group.ps1 сам поставит метку)
$p = & powershell -NoProfile -ExecutionPolicy Bypass -File 'publish-vk-group.ps1' 2>&1
$p | ForEach-Object { "$_" }
if ($LASTEXITCODE -ne 0) { "FAIL: publish-vk-group.ps1 завершился с кодом $LASTEXITCODE"; exit 1 }
"SUCCESS: тестовый пост убран, сегодняшняя позиция опубликована в VK-группу"
