import json,sys,base64,struct
for n in (1,2,3):
  for suf in ('','.Roblox'):
    p=f'D:/Dev/Roblox/Roblox Games/Colonies/Assets/Models/FarmerHut.Level{n}{suf}.gltf'
    g=json.load(open(p))
    mn=[1e9]*3;mx=[-1e9]*3;tris=0;meshes=0
    def walk(i,off):
        global tris,meshes
        nd=g['nodes'][i];t=nd.get('translation',[0,0,0]);s=nd.get('scale',[1,1,1]);o=[off[k]+t[k] for k in range(3)]
        if 'mesh' in nd:
            meshes+=1
            for pr in g['meshes'][nd['mesh']]['primitives']:
                a=g['accessors'][pr['attributes']['POSITION']]
                for k in range(3):
                    mn[k]=min(mn[k],o[k]+a['min'][k]*s[k]);mx[k]=max(mx[k],o[k]+a['max'][k]*s[k])
                tris+=(g['accessors'][pr['indices']]['count'] if 'indices' in pr else a['count'])//3
        for c in nd.get('children',[]):walk(c,o)
    for r in g['scenes'][g.get('scene',0)]['nodes']:walk(r,[0,0,0])
    imgs=len(g.get('images',[]))
    print(f'L{n}{suf}: meshes={meshes} tris={tris} min={[round(x,2) for x in mn]} max={[round(x,2) for x in mx]} images={imgs}')
