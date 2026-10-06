# Windows Actions 修改总结与复用指南

## 适用范围与成功基线

- 源码基线：`0.3.4+2110`；Flutter `3.47.4`，Python `3.12`，x64 Release，Go 版本由 `native/go.mod` 指定，原生核心使用 MinGW-w64。
- 用户在本轮反馈 Android 和 Windows 均已编译成功。本次仅核对源码、整理文档，没有重新运行 Actions 或本机验证；成功反馈未附新 run ID，不虚构成功日志证据。
- 本文记录最终有效方案，失败历史见 `ACTIONS_FIXES.md`。两平台共用的锁文件、格式、分析和 strict_tests 修复见 `ANDROID_BUILD_FIXES.md` 的“共用 checks”部分，同样适用于 Windows。
- 正常播放器业务没有因本轮 Windows 冒烟修复而修改；最终轨道选择修改仅在 `lib/package_smoke.dart`。

## 修改文件速查

| 文件 | 最终修改 | 解决的问题 |
| --- | --- | --- |
| `.github/workflows/build.yml` | 直接 choco 安装 MinGW，定位 gcc 并写入 GITHUB_PATH；始终尝试上传冒烟诊断 | 旧 setup-mingw action 删除不存在的库失败；失败报告不可见 |
| `windows/CMakeLists.txt` | 纯路径安装前缀；安装目标显式追加配置目录；MSVC 运行库同目录；native assets OPTIONAL；必要源文件诊断 | 生成器表达式成为字面路径、安装目录分散、可选目录缺失 |
| `scripts/build_windows.py` | UTF-8 控制台、verbose Flutter 输出、失败时列出资源并重放 CMake 安装 | MSB3073 隐藏底层安装错误 |
| `scripts/package_release.py` | UTF-8 读取 pubspec 版本 | cp1252 解码中文失败 |
| `scripts/smoke_windows.py` | UTF-8 文件读写；先保存/打印报告再判定失败；捕获进程输出和超时 | 编码失败、提前抛错导致错误报告被删除 |
| `lib/package_smoke.dart` | 打开媒体前 `setVideoTrack(VideoTrack.auto())` | 默认 vid=no 且关闭音频导致播放进度超时 |
| `scripts/sync_source.py` | 收录 ACTIONS_FIXES 及两平台总结文档 | 源码同步/归档遗漏复用记录 |

## 1. MinGW 安装

旧 `egor-tensin/setup-mingw@v2` 的 workaround 假设 `libpthread.dll.a` 存在，新 MinGW 包结构变化后删除失败。保留当前工作流步骤：

```powershell
choco install mingw --no-progress -y
$roots = 'C:\ProgramData\mingw64', 'C:\ProgramData\chocolatey\lib\mingw'
$bin = $roots | ForEach-Object { Join-Path $_ 'mingw64\bin' } |
  Where-Object { Test-Path (Join-Path $_ 'x86_64-w64-mingw32-gcc.exe') } | Select-Object -First 1
if (-not $bin) {
  $found = Get-ChildItem $roots -Recurse -Filter 'x86_64-w64-mingw32-gcc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $bin = $found.Directory.FullName }
}
if (-not $bin) { throw '未找到 MinGW-w64 的 x86_64-w64-mingw32-gcc.exe' }
$bin | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
& (Join-Path $bin 'x86_64-w64-mingw32-gcc.exe') --version
```

更新 Chocolatey 包或 runner 镜像后核对目录结构及 gcc 名称；不恢复无条件删除旧库文件的 action。

## 2. CMake 安装目录：只使用最终方案

当前最终代码：

```cmake
set(BUILD_BUNDLE_DIR "${CMAKE_BINARY_DIR}/runner")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/$<CONFIG>")
set(INSTALL_BUNDLE_DATA_DIR "${INSTALL_BUNDLE_LIB_DIR}/data")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

MSVC 运行库也必须使用相同安装目标：

```cmake
set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION "${INSTALL_BUNDLE_LIB_DIR}")
set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT Runtime)
include(InstallRequiredSystemLibraries)
```

在当前 x64 Release 构建中：

| 配置/路径 | 最终值或用途 |
| --- | --- |
| CMAKE_BINARY_DIR | build/windows/x64 |
| CMAKE_INSTALL_PREFIX | build/windows/x64/runner |
| 安装目标追加 `$<CONFIG>` | build/windows/x64/runner/Release |
| 数据目录 | build/windows/x64/runner/Release/data |
| 发布脚本查找目录 | build/windows/x64/runner/Release |

可执行文件、Flutter DLL、插件及其 bundled libraries、Go 核心、native assets、MSVC 运行库必须使用 INSTALL_BUNDLE_LIB_DIR；ICU、AOT、Flutter 资源使用 INSTALL_BUNDLE_DATA_DIR。更新其中一处时检查其余安装目标和 package_release 的目录一致性。

### 不要复用的中途方案

- 不将 `$<TARGET_FILE_DIR:...>` 写入 CMAKE_INSTALL_PREFIX 缓存：安装脚本曾将其当作字面路径，触发 file cannot create directory。
- 不使用 `${PROJECT_BUILD_DIR}/runner`：当前 PROJECT_BUILD_DIR 指向顶层 build，曾安装到 build/runner。
- 仅使用 `${CMAKE_BINARY_DIR}/runner` 作为最终文件目标仍不足：DLL 会安装到 runner，而 exe 在 runner/Release。
- CMake 多配置安装不会自动追加 Release，必须显式指定 `$<CONFIG>`。
- 不将 CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION 留为 `.`，否则 MSVC DLL 会相对纯路径前缀安装到 runner，发布脚本仍缺件。
- 不通过降低 package_release 缺件检查来掩盖目录错误。

## 3. native assets 与安装诊断

保留以下安装期可选语义：

```cmake
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  OPTIONAL
  COMPONENT Runtime)
