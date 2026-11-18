# send-vk-with-image.ps1
# Публикация в VK напрямую через VK API (в обход Postiz — у Postiz баг с медиа для VK).
#
# Использование:
#   Новый пост (текст из posts news JSON + картинка):
#     .\send-vk-with-image.ps1 -JsonPath "posts news\2026-11-05-...json" -ImagePath "posts\img\...jpg"
#   Тот же пост, но без картинки:
#     .\send-vk-with-image.ps1 -JsonPath "posts news\....json"
#   Прикрепить фото первым комментарием к уже опубликованному посту:
#     .\send-vk-with-image.ps1 -JsonPath "posts news\....json" -ImagePath "posts\img\...jpg" -CommentPostId 4
#
# Токен: posts news\group_id.env — ключ сообщества club242982533 (vk1.a... или "VK_TOKEN=...").
# Ответы VK проверяются: любой error VK API останавливает скрипт с ненулевым кодом.

param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath,            # путь к пост-JSON с платформой "ВКонтакте"

    [string]$ImagePath,           # локальная картинка (опционально)

    [string]$OwnerId = "-242982533",   # стена сообщества club242982533 (знак минус обязателен)

    [string]$EnvFile = "",        # файл с токеном; пусто = posts news\vk.env рядом со скриптом

    [string]$CommentPostId = "",  # если задан — не новый пост, а фото-комментарий к wall{OwnerId}_{CommentPostId}

    [string]$CommentText = ""     # текст фото-комментария (может быть пустым — только вложение)
)

$ErrorActionPreference = 'Stop'
$VK_API = 'https://api.vk.com/method'


function Get-VkToken {
    param([string]$File)
    $resolved = if ($File) { $File } else { Join-Path $PSScriptRoot 'posts news\group_id.env' }
    if (-not (Test-Path $resolved)) {
        throw ("Файл с токеном не найден: {0}`nСодержимое: либо сырой токен vk1.a..., либо строка VK_TOKEN=..." -f $resolved)
    }
    $linesRaw = Get-Content $resolved -Encoding UTF8 | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }
    if ($marked = $linesRaw | Where-Object { $_ -match '^VK_TOKEN\s*=' } | Select-Object -Last 1) {
        return ($marked -split '=', 2)[1].Trim()
    }
    # несколько ключей в файле — берём последний (самый свежий)
    if (-not $linesRaw) { throw "Токен в файле не найден" }
    return $linesRaw | Select-Object -Last 1
}


