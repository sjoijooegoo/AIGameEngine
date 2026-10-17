"""Current menu keyboard navigation and captures at common window aspect ratios."""
import argparse
import datetime
import json
from game.tests.verify_frontend import FrontendPeer, ROOT
from game.tests.verify_coop import until


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',choices=['bank'],required=True);parser.parse_args()
    folder=ROOT/'logs/sessions'/('bank-frontend-layout-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    print(folder,flush=True);peer=FrontendPeer(folder/'client',True);checks=[];captures=[]
    try:
        peer.call('act',keys=['Down']);peer.call('act',keys=['Enter'])
        until(lambda:peer.state()['page']=='multiplayer');peer.call('act',keys=['Escape'])
        until(lambda:peer.state()['page']=='home')
        checks.append({'name':'frontend_native_keyboard_navigation','status':'pass'})
        for width,height in [(1280,720),(800,600),(2560,1080)]:
            peer.call('resize',width=width,height=height)
            for page in ['home','multiplayer','settings','help']:
                if page!='home':peer.call('click',control=page)
                s=peer.state();assert s['bank_nodes']==0
                captures.append(peer.call('capture',name=f'{page}-{width}x{height}')['capture'])
                # The canvas expands to preserve its 1280x720 minimum; check
                # native control bounds and pairwise intersections in that space.
                vw=max(1280,width*720/height);vh=max(720,height*1280/width)
                controls=[(k,v['rect']) for k,v in s['controls'].items() if v['visible']]
                for name,(x,y,w,h) in controls:
                    assert min(x,y)>=0 and x+w<=vw+1 and y+h<=vh+1,(page,name,(x,y,w,h),(vw,vh))
                for index,(name,(x,y,w,h)) in enumerate(controls):
                    for other,(xx,yy,ww,hh) in controls[index+1:]:
                        assert not (min(x+w,xx+ww)-max(x,xx)>2 and min(y+h,yy+hh)-max(y,yy)>2),(page,name,other)
                if page!='home':peer.call('click',control='back')
            checks.append({'name':f'frontend_layout_{width}x{height}','status':'pass'})
    finally:
        peer.close();(folder/'report.json').write_text(json.dumps({'checks':checks,'captures':captures},indent=2),encoding='utf8')
    print(folder/'report.json',flush=True)


if __name__=='__main__':main()
