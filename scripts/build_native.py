import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path

from app_build import BuildVariant, add_variant_argument, record_native_build

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['android', 'windows', 'darwin'], required=True)
parser.add_argument('--abi', action='append', choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
add_variant_argument(parser)
options = parser.parse_args()
variant = BuildVariant(options.all_sources)

environment = os.environ.copy()
environment.setdefault('GOPROXY', 'https://goproxy.cn,direct')
environment.setdefault('GOSUMDB', 'off')
environment['CGO_ENABLED'] = '1'
go = shutil.which('go')
if not go:
    raise SystemExit('请先安装 Go 1.24.1 或更新版本。')
bootstrap_env = environment.copy()
bootstrap_env['GOSUMDB'] = os.environ.get('GOSUMDB', 'sum.golang.org')
if bootstrap_env['GOSUMDB'] == 'off':
    bootstrap_env['GOSUMDB'] = 'sum.golang.org'
toolchain_root = subprocess.check_output([go, 'env', 'GOROOT'], cwd=root / 'native',
    env=bootstrap_env, text=True).strip()
go = str(Path(toolchain_root) / 'bin' / ('go.exe' if platform.system() == 'Windows' else 'go'))

def build(goos, architecture, compiler, output, extra=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    build_env = environment.copy()
    build_env.update(GOOS=goos, GOARCH=architecture, CC=str(compiler))
    if extra:
        build_env.update(extra)
    print('Building ' + str(output.relative_to(root)), flush=True)
    subprocess.run([go, 'build', '-trimpath', '-buildmode=c-shared',
                    '-ldflags=' + variant.linker_flags, '-o', str(output), './bridge'],
                   cwd=root / 'native', env=build_env, check=True)
    record_native_build(output, variant, platform=goos, architecture=architecture)

def resolve_ndk(sdk):
    """选择与 Gradle 一致的 NDK 目录。

    工作流会先把选定版本写入 ANDROID_NDK_HOME，因此优先采用该值；
    未提供时再按版本排序选择：优先 28.2.13676358，否则取最高版本。
    """
    candidates = [os.environ.get('ANDROID_NDK_HOME'), os.environ.get('ANDROID_NDK_ROOT')]
    versions = sdk / 'ndk'
    if versions.is_dir():
        installed = sorted((item.name for item in versions.iterdir() if item.is_dir()),
                           key=lambda name: [int(part) if part.isdigit() else part
                                             for part in name.replace('-', '.').split('.')])
        preferred = '28.2.13676358'
        if preferred in installed:
            installed.remove(preferred)
            installed.append(preferred)
        candidates.extend(str(versions / name) for name in reversed(installed))
    for candidate in candidates:
        if candidate and (Path(candidate) / 'toolchains').is_dir():
            return Path(candidate)
    raise SystemExit('请设置 ANDROID_NDK_HOME 或在 SDK 的 ndk 目录中安装 NDK。')

if options.platform == 'android':
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise SystemExit('请设置 ANDROID_HOME 为 Android SDK 目录。')
    ndk = resolve_ndk(Path(sdk))
    host = {'Darwin': 'darwin-x86_64', 'Linux': 'linux-x86_64', 'Windows': 'windows-x86_64'}[platform.system()]
    compilers = ndk / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    mappings = {
        'arm64-v8a': ('arm64', 'aarch64-linux-android26-clang'),
        'armeabi-v7a': ('arm', 'armv7a-linux-androideabi26-clang'),
        'x86_64': ('amd64', 'x86_64-linux-android26-clang'),
    }
    for abi in options.abi or list(mappings):
        architecture, name = mappings[abi]
        compiler = compilers / (name + ('.cmd' if platform.system() == 'Windows' else ''))
        if not compiler.exists():
            raise SystemExit('缺少 Android NDK 编译器：' + str(compiler))
        output = root / 'android' / 'app' / 'src' / 'main' / 'jniLibs' / abi / 'libduanju_core.so'
        extra = {'CGO_LDFLAGS': '-Wl,-z,max-page-size=16384'}
        if architecture == 'arm':
            extra['GOARM'] = '7'
        build('android', architecture, compiler, output, extra)
elif options.platform == 'windows':
    compiler = shutil.which('x86_64-w64-mingw32-gcc') or (shutil.which('gcc') if platform.system() == 'Windows' else None)
    if not compiler:
        raise SystemExit('请安装 MinGW-w64，并将其 bin 目录加入 PATH。')
    build('windows', 'amd64', compiler, root / 'windows' / 'runner' / 'duanju_core.dll',
          {'CGO_LDFLAGS': '-static-libgcc'})
else:
    compiler = shutil.which('clang')
    if not compiler:
        raise SystemExit('需要安装 Xcode Command Line Tools。')
    build('darwin', 'arm64' if platform.machine() == 'arm64' else 'amd64', compiler,
          root / 'native' / 'build' / 'darwin' / 'libduanju_core.dylib')