function Invoke-VkApi {
    param([string]$Method, [hashtable]$Params, [string]$Token)
    # версия API обязательна с 2025: без неё VK возвращает error_code=8
    if (-not $Params.ContainsKey('v')) { $Params['v'] = '5.199' }
    $pairs = @()
    foreach ($k in $Params.Keys) {
        $pairs += ("{0}={1}" -f $k, [uri]::EscapeDataString([string]$Params[$k]))
    }
    $bodyString = ($pairs -join '&')
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyString)
    $headers = @{ Authorization = "Bearer $Token" }
    $response = Invoke-RestMethod -Uri "$VK_API/$Method" -Method Post -Body $bodyBytes `
        -ContentType "application/x-www-form-urlencoded; charset=UTF-8" -Headers $headers
    if ($response.error) {
        throw ("VK API {0} -> error_code={1}: {2}" -f $Method, $response.error.error_code, $response.error.error_msg)
    }
    return $response.response
}


function Publish-VkPhoto {
    # Загружает фото на стену и сохраняет: возвращает attachment-строку "photo{owner}_{id}"
    param([string]$PhotoPath, [string]$WallOwnerId, [string]$Token)

    # Для стены группы ВК создаёт сессию загрузки только по ПОЛОЖИТЕЛЬНОМУ group_id.
    # С owner_id=-NNN загрузка проходит, но hash не совпадает при saveWallPhoto (error 121).
    $wallOwnerId = if ($WallOwnerId.StartsWith('-')) { $WallOwnerId.TrimStart('-') } else { $WallOwnerId }
    $uploadParams = if ($WallOwnerId.StartsWith('-')) { @{ group_id = $wallOwnerId } } else { @{ owner_id = $WallOwnerId } }
    $upload = Invoke-VkApi -Method 'photos.getWallUploadServer' -Params $uploadParams -Token $Token

    # curl.exe требует кавычки вокруг пути с пробелами внутри спецификации -F.
    # Если в пути есть пробелы — сначала копируем файл в temp без пробелов.
    $photoArg = $PhotoPath
    if ($PhotoPath -match '\s') {
        $photoArg = Join-Path $env:TEMP ('vk_upload_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + [System.IO.Path]::GetExtension($PhotoPath))
        Copy-Item $PhotoPath $photoArg -Force
    }
    try {
        $spec = "photo=@$photoArg"
        # --http1.1 и явный MIME обязательны: по HTTP/2 VK-сервер возвращает пустое photo
        $curlOut = (& curl.exe -s --http1.1 -X POST -F "$spec;type=image/jpeg" $upload.upload_url) -join "`n"
        $uploadResult = $curlOut | ConvertFrom-Json
        if (-not $uploadResult.photo) {
            throw ("Загрузка фото не удалась, ответ сервера: {0}" -f $curlOut)
        }
    }
    finally {
        if ($photoArg -ne $PhotoPath -and (Test-Path $photoArg)) { Remove-Item $photoArg -Force }
    }

    $ownerIsGroup = $WallOwnerId.StartsWith('-')
    $saveParams = @{
        server = $uploadResult.server
        photo  = $uploadResult.photo
        hash   = $uploadResult.hash
    }
    if ($ownerIsGroup) { $saveParams.group_id = [int]$WallOwnerId.TrimStart('-') } else { $saveParams.user_id = $WallOwnerId }
    $saved = Invoke-VkApi -Method 'photos.saveWallPhoto' -Params $saveParams -Token $Token
    $p = $saved[0]
    return ("photo{0}_{1}" -f $p.owner_id, $p.id)
}


# --- Основной поток ---

$token = Get-VkToken -File $EnvFile
Write-Host ("VK API: токен найден ({0}...), владелец стены: {1}" -f $token.Substring(0, 8), $OwnerId)

if (-not (Test-Path $JsonPath)) { throw ("JSON не найден: {0}" -f $JsonPath) }
$json = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$vk = $json.platforms.'ВКонтакте'
if (-not $vk) { throw "В JSON нет платформы 'ВКонтакте'" }

$message = $vk.body
if ($vk.hashtags -and $vk.hashtags.Count -gt 0) {
    $message = $message + "`n`n" + ($vk.hashtags -join ' ')
}

$attachments = @()
if ($ImagePath) {
    if (-not (Test-Path $ImagePath)) { throw ("Картинка не найдена: {0}" -f $ImagePath) }
    $attachments += Publish-VkPhoto -PhotoPath $ImagePath -WallOwnerId $OwnerId -Token $token
    Write-Host ("Фото загружено: {0}" -f $attachments[0])
}

if ($CommentPostId) {
    if ($attachments.Count -eq 0) { throw "-CommentPostId требует -ImagePath" }
    $commentParams = @{
        owner_id    = $OwnerId
        post_id     = $CommentPostId
        attachments = $attachments -join ','
    }
    if ($CommentText) { $commentParams.message = $CommentText }
    $r = Invoke-VkApi -Method 'wall.createComment' -Params $commentParams -Token $token
    Write-Host ("Фото прикреплено комментарием: comment_id={0}" -f $r.comment_id)
}
else {
    $postParams = @{
        owner_id = $OwnerId
        message  = $message
    }
    # from_group применяется только при постинге на стену пользователя
    if (-not $OwnerId.StartsWith('-')) { $postParams.from_group = 0 }
    if ($attachments.Count -gt 0) { $postParams.attachments = $attachments -join ',' }
    $r = Invoke-VkApi -Method 'wall.post' -Params $postParams -Token $token
    Write-Host ("VK пост опубликован: https://vk.com/feed?w=wall{0}_{1}" -f $OwnerId, $r.post_id)
}
