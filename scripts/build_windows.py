import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from build_mirrors import china_mirror_environment, mirrored_pub_lockfile
from app_build import BuildVariant, add_variant_argument


for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, 'reconfigure'):
        stream.reconfigure(encoding='utf-8', errors='replace')


def diagnose_install(root, environment):
    build = root / 'build' / 'windows' / 'x64'
    for source in (
        root / 'windows' / 'flutter' / 'ephemeral' / 'icudtl.dat',
        root / 'windows' / 'flutter' / 'ephemeral' / 'flutter_windows.dll',
        root / 'windows' / 'runner' / 'duanju_core.dll',
        root / 'build' / 'flutter_assets',
        build / 'app.so',
    ):
        print(f'Install source: {source} exists={source.exists()}', flush=True)
    bundle = build / 'runner' / 'Release'
    if bundle.exists():
        for path in sorted(bundle.rglob('*')):
            print('Bundle: ' + str(path.relative_to(bundle)), flush=True)
    report = build / 'install_error.txt'
    if report.is_file():
        print(report.read_text(encoding='utf-8', errors='replace'), flush=True)
    cache = build / 'CMakeCache.txt'
    if cache.is_file():
        for line in cache.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('CMAKE_COMMAND:INTERNAL='):
                cmake = line.split('=', 1)[1]
                script = build / 'cmake_install.cmake'
                if Path(cmake).is_file() and script.is_file():
                    subprocess.run([cmake, '-DCMAKE_INSTALL_CONFIG_NAME=Release',
                                    '-P', str(script)], cwd=build, env=environment,
                                   check=False)
                break


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
with china_mirror_environment(environment, options.cn_mirrors, gradle=False) as env:
    with mirrored_pub_lockfile(root, env):
        subprocess.run([sys.executable, str(root / 'scripts' / 'build_native.py'), '--platform', 'windows', *variant.arguments],
                       cwd=root, env=env, check=True)
        subprocess.run([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=root, env=env, check=True)
        try:
            subprocess.run([flutter, 'build', 'windows', '--release', '--no-pub',
                            '--verbose', *variant.flutter_arguments], cwd=root, env=env, check=True)
        except subprocess.CalledProcessError:
            try:
                diagnose_install(root, env)
            except OSError as error:
                print('安装诊断失败：' + str(error), file=sys.stderr)
            raise
        subprocess.run([sys.executable, str(root / 'scripts' / 'package_release.py'), '--platform', 'windows', *variant.arguments],
                       cwd=root, env=env, check=True)
