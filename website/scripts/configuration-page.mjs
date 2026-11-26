// Writes docs/configuration.md: the default config.yaml (config.example.yaml,
// which a test keeps equal to the built-in default) with a short intro.
// Generated before every build and dev server start; not in git.
import { readFileSync, writeFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const yaml = readFileSync(new URL('config.example.yaml', root), 'utf8').trimEnd();
writeFileSync(new URL('docs/configuration.md', root), `---
title: "Configuration reference"
editUrl: https://github.com/jklaiber/kachel/edit/main/config.example.yaml
---

<!-- Generated from config.example.yaml by website/scripts/configuration-page.mjs: edit that file. -->

This is the complete default \`config.yaml\`, with every option and its
explanation. Kachel writes exactly this on first launch, and
\`Kachel --print-default-config\` prints it.

\`\`\`yaml title="config.yaml"
${yaml}
\`\`\`
`);
