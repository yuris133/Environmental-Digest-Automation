# SETUP — настройка проекта с нуля

Пошаговая настройка market-research-agent в новой среде. Описание самой системы — `README.md`, рабочие инструкции — скилл `environmental-digest-project`, типичные проблемы — `GOTCHAS.md`.

## 1. Prerequisites

- Windows 10/11, Claude Code (интерактивный режим + headless `claude -p`).
- Node.js + wrangler 3 (`npm install -g wrangler@3`) — для выгрузки ленты в Cloudflare Pages.
- PowerShell 5.1 (скрипты проекта на нём).
- Подписка SMMplanner с функцией «Репостер» (тариф уровня «Начальный»: 1 Репостер, 5 приёмников — достаточно).
- Ключи: Cloudflare API-токен, Gmail app password, fal.ai (MCP).

## 2. Секретные env-файлы (создаются руками, в git не попадают — уже в .gitignore)

| Файл | Ключи | Назначение |
|---|---|---|
| `.claude\auth-weekly.env` | `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`, `SMTP_USER`, `SMTP_PASS` | Авторизация headless `claude -p` + параметры моделей + SMTP для дайджестов |
| `.claude\auth-cloudflare.env` | `CF_API_TOKEN`, `CF_ACCOUNT_ID` | Токен воркера `deploy-feed.ps1` (wrangler) |
| `auth-fal.env` | (значения ключей fal — см. конфигурацию MCP fal-плагина) | Генерация картинок к постам |
| `posts news\user_id.env` | VK user-token (IP-привязанный) | VK-цепочки |
| `posts news\group_id.env` | group_id сообщества VK (без минуса) | VK-цепочки |
| `posts news\ID сообщества VK.env` | id сообщества для постинга | VK-цепочки |
| `posts news\proxy.env` | параметры прокси, если нужны | VK-цепочки |

Важно: headless-режим `claude -p` авторизуется **только** через `.claude\auth-weekly.env` — команда `/login` в интерактивной сессии на него не влияет. Проверка — `scripts\test-headless.cmd`.

## 3. Задачи Windows Task Scheduler

Две запланированные задачи (создать через Планировщик или `schtasks /Create`):

| Задача | Расписание | Запускает | Что делает |
|---|---|---|---|
| `MarketResearch-FMCG-Weekly` | пт 10:05 | `run-weekly.cmd` | Сбор новостей + еженедельный отчёт (headless `claude -p`, лог `weekly-run.log`) |
| `SMM-Daily-Post` | пн–пт 10:30 | `run-daily-post.cmd` | Один пост в RSS-ленту + выгрузка на Cloudflare (лог `daily-post-run.log`) |

Рабочая папка задач — корень проекта. Внимание на нейминг: `MarketResearch-Weekly` может быть занята другим проектом-клоном.

## 4. Cloudflare Pages

1. Создать проект Pages с именем `market-research-agent`.
2. Залить `rss-site/` (в репо: `feed.xml`, `img/`, `state.json` копируются туда скриптом).
3. Выгрузка — `scripts\deploy-feed.ps1` (берёт токен из `.claude\auth-cloudflare.env`, копирует картинки по `img_source`, дозаполняет `length` у enclosure). Успех = «✨ Deployment complete» в выводе.
4. Лента должна открываться: `https://<project>.pages.dev/feed.xml`. Если у оператора фильтруются `*.pages.dev` (SSL-сброс, «мигает») — деплой всё равно работает, проверяй через VPN/телефон; долгосрочно — привязать свой домен к Pages.
5. В настройках навыка «SMMplanner RSS Post» задать `BASE_URL` — вместо плейсхолдера `CHANGE-ME`, иначе ссылки в ленте будут нерабочими.

## 5. SMMplanner

1. Подписка с Репостером; создать Репостер: источник — RSS-лента из шага 4, приёмники — нужные соцстраницы.
2. В настройках Репостера: включить перенос «Картинка» в контент; ретроспектива — 1 час (наш стандарт); расписание — 24/7 или своё.
3. Проверка: «Репостер → История» — там видны все репосты и ошибки скачивания.
4. Telegram и ВКонтакте постятся напрямую скриптами проекта — SMMplanner для них не использовать, цепочки не смешивать.

## 6. Gmail (дайджесты) и fal (картинки)

- Gmail app password (16 символов) → `SMTP_PASS` в `.claude\auth-weekly.env`; адрес — `SMTP_USER`. Скрипт `scripts\send-weekly-email.ps1` шлёт дайджест на один разрешённый адрес.
-fal доступен через MCP-плагин (дешёвые flux/schnell ~$0,003 за картинку — разрешены к использованию без запроса; дорогие модели — только по явному запросу человека).

## 7. Проверка конфигурации (smoke test)

1. `scripts\test-headless.cmd` — headless Claude авторизуется.
2. Ручной запуск `scripts\run-weekly.cmd` — в `Report/` появился отчёт по шаблону `templates\report-template.md`.
3. Ручной запуск `scripts\run-daily-post.cmd` — в `rss-site\feed.xml` новый `<item>` сверху, выгрузка завершилась «Deployment complete», лента отдаётся по URL.
4. В SMMplanner «История» в течение часа появилась попытка репоста — с картинкой.
5. Картинки: `digest/img/` (из источников с атрибуцией) или `posts/img/` (сгенерированные fal); в ленте предпочтительно jpeg — см. GOTCHAS.

## 8. Что где смотреть на постоянной основе

- `daily-post-run.log` / `weekly-run.log` — логи фоновых задач.
- `Report/` — отчёты (нумерация выпусков сквозная), `digest/` — дайджесты, `posts news/` — утверждённые JSON-посты, `rss-site/state.json` — дедуп-реестр.
- Правила нейминга файлов: `[дата — опционально] — [тема] — [тип]`; существующие файлы не перезаписывать (суффикс `-2`, `-3`).
