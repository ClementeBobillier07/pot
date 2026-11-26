/**
 * Future "downloads plant trees" idea: set TREE_EVERY (e.g. 1000) to show how many trees the
 * community has planted and how far the next one is. 0 keeps the feature hidden. Only real,
 * counted installer downloads are used; nothing is promised before a partner/plan exists.
 */
export const TREE_EVERY = 0;

export function treeProgress(downloads: number, every = TREE_EVERY): { trees: number; toNext: number; fraction: number } | null {
  if (!(every > 0) || !Number.isFinite(downloads) || downloads < 0) return null;
  const trees = Math.floor(downloads / every);
  const into = downloads - trees * every;
  return { trees, toNext: every - into, fraction: into / every };
}
