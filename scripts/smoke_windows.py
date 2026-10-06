import argparse
import json
import platform
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from app_build import BuildVariant, add_variant_argument

root = Path(__file__).resolve().parents[1]

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, 'reconfigure'):
        stream.reconfigure(encoding='utf-8', errors='replace')


def main():
    parser = argparse.ArgumentParser()
    add_variant_argument(parser)
    variant = BuildVariant(parser.parse_args().all_sources)
    if platform.system() != 'Windows':
        raise SystemExit('此检查需要 Windows。')
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE).group(1)
    package = root / 'dist' / 'windows' / f'{variant.slug}-{version}-windows-x64.zip'
    with tempfile.TemporaryDirectory(prefix='zhenguojian-smoke-') as temporary:
        directory = Path(temporary)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(directory)
        media = directory / 'fixture.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi',
                        '-i', 'testsrc2=size=160x90:rate=12', '-t', '3',
                        '-c:v', 'libx264', '-threads', '1', str(media)], check=True)
        report = directory / 'result.json'
        command = [str(directory / (variant.slug + '.exe')), '--package-smoke', str(report), str(media)]
        diagnostics = {'timedOut': False, 'returncode': None, 'stdout': '', 'stderr': ''}
        try:
            result = subprocess.run(command, cwd=directory, check=False, timeout=90,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace')
            diagnostics.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        except subprocess.TimeoutExpired as error:
            diagnostics['timedOut'] = True
            for name in ('stdout', 'stderr'):
                value = getattr(error, name) or ''
                diagnostics[name] = value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value
        except OSError as error:
            diagnostics['launchError'] = str(error)
        try:
            evidence = json.loads(report.read_text(encoding='utf-8'))
            if not isinstance(evidence, dict):
                raise ValueError('应用报告不是 JSON 对象')
        except (OSError, ValueError) as error:
            evidence = {'ok': False, 'reportError': str(error)}
        evidence['process'] = diagnostics
        output = root / 'build' / 'windows-package-smoke.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        content = json.dumps(evidence, ensure_ascii=False, indent=2) + '\n'
        output.write_text(content, encoding='utf-8')
        print(content, flush=True)
        if diagnostics['timedOut'] or diagnostics['returncode'] != 0 or evidence.get('ok') is not True:
            raise SystemExit('Windows 包启动验收未通过，诊断已保存：' + str(output))


if __name__ == '__main__':
    main()
