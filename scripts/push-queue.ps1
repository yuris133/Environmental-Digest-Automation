# push-queue.ps1
# Заливка одного поста в облачную очередь Worker'а autopost (KV namespace FEED_KV).
# Использование: .\push-queue.ps1 -JsonPath "posts news\...-social-content.json" [-ImageType image/jpeg]
# Берёт схему posts news (platforms.'ВКонтакте' + platforms.telegram), кладёт
# KV-ключ queue:<n>, где n = "pushed" (счётчик залитого) + 1.
# Worker публикует по cron в 10:30 МСК пн-пт, беря queue:<cursor+1>.
# Токен: .claude\auth-cloudflare.env (CF_API_TOKEN, CF_ACCOUNT_ID).

param(
    [Parameter(Mandatory = $true)][string]$JsonPath,
    [string]$ImageName = ''            # имя файла картинки на pages.dev (rss-site/img/)
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path ".claude\auth-cloudflare.env")) { throw "Нет .claude\auth-cloudflare.env" }
$cfg = @{}
foreach ($line in (Get-Content '.claude\auth-cloudflare.env')) {
    if ($line -match '^\s*(CF_[A-Z_]+)\s*=\s*(\S+)\s*$') { $cfg[$matches[1]] = $matches[2].Trim() }
}
if (-not $cfg['CF_API_TOKEN']) { throw 'Нет CF_API_TOKEN' }

$kvId = 'fbe773e0ae9d4570a7c28789f42ea23f'   # worker-FEED_KV (создан 12.11.2026)
$kvBase = "https://api.cloudflare.com/client/v4/accounts/$($cfg['CF_ACCOUNT_ID'])/storage/kv/namespaces/$kvId/values"
$hdr = @{ Authorization = "Bearer $($cfg['CF_API_TOKEN'])" }

function Get-Kv([string]$key) {
    try {
        Invoke-RestMethod -Uri "$kvBase/$key" -Headers $hdr -Method Get
    } catch {
        # несуществующий ключ — норма для пустой очереди (VK/CF отдаёт 404 + код 10009)
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 404) { return $null }
        throw
    }
}

function Put-Kv([string]$key, [string]$value) {
    $r = Invoke-RestMethod -Uri "$kvBase/$key" -Headers $hdr -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($value)) `
        -ContentType 'text/plain; charset=utf-8'
    if (-not $r.success) { throw "KV put $key не удался: $(ConvertTo-Json $r -Compress)" }
}

$post = Get-Content $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$vk = $post.platforms.'ВКонтакте'
if (-not $vk) { throw "В JSON нет platforms.'ВКонтакте'" }

$message = $vk.body
if ($vk.hashtags -and $vk.hashtags.Count -gt 0) { $message = $message + "`n`n" + ($vk.hashtags -join ' ') }

$guid = [IO.Path]::GetFileNameWithoutExtension($JsonPath)
$pushed = 0
$pushedRaw = Get-Kv 'pushed'
if ($pushedRaw) { $pushed = [int]$pushedRaw }
$n = $pushed + 1

$imgType = @{ '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.webp' = 'image/webp' }
$img = if ($ImageName) { $ImageName } else { $null }
$imgTypeValue = if ($img) { $imgType[[IO.Path]::GetExtension($img).ToLowerInvariant()] } else { $null }
# точный размер картинки на pages.dev — файл должен лежать в rss-site\img\
$imgLength = 0
if ($img) {
    $imgLocal = Join-Path 'rss-site\img' $img
    if (-not (Test-Path $imgLocal)) { throw "Картинки нет в rss-site\img\: $img (сначала deploy-feed.ps1)" }
    $imgLength = (Get-Item $imgLocal).Length
}

$item = @{
    guid        = $guid
    title       = $vk.headline
    link        = if ($post.source -and $post.source.url) { $post.source.url.ToString() } else { $null }
    description = $message
    image       = $img
    imageType   = $imgTypeValue
    imageLength = $imgLength
    pushedAt    = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
}
Put-Kv "queue:$n" (ConvertTo-Json $item -Depth 5)
Put-Kv 'pushed' ([string]$n)
Write-Host ("В очередь залито: queue:{0} -> {1}" -f $n, $vk.headline)
