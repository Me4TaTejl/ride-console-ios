# Ride Console

Приложение для моноколёс на iPhone с iOS 17 или новее. Стартовая версия 0.1.0.

- Гараж сохраняет подключённые колёса и может автоматически подключать последнее.
- Для каждого колеса сохраняются отдельные панели. В плитке можно комбинировать метрики, менять оформление и ширину. Порядок плиток редактируется в настройках панели. Раскладки импортируются и экспортируются в JSON.
- «Кластер: WheelLog» доступен для набора из PWM, заряда, температуры контроллера и скорости колеса. В центре выводится PWM, а скорость под ним берётся из телеметрии контроллера.
- На вкладке «Поездки» хранятся GPS-маршруты, CSV и MP4. Карта показывает линию движения, набор высоты и синхронизированную телеметрию. Для подложки Яндекс Карт используется пользовательский ключ Tiles API.
- Камера накладывает показания на полноэкранный предпросмотр и сохраняемое видео. Стробоскоп и режимы педалей доступны для поддерживаемых протоколов.
- Оповещения поддерживают несколько условий по метрикам, задержку и повтор. Доступны звук, вибрация и голос.

## Сборка

В GitHub Actions запустите Build Ride Console IPA. Процесс проверяет BLE-декодеры, набор высоты, выбор кластера и пороги оповещений. Затем собирает IPA для arm64 с Apple SDK. Артефакт RideConsole-iOS содержит неподписанный RideConsole.ipa. Для установки требуется подпись своим Apple Account, например через iLoader или SideStore.

На Mac сначала выполните:

```sh
bash WheelCore/gradlew -p WheelCore jvmTest linkReleaseFrameworkIosArm64
```

Откройте RideConsole.xcodeproj, выберите схему RideConsole и настройте подпись. Для симулятора на Apple Silicon используйте linkReleaseFrameworkIosSimulatorArm64. Аргумент запуска --demo включает демонстрационную телеметрию в симуляторе.

## Источники протокола

- [euc_ble_library](https://github.com/Tritbool/euc_ble_library) (GPL-3.0), версия 0.1.3. Используются её протоколы и очередь опроса. [Исходные BLE-записи для тестов](https://github.com/Tritbool/euc_ble_library/tree/2300f85aa52e69a44bc2ee975de0c9708437775c/euc-ble-core/src/test/resources/ble_frames) воспроизводятся с помощью `bash WheelCore/gradlew -p WheelCore jvmTest`.

- [Адаптер Veteran в WheelLog для Android](https://github.com/Wheellog/Wheellog.Android/blob/master/app/src/main/java/com/cooper/wheellog/utils/VeteranAdapter.java) и [расчёт тока и мощности](https://github.com/Wheellog/Wheellog.Android/blob/master/app/src/main/java/com/cooper/wheellog/WheelData.java)
- [Описание BLE-протокола Veteran / LeaperKim](https://github.com/eried/eucplanet/blob/main/docs/protocols/veteran.md) и [сведения о командах фары Sherman S](https://loeuc.ru/en/docs/wheels)

Классическая панель использует шрифт, пиктограммы и геометрию шкалы из [WheelLog.Android 3.2.9](https://github.com/Wheellog/Wheellog.Android/tree/3.2.9). Условия распространения приведены в [LICENSE](LICENSE).

Логотип Яндекса используется для обозначения подложки карты по [правилам Tiles API](https://yandex.ru/maps-api/docs/tiles-api/index.html#ispolzovanie-logotipa-yandeksa).
