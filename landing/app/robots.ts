import type { MetadataRoute } from 'next';

/** Public since the v0.1.0 launch: search engines may index the site (decision 33). */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: '*', allow: '/', disallow: ['/api/', '/download'] },
    sitemap: 'https://agentpots.com/sitemap.xml',
    host: 'https://agentpots.com',
  };
}