```

目录存在时正常安装，不存在时允许跳过。不要换成配置期 `if(EXISTS)`，否则可能漏掉构建期才生成的 assets。其他必需资源仍保持强制安装和检查。

当前 CMake 在缺少必需源文件时写入 install_error.txt 并明确失败；build_windows.py 使用 verbose 输出，失败时列出源文件存在性、Release bundle 内容，读取 install_error.txt，并从 CMakeCache 找到 cmake 重放安装脚本。保留这些诊断，不只依赖笼统的 MSB3073 返回码。

## 4. Windows Python 编码

Windows runner 的默认文本编码曾为 cp1252，无法读取含中文的 UTF-8 pubspec。最终保留：

```python
(root / 'pubspec.yaml').read_text(encoding='utf-8')
report.read_text(encoding='utf-8')
output.write_text(content, encoding='utf-8')
```

适用文件：package_release.py 的版本读取；smoke_windows.py 的版本与报告读取、报告写出。构建脚本自身的控制台重配置不等于子进程文件读取编码已修复，必须分别指定。

## 5. 冒烟检查的最终轨道配置

lib/package_smoke.dart 通过包内原生核心初始化、FFprobe、转封装、再次探测，然后用 media_kit 播放合成视频。锁定的 media_kit 1.2.6 默认 `vid=no`，普通界面由 VideoController 启用视频；冒烟流程未挂接该控制器且关闭音频，原先所有轨道都关闭，等待进度 20 秒超时。

最终保留：

```dart
player = Player(
  configuration: const PlayerConfiguration(muted: true, vo: 'null'),
);
await player.setAudioTrack(AudioTrack.no());
await player.setVideoTrack(VideoTrack.auto());
final advancing = player.stream.position.firstWhere(
  (time) => time.inMilliseconds >= 400,
);
await player.open(Media(remuxed.path));
await advancing.timeout(const Duration(seconds: 20));
```

不靠延长超时或删除进度检查解决该问题。vo=null 的检查验证包内引擎加载和播放进度，不等于真实画面呈现、硬件解码、声音输出和设备交互已验收。

## 6. 失败报告必须先保存，再判定失败

smoke_windows.py 原先使用 check=True，在读取 result.json 前抛错，临时目录退出时报告被删除，日志只能看到 exit 1。

当前流程保留以下顺序：

1. 解压发布包，FFmpeg 生成 3 秒合成视频。
2. 启动 `<edition>.exe --package-smoke <report> <media>`，捕获 stdout、stderr、退出码，90 秒进程超时。
3. 读取应用报告；缺失/非法 JSON/超时分别记入诊断。
4. 保存到 build/windows-package-smoke.json 并打印到 Actions 日志。
5. 退出码非零或报告 ok 不为 true 时仍失败。

工作流诊断上传使用 `if: always()`，产物名为 `<edition>-windows-smoke-diagnostics`，报告不存在时忽略。正式安装包上传仍在前置步骤成功后执行，不将冒烟失败的包当成通过版本。

## 构建与产物（既有逻辑）

```text
python scripts/build_windows.py
python scripts/build_windows.py --all-sources
python scripts/smoke_windows.py --all-sources
```

命令仅用于有 Windows Flutter/MSVC/Go/MinGW 环境的机器，本次未执行。

build_windows.py 的链路：Go 共享库编译 → enforce-lockfile → Flutter Release → package_release。发布脚本从 runner/Release 校验并打包全部文件，将 exe 名称按 edition 调整，生成 dist/windows/<edition>-<version>-windows-x64.zip 及 SHA256SUMS.txt。

保留必需文件检查：zhenguojian.exe、duanju_core.dll、flutter_windows.dll、libffmpegkit.dll、libmpv-2.dll、msvcp140.dll、vcruntime140.dll、data/icudtl.dat、data/app.so。所需的其他插件库及 Flutter assets 也随整个 bundle 归档，不只复制上述必需清单。

## 下次更新源码的核对顺序

1. 合并本文文件速查中的最终修复，保留新增业务代码与依赖；共用 checks 参考 Android 文档。
2. 确认 CMake 前缀是纯路径，安装目标显式包含配置名；所有库及数据路径与发布脚本一致。
3. 升级 Flutter、media_kit 或 MinGW 后核对模板、默认轨道和目录结构，不机械照搬旧版本假设。
4. Actions 依次检查工具链、Go 核心、Flutter/MSBuild、CMake 安装、包校验、启动检查和上传。
5. 失败优先看底层错误、应用报告及 smoke diagnostics，避免根据最后 Python 退出码猜测根因。
6. 构建成功后，实际 Windows 画面播放、声音、下载、画质增强及用户交互仍需单独验收。

本文已加入 scripts/sync_source.py 的顶层 SOURCE_FILES，随源码镜像和归档保留。Android 与 Windows 文档仅用于用户要求的修复复用留档，日常使用说明仍以 README.md 为准。
