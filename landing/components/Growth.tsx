'use client';
import { useState } from 'react';
import Plant from './Plant';

const stages = [
  { title: 'A small beginning.', subtitle: 'A tiny sprout, getting to know your rhythm.' },
  { title: 'Finding its shape.', subtitle: 'Each leaf takes its own time. Every stem has a story.' },
  { title: 'Always becoming.', subtitle: 'New leaves. Unexpected flowers. A garden that keeps changing.' },
];

export default function Growth() {
  const [stage, setStage] = useState(2);
  return <div className="growth-demo">
    <div className="growth-art"><Plant stage={stage} /><span className="art-note">Illustrative growth preview</span></div>
    <div className="growth-detail">
      <span className="eyebrow">A life of its own</span>
      <h2>No two plants<br/>grow alike.</h2>
      <p>A little of your rhythm. A little of its own nature. Leaves grow individually, buds slowly open, and old growth makes room for something new.</p>
      <div className="growth-tabs" role="group" aria-label="Explore illustrative growth">
        {['Sprout', 'Growing', 'Blooming'].map((name,i) => <button key={name} type="button" aria-pressed={stage===i} onClick={()=>setStage(i)}>{name}</button>)}
      </div>
      <div className="growth-caption" aria-live="polite"><strong>{stages[stage].title}</strong><p>{stages[stage].subtitle}</p></div>
      <p className="fine-print">Your plant starts small and learns your pace over three days. Growth has no finish line, and no daily target to chase.</p>
    </div>
  </div>;
}
