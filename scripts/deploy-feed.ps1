# deploy-feed.ps1
# Выгрузка rss-site/ на Cloudflare Pages (проект market-research-agent).
# Токен и account_id — в .claude\auth-cloudflare.env (gitignored):
#   CF_API_TOKEN=... CF_ACCOUNT_ID=...
# Вызывается из run-daily-post.cmd и вручную:
#   powershell -NoProfile -ExecutionPolicy Bypass -File deploy-feed.ps1
# Ответ Cloudflare проверяется: любая ошибка -> ненулевой код выхода.

$ErrorActionPreference = 'Stop'

$RootDir = $PSScriptRoot
$EnvFile = Join-Path $RootDir '.claude\auth-cloudflare.env'
$ProjectName = 'market-research-agent'

if (-not (Test-Path $EnvFile)) { throw ("Нет файла с токеном: {0}" -f $EnvFile) }
$envCfg = @{}
foreach ($line in (Get-Content $EnvFile)) {
    if ($line -match '^\s*(CF_[A-Z_]+)\s*=\s*(\S+)\s*$') { $envCfg[$matches[1]] = $matches[2].Trim() }
}
if (-not $envCfg['CF_API_TOKEN'])  { throw "В $EnvFile нет CF_API_TOKEN" }
if (-not $envCfg['CF_ACCOUNT_ID']) { throw "В $EnvFile нет CF_ACCOUNT_ID" }

$env:CLOUDFLARE_API_TOKEN = $envCfg['CF_API_TOKEN']
$env:CLOUDFLARE_ACCOUNT_ID = $envCfg['CF_ACCOUNT_ID']

# npx.cmd ищем в npm-папке пользователя (как postiz-CLI), иначе — из PATH
$npx = Join-Path $env:APPDATA 'npm\npx.cmd'
if (-not (Test-Path $npx)) { $npx = 'npx.cmd' }

if (-not (Test-Path (Join-Path $RootDir 'rss-site\feed.xml'))) {
    throw "Не найден rss-site\feed.xml — лента не собрана, выгружать нечего"
}

