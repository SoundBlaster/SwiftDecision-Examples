# Oracle v1: готовность бесплатного reference app

Проверено: 2026-10-26. Цель — законченная бесплатная версия, демонстрирующая SwiftDecision + SwiftJev и policies SpecificationCore. **К App Store submission пока не готово.** Первоначальный аудит был read-only; результаты последующей реализации доставки модели перечислены в R1 и delivery guide.

## Что уже есть

| Возможность | Подтверждение и граница проверки |
| --- | --- |
| Реалистичный шар, scene lifecycle, жесты, haptics | Исходники `OracleBallApp/entities/oracle-ball`; приложение ранее установлено и запущено на физическом Air. Это не полная проверка final Release UI. |
| Noul / Choice / Score и явные альтернативы | `Sources/OracleGame`, `JevOracleBackend`; автоматическая маршрутизация и SpecificationCore pipeline. Экспорты с Air подтверждают реальные GLiNER Choice-решения и abstention. Остальные типы нельзя считать проверенными на Air только по этим экспортам. |
| Jev / GLiNER / None | `OracleInferenceSettings`, `OracleInferencePreferences`; Keychain для ключа, локальная модель отдельно от bundle. |
| Policies и честный отказ | `OracleGameEngine`, `OraclePageModel`; GLiNER-only entropy-confidence slider, default 5%, winning-weight floor 55%. Нормированные оценки не равны калиброванной точности. |
| История и экспорт JSON/text | `OracleHistory`, `OracleHistoryExportMenu`, `OraclePipelineDetailView`; пользователь уже экспортировал историю и отдельные вопросы с числовыми распределениями. |
| Исправления error history и warm-up | PR #71 сохраняет сбои без выдуманного ответа/уверенности, греет Core ML до readiness. Unit/regression tests и signed Debug build проходили ранее; exact failed-first-question flow после исправления требует проверки на устройстве. |
| Текущее состояние интеграции | Однократный snapshot PR [#71](https://github.com/SoundBlaster/SwiftDecision-Examples/pull/71), SHA `a6ec9ab0c339d49c6e0dffe4da5f58b905d3615a`: iOS и architecture SUCCESS, unresolved review threads отсутствуют, PR OPEN. Это не App Store validation. При следующем кодовом изменении snapshot устаревает. |

## Что необходимо до submission

Порядок R1–R5 — приоритет реализации. R6–R8 проверяют кандидата после продуктовых изменений. Указанные ниже критерии ещё не выполнены полностью.

### R1. GLiNER без подготовки файлов разработчиком — реализация готовится, Apple delivery не проверена

**Обновление реализации:** приложение содержит Apple-hosted on-demand installer, downloader extension, progress/cancellation и checked-in SHA-256 inventory. Legacy pilot flag больше не скрывает provider. Тот же runtime упакован в отдельный licensed GitHub ZIP и Apple `.aar`; веса не входят в app bundle. Ручной import остаётся Developer import.

**Оставшиеся условия:** новый extension должен получить профиль с App Group; доступный ASC credential был отклонён Xcode provisioning authentication. Видимой записи Oracle в ASC пока нет. `.aar` ещё не загружен и реальная доставка через TestFlight/Apple не подтверждена. Нельзя считать R1 закрытым по одному успешному build/packaging. Детали: [delivery guide](EXPERIMENTS/GLINER_ORACLE_PILOT.md).

**Готово, когда:** чистая установка → явная загрузка → подготовка → реальный локальный запрос без Mac/Python/ключа; отмена, offline, недостаток места и неверный hash не ломают предыдущую модель; удаление освобождает только модель, история остаётся. До установки classic доступен. Public UI не требует скрытого launch argument или pilot-тумблера для заявленной основной функции.

### R2. Показать назначение демо и возможности библиотек

**Факт:** в настройках есть TypeSafe.ai link, но нет About / Built with, ссылок на SwiftDecision/SwiftJev/reference source или коротких воспроизводимых примеров. `OracleModeSelector` существует, но не включён в дерево `OraclePage`; основные запросы идут через automatic mode.

**План:** компактный раздел «Built with SwiftDecision + SwiftJev», ссылка на SpecificationCore и этот репозиторий, версия сборки и реальные версии/revisions зависимостей. Дать проверенные примеры Noul / Choice / Score, объяснить None / local / cloud и где смотреть pipeline. Выбрать явное управление типом в дополнительных настройках либо примеры, реально демонстрирующие все три типа через auto; не добавлять selector только ради количества контролов.

**Готово, когда:** не читавший README пользователь понимает, что делает приложение; разработчик за несколько действий видит тип, backend, outcome, tracing и находит публичный код. Ссылки рабочие. Пример не обещает конкретный ответ там, где модель вправе воздержаться.

### R3. Privacy и согласие на Jev — submission blocker

**Факт:** в исходниках приложения нет доступной privacy-policy ссылки. Есть `Sources/OracleHistory/PrivacyInfo.xcprivacy`, но manifest не заменяет policy URL и App Privacy. Выбор Jev и сохранение ключа есть; отдельное раскрытие передачи текста вопроса стороннему AI и получение согласия до первой отправки в UI не найдены.

**План:** рабочая public privacy policy + in-app link; разделить local GLiNER, локальную историю/экспорт и передачу вопроса Jev при явном выборе. Добавить информированное согласие до отправки данных Jev, дать возможность вернуться в local/classic. Экспорт — явное действие пользователя. Сверить App Privacy с реальными практиками TypeSafe/transport, проверить required-reason declarations (включая shared UserDefaults для widget) по итоговому privacy report.

**Готово, когда:** политики и UI соответствуют реальному обмену данными, до согласия cloud-запросов нет; нет встроенного общего ключа; ошибка/trace/export не раскрывают Authorization. Не заявлять «ничего не покидает телефон» для Jev. Основание: [Apple 5.1.1 и 5.1.2](https://developer.apple.com/app-store/review/guidelines/#privacy).

### R4. Лицензии и воспроизводимый артефакт модели

**Факт:** pilot-документ требует Apache-2.0 attribution Fastino. Import копирует четыре runtime-компонента; экран лицензий и distributed NOTICE/license pack в приложении не найдены. `Package.swift` фиксирует SwiftDecision по revision `d655ab6…`, SwiftJev 0.5.0, SpecificationCore 2.1.0.

**План:** проверить лицензии именно выбранного checkpoint, tokenizer и используемого конвертера; приложить требуемые тексты, NOTICE при наличии и указание преобразований. Сохранить provenance/checksum/revision модели. Пакеты фиксировать воспроизводимо; stable tag SwiftDecision предпочтителен для публичного примера, но отсутствие тега само по себе не blocker App Store. Не обновлять зависимости без отдельной задачи и проверки.

**Готово, когда:** получаемый пользователем артефакт и приложение содержат необходимые notices, раздел лицензий доступен, команда разработки может воспроизвести совместимый export.

### R5. Имя и запись App Store Connect — пока отсутствует проверяемая цель

**Факт:** `Info.plist` / `project.yml` ещё показывают Oracle, версию 1.0 и build 1. По доступному профилю asc «Agent Session Monitor» запрос `apps list --bundle-id com.soundblaster.oracleball` вернул пустой список. Это доказывает отсутствие видимой записи для этого bundle ID в выбранном профиле, а не отсутствие приложения во всех командах Apple. Поэтому `asc validate` по реальному APP_ID не выполнялся. В tracked repository не найдены release metadata package, support/privacy pages или набор App Store screenshots; существующая demo-картинка в DOCS не подтверждает готовый комплект.

**План:** выбрать имя (актуальный кандидат Endless Answers: 8 Ball); проверить доступность. Найти/создать запись в правильной ASC team, не менять bundle ID без необходимости. Подготовить EN/RU name/subtitle/description/keywords, support/privacy URL, contact/review notes, скриншоты реального бесплатного приложения. Установить цену 0, availability, category, age-rating, content rights, App Privacy и корректный export-compliance ответ. Декларации заполнять по фактам, не ставить автоматически «no encryption».

**Готово, когда:** есть однозначный APP_ID/version и заполненные обязательные поля. `asc validate --app APP_ID --version 1.0 --platform IOS` и review doctor не показывают blockers; отдельно подтверждены App Privacy и availability. IAP/subscription не требуются для v1.

### R6. Final Release archive / TestFlight — ещё не подтверждено

**Факт:** проходили package tests, simulator CI build и signed Debug installation на Air. Это не подтверждает App Store distribution signing, upload validation и поведение Release. Новая Release archive в текущем аудите не создавалась.

**План:** зафиксировать release commit, синхронизировать version/build app + widget, собрать archive с distribution signing, проверить итоговые ресурсы/Metal shaders, icon, entitlement/app group, privacy manifests и linked dependencies. Иконка `.icon` есть, её отсутствие не является найденной проблемой; проверить именно exported archive. Прогнать TestFlight build на Air.

**Готово, когда:** финальный build принят ASC и связан с версией, Release smoke пройден, версия приложения и widget согласованы. Review notes дают реальный способ проверить local и cloud функции, без публикации личного ключа или ложного fixture-ответа под видом модели. Опциональный Jev не должен делать приложение неработоспособным без ключа.

### R7. Сценарии и физическая проверка

**Факт:** последние Air exports подтверждают воспроизводимость Choice при неизменных criterion/options и честный отказ при слабом распределении. Они не доказывают универсальную семантическую корректность GLiNER. CI собирает приложения и запускает package tests; находящиеся в repo UI tests не запускаются данным workflow. Нет замера актуальной холодной подготовки, времени первого/повторного вопроса, peak memory или нагрева. Последнее изменение top inset настроек ещё не было запущено на Air в этой сессии.

- [ ] Fresh-install classic / None без ключа и модели — пользователь сразу может получить явно обозначенный simulated answer.
- [ ] Получение модели, холодная подготовка, первый и последующий запросы — реальные времена записаны отдельно; progress не выглядит зависанием.
- [ ] Noul / Choice / Score, явные альтернативы, unsupported input, abstention — верный тип/outcome в UI и экспортируемом pipeline.
- [ ] Error после очистки истории — явный статус и одна failed запись без ответа/выдуманной уверенности; superseded/cancelled requests не добавляют поздние результаты.
- [ ] Смена backend, удаление/повторная установка модели, persistence порога — нет лишних загрузок, потери истории или приписывания старого ответа новому провайдеру.
- [ ] Ошибка/timeout Jev с injected transport; реальный облачный smoke только по явному разрешению, со своим ключом и ограниченным бюджетом.
- [ ] Replay, background/foreground, widget/random deep link, export JSON/text и очистка истории работают в final Release.

Не повышать scope до бенчмарка качества модели или тренировки. Известные языковые/семантические ограничения объяснить; отказ — допустимый outcome, бесконечное ожидание или потеря запроса — нет.

### R8. Поддерживаемые устройства, доступность и локализация

**Факт:** app target — iOS/iPadOS 26+, families 1/2; iPad landscape заявлен. EN/RU строки и Reduce Motion/VoiceOver hooks есть. Наличие кода не заменяет фактическую проверку контраста, Dynamic Type и управления. UI настроек недавно исправлялся по скриншотам; финальные отступы/slider нужно проверить.

**Готово, когда:** Air + доступный iOS 26+ iPad/simulator проходят portrait/landscape, keyboard, settings sheets, history/pipeline, export; Dynamic Type и VoiceOver дают доступ к ответу/submit/slider; Reduce Motion не мешает завершению ответа. EN/RU не обрезаются и не обещают русскоязычную компетентность English checkpoint. Декларации accessibility в ASC отмечены только для проверенных возможностей.

Duo-specific polish, новые сцены и отдельный рекламный ролик не являются условиями первого выпуска. Работа в поддерживаемых обычных размерах окна остаётся необходимой.

## Что не задерживает v1

StoreKit, trial, цены, lifetime access, платные сцены/материалы, редактор пресетов, Apple Foundation Models, новые облачные providers, общий оплачиваемый ключ, калибровка/переобучение GLiNER, telemetry backend и сложные ASO-эксперименты. История, tracing и экспорт уже есть — не переносить их за будущую покупку.

## Решение о выпуске

Сначала закрыть R1–R5, затем собрать и пройти R6–R8 на том же release candidate. После зелёной readiness-проверки и отдельной команды пользователя — submission. Текущий документ не создаёт приложение в ASC, не публикует модель, не запускает платный inference, не сливает PR и не отправляет приложение на review.

Ближайшая задача: завершить provisioning/ASC setup для Apple asset pack и пройти реальную чистую установку через app UI, затем R2/R3. GitHub distribution и Apple hosting имеют отдельные статусы публикации.

## Источники

- [Продуктовый roadmap](ORACLE_PRODUCT_ROADMAP.md).
- [Текущая установка и ограничения GLiNER](EXPERIMENTS/GLINER_ORACLE_PILOT.md).
- [История и экспорт](ORACLE_HISTORY_EXPORT.md).
- Код: `project.yml`, `Package.swift`, `OracleBallApp/pages/oracle/ui/{OraclePage,OraclePageModel,OracleInferenceSettings}.swift`, `Sources/OracleGLiNER/{OracleInferencePreferences,OracleGLiNERModelStore}.swift`, `Sources/OracleHistory/PrivacyInfo.xcprivacy`, `.github/workflows/ci.yml`.
- [Apple: подготовка полного review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/).
- [Apple: App Privacy](https://developer.apple.com/app-store/app-privacy-details/).
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
