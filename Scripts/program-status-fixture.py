"""Interactive OSC 7501 producer for the isolated local PTY browser check."""
import os
import select
import termios
import tty


def write(value):
    os.write(1, value.encode())


def osc(body, end='\x1b\\'):
    write('\x1b]7501;' + body + end)


saved = termios.tcgetattr(0)
try:
    tty.setraw(0)
    osc('?')
    reply = b''
    while not reply.endswith(b'\x1b\\') and select.select([0], [], [], 5)[0]:
        reply += os.read(0, 1)
    write('QUERY_OK\r\n' if reply == b'\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth\x1b\\' else 'QUERY_FAILED\r\n')
    while True:
        line = b''
        while not line.endswith((b'\r', b'\n')):
            line += os.read(0, 1)
        command = line.strip().decode()
        if command == 'working':
            osc('state=working:app=demo:progress=40:msg=QnVpbGRpbmc=')
        elif command == 'blocked':
            osc('state=blocked:id=build/test:kind=permission:title=VGVzdHM=:msg=QXBwcm92ZT8=', '\x07')
        elif command == 'bad':
            osc('state=done:msg=Cg==')
        elif command == 'clear-child':
            osc('state=clear:id=build')
        elif command == 'done':
            osc('state=clear')
            osc('state=done:app=demo:msg=RmluaXNoZWQ=')
        elif command == 'prompt':
            write('\x1b]133;A\x1b\\')
        elif command == 'reset':
            write('\x1bc')
        elif command == 'soft-reset':
            write('\x1b[!p')
        elif command == 'alternate':
            write('\x1b[?1049h\x1b[?1049l')
        elif command == 'quit':
            break
finally:
    termios.tcsetattr(0, termios.TCSANOW, saved)
