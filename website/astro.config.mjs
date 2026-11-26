// The website: a home page of its own (src/pages/index.astro) and the
// documentation, written in ../docs as Markdown, shown with Starlight.
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

export default defineConfig({
  site: 'https://jklaiber.github.io',
  base: '/kachel',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Kachel',
      description: 'A native tiling window manager for macOS with xmonad’s workspace model.',
      logo: { src: '../docs/images/icon.svg' },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/jklaiber/kachel' }],
      editLink: { baseUrl: 'https://github.com/jklaiber/kachel/edit/main/' },
      routeMiddleware: './src/routeData.ts',
      customCss: ['./src/styles/docs.css'],
      // Broken links (and #anchors) fail the build, like `mkdocs build --strict` did.
      plugins: [starlightLinksValidator()],
      sidebar: [
        { label: 'Getting started', slug: 'getting-started' },
        { label: 'Coming from…', slug: 'coming-from' },
        {
          label: 'Using Kachel',
          items: [
            { label: 'Workspaces and displays', slug: 'workspaces' },
            { label: 'Layouts', slug: 'layouts' },
            { label: 'Keys', slug: 'keys' },
            { label: 'The bar', slug: 'bar' },
            { label: 'Window search and app rules', slug: 'window-search-and-rules' },
            { label: 'Scratchpads', slug: 'scratchpads' },
            { label: 'Mouse and trackpad', slug: 'mouse-and-trackpad' },
            { label: 'Command line', slug: 'command-line' },
          ],
        },
        {
          label: 'Configuration',
          items: [
            { label: 'Settings and config.yaml', slug: 'settings' },
            { label: 'Reference', slug: 'configuration' },
          ],
        },
        {
          label: 'Help',
          items: [
            { label: 'Troubleshooting', slug: 'troubleshooting' },
            { label: 'Development', slug: 'development' },
            { label: 'Changelog', link: 'https://github.com/jklaiber/kachel/blob/main/CHANGELOG.md' },
          ],
        },
      ],
    }),
  ],
});
