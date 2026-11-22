import { readFileSync } from "node:fs";
import { extname } from "node:path";

const DIRECTIVE = /^\s*(@ts-expect-error|@ts-ignore|oxlint-disable(?:-next-line|-line)?)(?=$|\s|:)/;

const KINDS = {
  ".js": "JS", ".mjs": "JS", ".cjs": "JS", ".jsx": "JSX",
  ".ts": "TS", ".mts": "TS", ".cts": "TS", ".tsx": "TSX",
};

function fail(code, message) {
  process.stderr.write(message + "\n");
  process.exit(code);
}

let ts;
try {
  ts = (await import("typescript")).default;
} catch (err) {
  fail(3, "the typescript module is not installed (" + err.code + "): run npm ci");
}

const path = process.argv[2] || "";
const kind = KINDS[extname(path)];
if (!kind) fail(2, path + ": not a JS or TS extension");

const text = readFileSync(0, "utf8").replace(/^﻿/, "");
const file = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true, ts.ScriptKind[kind]);
if (file.parseDiagnostics.length > 0) {
  const first = file.parseDiagnostics[0];
  const where = file.getLineAndCharacterOfPosition(first.start ?? 0);
  fail(2, path + ":" + (where.line + 1) + ": typescript could not parse it (" + ts.flattenDiagnosticMessageText(first.messageText, " ") + ")");
}

const comments = new Map();
function collect(ranges) {
  for (const range of ranges || []) comments.set(range.pos, range);
}

const jsxTextStarts = new Set();
function findJsxText(node) {
  if (node.kind === ts.SyntaxKind.JsxText) jsxTextStarts.add(node.getFullStart());
  ts.forEachChild(node, findJsxText);
}
findJsxText(file);

function visit(node) {
  if (!jsxTextStarts.has(node.getFullStart())) collect(ts.getLeadingCommentRanges(text, node.getFullStart()));
  if (node.getChildCount(file) === 0) {
    collect(ts.getTrailingCommentRanges(text, node.getEnd()));
    return;
  }
  for (const child of node.getChildren(file)) visit(child);
}
visit(file);

const spans = [...comments.values()];
const starts = new Set(spans.map((range) => range.pos));

function inComment(index) {
  return spans.some((range) => range.pos <= index && index < range.end);
}

let count = 0;
let offset = 0;
for (const line of text.split(/\r\n|\n|\r/)) {
  const first = line.search(/\S/);
  if (first !== -1) {
    const at = offset + first;
    const jsx = line[first] === "{" && starts.has(at + 1);
    const here = jsx ? comments.get(at + 1) : comments.get(at);
    const exempt = here && here.kind === ts.SyntaxKind.SingleLineCommentTrivia && DIRECTIVE.test(text.slice(here.pos + 2, here.end));
    if ((jsx || inComment(at)) && !exempt) count += 1;
  }
  offset += line.length + (text.startsWith("\r\n", offset + line.length) ? 2 : 1);
}
process.stdout.write(count + "\n");
