"""Loopback HTTP -> ESP-AT UART bridge. One owner, one request, explicit mock default."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
import json
from pathlib import Path
import signal
import sys
import threading
import time
from protocol import strict_loads,validate_request,validate_response
from at_protocol import AtLink

MAX_BODY=196608


def request_bytes(host,port,task,raw):
    # UUID validation prevents request-ID text from becoming a header injection.
    jpeg=validate_request(task)
    if len(jpeg)>128*1024 or len(raw)>MAX_BODY:
        raise ValueError('ROI or request exceeds bridge limit')
    header=('POST /v1/semantic-review HTTP/1.0\r\nHost: {}:{}\r\n'
            'Content-Type: application/json\r\nContent-Length: {}\r\n'
            'X-Request-ID: {}\r\nConnection: close\r\n\r\n'
            .format(host,port,len(raw),task['request_id']).encode())
    return header+raw,hashlib.sha256(jpeg).hexdigest()


class Forwarder:
    def __init__(self,link,host,port,require_mock=True):
        self.link,self.host,self.port,self.require_mock=link,host,port,require_mock
        self.failed=False

    def forward(self,raw):
        if self.failed:
            raise RuntimeError('Transport needs restart/recovery')
        task=strict_loads(raw)
        packet,digest=request_bytes(self.host,self.port,task,raw)
        started=time.monotonic()
        try:
            (status,body),timing=self.link.request(self.host,self.port,packet,seconds=14)
            if status!=200:
                raise ValueError('Upstream HTTP {}'.format(status))
            response=validate_response(strict_loads(body),task)
            if self.require_mock and response['meta'].get('is_mock') is not True:
                raise ValueError('Expected mock response')
            self.link.close_connection()
            return body,{'request_id':task['request_id'],'jpeg_sha256':digest,
                         'timing_ms':timing,'wall_ms':1000*(time.monotonic()-started)}
        except Exception:
            # Do not blindly retry an upload whose remote completion is unknown.
            self.failed=True
            raise


def make_server(forwarder,port,log):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(3)

        def log_message(self,*args):
            pass

        def send_json(self,status,body):
            if not isinstance(body,bytes):
                body=json.dumps(body,separators=(',',':')).encode()
            self.send_response(status)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(body)))
            self.send_header('Connection','close')
            self.end_headers()
            try:self.wfile.write(body)
            except (BrokenPipeError,ConnectionResetError):pass

        def do_GET(self):
            if self.path!='/healthz':
                return self.send_json(404,{'error':'NOT_FOUND'})
            self.send_json(200,{'mode':'esp32-uart-bridge','available':not forwarder.failed,
                                'advisory_only':True,'require_mock':forwarder.require_mock})

        def do_POST(self):
            if self.path!='/v1/semantic-review':
                return self.send_json(404,{'error':'NOT_FOUND'})
            lengths=self.headers.get_all('Content-Length',[])
            if len(lengths)!=1 or not lengths[0].isdigit() or self.headers.get('Transfer-Encoding'):
                return self.send_json(400,{'error':'INVALID_LENGTH'})
            size=int(lengths[0])
            if not 0<size<=MAX_BODY:
                return self.send_json(413,{'error':'BODY_LIMIT'})
            try:
                raw=self.rfile.read(size)
                if len(raw)!=size:
                    raise ValueError('Incomplete local body')
                validate_request(strict_loads(raw))
            except Exception:
                return self.send_json(400,{'error':'INVALID_REQUEST'})
            try:
                body,record=forwarder.forward(raw)
                with log.open('a',encoding='utf8') as stream:
                    stream.write(json.dumps(record)+'\n')
                self.send_json(200,body)
            except (BrokenPipeError,ConnectionResetError):
                pass
            except Exception as exc:
                with log.open('a',encoding='utf8') as stream:
                    stream.write(json.dumps({'error':type(exc).__name__,'message':str(exc)[:500],
                        'transport_failed':True,'safe_command_state':forwarder.link.safe_command_state,
                        'last_events':[e.decode(errors='replace')[:160] for e in forwarder.link.stream.events[-12:]]})+'\n')
                self.send_json(503,{'error':'TRANSPORT_UNAVAILABLE'})

    server=HTTPServer(('127.0.0.1',port),Handler)
    server.timeout=.5
    return server


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--pc-host',required=True,type=lambda value:str(ipaddress.IPv4Address(value)))
    parser.add_argument('--pc-port',type=int,default=8767)
    parser.add_argument('--listen-port',type=int,default=18765)
    parser.add_argument('--usb-path',default='1-1.1')
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--allow-real',action='store_true')
    args=parser.parse_args()
    if not 1<=args.pc_port<=65535 or not 1<=args.listen_port<=65535:
        parser.error('Invalid port')
    root=Path(__file__).resolve().parents[1]
    sys.path.insert(0,str(Path(__file__).resolve().parent/'vendor'))
    from ch340_usb import Ch340,devices,location
    from uart_session import UartSession
    report={}
    stopping=threading.Event()
    for sig in (signal.SIGINT,signal.SIGTERM):
        signal.signal(sig,lambda *_:stopping.set())
    args.log.parent.mkdir(parents=True,exist_ok=True)
    with Ch340(next(d for d in devices() if location(d)==args.usb_path)) as uart:
        session=UartSession(uart,921600,report)
        try:
            with session:
                link=AtLink(uart,chunk_size=2048,passive_read=8)
                try:
                    for cmd in ('ATE0','AT+CIPMUX=0','AT+CIPMODE=0','AT+CIPRECVMODE=1','AT+CIPDINFO=0'):
                        link.command(cmd,time.monotonic()+3)
                    link.close_connection()
                    health=('GET /healthz HTTP/1.0\r\nHost: {}:{}\r\nConnection: close\r\n\r\n'
                            .format(args.pc_host,args.pc_port).encode())
                    (status,body),_=link.request(args.pc_host,args.pc_port,health)
                    remote=strict_loads(body)
                    if status!=200 or (not args.allow_real and remote.get('mode')!='mock'):
                        raise RuntimeError('Upstream mode is not the requested mode')
                    link.close_connection()
                    forwarder=Forwarder(link,args.pc_host,args.pc_port,not args.allow_real)
                    server=make_server(forwarder,args.listen_port,args.log)
                    print('READY 127.0.0.1:{} 921600/8N1 passive=8 chunk=2048'.format(args.listen_port),flush=True)
                    try:
                        while not stopping.is_set():
                            server.handle_request()
                    finally:
                        server.server_close()
                finally:
                    session.safe=link.safe_command_state
                    if session.safe:
                        try:
                            link.close_connection()
                        except Exception:
                            pass
        finally:
            args.log.with_suffix('.session.json').write_text(json.dumps(report,indent=2))
    return 0 if report.get('UART_restored') else 1


if __name__=='__main__':
    raise SystemExit(main())
