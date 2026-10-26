# yapnest-website

The static website behind `https://yapnest.fr`: a home page, the privacy policy, the terms of use, support and the legal notice. It is
plain HTML and one stylesheet, with no JavaScript, no build step and nothing loaded from other sites, so the privacy
policy page doesn't contradict itself. This repo also holds what serves it: an nginx config, a Dockerfile and CI. It
used to live in the app repo as `site/`, and its history came with it.

- `public/`: the pages (`index.html`, `privacy/`, `terms/`, `support/`, `legal/`, `404.html`), `style.css` and `icon.svg`
  (a copy of the app's `design/app-icon/AppIcon.svg`). Each page repeats the header and footer.
- `nginx.conf`: the server. `Dockerfile`: the image, and the `test` stage that checks it.
- `tests/`, `.htmlvalidate.json`: the checks the `test` stage runs.
- `.github/workflows/`: `test.yml` on every push and pull request, `image.yml` on `v*` tags.

## Preview

```sh
docker build -t yapnest-website .
docker run --rm -p 8080:8080 yapnest-website
```

Then open http://localhost:8080. The build runs the checks first. To run only them: `docker build --target test .`.
Links are absolute (`/privacy`), so the pages need to be served from the root, as the image does.

## The URL contract with the app

The app opens these from Settings (`YapnestPrivacyPolicyURL`, `YapnestTermsURL`, `YapnestSupportURL` in the app's
`project.yml`), and App Store Connect points at them too. They must keep working:

- `https://yapnest.fr/privacy`
- `https://yapnest.fr/terms`
- `https://yapnest.fr/support` (the app's support item is `mailto:support@yapnest.fr` today; the page is the
  App Store's support URL)

The canonical form has no trailing slash. `/privacy/` and `/privacy/index.html` redirect to `/privacy` with a 301, and
`/index.html` to `/`. The smoke test in `tests/smoke.sh` checks all of it.

## What the server does

- Security headers on every response, redirects and errors included: a CSP of `default-src 'none'` that allows only
  same-origin styles and images (the pages have no inline styles or scripts), `frame-ancestors 'none'`,
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and a `Permissions-Policy` that turns features off.
- **No access log.** The privacy policy makes no statement about visitors to the website, so the server keeps no
  record of them: no IP addresses, no paths. Errors still go to stderr. If you ever turn the log on, add a sentence
  to the privacy policy first.
- `server_tokens off`, gzip for HTML, CSS and SVG, 5 minutes of caching for pages and a day for CSS and SVG.
- `Strict-Transport-Security: max-age=63072000` on every response, without `includeSubDomains` (`push.yapnest.fr` is not a
  website) or `preload`.
- `www.yapnest.fr` gets a 301 to the same path on `https://yapnest.fr`, whether the proxy passes the domain in `Host` or
  in `X-Forwarded-Host`. The redirect carries the same headers.
- `GET` and `HEAD` only, checked before the www redirect, so a POST to www is refused rather than turned into a GET.
- `/healthz` answers `200 ok`; the image's `HEALTHCHECK` uses it.

The image is `nginxinc/nginx-unprivileged` (nginx 1.30.5 on alpine, pinned by digest). It runs as uid 101 and listens
on 8080, so it needs no root and no capabilities, and works with a read-only root filesystem and a `/tmp` tmpfs.

## Tests

The Dockerfile's `test` stage runs, in this order: `html-validate` on every page, a check that every internal link
and asset resolves to a canonical URL (`tests/links.mjs`), `nginx -t`, and `tests/smoke.sh`, which starts nginx and
curls each page, redirect, the 404, the headers, caching and gzip. The final image mounts a file the stage creates
when it passes, so a failing check fails the image. Running the checks in the build means CI needs only Docker, and
tests the same nginx the image ships.

## Deploy

On a `v*` tag, `image.yml` builds the image for amd64 and pushes `ghcr.io/shimmerglass/yapnest-website:<tag>`
and `:latest` with the workflow's own token, so the repo needs no secret. The site runs as a Scaleway Serverless
Container pinned to a tag, with no reverse proxy of our own in front: a release is a tag here, then pointing the
container at it.

**TLS and the HTTP to HTTPS redirect are Scaleway's; HSTS and the www redirect are the image's.** The container speaks
plain HTTP on 8080 and terminates nothing. Scaleway's edge terminates TLS and redirects plain HTTP before a request
arrives, but it can't set response headers or redirect by host, so nginx sends `Strict-Transport-Security` and
redirects `www.yapnest.fr` itself. Browsers only ever reach this origin through the edge's HTTPS, so the header is
always seen over a secure connection.

## License

Free software under the GNU Affero General Public License, version 3 or later, like the app (`NOTICE`, with the
licence's text in `LICENSE`). `public/icon.svg` comes from the app's repo under the same licence.

Copyright © 2026 Mathilde Gilles.
