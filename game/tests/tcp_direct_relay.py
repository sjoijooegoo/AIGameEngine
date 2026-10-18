"""Loopback-only diagnostic relay using a chosen Windows interface per socket.

No proxy files, routing table or game payloads are changed. The destination is
fixed by the test harness. Queues and connection lifetime are bounded.
"""
import select,socket,struct,threading

class DirectTcpRelay:
    def __init__(self,target,interface,address):
        self.target=target;self.interface=interface;self.address=address;self.closed=threading.Event()
        self.errors=[];self.connections=0;self.threads=[];self.sockets=[]
        self.listener=socket.socket();self.listener.bind(('127.0.0.1',0));self.listener.listen(4);self.listener.settimeout(.2)
        self.port=self.listener.getsockname()[1]
        self.thread=threading.Thread(target=self.accept,daemon=True);self.thread.start()
    def accept(self):
        while not self.closed.is_set():
            try:client,_=self.listener.accept()
            except socket.timeout:continue
            except OSError:break
            thread=threading.Thread(target=self.pipe,args=(client,),daemon=True);self.threads.append(thread);thread.start()
    def pipe(self,client):
        upstream=socket.socket();self.sockets.extend([client,upstream]);self.connections+=1
        try:
            upstream.bind((self.address,0));upstream.setsockopt(socket.IPPROTO_IP,31,struct.pack('!I',self.interface))
            upstream.settimeout(10);upstream.connect(self.target)
            peers=[client,upstream];pending={client:bytearray(),upstream:bytearray()}
            for sock in peers:sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);sock.setblocking(False)
            while not self.closed.is_set():
                readers=[sock for sock in peers if len(pending[peers[1-peers.index(sock)]])<262144]
                readable,writable,_=select.select(readers,[sock for sock in peers if pending[sock]],[],.1)
                for sock in readable:
                    data=sock.recv(65536)
                    if not data:return
                    pending[peers[1-peers.index(sock)]].extend(data)
                for sock in writable:
                    sent=sock.send(pending[sock]);del pending[sock][:sent]
        except (ConnectionResetError,ConnectionAbortedError):pass
        except OSError as exc:
            if not self.closed.is_set():self.errors.append(str(exc))
        finally:client.close();upstream.close()
    def close(self):
        self.closed.set();self.listener.close();self.thread.join(2)
        for sock in self.sockets:
            try:sock.shutdown(socket.SHUT_RDWR)
            except OSError:pass
        for thread in self.threads:thread.join(2)
    def report(self):return {'connections':self.connections,'errors':self.errors,'interface':self.interface,'destination':self.target,'route_changes':False}
