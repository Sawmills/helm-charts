"""Persist bounded child diagnostics before caller guards or parsing."""
import json
import os
import signal
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent
SENSITIVE = re.compile(r'authorization|bearer|token|secret|password|credential|(?:api[ _-]?)?key|https?://|[A-Za-z0-9_+/=-]{24,}', re.I)


def redact(stderr):
    if isinstance(stderr, bytes):
        stderr = stderr.decode('utf-8', errors='replace')
    lines = []
    for line in (stderr or '')[:16384].splitlines():
        if len(line) > 256 or SENSITIVE.search(line):
            lines.append('<sensitive line omitted>')
        else:
            lines.append(line)
    return '\n'.join(lines).encode('utf-8')[:2048].decode('utf-8', errors='ignore')


def run(argv, *, receipt_dir=None, retain_stdout=False, **kwargs):
    directory = Path(receipt_dir) if receipt_dir is not None else ROOT/'child-receipts'
    directory.mkdir(parents=True, exist_ok=True)
    path = directory/(str(time.time_ns())+'-'+uuid.uuid4().hex+'.json')
    record = {'exit_code':None, 'stderr_excerpt':'', 'timed_out':False}
    with path.open('x') as stream:
        json.dump(record, stream)
    check = kwargs.pop('check', False)
    timeout = kwargs.pop('timeout', None)
    input_value = kwargs.pop('input', None)
    capture_output = kwargs.pop('capture_output', False)
    if not capture_output or 'stdout' in kwargs or 'stderr' in kwargs:
        raise ValueError('CAPTURE_OUTPUT_REQUIRED')
    if input_value is not None:
        kwargs['stdin'] = subprocess.PIPE
    kwargs["start_new_session"] = True
    try:
        with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs) as process:
            try:
                stdout, stderr = process.communicate(input=input_value, timeout=timeout)
            except subprocess.TimeoutExpired as original_timeout:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=2)
                try:
                    stdout, stderr = process.communicate(timeout=0.5)
                except subprocess.TimeoutExpired as drain_timeout:
                    stdout = drain_timeout.output or original_timeout.output
                    stderr = drain_timeout.stderr or original_timeout.stderr
                    for channel in [process.stdout, process.stderr]:
                        if channel:
                            channel.close()
                record.update(exit_code=process.returncode, stderr_excerpt=redact(stderr), stdout_excerpt=redact(stdout), timed_out=True)
                path.write_text(json.dumps(record, indent=2)+'\n')
                raise subprocess.TimeoutExpired(argv, timeout, output=stdout, stderr=stderr) from None
            record.update(exit_code=process.returncode, stderr_excerpt=redact(stderr))
            if process.returncode != 0 or retain_stdout:
                record['stdout_excerpt'] = redact(stdout)
            path.write_text(json.dumps(record, indent=2)+'\n')
            result = subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
    except OSError as error:
        record['stderr_excerpt'] = 'CHILD_SPAWN_FAILED:'+type(error).__name__
        path.write_text(json.dumps(record, indent=2)+'\n')
        raise
    result.receipt_path = path
    if check:
        result.check_returncode()
    return result


def retain_guard_stdout(result):
    """Retain redacted output when an exit-zero result fails a caller guard."""
    path = result.receipt_path
    record = json.loads(path.read_text())
    record['stdout_excerpt'] = redact(result.stdout)
    path.write_text(json.dumps(record, indent=2)+'\n')
