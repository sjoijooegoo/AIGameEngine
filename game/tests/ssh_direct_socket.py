"""OpenSSH ProxyCommand for one physical-interface TCP socket on Windows.

Keeps OpenSSH authentication/host-key verification; never changes global proxy
or route configuration. Diagnostic source IP/interface must be supplied.
"""
import argparse,os,socket,struct,sys,threading

def main():
    p=argparse.ArgumentParser();p.add_argument('--interface',type=int,required=True);p.add_argument('--address',required=True)
    p.add_argument('--host',required=True);p.add_argument('--port',type=int,required=True);args=p.parse_args()
    with socket.socket() as sock:
        sock.settimeout(10);sock.bind((args.address,0));sock.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',args.interface))
        sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);sock.connect((args.host,args.port));sock.settimeout(None)
        def upload():
            try:
                while data:=os.read(0,65536):sock.sendall(data)
                sock.shutdown(socket.SHUT_WR)
            except OSError:pass
        threading.Thread(target=upload,daemon=True).start()
        while data:=sock.recv(65536):sys.stdout.buffer.write(data);sys.stdout.buffer.flush()

if __name__=='__main__':main()
