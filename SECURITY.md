# Security

Kachel runs with Accessibility permission, so it can read and move every window
and receives global key presses. Problems that could let something else abuse
that are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through GitHub:
[Security → Report a vulnerability](https://github.com/jklaiber/kachel/security/advisories/new).

Include what an attacker could do, how to reproduce it, and the Kachel and macOS
versions. You'll get an answer within a week. Once it's fixed, the release notes
credit you unless you'd rather not.

## Supported versions

Only the latest release gets fixes. Upgrade with
`brew update && brew upgrade --cask kachel`.
