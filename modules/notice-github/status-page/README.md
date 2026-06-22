# Status page

A zero-dependency, zero-build status page for on-demand fargate services
(issue #140). It fetches the `state.json` that the
[`notice-github`](../) Lambda commits and renders one card per service —
status badge, cluster, "updated N ago", and a staleness warning.

Hosting it on GitHub Pages keeps it free: nothing runs on AWS to serve it.

## Files

| File         | Purpose                                                     |
| ------------ | ----------------------------------------------------------- |
| `index.html` | Page shell.                                                 |
| `app.js`     | Fetches `state.json`, renders cards, refreshes each 60s.    |
| `styles.css` | Dark theme, responsive card grid.                           |
| `state.json` | **Sample** data so the page renders standalone for preview. |

## Deploy

The page and the `state.json` it reads should live in the **same** repository so
the relative `fetch("state.json")` resolves — the repo the `notice-github`
Lambda writes to (`github_repo`).

1. Copy `index.html`, `app.js`, and `styles.css` into that repo (e.g. a `docs/`
   folder or the repo root). The Lambda writes `state.json` alongside them
   (`state_file_path`).
2. Enable GitHub Pages on that repo (Settings → Pages) pointed at the branch and
   folder you used.
3. Open the published URL. As services emit task-state events the Lambda commits
   `state.json` and the page reflects it on the next refresh.

> The bundled `state.json` is sample data for local preview. In production the
> Lambda overwrites it — don't hand-edit it. To preview locally, serve the
> folder (`python3 -m http.server`) rather than opening the file directly, so
> `fetch` works.

## Schema

The page renders against `schema_version: 1` of the
[`state.json` contract](../README.md#the-statejson-contract). If it sees a newer
`schema_version` it still renders and shows a banner noting some fields may not
display.
