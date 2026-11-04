"""CH34x rate selection using the 48 MHz equation documented in Linux ch341.c.

Reference: Linux v6.12 drivers/usb/serial/ch341.c. No USB access here.
"""


def divisor_config(baud):
    if baud not in (115200,230400,460800,921600):
        raise ValueError('Unsupported diagnostic baud')
    choices=[]
    for prescaler in range(4):
        for factor in (0,1):
            clock_div=1 << (12-3*prescaler-factor)
            for divisor in range(9 if factor else 2,257):
                actual=48000000/(clock_div*divisor)
                choices.append((abs(actual-baud),factor,-prescaler,divisor,actual))
    _,factor,negative_ps,divisor,actual=min(choices)
    ps=-negative_ps
    return {'register':((256-divisor)<<8)|(factor<<2)|ps,
            'prescaler':ps,'factor':factor,'divisor':divisor,
            'requested_baud':baud,'calculated_baud':actual,'error_percent':100*(actual-baud)/baud}
