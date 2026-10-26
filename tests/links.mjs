// Every internal link and asset must resolve to what the server will serve. Links are absolute, so they are checked
// against the canonical URLs (/privacy, not /privacy/ or /privacy/index.html): a link to a redirect is a mistake.
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.argv[2] ?? "public";

function htmlFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return htmlFiles(path);
    return path.endsWith(".html") ? [path] : [];
  });
}

// The file that serves a canonical URL path, or null.
function fileFor(path) {
  if (path === "/") return join(root, "index.html");
  const folder = join(root, path, "index.html");
  if (/^\/[a-z]+$/.test(path) && existsSync(folder)) return folder;
  const file = join(root, path);
  return !path.endsWith("/") && existsSync(file) && statSync(file).isFile() && !file.endsWith("index.html")
    ? file
    : null;
}

let failures = 0;
function fail(page, message) {
  console.error(`${relative(root, page)}: ${message}`);
  failures += 1;
}

const pages = htmlFiles(root);
for (const page of pages) {
  const html = readFileSync(page, "utf8");
  for (const [, , url] of html.matchAll(/\s(href|src)="([^"]*)"/g)) {
    if (/^(mailto:|https:\/\/)/.test(url)) continue;
    if (/^[a-z]+:|^\/\//.test(url)) {
      fail(page, `unexpected scheme in ${url}`);
      continue;
    }
    if (!url.startsWith("/")) {
      fail(page, `${url} is not an absolute path`);
      continue;
    }
    const [path, fragment] = url.split("#");
    const file = fileFor(path);
    if (!file) {
      fail(page, `${url} does not resolve to a canonical URL or an asset`);
    } else if (fragment && !new RegExp(`\\sid="${fragment}"`).test(readFileSync(file, "utf8"))) {
      fail(page, `${url} points at a missing id`);
    }
  }
}

if (failures > 0) process.exit(1);
console.log(`links: ${pages.length} pages, all internal links and assets resolve`);
