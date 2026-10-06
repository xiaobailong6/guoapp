# Android Actions 修改总结与复用指南

## 适用范围与成功基线

- 源码基线：`0.3.4+2110`，Flutter `3.47.4`，根包 Dart 语言版本下限 `3.12`，Java `17`，Android NDK `28.2.13676358`，Go 版本由 `native/go.mod` 指定。
- 用户在本轮反馈 Android 与 Windows 均已编译成功。本次仅核对当前源码并整理文档，没有重新运行 Actions、本机编译或设备验收。
- 本文总结本轮 Actions 构建修复，不是应用业务功能变更清单。详细失败历史见 `ACTIONS_FIXES.md`；Windows 专属修复见 `WINDOWS_BUILD_FIXES.md`。
- 红果版不带构建参数，全站源真果版使用 `--all-sources`。复制修复时应合并具体配置，不应覆盖更新后的整份业务源码。

## 需要保留的文件和修改

| 文件 | 最终保留内容 | 下次更新源码的注意事项 |
| --- | --- | --- |
| `.github/workflows/build.yml` | SDK 目录定位 NDK、导出 `ANDROID_NDK_HOME`、缺失时定位 sdkmanager 安装；Flutter/Java 工具链及共用 checks | 不再假设 sdkmanager 已在 PATH 中 |
| `android/app/build.gradle.kts` | `ndkVersion = "28.2.13676358"` | 与工作流及原生脚本同步升级 |
| `scripts/build_native.py` | Android NDK 回落版本 `28.2.13676358`，优先使用 `ANDROID_NDK_HOME` | 不混用另一版本的 Go C 共享库 |
| `pubspec.lock` | 保留本轮修复后的依赖版本与真实归档 SHA-256 | 不复制旧锁文件覆盖新增依赖，不删除 enforce-lockfile |
| `analysis_options.yaml` | 保留三条有效的历史风格 lint 关闭配置及已有分析设置 | 后两条诊断最终直接修复了源码，详见下文 |
| Dart 源码及测试 | 按 Dart 3.12 整理排版，清理未使用参数和多余导入 | 更新源码后仍需实际格式化，固定 CI 参数本身不会重排源码 |
| `scripts/package_release.py` | 显式 UTF-8 读取 pubspec 版本 | 此改动两平台共享，主要解决 Windows 编码问题 |
| `scripts/configure_signing.py` | CI 缺 Secrets 时中止构建；解码后校验 JKS/PKCS12 文件头魔数 | 升级签名密钥时保留四个 Secret 名称与魔数校验 |

NDK 三处版本是本轮核对确认保留的耦合配置，不表示三份文件本轮都重新改写过。

## Android 专属修复：NDK 定位

原失败为 `sdkmanager: command not found`。当前工作流先使用 runner 已安装的指定 NDK，不存在时再在 SDK 下定位 sdkmanager，安装完成后确认目录存在并写入环境变量：

```bash
sdk_root="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
ndk="$sdk_root/ndk/28.2.13676358"
if [ ! -d "$ndk" ]; then
  sdkmanager=$(find "$sdk_root" -maxdepth 4 -name sdkmanager -type f 2>/dev/null | head -n 1)
  if [ -n "$sdkmanager" ]; then
    yes | "$sdkmanager" "ndk;28.2.13676358"
  fi
fi
if [ -d "$ndk" ]; then
  echo "ANDROID_NDK_HOME=$ndk" >> "$GITHUB_ENV"
  exit 0
fi
ls "$sdk_root/ndk" || true
echo "缺少 Android NDK 28.2.13676358：$ndk" >&2
exit 1
```

升级 NDK 必须同时修改：

1. `android/app/build.gradle.kts` 的 `ndkVersion`。
2. `scripts/build_native.py` 的默认 NDK 目录版本。
3. 工作流该步骤的目录、安装参数和错误提示中的版本。

## 两平台共用 checks 修复

### 依赖锁文件

历史锁文件中 `objective_c 9.6.1` 被撤回，导致 `flutter pub get --enforce-lockfile` 退出 65。最终保留的修复版本：

| 包 | 修复后锁定版本 |
| --- | --- |
| objective_c | 9.6.2 |
| dbus | 0.8.0 |
| file_picker_linux | 2.0.1 |
| jni | 1.1.0 |
| package_info_plus | 10.2.2 |
| wakelock_plus | 1.8.1 |

