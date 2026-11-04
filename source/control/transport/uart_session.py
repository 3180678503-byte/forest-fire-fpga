"""Temporary ESP UART settings, with restoration even when switching fails."""
import re
import time

BAUDS = (115200, 230400, 460800, 921600)


def synchronize(port):
    attempts = []
    for baud in BAUDS:
        port.set_baud(baud)
        port.drain(.12)
        # Probing at another baud can leave a partial command in the ESP line buffer.
        # Terminate that line before looking for a fresh AT response.
        port.write(b'\r\n')
        port.drain(.08)
        raw = port.command('AT', .45)
        if b'\r\nERROR\r\n' in raw:
            raw = port.command('AT', .45)
        attempts.append({'baud': baud, 'reply_hex': raw.hex()})
        if b'\r\nOK\r\n' in raw:
            return baud, attempts
    raise RuntimeError('No AT synchronization at any candidate baud: ' + str(attempts))


class UartSession:
    def __init__(self, port, baud, report):
        self.port, self.baud, self.report = port, baud, report
        self.original = None
        self.safe = True

    def __enter__(self):
        port = self.port
        found, attempts = synchronize(port)
        self.report['synchronization'] = attempts
        raw = port.command('AT+UART_CUR?', 2)
        self.report['original_UART_CUR_raw_hex']=raw.hex()
        match = re.search(rb'\+UART_CUR:(\d+),8,1,0,([0-3])', raw)
        if not match:
            raise RuntimeError('Unknown existing UART format')
        self.original = (found, int(match.group(2)))
        self.report['original_UART_CUR'] = raw.decode(errors='replace')
        # AT command echo tells us the prior ATE state without persistent writes.
        self.echo = b'AT+UART_CUR?' in raw
        self.report['original_echo'] = self.echo
        try:
            port.command('ATE0')
            # Long diagnostic replies are collected before moving to the test rate.
            self.report['pre_switch_GMR']=port.command('AT+GMR',2).decode(errors='replace')
            port.command('AT+UART_CUR={},8,1,0,0'.format(self.baud), .15)
            port.set_baud(self.baud)
            port.drain(.10)
            if b'\r\nOK\r\n' not in port.command('AT', 1):
                raise RuntimeError('Target baud AT synchronization failed')
            self.report['target_UART_CUR'] = port.command('AT+UART_CUR?', 2).decode(errors='replace')
            return self
        except BaseException:
            self.restore()
            raise

    def restore(self):
        if not self.original:
            return
        if not self.safe:
            self.report['requires_operator_recovery'] = True
            return
        port = self.port
        try:
            synchronize(port)
            old_baud, old_flow = self.original
            port.command('AT+CIPRECVMODE=0',1)
            port.command('AT+UART_CUR={},8,1,0,{}'.format(old_baud, old_flow), .15)
            port.set_baud(old_baud)
            port.drain(.1)
            port.command('ATE1' if self.echo else 'ATE0')
            raw = port.command('AT+UART_CUR?', 2)
            match = re.search(rb'\+UART_CUR:(\d+),8,1,0,([0-3])', raw)
            self.report['final_UART_CUR'] = raw.decode(errors='replace')
            self.report['UART_restored'] = bool(match and abs(int(match.group(1)) - old_baud) < old_baud*.01
                                                and int(match.group(2)) == old_flow)
        except Exception as exc:
            self.report['restore_error'] = repr(exc)
            self.report['UART_restored'] = False

    def __exit__(self, *args):
        self.restore()
