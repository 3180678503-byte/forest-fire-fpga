"""Choose a previously verified ESP UART or one uniquely responding candidate."""
import json
import os


def save_selection(path, value):
    """Commit the last good port before publishing its filename."""
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as stream:
        json.dump(value, stream)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(str(temporary), 0o600)
    temporary.replace(path)
    if os.name != 'nt':
        directory = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)


def select_usb(preferred_path, automatic, candidates, probe):
    """Candidates are (USB location, device) pairs; probe returns an AT baud.

    The caller holds no other UART handle. Probe errors are recorded by type
    only, so command bytes and private configuration cannot enter diagnostics.
    """
    by_path = dict(candidates)
    report = {'mode': 'auto' if automatic else 'fixed',
              'preferred_path': preferred_path, 'attempts': []}
    if not automatic:
        if preferred_path not in by_path:
            raise RuntimeError('ESP_USB_CONFIGURED_PORT_MISSING')
        report.update(selected_path=preferred_path, verified=False)
        return by_path[preferred_path], report

    def check(path):
        try:
            baud = probe(by_path[path])
        except Exception as exc:
            report['attempts'].append({'path': path, 'at_ok': False,
                                       'error_type': type(exc).__name__})
            return False
        report['attempts'].append({'path': path, 'at_ok': True, 'baud': baud})
        return True

    # A responding previously selected port preserves the established binding.
    if preferred_path in by_path and check(preferred_path):
        report.update(selected_path=preferred_path, verified=True)
        return by_path[preferred_path], report

    responding = [path for path in sorted(by_path)
                  if path != preferred_path and check(path)]
    if not responding:
        raise RuntimeError('ESP_USB_NO_AT_RESPONSE')
    if len(responding) != 1:
        raise RuntimeError('ESP_USB_MULTIPLE_AT_RESPONDERS')
    selected = responding[0]
    report.update(selected_path=selected, verified=True)
    return by_path[selected], report
