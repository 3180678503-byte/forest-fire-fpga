# SPDX-License-Identifier: GPL-2.0
"""Limited CH34x userspace UART for an unbound USB interface.

Register/baud sequence follows Linux drivers/usb/serial/ch341.c (GPL-2.0).
No kernel detach, USB reset, persistent UART config, or ESP reset is performed.
"""
import fcntl
from pathlib import Path
import time
import queue
import threading
import os
from baud_divisor import divisor_config
import usb.core
import usb.util


def location(device):
    return '{}-{}'.format(device.bus, '.'.join(str(p) for p in device.port_numbers))


def devices():
    return sorted(usb.core.find(find_all=True, idVendor=0x1a86, idProduct=0x7523),
                  key=lambda d: (d.bus, tuple(d.port_numbers)))


class Ch340:
    def __init__(self, device, baud=115200, rx_mode='thread'):
        self.device = device
        self.claimed = False
        self.rx_mode = rx_mode
        self.rx_queue = queue.Queue(maxsize=16384)
        self.rx_stop = threading.Event()
        self.rx_thread = None
        self.rx_error = None
        self.stats = {'rx_bytes': 0, 'rx_packets': 0, 'tx_bytes': 0, 'short_writes': 0,
                      'rx_queue_peak': 0, 'rx_mode': rx_mode}
        lock_dir = Path(os.environ.get('ESP_UART_LOCK_DIR',
                        '/home/work/esp32_qwen_demo/board_validation_20261025/validation'))
        lock_dir.mkdir(exist_ok=True)
        self.lock = (lock_dir / ('usb-' + location(device) + '.lock')).open('a')
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            if device.is_kernel_driver_active(0):
                raise RuntimeError('USB interface has a kernel owner; refusing detach')
            config = device.get_active_configuration()
            interface = config[(0, 0)]
            self.ep_in = next(e for e in interface
                              if usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK
                              and usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)
            self.ep_out = next(e for e in interface
                               if usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK
                               and usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
            usb.util.claim_interface(device, 0)
            self.claimed = True
            version = bytes(device.ctrl_transfer(0xc0, 0x5f, 0, 0, 2, timeout=1000))
            self.chip_version=version[0]
            device.ctrl_transfer(0x40, 0xa1, 0, 0, timeout=1000)
            self.set_baud(baud)
            # Both modem signals deasserted, matching DTR=False, RTS=False.
            device.ctrl_transfer(0x40, 0xa4, 0xffff, 0, timeout=1000)
            self.identity = {'usb_path': location(device), 'bus': device.bus,
                             'address': device.address, 'vid': '1a86', 'pid': '7523',
                             'chip_version_hex': version.hex(), 'baud': baud,
                             'ep_in': self.ep_in.bEndpointAddress,
                             'ep_out': self.ep_out.bEndpointAddress,
                             'transport': 'libusb_userspace', 'flow_control': False}
            if rx_mode not in ('sync', 'thread'):
                raise ValueError('Unknown RX mode')
            if rx_mode == 'thread':
                self.rx_thread = threading.Thread(target=self._receive, daemon=True)
                self.rx_thread.start()
        except BaseException:
            self.close()
            raise

    def set_baud(self, baud):
        config=divisor_config(baud)
        if config['prescaler'] != 3:
            raise ValueError('Unverified lower-prescaler variant')
        rate_register=config['register'] | (0x80 if self.chip_version>0x27 else 0)
        self.device.ctrl_transfer(0x40, 0x9a, 0x1312, rate_register, timeout=1000)
        self.device.ctrl_transfer(0x40, 0x9a, 0x2518, 0xc3, timeout=1000)
        self.baud = baud
        self.stats['baud_config']=config

    def write(self, data, timeout_ms=1500):
        deadline = time.monotonic() + timeout_ms / 1000
        offset = 0
        while offset < len(data):
            if self.rx_error:
                raise IOError('RX failed: ' + str(self.rx_error))
            remaining = int((deadline - time.monotonic()) * 1000)
            if remaining <= 0:
                raise TimeoutError('USB write deadline exceeded')
            count = self.device.write(self.ep_out.bEndpointAddress, data[offset:], timeout=max(1, remaining))
            if not 0 < count <= len(data) - offset:
                raise IOError('Invalid USB write length')
            if count < len(data) - offset:
                self.stats['short_writes'] += 1
            offset += count
            self.stats['tx_bytes'] += count
        return offset

    def _read_packet(self, timeout_ms=50):
        try:
            # Keep the packet-sized receive mode validated on this DWC2 host.
            return bytes(self.device.read(self.ep_in.bEndpointAddress,
                                          self.ep_in.wMaxPacketSize, timeout=timeout_ms))
        except usb.core.USBTimeoutError:
            return b''

    def _receive(self):
        try:
            while not self.rx_stop.is_set():
                data = self._read_packet(10)
                if data:
                    self.stats['rx_bytes'] += len(data)
                    self.stats['rx_packets'] += 1
                    self.rx_queue.put_nowait(data)
                    self.stats['rx_queue_peak'] = max(self.stats['rx_queue_peak'], self.rx_queue.qsize())
        except Exception as exc:
            self.rx_error = exc

    def read(self, timeout_ms=50):
        if self.rx_mode == 'sync':
            data = self._read_packet(timeout_ms)
            self.stats['rx_bytes'] += len(data)
            self.stats['rx_packets'] += bool(data)
            return data
        if self.rx_error:
            raise IOError('RX failed: ' + str(self.rx_error))
        try:
            return self.rx_queue.get(timeout=max(.001, timeout_ms / 1000))
        except queue.Empty:
            return b''

    def drain(self, seconds=0.3):
        deadline = time.monotonic() + seconds
        output = bytearray()
        while time.monotonic() < deadline:
            output.extend(self.read())
        return bytes(output)

    def command(self, command, seconds=3):
        self.write(command.encode('ascii') + b'\r\n')
        deadline = time.monotonic() + seconds
        output = bytearray()
        while time.monotonic() < deadline:
            output.extend(self.read())
            if b'\r\nOK\r\n' in output or b'\r\nERROR\r\n' in output:
                break
        return bytes(output)

    def close(self):
        self.rx_stop.set()
        if self.rx_thread:
            self.rx_thread.join(timeout=2)
            if self.rx_thread.is_alive():
                raise RuntimeError('RX thread did not stop; USB interface retained')
        if self.claimed:
            usb.util.release_interface(self.device, 0)
            self.claimed = False
        usb.util.dispose_resources(self.device)
        if not self.lock.closed:
            self.lock.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
