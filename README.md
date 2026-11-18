# Environmental Digest — автоматизация мониторинга «зелёных» технологий FMCG

Автоматизированная цепочка мониторинга «зелёных» технологий утилизации отходов FMCG-компаний: сбор новостей → еженедельный отчёт → дайджест → посты для соцсетей → автопостинг в Telegram, ВКонтакте и дополнительные сети через SMMplanner.

> **Эта папка — publish-ready пакет проекта**: документация, скрипты, шаблоны и образцы форматов, собранные для публикации в репозиторий. Секретов здесь нет (env только по именам ключей) — проверка перед публикацией описана в `GOTCHAS.md`, п. 24.

## Состав пакета

| Файл/папка | Что там |
|---|---|
| `README.md` | Обзор системы: архитектура, папки, скрипты, сервисы |
| `SETUP.md` | Настройка с нуля в новой среде: env-файлы, задачи планировщика, Cloudflare, SMMplanner, проверка |
| `GOTCHAS.md` | Все практические грабли: дедуп Репостера, свежесть 1 час, фильтр pages.dev, webp, headless, VK/TG-нюансы |
| `scripts/` | Копии всех скриптов цепочки (живые версии — в корне проекта; копии для этого пакета) |
| `templates/` | `report-template.md` (шаблон структуры отчёта = `Report/_template.md`) и `digest-template.html` (шаблон «полевого журнала») |
| `examples/` | Образцы форматов: отчёт выпуска №8, дайджест (.md / .html / .telegram), JSON-пост, `feed.xml`, `state.json` |

## Примеры (папка `examples/`)

Взгляд на реально выпущенные материалы выпуска №8 от 13.11.2026 — эталоны форматов для новых выпусков:

| Файл | Что показывает |
|---|---|
| [`2026-11-13-green-waste-tech-fmcg-weekly-report.md`](examples/2026-11-13-green-waste-tech-fmcg-weekly-report.md) | Полный еженедельный отчёт (выпуск №8): структура разделов, формат ссылок на источники |
| [`2026-11-13-green-waste-tech-fmcg-digest.md`](examples/2026-11-13-green-waste-tech-fmcg-digest.md) | Дайджест в Markdown — свёртывание отчёта без новых фактов |
| [`2026-11-13-green-waste-tech-fmcg-digest.html`](examples/2026-11-13-green-waste-tech-fmcg-digest.html) | HTML-версия в стиле «полевого журнала» (антиква Cormorant Garamond, §-глыфы, тёмный блок «Связка недели») — эталон вёрстки по `templates/digest-template.html` |
| [`2026-11-13-green-waste-tech-fmcg-digest-telegram.md`](examples/2026-11-13-green-waste-tech-fmcg-digest-telegram.md) | Telegram-версия дайджеста (короткие посты) |
| [`post-json-example.json`](examples/post-json-example.json) | Схема JSON-поста: `platforms` (ВКонтакте + telegram), `image_prompt`, `source` |
| [`feed.xml`](examples/feed.xml) | RSS-лента: формат item (CDATA, guid, pubDate, enclosure) |
| [`state.json`](examples/state.json) | Дедуп-реестр ленты (записи guid + pubDate + image) |

Нумерация: у отчёта и дайджеста общий номер выпуска («выпуск №8»/«дайджест №8»).

## Как работает (полный цикл)

```
 Новости сети (news-researcher)
        ↓
 Еженедельный отчёт (report-writer)  →  Report/  → PDF (вручную, Obsidian)
        ↓
 Дайджест (HTML «полевой журнал»)   →  digest/  → письмо на Gmail
        ↓
 Посты для соцсетей (JSON)          →  posts news/
        ↓                 ↓
        ↓          Telegram + VK — прямые публикации (скрипты)
        ↓
 RSS-лента feed.xml (SMMplanner RSS Post) → rss-site/
        ↓
 Выгрузка deploy-feed.ps1 → Cloudflare Pages (market-research-agent.pages.dev)
        ↓
 SMMplanner «Репостер» — раз в сутки до 10:50 забирает 1 свежий пост
        ↓
 Дополнительные соцсети (включая VK-сообщество club242982533)
```

