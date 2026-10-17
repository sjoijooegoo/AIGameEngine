import socket,threading,time,unittest
from game.tests.network_fault_proxy import FaultProxy,Profile

class ProxyContract(unittest.TestCase):
    def test_two_clients_delay_loss_and_duplicate(self):
        server=socket.socket(type=socket.SOCK_DGRAM);server.bind(('127.0.0.1',0));server.settimeout(.05)
        stop=threading.Event();addresses=set()
        def echo():
            while not stop.is_set():
                try:data,addr=server.recvfrom(1024);addresses.add(addr);server.sendto(data,addr)
                except socket.timeout:pass
        thread=threading.Thread(target=echo);thread.start();proxies=[];clients=[]
        try:
            proxy=FaultProxy(server.getsockname(),Profile('delay',rtt_ms=100,duplicate=1),17);proxies.append(proxy)
            for data in [b'alpha',b'bravo']:
                client=socket.socket(type=socket.SOCK_DGRAM);client.settimeout(1);clients.append(client)
                start=time.monotonic();client.sendto(data,('127.0.0.1',proxy.port))
                self.assertEqual(client.recv(1024),data);self.assertGreaterEqual(time.monotonic()-start,.095)
                self.assertEqual(client.recv(1024),data)
            self.assertEqual(len(addresses),2)
            # A late reply to a closed UDP endpoint must not kill the proxy.
            closed_address=('127.0.0.1',clients[0].getsockname()[1]);clients[0].close()
            proxy.local.sendto(b'late reply',closed_address);time.sleep(.06)
            extra=socket.socket(type=socket.SOCK_DGRAM);extra.settimeout(1);clients.append(extra)
            extra.sendto(b'after-close',('127.0.0.1',proxy.port))
            self.assertEqual(extra.recv(1024),b'after-close')
            self.assertTrue(proxy.thread.is_alive());self.assertIsNone(proxy.report()['error'])
            drop=FaultProxy(server.getsockname(),Profile('loss',loss=1),18);proxies.append(drop)
            client=socket.socket(type=socket.SOCK_DGRAM);client.settimeout(.15);clients.append(client)
            client.sendto(b'blocked',('127.0.0.1',drop.port))
            with self.assertRaises(socket.timeout):client.recv(1024)
            self.assertEqual(drop.report()['directions']['up']['random_dropped'],1)
        finally:
            for proxy in proxies:proxy.close()
            for client in clients:client.close()
            stop.set();thread.join();server.close()

if __name__=='__main__':unittest.main()
