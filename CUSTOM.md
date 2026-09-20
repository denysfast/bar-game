# Кастомная сборка BAR (denysfast/bar-game, ветка `custom`)

Что изменено относительно upstream `beyond-all-reason/Beyond-All-Reason` и где это крутить.
Теги `custom-vN` — релизы; сервер и все игроки должны быть на одном теге.

## Маркер сборки

`luaui/Widgets/gui_custom_build_marker.lua` — надпись `BAR custom build <тег>` сверху по
центру (через `WG.fonts`; `gl.Text` под UI BAR ничего не рисует). Обновлять `CUSTOM_BUILD` при
каждом теге.

## Бонус ресурсов для ИИ (модопции, раздел «AI Bonus»)

`luarules/gadgets/game_ai_resource_bonus.lua` + `modoptions.lua` (`ai_bonus_*`):

| Опция | Смысл | Диапазон |
|---|---|---|
| `ai_bonus_max` | бонус к доходу металла и энергии ИИ после разгона, % от собственного дохода | 0–5000 |
| `ai_bonus_start` | бонус на старте | 0–5000 |
| `ai_bonus_ramp` | за сколько минут бонус растёт от старта до максимума | 1–240 |
| `ai_bonus_delay` | задержка до начала роста, минут | 0–120 |
| `ai_bonus_curve` | форма роста: `linear` / `slow_start` (квадрат) / `fast_start` (корень) | |

Механика: раз в секунду (кадр `% 30 == 15`) гаджет читает доход команды, вычитает то, что
сам добавил секунду назад (иначе бонус компаундится — проверено, уходило в Inf), и
добавляет `база × бонус`. Только для skirmish-ИИ (BARb и т.п.), не для Raptors/Scavengers.
Публикует `TeamRulesParam`: `ai_bonus_pct`, `ai_bonus_max_pct`, `ai_known_enemy_nukes`,
`ai_known_enemy_antinukes` (ядерки/антиядерки врага, которые команда ИИ видела) — их читает
скрипт ИИ.

## Поведение BARbarian (профиль `hard` = профиль по умолчанию)

Сам ИИ — бинарник CircuitAI в движке; игра несёт только конфиги
`luarules/configs/BARb/stable/config/hard/*.json` и скрипты `script/hard/*.as`.

| Требование | Где | Что сделано |
|---|---|---|
| Не отводить раненых юнитов | `behaviour.json` → `retreat.fighter = [0,0,0]` | третий элемент — множитель per-unit `retreat`, 0 обнуляет и их; строители отступают как раньше |
| Меньше рабочих, больше башен | `behaviour.json` лимиты `armck/corck/armcv/corcv=4`, `beaver/muskrat=2`, T2 cons=5; `factory.json` вероятность строителей ×0.6; `build_chain.json` `prevent=3`, `amount.factor=[80,56]`, длинная лестница `land`; `economy.json` `buildpower=2.0` (нано-турели) | |
| Супер-юниты | `factory.json` T3 (`armshltx`/`corgant`) `income_tier=[60,120,200,300]`, веса Bantha/Thor/Korgoth/Juggernaut подняты; лимит T3-фабрик 3 | |
| Без ранней беготни одиночек | `military.as` `AiMakeTask`: наземные рейдеры идут в общую армию (DEFEND→ATTACK), не в RAID; наземных скаутов по 2 на тип (совсем без них ИИ слеп и не находит врага); в `misc/commander.as` из открывашек убраны SCOUT | |
| Армия волнами | `military.as` `UpdateArmySize`: `quota.attack = 100 + 35/мин`, потолок 1200 (мощь ~ 9 за Stumpy, ~250 за Bantha, ≈ 0.035 × металл армии); группа копится на базе (DEFEND) и уходит в ATTACK, достигнув порога. `behaviour.json` `thr_mod.defence = [1,1]` — иначе порог случайно умножается на 2–3.3 и волны не выходят. Если волны не было `WAVE_MAX_GAP` (7 мин) — порог опускается до текущей армии. Каждая волна пишется в infolog: `[custom] ATTACK wave launched at Nmin` | константы `ATTACK_BASE/PER_MIN/CAP`, `WAVE_MAX_GAP` |
| Больше экономики | `economy.json`: `factor` энергии выше и раньше, `production` ниже (новые фабрики раньше), `mex_up=6`; лимит T1-фабрик 2, T2 3 | |
| Антиядерки с дублированием | `build_chain.json` `base`: индекс 14 (`armamd`/`corfmd`) на 1250, 1500, 2100, 2700, 3300, 4200 с; `military.as` `UpdateAntiNukes`: `maxThisUnit = 2 + 2 × известных ядерок врага` (до 8), при росте числа — заказ с приоритетом HIGH у каждой базы | |
| Массовая авиаразведка | `military.as` `UpdateAirScouting`: каждые 6 мин квота скаутов 8 и +4 `armpeep`/`corfink` с фабрики, потом квота 2; лимит peep/fink 10, вес в `factory.json` ×1.6 | |
| Щиты на поздней стадии | `build_chain.json` `base`: индекс 28 (`armgate`/`corgate`) с 1600 с и далее; `military.as` `UpdateShields`: с 25-й минуты каждые 8 мин по щиту на каждую базу (лимит 12) | |

Базы для заказов (`misc/base.as`) — позиции собственных фабрик (`Factory::AiUnitAdded`).
Каждые 2 минуты ИИ пишет в infolog строку `[custom] t=… quota.attack=… m-income=… armyCost=…`.

## Как проверять без человека

Headless ИИ против ИИ (~2 мин реального времени на 40 игровых минут):

```
spring-headless.exe --isolation --write-dir <data> <startscript>
```

Стартскрипт — `tools/headless_testing/startscript_barb_smoke.txt` с
`debugcommands=1:setmaxspeed 60|2:setminspeed 30|72000:quitforce;` и модопциями `ai_bonus_*`.
В infolog: `[custom] …` (ИИ), `[census] …` (гаджет `dbg_ai_census.lua`, включить на время
теста `enabled = true`), ошибки Lua/AngelScript. Визуально — e2e из репо
`beyond-all-reason` (`tools/desktop/bar-e2e.py`) с BARbarian вместо Inactive AI.