1. **Еженедельный отчёт.** Пятница 10:05, задача планировщика Windows `MarketResearch-Weekly` запускает `run-weekly.cmd` (headless `claude -p`, авторизация через gitignored `.claude\auth-weekly.env`). Лог — в папку проекта `weekly-run.log`. Итог: `Report/[дата]-green-waste-tech-fmcg-weekly-report.md`, у отчёта есть номер выпуска («выпуск №N»).
2. **Дайджест.** После отчёта (вручную или по фразе «сделай дайджест»). Полный — HTML в стиле «полевого журнала» по шаблону `C:\Users\Windows\My Ai\Web Site Fortutil\Дайджест\digest-template.html` (антиква Cormorant Garamond, §-разделы, тёмный блок «Связка недели»), блоки по навыку «Environmental digest». ТГ-версия — `...-digest-telegram.md`. Отправка на `user@example.com` через `send-weekly-email.ps1` (Gmail SMTP, пароль приложения в `.claude\auth-weekly.env`) — единственное разрешённое отправление во внешний мир, кроме ленты.
3. **Посты.** Из отчёта/дайджеста по навыкам News Environmental Post / AI News Environmental Post готовятся JSON-файлы в `posts news/`: платформы `ВКонтакте` + `telegram`, поле `image_prompt`, `source` (url, issue, note). Тексты утверждённые — **не переписывать** на этапах ниже.
4. **Ежедневный автопостинг.** Пн–пт 10:30, задача `SMM-Daily-Post` запускает `run-daily-post.cmd`: headless-агент берёт одну неопостенную новость из последнего отчёта (дедуп по `rss-site/state.json` по URL/заголовку), делает JSON-пост, вставляет `<item>` в начало `feed.xml` (свежие сверху, максимум 20, pubDate 10:35 +0300 текущего дня), затем `deploy-feed.ps1` выгружает ленту на Cloudflare Pages (wrangler, токен и account_id в gitignored `.claude\auth-cloudflare.env`). Пост в сутки — один. Лог — `daily-post-run.log`.
5. **SMMplanner Репостер.** Дополнительные сети сверх TG/VK подключены к функции «Репостер» (RSS-источник `https://market-research-agent.pages.dev/feed.xml`, ретроспектива 1 час). С 12.11.2026 Репостер также публикует в VK-сообщество club242982533 (фото прикрепляет сам) — облачная публикация в группу через VK API не нужна. TG и VK постятся **не через SMMplanner** — это отдельные цепочки.

## Структура папок

| Папка/файл | Что там |
|---|---|
| `Report/` | Еженедельные отчёты `.md` + `_template.md` (шаблон структуры) |
| `digest/`, `digest/img/` | Дайджесты (`.md`, `.html`, `-telegram.md`) и фото новостей |
| `posts news/` | Готовые JSON-посты (вход всех цепочек публикации) |
| `posts/img/` | Картинки к постам (в т.ч. сгенерированные fal) |
| `rss-site/` | `feed.xml` (лента, ≤20 позиций, свежие сверху), `img/` (копии картинок), `state.json` (дедуп-реестр) |
| `autopost-cf/` | Worker автопостинга Cloudflare (наработка, не основная цепочка) |
| `Environmental Digest/` | Документация проекта (этот README) |
| `.claude/skills/` | Родные навыки: Main Environmental News (весь цикл), Environmental digest, News Environmental Post, AI News Environmental Post, SMMplanner RSS Post; `.claude/agents/` — субагенты news-researcher, report-writer, social-poster, post-illustrator |

## Скрипты и задачи

