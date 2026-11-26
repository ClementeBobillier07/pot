/**
 * Plant illustrations rendered by the macOS app's own renderer (`Pot --render-landing`), so the
 * website shows exactly what the app draws. Illustrative growth, not anyone's usage.
 * Stage 0 ≈ day 7, 1 ≈ day 21, 2 ≈ day 45, 3 = fully grown (day 90 of steady work).
 */
export type Provider = 'codex' | 'claude';
export type Variant = 'classic' | 'blossom';

export default function Plant({ provider = 'codex', variant = 'classic', stage = 3, className = '', label, eager = false }: {
  provider?: Provider; variant?: Variant; stage?: number; className?: string; label?: string; eager?: boolean;
}) {
  const name = provider === 'claude' ? 'Claude Code' : 'Codex';
  return <span className={`plant ${className}`} role="img" aria-label={label || `${name} plant illustration`}>
    <img className="plant-foliage" src={`/plants/${provider}-${variant}-${stage}.png`} alt="" width={320} height={400}
      loading={eager ? 'eager' : 'lazy'} decoding="async" draggable={false} />
  </span>;
}
