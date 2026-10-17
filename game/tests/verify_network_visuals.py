"""Rendered current-bank prediction/door/fire sequences through normal inputs."""
import argparse,datetime,json,socket
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image,ImageDraw
from game.tests.verify_bank_coop import BankPeer,ROOT
from game.tests.verify_coop import until

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',required=True,choices=['bank']);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-network-visual-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir();print(folder,flush=True)
    peers=[];sequences=[];checks=[];pool=ThreadPoolExecutor(max_workers=2)
    with socket.socket(type=socket.SOCK_DGRAM) as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    def frames(count):
        for _ in range(count//3):
            for future in [pool.submit(a.call,'step',frames=3),pool.submit(b.call,'step',frames=3)]:future.result()
            server.call('step',frames=3)
    def sequence(name,count,spacing):
        captures=[];states=[]
        for _ in range(count):
            frames(spacing);captures.append(a.call('capture')['capture']);states.append(a.state())
        images=[Image.open(p).convert('RGB') for p in captures]
        thumbs=[im.resize((480,270)) for im in images]
        sheet=Image.new('RGB',(480*4,292*((len(images)+3)//4)),(15,20,18));draw=ImageDraw.Draw(sheet)
        for i,im in enumerate(thumbs):
            x=(i%4)*480;y=(i//4)*292;sheet.paste(im,(x,y));draw.text((x+8,y+273),f'{i*spacing/60:.2f}s',(220,220,220))
        contact=folder/(name+'.jpg');sheet.save(contact,quality=90)
        animation=folder/(name+'.webp');images[0].save(animation,save_all=True,append_images=images[1:],duration=int(spacing/60*1000),loop=0,lossless=True)
        (folder/(name+'.json')).write_text(json.dumps({'frames':captures,'states':states},ensure_ascii=False,indent=2),encoding='utf8')
        sequences.append({'name':name,'contact':str(contact),'animation':str(animation),'frames':captures})
        return states
    try:
        server=BankPeer(folder/'server',['--server',f'--port={port}']);peers.append(server)
        a=BankPeer(folder/'alpha',[],True);peers.append(a)
        b=BankPeer(folder/'bravo',[]);peers.append(b)
        for client,name in [(a,'Alpha'),(b,'Bravo')]:client.call('fields',nickname=name,port=port);client.call('click',control='join_button')
        until(lambda:len(server.state()['players'])==2 and len(a.state()['players'])==2 and len(b.state()['players'])==2,30);frames(30)
        server.call('fixture',name='firearms_range');frames(18)
        a.call('input',keys=['S']);states=sequence('predicted_walk',12,6);a.call('input');frames(24)
        assert states[-1]['prediction']['pending']<=120
        a.call('input',buttons=['left']);states=sequence('predicted_fire',12,3);a.call('input');frames(12)
        assert states[-1]['preview_shots']>0
        server.call('fixture',name='door_g_inner_a');frames(18)
        a.call('input',keys=['E']);frames(3);a.call('input');frames(102)
        assert a.state()['doors']['g_inner']['progress']>.98
        a.call('input',keys=['E']);frames(3);a.call('input');states=sequence('door_close',16,6)
        assert states[0]['doors']['g_inner']['progress']>states[-1]['doors']['g_inner']['progress']+.5
        a.call('menu');menu=a.call('capture')['capture'];sequences.append({'name':'session_menu','image':menu})
        checks.append({'name':'bank_network_rendered_sequences','status':'pass','normal_input':True,'frozen_between_steps':True})
        for peer in peers:
            text=(peer.folder/'engine.log').read_text(encoding='utf8');assert 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-1500:]
    finally:
        for peer in reversed(peers):peer.close()
        pool.shutdown()
        (folder/'report.json').write_text(json.dumps({'checks':checks,'sequences':sequences},ensure_ascii=False,indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)

if __name__=='__main__':main()
