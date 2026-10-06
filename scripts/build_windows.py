import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from build_mirrors import china_mirror_environment, mirrored_pub_lockfile
from app_build import BuildVariant, add_variant_argument

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except AttributeError:
    pass

root = Path(__file__).resolve().parents[1]
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


def diagnose_failure(reason):
    print('构建失败：' + reason, flush=True)
    release = root / 'build' / 'windows' / 'x64' / 'runner' / 'Release'
    source = root / 'windows' / 'runner' / 'duanju_core.dll'
    print('必需源文件存在性：', flush=True)
    for candidate in [source]:
        print('  ' + ('存在' if candidate.is_file() else '缺失') + ' ' + str(candidate), flush=True)
    print('Release bundle 内容：', flush=True)
    if release.is_dir():
        for item in sorted(release.rglob('*')):
            if item.is_file():
                print('  ' + str(item.relative_to(release)), flush=True)
    else:
        print('  （目录不存在：' + str(release) + '）', flush=True)
    error_txt = root / 'build' / 'windows' / 'x64' / 'install_error.txt'
    if error_txt.is_file():
        print('install_error.txt：', flush=True)
        print(error_txt.read_text(encoding='utf-8'), flush=True)
    else:
        print('（未找到 install_error.txt）', flush=True)
    cache = root / 'build' / 'windows' / 'x64' / 'CMakeCache.txt'
    if cache.is_file():
        for line in cache.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('CMAKE_COMMAND:INTERNAL='):
                cmake = line.split('=', 1)[1]
                print('重放 CMake 安装：', flush=True)
                subprocess.run([cmake, '--install', str(root / 'build' / 'windows' / 'x64')],
                               cwd=root, env=environment)
                break


with china_mirror_environment(environment, options.cn_mirrors, gradle=False) as env:
    with mirrored_pub_lockfile(root, env):
        try:
            subprocess.run([sys.executable, str(root / 'scripts' / 'build_native.py'), '--platform', 'windows', *variant.arguments],
                           cwd=root, env=env, check=True)
            subprocess.run([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=root, env=env, check=True)
            subprocess.run([flutter, 'build', 'windows', '--release', '--no-pub', '-v', *variant.flutter_arguments],
                           cwd=root, env=env, check=True)
            subprocess.run([sys.executable, str(root / 'scripts' / 'package_release.py'), '--platform', 'windows', *variant.arguments],
                           cwd=root, env=env, check=True)
        except subprocess.CalledProcessError as error:
            diagnose_failure(str(error))
            raise SystemExit(1) from error