包的 SHA-256 以当前 `pubspec.lock` 为准。不要手写未经核对的归档哈希，也不要使用历史整文件哈希判断新锁文件；增加依赖后应以 CI 工具链重新解析结果为准。

### 格式与静态分析

工作流最终命令：

```text
dart format --language-version 3.12 --output=none --set-exit-if-changed lib test integration_test test_driver
dart analyze lib test integration_test test_driver
```

源码更新曾重新带入不同排版规则，35 个文件被 CI 判为需格式化；随后测试文件修改漏掉方法间空行，又造成单文件失败。需要整理源码时使用：

```text
dart format --language-version 3.12 -o write lib test integration_test test_driver
```

语言版本取根包 `pubspec.yaml` 的 SDK 下限，不取安装的 Dart SDK 最新版本，也不取锁文件中传递依赖要求的 SDK 下限。升级根包下限后需同步调整工作流及排版。

`analysis_options.yaml` 当前关闭以下五个名称：

```yaml
linter:
  rules:
    curly_braces_in_flow_control_structures: false
    prefer_initializing_formals: false
    prefer_interpolation_to_compose_strings: false
    unnecessary_import: false
    unused_element_parameter: false
```

其中 `unnecessary_import` 与 `unused_element_parameter` 属于 analyzer 诊断，放在 linter.rules 下未解决实际诊断；最终通过源码清理解决：

- `test/live_screen_test.dart` 移除 `_FakeRepository` 从未传值的 `extraGroups`、`failGroups` 参数、字段及无效分支，保留默认测试行为和方法间空行。
- `lib/video_enhancement.dart`、`lib/video_output_size.dart` 删除多余 `dart:ui` 导入，所用类型由 Flutter services 提供。

不要将上述两个 false 配置当成有效的 analyzer 错误豁免，也不要为绕过错误而关闭整个分析步骤。

### 暂停测试不阻断出包

`strict_tests` 是 workflow_dispatch 的字符串 choice，默认 `false`。两组 Flutter 测试与两组 Go race 测试分别保留：

```yaml
continue-on-error: ${{ github.event.inputs.strict_tests != 'true' }}
```

此策略不表示测试已通过。Python 脚本检查、依赖解析、格式和分析仍强制阻断。严格测试模式选 `true` 时，测试失败重新阻断。

## 构建、签名与发布链路（既有逻辑）

`build_android.py` 的既有链路是：原生 Go 核心编译 → enforce-lockfile → Flutter Release APK → package_release 校验与命名。全站源标志同时传入 Go 与 Flutter，不能只执行 flutter build 后复用旧核心。

```text
python scripts/build_android.py
python scripts/build_android.py --all-sources
python scripts/build_android.py --all-sources --abi arm64-v8a
```

这些命令仅供具备工具链的环境使用，本次文档任务未执行。

产物在 `dist/android/`：`<edition>-<version>-<abi>.apk` 和 `SHA256SUMS.txt`。发布脚本检查 APK 内核心、Flutter、mpv、FFmpeg 库及原生核心记录与打包字节一致性，保留这些校验。

Actions 签名由 `configure_signing.py` 使用仓库 Secrets 注入，之后 `if: always()` 清理签名文件。保留现有 Secret 名称，不将密钥、key.properties 或签名文件写入复用文档及源码归档。

### 本轮签名改动：固定正式签名与提前报错

为让 GitHub Actions 每次产物都用同一正式签名（Android 更新 APK 可直接覆盖升级、无需先卸载），`scripts/configure_signing.py` 本轮新增两条校验：

1. **CI 缺 Secrets 直接失败**：脚本用 `GITHUB_ACTIONS == 'true'` 区分 CI 与本机。CI 上四个 `ANDROID_KEYSTORE_*` Secrets 全空时直接 `raise SystemExit` 中止构建，不再静默生成随机签名预览 APK；四个 Secrets 部分缺失时报"需同时配置全部四个"。本机全空仍保留预览 APK 行为（exit 0），不阻塞本地开发。
2. **解码后魔数校验**：Base64 解码写盘前检查文件头——JKS 固定以 `FE ED FE ED` 开头、PKCS12 以 `30 82` 开头。若头不对立即报"不是有效的 Java 签名文件"，提示重新复制 Base64 并确认未截断。这能把"Secret 值损坏"提前暴露在配置步骤，而不是拖到 Gradle `packageRelease` 报 `DerInputStream.getLength(): lengthTag=... too big`。

