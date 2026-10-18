"""Offline ENet header audit. Emits no application payloads or recovery tokens."""
import collections,hashlib,json,struct,sys

def decode(path,game_port=24567):
    rows=[]
    with open(path,'rb') as f:
        h=f.read(24);endian='<' if h[:4].hex()=='d4c3b2a1' else '>'
        link=struct.unpack(endian+'I',h[20:24])[0];assert link in (1,113,276)
        while h:=f.read(16):
            sec,usec,length,_=struct.unpack(endian+'IIII',h);frame=f.read(length)
            assert len(frame)==length,'Truncated pcap'
            offset={1:14,113:16,276:20}[link];proto=frame[12:14] if link==1 else frame[14:16] if link==113 else frame[:2]
            if proto.hex()!='0800':continue
            ip=frame[offset:];ihl=(ip[0]&15)*4
            if ip[9]!=17 or struct.unpack('!H',ip[6:8])[0]&0x3fff:continue
            u=ip[ihl:];src,dst,n,_=struct.unpack('!HHHH',u[:8]);data=u[8:n]
            if src!=game_port and dst!=game_port:continue
            commands=[];head=struct.unpack('!H',data[:2])[0];pos=4 if head&0x8000 else 2
            while pos+4<=len(data) and not head&0x4000:
                cmd,ch,seq=struct.unpack('!BBH',data[pos:pos+4]);cmd&=15
                size={1:8,2:48,3:44,4:8,5:4,6:6,7:8,8:24,9:8,10:12,11:16,12:24}.get(cmd,0)
                if not size or pos+size>len(data):break
                payload=struct.unpack('!H',data[pos+(4 if cmd==6 else 6):pos+(6 if cmd==6 else 8)])[0] if cmd in (6,7,8,9,12) else 0
                item={'command':cmd,'channel':ch,'sequence':seq,'bytes':payload}
                if cmd==1:item['ack']=struct.unpack('!H',data[pos+4:pos+6])[0]
                commands.append(item);pos+=size+payload
            rows.append({'time':sec+usec/1e6,'direction':'down' if src==game_port else 'up','size':len(data),'hash':hashlib.sha256(data).hexdigest(),
                         'client_port':dst if src==game_port else src,'source_ip':'.'.join(map(str,ip[12:16])),
                         'destination_ip':'.'.join(map(str,ip[16:20])),'commands':commands})
    return rows

def reliability(rows):
    flows={}
    for row in rows:
        flow=flows.setdefault(row['client_port'],{'sent':{},'acks':set(),'disconnects':[]})
        for command in row['commands']:
            if row['direction']=='down' and command['command'] in (6,8):
                key=command['channel'],command['sequence'];entry=flow['sent'].setdefault(key,{'first':row['time'],'last':row['time'],'attempts':0,'bytes':command['bytes']})
                entry['last']=row['time'];entry['attempts']+=1
            if row['direction']=='up' and command['command']==1:flow['acks'].add((command['channel'],command['ack']))
            if command['command']==4:flow['disconnects'].append({'time':row['time'],'direction':row['direction']})
    return {port:{'unacked':[dict(channel=key[0],sequence=key[1],span=value['last']-value['first'],**value) for key,value in flow['sent'].items() if key not in flow['acks']],
                  'disconnects':flow['disconnects']} for port,flow in flows.items()}

if __name__=='__main__':
    print(json.dumps(reliability(decode(sys.argv[1],int(sys.argv[2]) if len(sys.argv)>2 else 24567))))
