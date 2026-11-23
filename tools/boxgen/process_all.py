import cv2, numpy as np, json, sys
PARITY_X={1:(67,1044),0:(195,1172)}
TPL=cv2.cvtColor(cv2.imread("p3.png"),cv2.COLOR_BGR2GRAY).astype(np.float32)[892-22:892+22,301-22:301+22]
meta=json.load(open("page_meta.json"))
def clean_ink(gray):
    ink=gray<135; H,W=ink.shape
    ink[:, ink.sum(0)>H*0.5]=False; ink[ink.sum(1)>W*0.5,:]=False
    ink[:115]=False; ink[1700:]=False; ink[:,:90]=False; ink[:,1180:]=False
    return ink
def detect_lines(ink):
    rs=ink.sum(1).astype(float); H=len(rs)
    on=rs>max(rs.max()*0.04,6); raw=[];st=None
    for y,v in enumerate(on):
        if v and st is None: st=y
        if not v and st is not None: raw.append([st,y-1]);st=None
    if st is not None: raw.append([st,H-1])
    raw=[b for b in raw if b[1]-b[0]>=6]
    if not raw: return []
    hs=sorted(b[1]-b[0] for b in raw); med=hs[len(hs)//2]
    raw=[b for b in raw if (b[1]-b[0])>=max(28,med*0.45)]
    pitch=med if med>40 else 70; out=[]
    for b0,b1 in raw:
        n=max(1,round((b1-b0)/pitch))
        if n==1: out.append([b0,b1]); continue
        seg=rs[b0:b1+1]; cuts=[]
        for _ in range(n-1):
            lo,hi=int((b1-b0)*0.12),int((b1-b0)*0.88); idx=None;best=1e18
            for j in range(lo,hi):
                if any(abs(j-c)<pitch*0.5 for c in cuts): continue
                if seg[j]<best: best=seg[j]; idx=j
            if idx is None: break
            cuts.append(idx)
        cuts=sorted(cuts); prev=b0
        for c in cuts: out.append([prev,b0+c]); prev=b0+c+1
        out.append([prev,b1])
    return out
def markers(gray,N):
    G=gray.astype(np.float32); pts=[]
    for sc in (0.8,0.9,1.0,1.1,1.2):
        t=cv2.resize(TPL,None,fx=sc,fy=sc); r=t.shape[0]//2
        res=cv2.matchTemplate(G,t,cv2.TM_CCOEFF_NORMED)
        ys,xs=np.where(res>0.30)
        for yy,xx in zip(ys,xs): pts.append((float(res[yy,xx]),int(xx+r),int(yy+r)))
    pts.sort(reverse=True); kept=[]
    for sc,x,y in pts:
        if 95<x<1155 and 120<y<1695 and all((x-kx)**2+(y-ky)**2>26**2 for kx,ky,_ in kept):
            kept.append((int(x),int(y),float(sc)))
    return kept
def page_boxes(pg):
    fn=f"scans/{pg}.png"; gray=cv2.cvtColor(cv2.imread(fn),cv2.COLOR_BGR2GRAY); H,W=gray.shape
    exp=meta[str(pg)]; N=len(exp)
    par=pg%2; Lpar,Rpar=PARITY_X[par]
    ink=clean_ink(gray.copy()); lines=detect_lines(ink)
    if not lines: return [],{"pg":pg,"status":"no_lines"}
    # On surah-start pages, drop ornamental header bands (high density) and basmala bands (low density).
    n_starts=sum(1 for s,a in exp if a==1 and s!=1)
    if n_starts>0 and len(lines)>4:
        dens=[ink[b0:b1+1].mean() for b0,b1 in lines]
        keep=[]
        hdr=sorted(range(len(lines)),key=lambda i:-dens[i])[:n_starts]
        hdr=[i for i in hdr if dens[i]>0.12]
        bas=sorted(range(len(lines)),key=lambda i:dens[i])[:n_starts]
        bas=[i for i in bas if dens[i]<0.078]
        drop=set(hdr)|set(bas)
        lines=[b for i,b in enumerate(lines) if i not in drop]
    lx=[]
    for b0,b1 in lines:
        cols=np.where(ink[b0:b1+1].sum(0)>(b1-b0)*0.12)[0]
        lx.append((max(int(cols.min()),Lpar),min(int(cols.max()),Rpar)) if len(cols) else (Lpar,Rpar))
    mall=markers(gray,N)
    found=len(mall)
    mk=mall[:N]
    nth=mk[-1][2] if len(mk)>=N else None
    nxt=mall[N][2] if found>N else None
    mk=sorted([(x,y) for x,y,s in mk],key=lambda m:(min(range(len(lines)),key=lambda i:abs((lines[i][0]+lines[i][1])/2-m[1])),-m[0]))
    lo=lambda y:min(range(len(lines)),key=lambda i:abs((lines[i][0]+lines[i][1])/2-y))
    out=[]; prev=None
    for k,(mx,my) in enumerate(mk):
        s,a=exp[k]; li=lo(my)
        pl,px=(0,lx[0][1]) if prev is None else prev
        rects=[(li,mx,px)] if pl==li else [(pl,lx[pl][0],px)]+[(L,lx[L][0],lx[L][1]) for L in range(pl+1,li)]+[(li,mx,lx[li][1])]
        nr=[[round(x0/W,4),round(lines[l][0]/H,4),round((x1-x0)/W,4),round((lines[l][1]-lines[l][0])/H,4)] for l,x0,x1 in rects]
        out.append({"s":s,"a":a,"r":nr}); prev=(li,mx)
    diag={"pg":pg,"N":N,"found":found,"lines":len(lines),"nth":round(nth,3) if nth else None,"next":round(nxt,3) if nxt else None,"ok":found>=N}
    return out,diag
data={}; diags=[]
for pg in range(3,605):
    boxes,d=page_boxes(pg); data[str(pg)]=boxes; diags.append(d)
    if pg%100==0: print("...",pg)
json.dump(data,open("/Users/sohaib/code/quran-mac/Sources/Mushaf/Resources/boxes.json","w"),separators=(',',':'))
json.dump(diags,open("diags.json","w"))
bad=[d for d in diags if not d.get("ok")]
lowgap=[d for d in diags if d.get("ok") and d.get("next") and d.get("nth") and d["next"]>d["nth"]-0.03]
print(f"\nDONE: {len(data)} pages")
print(f"  missing medallions (found<N): {len(bad)} pages")
print(f"  weak score gap (ambiguous Nth vs N+1): {len(lowgap)} pages")
print("  worst missing:",[(d['pg'],d['found'],d['N']) for d in bad[:15]])