复现的失败日志：CI 的 `configure_signing.py` 正常打印"已配置固定 Android 发布签名"，但后续 `:app:packageRelease` 读 keystore 报 `lengthTag=109, too big`，根因是仓库里 `ANDROID_KEYSTORE_BASE64` Secret 值在复制时被截断/改动，解码出的字节不是有效 JKS。四个 Secret 与既有 `android/app/build.gradle.kts` 的 release 签名回退逻辑、workflow 的 signing → build → `--clean` 顺序保持不变。

升级正式签名密钥时：重新用 `keytool` 生成 JKS，重新填写仓库四个 Secrets，并保留 `configure_signing.py` 的魔数校验；不要在 CI 里回退 debug 签名。

### 签名 Secrets 配置与更新

本文件被 `sync_source.py` 打进源码镜像与压缩包，因此**不写入实际密钥值、key.properties 或 JKS 内容**。四个 Secret 的名称、来源、生成与填写命令如下，按此即可在新环境重新配置并保证每次 CI 产物可用同一签名覆盖升级：

| Secret 名称 | 来源 / 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | JKS 文件的 Base64（单行、无换行、无截断） |
| `ANDROID_KEYSTORE_PASSWORD` | 签名文件口令（`keytool` 的 `-storepass`） |
| `ANDROID_KEY_ALIAS` | 密钥别名（`keytool` 的 `-alias`） |
| `ANDROID_KEY_PASSWORD` | 密钥口令（`keytool` 的 `-keypass`，可与 storepass 相同） |

首次或换密钥时，在**本机**（不是 GitHub）生成正式 JKS 并保存到项目外（如 `E:\Github Local\keystore\zhenguojian-release.jks`）：

```powershell
New-Item -ItemType Directory -Force -Path "E:\Github Local\keystore"
keytool -genkeypair -v `
  -keystore "E:\Github Local\keystore\zhenguojian-release.jks" `
  -storetype JKS -alias zhenguojian -keyalg RSA -keysize 2048 -validity 10000 `
  -storepass "<你的文件口令>" -keypass "<你的密钥口令>" `
  -dname "CN=ZhenGuoJian, OU=Dev, O=GuoJian, L=Hangzhou, S=Zhejiang, C=CN"
```

导出 `ANDROID_KEYSTORE_BASE64` 的值（**确认输出单行、以 `u3+7Q` 开头、`Y5U=` 结尾、末尾无换行**）：

```powershell
[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("E:\Github Local\keystore\zhenguojian-release.jks"))
```

然后到仓库 **Settings → Secrets and variables → Actions**，用上面的值新增/覆盖 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 四个 Secret。

**必须遵守**：
- 本机 `android/key.properties`（格式 `storeFile=...` / `storePassword=...` / `keyAlias=...` / `keyPassword=...`）仅存在于项目内，已被同步排除，不入库。
- 密钥与密码**只能**存在本机 keystore 目录和 GitHub Secrets 中，任何入库行为都会让正式签名公开失效。
- 生成后可自检 JKS 有效：`keytool -list -keystore "<你的jks>" -storetype JKS -storepass "<你的口令>"`，能列出 `zhenguojian` 私钥条目即为有效。
- 若 CI 的 `configure_signing.py` 报"不是有效的 Java 签名文件"，说明 `ANDROID_KEYSTORE_BASE64` 值被截断或含换行，重新按上述命令导出后覆盖。

## 下次更新源码的核对顺序

1. 合并当前锁文件、共用 checks、NDK 定位修复，保留新增业务依赖及源码。
2. 确认 NDK 三处版本一致、Java 17 和 Flutter 版本符合当前构建输入。
3. 对修改过的 Dart 文件按根包语言版本整理格式；本机无工具链时交给 Actions 确认，不声称本地检查通过。
4. 在 GitHub Actions 先看 checks，再看 Android 原生构建、Gradle、发布校验和产物上传，不只看最后退出码。
5. 构建成功后设备安装、真实播放和 Android TV 行为仍需单独验收。

本文已加入 `scripts/sync_source.py` 的源码白名单，与 README、ACTIONS_FIXES 一同保留在源码镜像及压缩包中。
