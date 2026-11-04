"""Canonical, bounded authenticated messages; no credentials in telemetry."""
import hashlib,hmac,json,uuid
MAX_WIRE=200000
def pack(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')
def seal(value,key):
    value=dict(value)
    value['mac']=hmac.new(bytes.fromhex(key),pack(value),hashlib.sha256).hexdigest()
    return value
def verify(value,key):
    value=dict(value);mac=value.pop('mac','')
    if not isinstance(mac,str) or not hmac.compare_digest(mac,hmac.new(bytes.fromhex(key),pack(value),hashlib.sha256).hexdigest()):
        raise ValueError('AUTH_FAILED')
    if value.get('v')!=1:raise ValueError('PROTOCOL_VERSION')
    return value
def valid_id(value):
    if str(uuid.UUID(value))!=value:raise ValueError('INVALID_ID')
    return value
def read_body(handler,limit=MAX_WIRE):
    lengths=handler.headers.get_all('Content-Length',[])
    if handler.headers.get('Transfer-Encoding') or len(lengths)!=1:raise ValueError('INVALID_LENGTH')
    n=int(lengths[0])
    if not 0<n<=limit:raise ValueError('BODY_LIMIT')
    raw=handler.rfile.read(n)
    if len(raw)!=n:raise ValueError('INCOMPLETE_BODY')
    return json.loads(raw)
def reply(handler,code,value):
    raw=pack(value)
    try:
        handler.send_response(code);handler.send_header('Content-Type','application/json')
        handler.send_header('Content-Length',str(len(raw)));handler.send_header('Connection','close')
        handler.end_headers();handler.wfile.write(raw)
    except (BrokenPipeError,ConnectionResetError):pass
