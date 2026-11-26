import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

// src/content/docs is a link to the repository's docs/ folder: the pages stay
// there, next to their images, where the README and scripts expect them.
export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
};
