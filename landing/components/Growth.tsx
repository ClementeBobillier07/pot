'use client';
import { useState } from 'react';
import Plant from './Plant';

const stages = [
  { stage: 0, title: 'A small beginning.', subtitle: 'A seedling. Every day of work adds a little.' },
  { stage: 1, title: 'Finding its shape.', subtitle: 'Leaves first, then branches. Each seed takes its own form.' },
  { stage: 3, title: 'In full bloom.', subtitle: 'After a season of steady work, a full plant whose flowers keep renewing.' },
];

export default function Growth() {
  const [index, setIndex] = useState(2);
  return <div className="growth-demo">
    <div className="growth-art"><Plant variant="blossom" stage={stages[index].stage} /><span className="art-note">Illustrative growth preview</span></div>
    <div className="growth-detail">
      <span className="eyebrow">A life of its own</span>
      <h2>No two plants<br/>grow alike.</h2>
      <p>A little of your rhythm. A little of its own nature. Your plant grows steadily with the days you work, takes about a season to bloom fully, and shows it when you’ve been away.</p>
      <div className="growth-tabs" role="group" aria-label="Explore illustrative growth">
        {['Sprout', 'Growing', 'Blooming'].map((name,i) => <button key={name} type="button" aria-pressed={index===i} onClick={()=>setIndex(i)}>{name}</button>)}
      </div>
      <div className="growth-caption" aria-live="polite"><strong>{stages[index].title}</strong><p>{stages[index].subtitle}</p></div>
      <p className="fine-print">A day off changes nothing. After a few days away it starts to look thirsty, and after two weeks it dries out. It never dies: a week of work brings it back.</p>
    </div>
  </div>;
}