# ---- Generate images for state entries that carry img_prompt (no image yet) ----
# Headless preparer cannot call fal or download binaries, so it only records
# img_prompt; this script does the rest: fal REST queue API, flux/schnell
# (~$0.003 per picture, standing approval). Key file: auth-fal.env in the
# project root or .claude\auth-fal.env (gitignored) - a bare key on one line,
# or FAL_KEY=<key>. On failure the entry keeps img_prompt and the feed item
# stays without enclosure so the next run can retry.
$FeedPath0 = Join-Path $RootDir 'rss-site\feed.xml'
$StatePath0 = Join-Path $RootDir 'rss-site\state.json'
$FalKey = $null
foreach ($cand in @((Join-Path $RootDir 'auth-fal.env'), (Join-Path $RootDir '.claude\auth-fal.env'))) {
    if ($FalKey) { break }
    if (Test-Path $cand) {
        $val = (Get-Content $cand -TotalCount 1).Trim()
        if ($val -match '^FAL_KEY\s*=\s*(.+)$') { $val = $Matches[1].Trim() }
        if ($val) { $FalKey = $val }
    }
}
if (-not $FalKey) {
    Write-Host "IMG GENERATION SKIPPED: no fal key file (auth-fal.env) in project root or .claude"
}
if ($FalKey -and (Test-Path $StatePath0)) {
    $FalHeaders = @{ Authorization = ('Key ' + $FalKey) }
    $FalUri = 'https://queue.fal.run/fal-ai/flux/schnell'
    $BaseImgUrl = 'https://market-research-agent.pages.dev/img/'
    $falState = Get-Content $StatePath0 -Raw -Encoding UTF8 | ConvertFrom-Json
    $falNeedSave = $false
    foreach ($it in @($falState.added)) {
        if (-not $it.img_prompt -or $it.image) { continue }
        $imgName = (($it.guid -replace '-social-content$', '') + '-post.jpg')
        $postsImgDir = Join-Path $RootDir 'posts\img'
        if (-not (Test-Path $postsImgDir)) { New-Item -ItemType Directory -Force $postsImgDir | Out-Null }
        $dstFile = Join-Path $postsImgDir $imgName
        try {
            if (-not (Test-Path $dstFile)) {
                $body = @{ prompt = $it.img_prompt; image_size = 'landscape_16_9'; num_images = 1 } | ConvertTo-Json
                $sub = $null
                for ($attempt = 1; $attempt -le 2; $attempt++) {
                    try {
                        $sub = Invoke-RestMethod -Method Post -Uri $FalUri -Headers $FalHeaders -ContentType 'application/json' -Body $body -TimeoutSec 30
                        break
                    } catch {
                        if ($attempt -eq 1) { Write-Host "fal submit retry after: $($_.Exception.Message)"; Start-Sleep -Seconds 5 } else { throw }
                    }
                }
                $imgUrl = $null
                $deadline = (Get-Date).AddSeconds(150)
                $stp = $null
                while ((Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 3
                    $stp = Invoke-RestMethod -Uri $sub.status_url -Headers $FalHeaders -TimeoutSec 20
                    if ($stp.status -eq 'COMPLETED') {
                        $res = Invoke-RestMethod -Uri $sub.response_url -Headers $FalHeaders -TimeoutSec 30
                        $imgUrl = $res.images[0].url
                        break
                    }
                    if ($stp.status -ne 'IN_QUEUE' -and $stp.status -ne 'IN_PROGRESS') { break }
                }
                if (-not $imgUrl) { throw ('fal job not completed, status: ' + $stp.status) }
                Invoke-WebRequest -Uri $imgUrl -OutFile $dstFile -TimeoutSec 60
            }
            $it | Add-Member -NotePropertyName image -NotePropertyValue $imgName -Force
            $it | Add-Member -NotePropertyName img_source -NotePropertyValue ('posts/img/' + $imgName) -Force
            $it.PSObject.Properties.Remove('img_prompt')
            $falNeedSave = $true
            Write-Host ("IMG GENERATED: {0}" -f $imgName)
            # feed.xml: add enclosure right after the guid line of this item, only if absent
            $feedText = [IO.File]::ReadAllText($FeedPath0, [Text.Encoding]::UTF8)
            $guidPat = '<guid isPermaLink="false">' + ([regex]::Escape($it.guid)) + '</guid>'
            $encPat = '<enclosure\s+url="' + [regex]::Escape(($BaseImgUrl + $imgName)) + '"'
            if ([regex]::IsMatch($feedText, $guidPat) -and -not [regex]::IsMatch($feedText, $encPat)) {
                $encLine = '<enclosure url="' + ($BaseImgUrl + $imgName) + '" length="' + (Get-Item $dstFile).Length + '" type="image/jpeg" />'
                $rx = New-Object System.Text.RegularExpressions.Regex($guidPat)
                $feedText = $rx.Replace($feedText, ($guidPat + [Environment]::NewLine + '      ' + $encLine), 1)
                [IO.File]::WriteAllText($FeedPath0, $feedText, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host ("ENCLOSURE ADDED for {0}" -f $it.guid)
            }
        } catch {
            Write-Host ("IMG GENERATION FAILED for {0}: {1}" -f $it.guid, $_.Exception.Message)
        }
    }
    if ($falNeedSave) {
        $json = $falState | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText($StatePath0, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "state.json updated with generated image entries"
    }
}

# Копируем картинки: headless-подготовщик не умеет копировать битые файлы,
# поэтому в state.json он пишет img_source (путь в проекте), а здесь файл
# ложится в rss-site\img\ перед выгрузкой.
$statePath = Join-Path $RootDir 'rss-site\state.json'
if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($it in @($state.added)) {
        $src = if ($it.img_source) { Join-Path $RootDir $it.img_source } else { $null }
        $dst = if ($it.image) { Join-Path $RootDir ("rss-site\img\" + $it.image) } else { $null }
        if ($src -and $dst -and (Test-Path $src) -and -not (Test-Path $dst)) {
            Copy-Item $src $dst
            Write-Host ("Картинка скопирована: {0}" -f $it.image)
        }
    }
}

# Enclosure'ы без length: headless-подготовщик не знает размер файла,
# здесь дозаполняем length из размера локального файла в rss-site\img\.
# Правка текстовая (regex по тегам enclosure), XML не пересобирается заново.
$feedPath = Join-Path $RootDir 'rss-site\feed.xml'
$feedXml = [IO.File]::ReadAllText($feedPath, [Text.Encoding]::UTF8)
$encPattern = '<enclosure\s+url="(?<url>[^"]+)"(?<rest>[^>]*)/>'
$changed = 0
$fixed = [regex]::Replace($feedXml, $encPattern, {
    param($m)
    $url = $m.Groups['url'].Value
    $rest = $m.Groups['rest'].Value
    if ($rest -match 'length\s*=' -or $url -notmatch '/img/') { return $m.Value }
    $fileName = [uri]::UnescapeDataString(($url -split '/img/')[-1])
    $local = Join-Path $RootDir ("rss-site\img\" + $fileName)
    if (-not (Test-Path $local)) {
        Write-Host ("ВНИМАНИЕ: для {0} нет локального файла, length не проставлен" -f $fileName)
        return $m.Value
    }
    $script:changed++
    return ('<enclosure url="{0}" length="{1}" type="{2}" />' -f $url, (Get-Item $local).Length, ($rest | Select-String -Pattern 'type="([^"]+)"').Matches[0].Groups[1].Value)
})
if ($changed -gt 0) {
    [IO.File]::WriteAllText($feedPath, $fixed, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("length проставлен для {0} enclosure" -f $changed)
}

# --branch main = production-ветка: лента публикуется в основное место проекта
# EAP 'Continue' на время вызова: wrangler пишет прогресс в stderr,
# PS 5.1 с ErrorActionPreference 'Stop' обрывает его как NativeCommandError.
$ErrorActionPreference = 'Continue'
& $npx --yes wrangler@3 pages deploy (Join-Path $RootDir 'rss-site') `
    --project-name=$ProjectName --branch=main --commit-dirty=true 2>&1 | ForEach-Object { "$_" }
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "wrangler завершился с кодом $LASTEXITCODE" }

Write-Host ("Лента выгружена: https://{0}.pages.dev/feed.xml" -f $ProjectName)
