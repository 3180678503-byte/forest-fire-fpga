"""Single-reader, length-delimited ESP-AT parser for board smoke tests."""
import re
import time


class AtStream:
    def __init__(self):
        self.pending = bytearray()
        self.payload = bytearray()
        self.remaining = 0
        self.events = []
        self.closed = False
        self.passive_available = 0
        self.trace = bytearray()

    def feed(self, data):
        if len(self.trace) < 16384:
            self.trace.extend(data[:16384-len(self.trace)])
        self.pending.extend(data)
        while self.pending:
            if self.remaining:
                count = min(self.remaining, len(self.pending))
                self.payload.extend(self.pending[:count])
                del self.pending[:count]
                self.remaining -= count
                if len(self.payload) > 80 * 1024:
                    raise ValueError('Response exceeds limit')
                continue
            if self.pending.startswith(b'+IPD,'):
                passive = re.match(rb'\+IPD,\d+\r\n', self.pending)
                if passive:
                    self.passive_available=int(bytes(self.pending[:passive.end()-2]).split(b',')[1])
                    self.events.append(bytes(self.pending[:passive.end()-2]))
                    del self.pending[:passive.end()]
                    continue
                end = self.pending.find(b':')
                if end < 0:
                    if len(self.pending) > 32:
                        raise ValueError('Invalid IPD header')
                    return
                match = re.fullmatch(rb'\+IPD,(\d+)', self.pending[:end])
                if not match or int(match.group(1)) > 80 * 1024:
                    raise ValueError('Invalid IPD length')
                self.remaining = int(match.group(1))
                del self.pending[:end + 1]
                continue
            if self.pending.startswith(b'+CIPRECVDATA:'):
                match = re.match(rb'\+CIPRECVDATA:(\d+),', self.pending)
                if not match:
                    if len(self.pending)>40:
                        raise ValueError('Invalid passive data header')
                    return
                self.remaining=int(match.group(1))
                self.passive_available=max(0,self.passive_available-self.remaining)
                if self.remaining>65536:
                    raise ValueError('Passive payload too large')
                del self.pending[:match.end()]
                continue
            if self.pending.startswith(b'>'):
                self.events.append(b'>')
                del self.pending[:1]
                continue
            end = self.pending.find(b'\r\n')
            if end < 0:
                if len(self.pending) > 4096:
                    raise ValueError('Control line exceeds limit')
                return
            line = bytes(self.pending[:end]).strip()
            del self.pending[:end + 2]
            if line:
                self.events.append(line)
                self.closed |= line == b'CLOSED'

    def http_response(self):
        split = self.payload.find(b'\r\n\r\n')
        if split < 0:
            if len(self.payload) > 16384:
                raise ValueError('HTTP head exceeds limit')
            return None
        if split > 16384:
            raise ValueError('HTTP head exceeds limit')
        lines = bytes(self.payload[:split]).split(b'\r\n')
        status = re.fullmatch(rb'HTTP/1\.[01] ([0-9]{3}) .*', lines[0])
        if not status:
            raise ValueError('Invalid HTTP status')
        lengths = []
        for line in lines[1:]:
            key, separator, value = line.partition(b':')
            if not separator:
                raise ValueError('Invalid HTTP header')
            if key.lower() == b'transfer-encoding':
                raise ValueError('Transfer-Encoding is unsupported')
            if key.lower() == b'content-length':
                if not value.strip().isdigit():
                    raise ValueError('Invalid Content-Length')
                lengths.append(int(value.strip()))
        if len(lengths) != 1 or not 0 <= lengths[0] <= 65536:
            raise ValueError('Invalid Content-Length')
        body = bytes(self.payload[split + 4:])
        if len(body) < lengths[0]:
            return None
        if len(body) > lengths[0]:
            raise ValueError('Trailing HTTP body bytes')
        return int(status.group(1)), body


class AtLink:
    def __init__(self, port, chunk_size=1024, passive_read=0):
        self.port = port
        if chunk_size not in (1024,2048):
            raise ValueError('Unsupported chunk size')
        self.chunk_size = chunk_size
        self.passive_read = passive_read
        self.stream = AtStream()
        self.safe_command_state = True

    def pump(self, deadline):
        milliseconds = max(1, min(50, int((deadline - time.monotonic()) * 1000)))
        self.stream.feed(self.port.read(milliseconds))

    def wait(self, expected, deadline):
        while True:
            for event in self.stream.events:
                if event in expected:
                    return event
                if event in (b'ERROR', b'SEND FAIL', b'WIFI DISCONNECT', b'ready'):
                    raise RuntimeError('AT event: ' + event.decode('ascii'))
            if time.monotonic() >= deadline:
                raise TimeoutError('AT deadline exceeded')
            self.pump(deadline)

    def command(self, value, deadline, expected=(b'OK',)):
        self.stream.events.clear()
        self.port.write(value.encode('ascii') + b'\r\n',
                        max(1, min(1500, int((deadline - time.monotonic()) * 1000))))
        return self.wait(expected, deadline)

    def request(self, host, port_number, request, seconds=14):
        self.stream = AtStream()
        started = time.monotonic()
        deadline = started + seconds
        self.command('AT+CIPSTART="TCP","{}",{}'.format(host, port_number),
                     min(deadline, started + 3))
        connected = time.monotonic()
        chunks = 0
        for offset in range(0, len(request), self.chunk_size):
            if time.monotonic() >= deadline:
                raise TimeoutError('Request deadline exceeded before next chunk')
            block = request[offset:offset + self.chunk_size]
            # Unknown state after a lost prompt must not accept a new AT command.
            self.safe_command_state = False
            self.command('AT+CIPSEND={}'.format(len(block)), min(deadline, time.monotonic() + 3), (b'>',))
            self.port.write(block, max(1, min(1500, int((deadline - time.monotonic()) * 1000))))
            self.stream.events.clear()
            self.wait((b'SEND OK',), deadline)
            self.safe_command_state = True
            chunks += 1
        sent = time.monotonic()
        passive_reads=0
        while True:
            result = self.stream.http_response()
            if result is not None:
                finished = time.monotonic()
                return result, {'connect_ms': (connected-started)*1000,
                                'uart_send_ms': (sent-connected)*1000,
                                'wait_response_ms': (finished-sent)*1000,
                                'total_ms': (finished-started)*1000, 'chunks': chunks,
                                'passive_reads':passive_reads}
            if self.passive_read:
                if self.stream.passive_available>0 and not self.stream.closed:
                    amount=min(self.passive_read,self.stream.passive_available)
                    self.command('AT+CIPRECVDATA={}'.format(amount),deadline)
                    passive_reads+=1
                    continue
            if self.stream.closed:
                raise RuntimeError('TCP closed before complete HTTP reply')
            if time.monotonic() >= deadline:
                raise TimeoutError('HTTP response deadline exceeded')
            self.pump(deadline)

    def close_connection(self):
        if not self.safe_command_state:
            raise RuntimeError('Uncertain ESP data state; operator resynchronization required')
        try:
            self.command('AT+CIPCLOSE', time.monotonic()+2)
        except RuntimeError:
            # ERROR is expected when the server already closed the TCP connection.
            if b'ERROR' not in self.stream.events:
                raise
