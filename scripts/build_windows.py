import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from build_mirrors import china_mirror_environment, mirrored_pub_lockfile
from app_build import BuildVariant, add_variant_argument

root = Path(__file__).resolve().parents[1]


def find_cmake(build_dir):
    cache = build_dir / 'CMakeCache.txt'
    if cache.is_file():
        for line in cache.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('CMAKE_COMMAND:INTERNAL='):
                candidate = Path(line.split('=', 1)[1])
                if candidate.is_file():
                    return str(candidate)
    return shutil.which('cmake')


def diagnose_windows_install(build_dir, env):
    print('[诊断] Windows 安装步骤失败，输出 CMake 原始报错：', flush=True)
    sources = (root / 'build' / 'native_assets' / 'windows', root / 'build' / 'flutter_assets',
               root / 'build' / 'windows' / 'app.so', root / 'windows' / 'runner' / 'duanju_core.dll')
    for path in sources:
        print(f'[诊断] {"存在" if path.exists() else "缺失"} {path}', flush=True)
    bundle = build_dir / 'runner' / 'Release'
    if bundle.is_dir():
        print('[诊断] 安装目录内容：' + ' '.join(sorted(item.name for item in bundle.iterdir())), flush=True)
    cmake = find_cmake(build_dir)
    script = build_dir / 'cmake_install.cmake'
    if not cmake or not script.is_file():
        print(f'[诊断] 无法重放安装脚本（cmake={cmake}，脚本存在={script.is_file()}）', flush=True)
        return
    print('[诊断] 重放安装脚本以显示 CMake 原始报错', flush=True)
    result = subprocess.run([cmake, '-DBUILD_TYPE=Release', '-P', 'cmake_install.cmake'], cwd=build_dir, env=env)
    print(f'[诊断] 重放安装脚本退出码：{result.returncode}', flush=True)


parser = argparse.ArgumentParser()
parser.add_argument('--cn-mirrors', action='store_true', help='使用 Flutter 中国镜像')
add_variant_argument(parser)
options = parser.parse_args()
variant = BuildVariant(options.all_sources)
environment = os.environ.copy()
environment.setdefault('GOPROXY', 'https://goproxy.cn,direct')
environment.setdefault('GOSUMDB', 'off')
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('请先将 Flutter SDK 的 bin 目录加入 PATH。')
with china_mirror_environment(environment, options.cn_mirrors, gradle=False) as env:
    with mirrored_pub_lockfile(root, env):
        subprocess.run([sys.executable, str(root / 'scripts' / 'build_native.py'), '--platform', 'windows', *variant.arguments],
                       cwd=root, env=env, check=True)
        subprocess.run([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=root, env=env, check=True)
        try:
            subprocess.run([flutter, 'build', 'windows', '--release', '--no-pub', *variant.flutter_arguments], cwd=root, env=env, check=True)
        except subprocess.CalledProcessError:
            diagnose_windows_install(root / 'build' / 'windows' / 'x64', env)
            raise
        subprocess.run([sys.executable, str(root / 'scripts' / 'package_release.py'), '--platform', 'windows', *variant.arguments],
                       cwd=root, env=env, check=True)
