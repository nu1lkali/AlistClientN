# AGENTS.md

## Project overview

Flutter (Dart) Android client for [Alist](https://github.com/alist-org/alist) file servers. Package name: `alist`. Primarily Chinese UI with English fallback via GetX translations.

## Flutter version

Pinned to **Flutter 3.13.8** via FVM (`.fvm/fvm_config.json`). Use `fvm flutter` instead of `flutter` if FVM is installed, otherwise ensure your global Flutter matches.

## Key commands

```bash
flutter pub get                          # install dependencies
dart run build_runner build              # regenerate Floor DB code (required after editing database/ files)
flutter build apk --release --no-tree-shake-icons   # production build
flutter analyze                          # static analysis
flutter test                             # run tests (only widget_test.dart exists)
```

**Codegen is mandatory before build**: The Floor ORM generates `lib/database/alist_database.g.dart`. After changing any `@Entity` table or `@Dao` class, run `dart run build_runner build` or the build will fail.

## Architecture

- **State management / routing**: GetX (`get` package). Routes defined in `lib/router.dart` using `GetPage`; route names in `lib/util/named_router.dart`.
- **Entry point**: `lib/main.dart` — initializes SpUtil, MediaKit, Bugly (release only), proxy override, then launches `MyApp` (GetMaterialApp).
- **Global controllers** registered in `_routerBuilder`: `AlistDatabaseController`, `UserController`, `ProxyServer`, `SecurityLockController`.
- **Theme**: reactive via `ThemeController` (Material 3, `ColorScheme.fromSeed`).
- **HTTP**: Dio (`lib/net/`). Proxy bypass for LAN addresses via `AlistHttpOverrides`.
- **Database**: Floor ORM over SQLite. DB version 8. DAOs in `lib/database/dao/`, tables in `lib/database/table/`.
- **Localization**: `lib/l10n/` with `AlistTranslations` (GetX pattern). String keys in `lib/l10n/intl_keys.dart`.

## Directory layout

| Path | Purpose |
|---|---|
| `lib/screen/` | All screens/pages (30+). Subdirs for complex features: `file_list/`, `iptv/`, `security/` |
| `lib/widget/` | Reusable widgets |
| `lib/net/` | HTTP layer (Dio utils, interceptors, error handling) |
| `lib/database/` | Floor ORM: `alist_database.dart` (abstract DB), `dao/`, `table/`, generated `.g.dart` |
| `lib/util/` | Utilities, controllers, helpers (30+ files) |
| `lib/generated/` | Generated code (color schemes, image refs, JSON models) |
| `lib/l10n/` | Localization files |
| `lib/entity/` | API response entities |
| `assets/images/` | Bundled image assets |
| `android/` | Android native code, Gradle config, native libs (`libs/`), docviewer module |

## Android specifics

- `minSdkVersion 26`, `compileSdk 36`, NDK `26.1.10909125`
- Java 11 compatibility, Kotlin with Compose dependencies
- Signing config read from `local.properties` (`keyAlias`, `keyPassword`, `storeFile`, `storePassword`)
- ABI splits enabled: `armeabi-v7a`, `arm64-v8a`, `x86_64` + universal
- ProGuard enabled for release builds
- Native modules: `docviewer` (local project module), `mpv-android-lib` (local AAR in `libs/`)
- Key native deps: GSYVideoPlayer, PhotoView, Jetpack Compose, Room, Koin, Media3

## Gotchas

- `flutter_aliplayer` is sourced from a Git repo (`GeekTR/flutter_aliplayer`, branch `feature/5.5.6.0`), not pub.dev.
- `dependency_overrides` pins `win32`, `sqflite_common`, `sqflite`, `sqflite_common_ffi` — do not remove without checking compatibility.
- `flutter_aliplayer` and `media_kit` both bundle native `.so` files; `packagingOptions` uses `pickFirst` to resolve conflicts.
- Bugly crash reporting only initializes in release mode (`kReleaseMode`).
- The `_SecurityLockWrapper` uses `Offstage` (not removal) to preserve navigation state when locked.
- Audio player has two UI styles toggled by `AlistConstant.audioPlayerUiStyle` (0=classic, 1=v2).
- Database migration: version 8 with 8 entity tables. Migrations must be added in `alist_database.dart` when schema changes.
