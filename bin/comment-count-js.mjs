import { readFileSync } from "node:fs";
import { extname } from "node:path";

const DIRECTIVE = /^\s*(@ts-expect-error|@ts-ignore|oxlint-disable(?:-next-line|-line)?)(?=$|\s|:)/;

const KINDS = {
  ".js": "JS", ".mjs": "JS", ".cjs": "JS", ".jsx": "JSX",
  ".ts": "TS", ".mts": "TS", ".cts": "TS", ".tsx": "TSX",
};

const LEGACY_HTML_COMMENTS = new Set([".js", ".cjs"]);

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

let source;
try {
  source = new TextDecoder("utf-8", { fatal: true }).decode(readFileSync(0));
} catch {
  fail(2, path + ": not valid UTF-8");
}

function parse(code) {
  const file = ts.createSourceFile(path, code, ts.ScriptTarget.Latest, true, ts.ScriptKind[kind]);
  const host = {
    getSourceFile: (name) => (name === path ? file : undefined),
    getDefaultLibFileName: () => "lib.d.ts",
    writeFile() {},
    getCurrentDirectory: () => "/",
    getDirectories: () => [],
    fileExists: (name) => name === path,
    readFile: () => undefined,
    getCanonicalFileName: (name) => name,
    useCaseSensitiveFileNames: () => true,
    getNewLine: () => "\n",
  };
  const options = { allowJs: true, noResolve: true, noLib: true, jsx: ts.JsxEmit.Preserve };
  const program = ts.createProgram([path], options, host);
  return { file, diagnostics: program.getSyntacticDiagnostics(file) };
}

let text = source;
let parsed = parse(text);
if (parsed.diagnostics.length > 0 && LEGACY_HTML_COMMENTS.has(extname(path))) {
  const neutral = source.replace(/<!--/g, "//  ").replace(/^([ \t]*)-->/gm, "$1// ");
  const retry = parse(neutral);
  if (retry.diagnostics.length === 0) {
    text = neutral;
    parsed = retry;
  }
}
const file = parsed.file;
if (parsed.diagnostics.length > 0) {
  const first = parsed.diagnostics[0];
  const where = file.getLineAndCharacterOfPosition(first.start ?? 0);
  fail(2, path + ":" + (where.line + 1) + ": typescript could not parse it (" + ts.flattenDiagnosticMessageText(first.messageText, " ") + ")");
}

const comments = new Map();
function collect(ranges) {
  for (const range of ranges || []) comments.set(range.pos, range);
}

const jsxTextStarts = new Set();
const jsxCommentStarts = new Set();
function findJsx(node) {
  if (node.kind === ts.SyntaxKind.JsxText) jsxTextStarts.add(node.getFullStart());
  if (node.kind === ts.SyntaxKind.JsxExpression && !node.expression) jsxCommentStarts.add(node.getStart(file));
  ts.forEachChild(node, findJsx);
}
findJsx(file);

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

function inComment(index) {
  return spans.some((range) => range.pos <= index && index < range.end);
}

let count = 0;
let offset = 0;
for (const line of text.split(/\r\n|[\n\r\u2028\u2029]/)) {
  const first = line.search(/\S/);
  if (first !== -1) {
    const at = offset + first;
    const afterBrace = line[first] === "{" ? line.slice(first + 1).search(/\S/) : -1;
    const jsxAt = afterBrace === -1 ? -1 : at + 1 + afterBrace;
    const jsx = jsxAt !== -1 && jsxCommentStarts.has(at) && comments.has(jsxAt);
    const here = jsx ? comments.get(jsxAt) : comments.get(at);
    const exempt = here && here.kind === ts.SyntaxKind.SingleLineCommentTrivia && DIRECTIVE.test(source.slice(here.pos + 2, here.end));
    if ((jsx || inComment(at)) && !exempt) count += 1;
  }
  offset += line.length + (text.startsWith("\r\n", offset + line.length) ? 2 : 1);
}
process.stdout.write(count + "\n");
