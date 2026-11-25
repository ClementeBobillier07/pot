import { useId } from 'react';

type LeafSpec = [number, number, number, number, number];
const codexLeaves: LeafSpec[] = [[151,241,-147,45,0],[151,222,-35,47,1],[148,194,-145,53,1],[150,178,-27,53,2],[151,149,-150,53,0],[155,125,-36,46,1],[160,95,-145,42,2],[163,71,-32,39,2]];
const claudeLeaves: LeafSpec[] = [[153,241,-133,55,1],[151,220,-45,58,0],[134,194,-151,50,2],[161,179,-31,57,1],[131,154,-136,53,1],[177,145,-51,61,0],[144,117,-147,57,0],[168,103,-36,45,2]];

export default function Plant({ provider = 'codex', stage = 3, className = '', label }: { provider?: 'codex' | 'claude'; stage?: number; className?: string; label?: string }) {
  const id = useId();
  const claude = provider === 'claude';
  const palette = claude ? ['#537850','#6e915c','#9cab76'] : ['#477c60','#63976f','#9db68d'];
  const leaves = (claude ? claudeLeaves : codexLeaves).slice(0, stage === 0 ? 2 : stage === 1 ? 4 : 8);
  const stemTop = stage === 0 ? 215 : stage === 1 ? 165 : 58;
  return <svg className={`plant ${className}`} viewBox="0 0 310 385" role="img" aria-labelledby={id}>
    <title id={id}>{label || `${claude ? 'Claude Code' : 'Codex'} plant illustration`}</title>
    <ellipse cx="155" cy="365" rx="78" ry="9" fill="#223b2b" opacity=".09" />
    <g className="plant-foliage">
      <path d={`M155 288 C142 230 151 156 165 ${stemTop}`} fill="none" stroke={claude ? '#73864c' : '#55815b'} strokeWidth="4.2" strokeLinecap="round" />
      {claude && stage > 1 && <g fill="none" stroke="#73864c" strokeWidth="3.5" strokeLinecap="round"><path d="M155 272Q210 223 214 127"/><path d="M153 255Q112 203 112 143"/><path d="M158 205Q184 171 179 100"/></g>}
      {leaves.map(([x,y,angle,size,color], i) => <g key={i} transform={`translate(${x} ${y}) rotate(${angle})`}>
        <path d={claude ? `M0 0Q${size*.28} ${-size*.52} ${size} 0Q${size*.3} ${size*.33} 0 0` : `M0 0C${size*.1} ${-size*.68} ${size*.92} ${-size*.62} ${size} 0C${size*.82} ${size*.55} ${size*.15} ${size*.58} 0 0`} fill={palette[color]} />
      </g>)}
      {stage >= 2 && <>
        <path d={claude ? 'M160 177Q123 141 113 117M172 159Q206 123 219 96M161 119Q165 81 172 56' : 'M150 171Q111 143 108 113M158 142Q202 134 219 143M160 116Q169 79 167 58'} fill="none" stroke={claude ? '#73864c' : '#55815b'} strokeWidth="3.4" strokeLinecap="round" />
        <Flower x={claude ? 113 : 108} y={claude ? 117 : 113} color={claude ? '#e79c77' : '#e4c761'} petals={claude ? 6 : 5} />
        <Flower x="219" y={claude ? 96 : 143} color={claude ? '#db8069' : '#f2e9ba'} petals={claude ? 6 : 5} />
        <Flower x={claude ? 172 : 167} y={claude ? 56 : 58} color={claude ? '#f1d69b' : '#dfb5cd'} petals={claude ? 6 : 5} />
        {claude && <><path d="M143 222Q107 204 83 181" fill="none" stroke="#73864c" strokeWidth="3"/><Flower x="83" y="181" color="#ae94c0" petals={6}/></>}
      </>}
      {stage === 1 && <g><path d="M152 188L169 153" fill="none" stroke="#55815b" strokeWidth="3"/><ellipse cx="170" cy="151" rx="5" ry="8" fill={claude ? '#e79c77' : '#dfb5cd'}/></g>}
    </g>
    {claude ? <g><path d="M85 294H225L212 353Q155 369 98 353Z" fill="#bb7b59"/><rect x="78" y="282" width="154" height="22" rx="6" fill="#d49d7d"/><path d="M95 309L107 348" fill="none" stroke="#d99e7c" strokeWidth="6" strokeLinecap="round"/></g> : <g><path d="M88 289H222V344Q222 360 203 360H107Q88 360 88 341Z" fill="#74998d"/><rect x="86" y="282" width="138" height="17" rx="6" fill="#91afa3"/><path d="M100 306V339Q100 348 110 348" fill="none" stroke="#a8c0b4" strokeWidth="6" strokeLinecap="round" opacity=".7"/></g>}
  </svg>;
}

function Flower({ x, y, color, petals }: { x: number | string; y: number | string; color: string; petals: number }) {
  return <g transform={`translate(${x} ${y})`}>
    {Array.from({length: petals}, (_,i) => <ellipse key={i} cx="0" cy="-12" rx="8" ry="17" transform={`rotate(${i*360/petals})`} fill={color}/>)}
    <circle r="8.5" fill="#c49c49"/>
  </g>;
}