| Скрипт/задача | Роль |
|---|---|
| `run-weekly.cmd` + задача `MarketResearch-FMCG-Weekly` (пт 10:05) | Еженедельный отчёт, headless-режим |
| `run-daily-post.cmd` + задача `SMM-Daily-Post` (пн–пт 10:30) | Ежедневный пост в RSS-ленту + деплой |
| `deploy-feed.ps1` | Копирует картинки по `img_source` и выгружает `rss-site/` через wrangler |
| `send-weekly-email.ps1` | Письмо дайджеста на `user@example.com` |
| `publish-vk-group.ps1`, `publish-vk-once.ps1`, `publish-vk-when-unblocked.ps1`, `send-vk-with-image.ps1` | VK-цепочки (пост на стену сообщества/личную стену), не основная траектория |
| `push-queue.ps1` | Заливка очереди автопостинга (пятничная подготовка) |
| `.claude/scheduled_tasks.json` | Состояние задач планировщика, заведённых через агента |

## Внешние сервисы

- **Cloudflare Pages** — хостинг ленты, проект `market-research-agent`, `https://market-research-agent.pages.dev/feed.xml`.
- **SMMplanner** — автопостинг «Репостер» (тариф, включающий 1 Репостер / 5 приёмников, достаточен). `BASE_URL` ленты задаётся в настройках навыка SMMplanner RSS Post — пока там плейсхолдер `CHANGE-ME`, ссылки в ленте считаются нерабочими и это предупреждать в отчётах.
- **Gmail (SMTP)** — дайджесты на `user@example.com`.
- **fal.ai MCP** — генерация картинок к постам (flux/schnell, ~$0,003).

## Секреты

Все — в gitignored env-файлах, никогда не коммитить:
`.claude\auth-weekly.env` (headless-авторизация Claude + Gmail), `.claude\auth-cloudflare.env` (wrangler), `auth-fal.env`.

## Известные грабли (актуально на 18.11.2026)

- **Репостер дедуплицирует по guid.** Обновлять уже забранный пост можно только сменой guid (суффикс `-2`, `-3`...) + свежий pubDate + деплой. Один pubDate не спасает.
- **«Свежесть» Репостера — 1 час.** Любая поздняя правка позиции ленты требует обновления pubDate на текущее время.
- **`*.pages.dev` фильтруется российскими операторами с «миганием»** (и у человека, и, судя по `UNABLE_TO_DOWNLOAD_ATTACHMENT`, у серверов SMMplanner). Репостер может дотянуть ленту, но не скачать картинку. Деплой при этом работает всегда (wrangler идёт через `api.cloudflare.com`). Радикальное решение — свой домен для Pages-проекта.
- **`.webp` — рискованный формат** для картинок в ленте: парсер/сеть могут не принять. Предпочтение jpeg.
- **Headless `claude -p` работает только с `.claude\auth-weekly.env`** — `/login` в интерактивной сессии на него не влияет. Проверка — `test-headless.cmd`.
- **Не перезаписывать существующие файлы отчётов/лент:** если имя занято — суффикс `-2`, `-3`.
- **Картинки из пресс-релизов** качаются в `digest/img/` с атрибуцией; если источник недоступен — рисуется SVG-схема в палитре шаблона.

## Границы (чего не делать)

Не удалять/перемещать/переименовывать файлы, не выходить за пределы рабочей папки, не отправлять вовне (кроме дайджестов на `user@example.com` и ленты через штатный деплой), не делать `git push`, не менять настройки системы. Правила нейминга и формат ответов — в родительской инструкции `My Ai/CLAUDE.md`.

## Как публиковать пакет в репозиторий

1. Вся папка `Environmental Digest/` — publish-ready package: документация + скрипты + шаблоны + образцы. Публично выкладывается целиком.
2. Скилл установлен в проекте: `.claude/skills/environmental-digest-project/SKILL.md` (папка `.claude/skills/` отслеживается git — скилл публикуется по своему рабочему пути). В чужой среде скопируй его по тому же пути — Claude Code подхватит автоматически в следующей сессии.
3. Перед публикацией — проверка секретов по `GOTCHAS.md` п. 24 (сам пакет чист, проверено 18.11.2026).
4. env-файлы с реальными значениями в git не попадают (все в `.gitignore`); в новой среде создать по именам ключей из `SETUP.md`, п. 2.
