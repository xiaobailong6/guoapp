import argparse
import json
import platform
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

from app_build import BuildVariant, add_variant_argument

root = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    add_variant_argument(parser)
    variant = BuildVariant(parser.parse_args().all_sources)
    if platform.system() != 'Windows':
        raise SystemExit('此检查需要 Windows。')
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE).group(1)
    package = root / 'dist' / 'windows' / f'{variant.slug}-{version}-windows-x64.zip'
    output = root / 'build' / 'windows-package-smoke.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
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
        try:
            result = subprocess.run(command, cwd=directory, timeout=90,
                                    capture_output=True, encoding='utf-8', errors='replace')
            process = {'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
        except subprocess.TimeoutExpired as error:
            def text(value):
                return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''
            process = {'timeout': True, 'stdout': text(error.stdout), 'stderr': text(error.stderr)}
        evidence = {'ok': False, 'error': '应用未生成冒烟检查报告。'}
        if report.is_file():
            raw = report.read_text(encoding='utf-8')
            try:
                decoded = json.loads(raw)
                if not isinstance(decoded, dict):
                    raise ValueError('报告必须是 JSON 对象。')
                evidence = decoded
            except (ValueError, json.JSONDecodeError) as error:
                evidence = {'ok': False, 'error': str(error), 'rawReport': raw}
        evidence['process'] = process
        output.write_text(json.dumps(evidence, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
        print(json.dumps(evidence, ensure_ascii=True), flush=True)
        if process.get('exitCode') != 0 or evidence.get('ok') is not True:
            raise SystemExit('Windows 包启动验收未通过，详细报告：' + str(output))


if __name__ == '__main__':
    main()
