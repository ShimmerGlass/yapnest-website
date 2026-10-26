#!/bin/sh
# Starts nginx with the real config and checks what a visitor and the app would get: each page, the redirects to the
# canonical URLs, the 404 page, the security headers, HSTS, the www redirect and compression.
set -eu

nginx
trap 'nginx -s stop' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS -o /dev/null http://127.0.0.1:8080/healthz 2>/dev/null && break
  sleep 0.5
done

base=http://127.0.0.1:8080
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
headers() { curl -s -D - -o /dev/null "$@" | tr -d '\r'; }

expect_status() { # path status
  got=$(status "$base$1")
  [ "$got" = "$2" ] && echo "ok   $1 -> $2" || fail "$1: expected $2, got $got"
}
expect_redirect() { # path location
  h=$(headers "$base$1")
  code=$(printf '%s\n' "$h" | sed -n '1s/[^ ]* \([0-9]*\).*/\1/p')
  loc=$(printf '%s\n' "$h" | sed -n 's/^[Ll]ocation: //p')
  [ "$code" = 301 ] && [ "$loc" = "$2" ] && echo "ok   $1 -> 301 $2" || fail "$1: expected 301 $2, got $code '$loc'"
}
expect_body() { # path text
  curl -s "$base$1" | grep -q "$2" && echo "ok   $1 contains '$2'" || fail "$1: missing '$2'"
}

for page in privacy terms support legal; do
  expect_status "/$page" 200
  expect_redirect "/$page/" "/$page"
  expect_redirect "/$page/index.html" "/$page"
done
expect_status / 200
expect_redirect /index.html /
expect_body / "<h1>Yapnest</h1>"
expect_body /privacy "Privacy"
expect_status /style.css 200
expect_status /icon.svg 200
expect_status /healthz 200
expect_status /nope 404
expect_status /privacy/nope 404
expect_status /404.html 404
expect_status /.git/config 404
expect_body /nope "Page not found"
[ "$(status -X POST "$base/")" = 405 ] && echo "ok   POST / -> 405" || fail "POST / should be 405"

for path in / /privacy /nope /style.css /privacy/; do
  h=$(headers "$base$path")
  for want in \
    "Content-Security-Policy: default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" \
    "X-Content-Type-Options: nosniff" \
    "Referrer-Policy: no-referrer" \
    "Strict-Transport-Security: max-age=63072000" \
    "Permissions-Policy: "; do
    printf '%s\n' "$h" | grep -qF "$want" || fail "$path: missing header '$want'"
  done
  printf '%s\n' "$h" | grep -qi '^server: nginx/' && fail "$path: Server header leaks the version"
done
echo "ok   security headers on pages, assets, errors and redirects"

# The proxy may pass the custom domain as Host or as X-Forwarded-Host, so both must redirect.
expect_www_redirect() { # description, curl options...
  desc=$1; shift
  h=$(headers "$@" "$base/privacy")
  code=$(printf '%s\n' "$h" | sed -n '1s/[^ ]* \([0-9]*\).*/\1/p')
  loc=$(printf '%s\n' "$h" | sed -n 's/^[Ll]ocation: //p')
  [ "$code" = 301 ] && [ "$loc" = https://yapnest.fr/privacy ] && echo "ok   $desc -> 301 $loc" || fail "$desc: expected 301 https://yapnest.fr/privacy, got $code '$loc'"
  printf '%s\n' "$h" | grep -qF "Strict-Transport-Security: max-age=63072000" || fail "$desc: redirect lacks HSTS"
  printf '%s\n' "$h" | grep -qF "X-Content-Type-Options: nosniff" || fail "$desc: redirect lacks security headers"
}
expect_www_redirect "Host www.yapnest.fr" -H 'Host: www.yapnest.fr'
expect_www_redirect "Host WWW.Yapnest.FR" -H 'Host: WWW.Yapnest.FR'
expect_www_redirect "X-Forwarded-Host www.yapnest.fr" -H 'Host: container.example' -H 'X-Forwarded-Host: www.yapnest.fr'
expect_www_redirect "X-Forwarded-Host WWW.Yapnest.FR" -H 'Host: container.example' -H 'X-Forwarded-Host: WWW.Yapnest.FR'
[ "$(status -H 'Host: yapnest.fr' "$base/privacy")" = 200 ] && echo "ok   Host yapnest.fr is not redirected" || fail "Host yapnest.fr should be served"
[ "$(status -H 'Host: yapnest.fr' -H 'X-Forwarded-Host: yapnest.fr' "$base/privacy")" = 200 ] || fail "X-Forwarded-Host yapnest.fr should be served"
[ "$(status -X POST -H 'Host: www.yapnest.fr' "$base/privacy")" = 405 ] && echo "ok   POST to www -> 405" || fail "POST to www should be 405"

headers "$base/style.css" | grep -qi '^cache-control: max-age=86400' || fail "css should cache for a day"
headers "$base/privacy" | grep -qi '^cache-control: max-age=300' || fail "html should cache for 5 minutes"
curl -s -H 'Accept-Encoding: gzip' -D - -o /dev/null "$base/privacy" | grep -qi '^content-encoding: gzip' || fail "html not gzipped"
curl -s -H 'Accept-Encoding: gzip' -D - -o /dev/null "$base/style.css" | grep -qi '^content-encoding: gzip' || fail "css not gzipped"
echo "ok   caching and gzip"

# No access log, so the visitors above left no trace.
[ -e /var/log/nginx/access.log ] && [ -s /var/log/nginx/access.log ] && fail "an access log was written"

[ "$fails" = 0 ] || { echo "$fails check(s) failed" >&2; exit 1; }
echo "smoke: all checks passed"
