# publish-vk-group.ps1
# Шаг ежедневного прогона (run-daily-post.cmd): публикация новой позиции ленты
# на стену сообщества club242982533 через send-vk-with-image.ps1 (личный токен).
#
# Берёт ПОСЛЕДНЮЮ запись rss-site\state.json (её же добавил headless-подготовщик),
# пропускает, если vk_group_published уже true, публикует и ставит метку.
# Токен: posts news\user_id.env (последняя строка). Ошибка VK -> код выхода 1.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$statePath = 'rss-site\state.json'
if (-not (Test-Path $statePath)) { throw "Нет $statePath" }
$state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $state.added -or $state.added.Count -eq 0) { throw "state.json пуст" }

# новые записи добавляются в конец массива added — берём последнюю
$latest = $state.added[-1]
if ($latest.vk_group_published) {
    Write-Host ("Уже опубликовано в VK-группе: {0} — пропуск" -f $latest.guid)
    exit 0
}
if (-not $latest.file) { throw "У последней записи нет поля file" }

$args = @{ JsonPath = $latest.file; EnvFile = 'posts news\user_id.env' }
if ($latest.image) {
    $imgPath = Join-Path 'rss-site\img' $latest.image
    if (Test-Path $imgPath) { $args.ImagePath = $imgPath }
    else { Write-Host ("Картинки нет ({0}) — пост без фото" -f $imgPath) }
}

# send-vk-with-image.ps1 в UTF-8 без BOM ломает парсер PS 5.1 — запуск через scriptblock
$vkScript = [ScriptBlock]::Create([IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot 'send-vk-with-image.ps1'), [Text.Encoding]::UTF8))
& $vkScript @args

# scriptblock с throw при ошибке VK прервёт нас (EAP Stop); сюда попадаем только при успехе
$latest | Add-Member -NotePropertyName vk_group_published -NotePropertyValue $true -Force
$out = $state | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Resolve-Path $statePath), $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Метка vk_group_published записана для {0}" -f $latest.guid)
