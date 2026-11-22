#!/usr/bin/env python3
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tokenize

DATA_EXTENSIONS = {
    ".md", ".json", ".yml", ".yaml", ".html", ".css", ".txt", ".tsv", ".jsonl",
    ".conf", ".plist", ".example", ".svg", ".png", ".gif", ".jq",
}
SHELL_EXTENSIONS = {".sh"}
PYTHON_EXTENSIONS = {".py"}
JS_EXTENSIONS = {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"}

SHELL_DIRECTIVE = re.compile(r"\s*shellcheck\s+(disable|source|shell)=")
PYTHON_DIRECTIVE = re.compile(
    r"\s*(noqa(?=$|\s|:)|type:\s*ignore(?=$|\s|\[)|pragma:\s*\S)"
)
JS_DIRECTIVE = re.compile(
    r"\s*(@ts-expect-error|@ts-ignore|oxlint-disable(?:-next-line|-line)?)(?=$|\s|:)"
)

REGEX_PRECEDERS = set("(,=:[!&|?{};+-*%<>~^")
CONTROL_KEYWORDS = {"if", "while", "for", "with"}
REGEX_KEYWORDS = {
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "throw", "case", "do", "else", "yield", "await",
}


class CountError(Exception):
    pass


def read_bytes(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError as err:
        raise CountError("%s: cannot read (%s)" % (path, err.strerror or err))


def decode(path, data):
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as err:
        raise CountError("%s: not valid UTF-8 (%s)" % (path, err))


def language_of(path, data):
    ext = os.path.splitext(path)[1]
    if ext in SHELL_EXTENSIONS:
        return "sh"
    if ext in PYTHON_EXTENSIONS:
        return "py"
    if ext in JS_EXTENSIONS:
        return "js"
    if ext in DATA_EXTENSIONS:
        return None
    first = data.split(b"\n", 1)[0]
    if not first.startswith(b"#!"):
        return None
    if b"python" in first:
        return "py"
    if re.search(rb"bash|/sh(\s|$)|env\s+sh(\s|$)", first):
        return "sh"
    return None


def shfmt_json_flag(binary):
    for flag in ("--to-json", "-tojson"):
        probe = subprocess.run(
            [binary, flag, "-ln", "bash"], input=b"true\n", capture_output=True
        )
        if probe.returncode == 0:
            return flag
    raise CountError("shfmt at %s accepts neither --to-json nor -tojson" % binary)


class Shfmt:
    def __init__(self):
        self.binary = None
        self.flag = None

    def locate(self):
        if self.binary is not None:
            return
        wanted = os.environ.get("COMMENT_COUNT_SHFMT", "shfmt")
        found = shutil.which(wanted)
        if found is None:
            raise CountError(
                "shfmt not found (%s): the ratchet parses shell with it and cannot count "
                "without it. Install it: brew install shfmt, or apt-get install shfmt" % wanted
            )
        self.flag = shfmt_json_flag(found)
        self.binary = found

    def tree(self, path, data):
        self.locate()
        run = subprocess.run(
            [self.binary, self.flag, "-ln", "bash"], input=data, capture_output=True
        )
        if run.returncode != 0:
            detail = run.stderr.decode("utf-8", "replace").strip().splitlines()
            raise CountError("%s: shfmt could not parse it (%s)" % (path, detail[0] if detail else "exit %d" % run.returncode))
        try:
            return json.loads(run.stdout)
        except ValueError as err:
            raise CountError("%s: shfmt printed JSON that does not parse (%s)" % (path, err))


SHFMT = Shfmt()


def comment_nodes(node):
    stack = [node]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if isinstance(current.get("Hash"), dict):
                yield current
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)


def comment_offset(path, node):
    for key in ("Hash", "Pos"):
        pos = node.get(key)
        if isinstance(pos, dict) and isinstance(pos.get("Offset"), int):
            return pos["Offset"]
    raise CountError("%s: shfmt comment node carries no offset" % path)


def count_shell(path, data):
    tree = SHFMT.tree(path, data)
    starts = {}
    for node in comment_nodes(tree):
        offset = comment_offset(path, node)
        if data[offset:offset + 1] != b"#":
            raise CountError("%s: shfmt comment offset %d does not point at a '#'" % (path, offset))
        starts[offset] = node.get("Text", "")
    lines = set()
    for offset, text in starts.items():
        line_start = data.rfind(b"\n", 0, offset) + 1
        if data[line_start:offset].strip() != b"":
            continue
        if line_start == 0 and text.startswith("!"):
            continue
        if SHELL_DIRECTIVE.match(text):
            continue
        lines.add(line_start)
    return len(lines)


def count_python(path, data):
    lines = set()
    try:
        for token in tokenize.tokenize(io.BytesIO(data).readline):
            if token.type != tokenize.COMMENT:
                continue
            row, col = token.start
            if token.line[:col].strip() != "":
                continue
            body = token.string[1:]
            if row == 1 and body.startswith("!"):
                continue
            if PYTHON_DIRECTIVE.match(body):
                continue
            lines.add(row)
    except (tokenize.TokenError, SyntaxError, UnicodeError) as err:
        raise CountError("%s: python could not tokenize it (%s)" % (path, err))
    return len(lines)


class JsScanner:
    def __init__(self, path, text):
        self.path = path
        self.text = text
        self.n = len(text)
        self.i = 0
        self.line = 1
        self.code_lines = set()
        self.comment_lines = {}
        self.prev = ""
        self.prev2 = ""
        self.word = ""
        self.stack = []
        self.parens = []
        self.paren_is_control = False

    def peek(self, k=0):
        j = self.i + k
        return self.text[j] if j < self.n else ""

    def newline(self):
        self.line += 1

    def break_length(self, at):
        if self.text[at:at + 2] == "\r\n":
            return 2
        if self.text[at:at + 1] == "\n":
            return 1
        return 0

    def set_prev(self, ch, word=""):
        self.prev2 = self.prev
        self.prev = ch
        self.word = word

    def code(self):
        self.code_lines.add(self.line)

    def note_comment(self, line, directive):
        if line not in self.comment_lines or not directive:
            self.comment_lines[line] = directive

    def line_comment(self):
        end = self.text.find("\n", self.i)
        end = self.n if end < 0 else end
        body = self.text[self.i + 2:end]
        directive = bool(JS_DIRECTIVE.match(body)) or (self.line == 1 and self.text.startswith("#!"))
        self.note_comment(self.line, directive)
        self.i = end

    def block_comment(self):
        start = self.i
        end = self.text.find("*/", start + 2)
        if end < 0:
            raise CountError("%s: block comment starting at line %d is never closed" % (self.path, self.line))
        for _ in range(start, end + 2):
            ch = self.text[self.i]
            if ch == "\n":
                self.newline()
            elif not ch.isspace():
                self.note_comment(self.line, False)
            self.i += 1

    def string(self, quote):
        self.code()
        self.i += 1
        while self.i < self.n:
            ch = self.text[self.i]
            if ch == "\\":
                brk = self.break_length(self.i + 1)
                self.i += 1 + (brk or 1)
                if brk:
                    self.newline()
                    self.code()
                continue
            if ch == "\n":
                return
            self.i += 1
            if ch == quote:
                return

    def template(self):
        self.code()
        while self.i < self.n:
            ch = self.text[self.i]
            if ch == "\\":
                brk = self.break_length(self.i + 1)
                self.i += 1 + (brk or 1)
                if brk:
                    self.newline()
                self.code()
                continue
            if ch == "\n":
                self.newline()
                self.i += 1
                self.code()
                continue
            if ch == "`":
                self.i += 1
                return True
            if ch == "$" and self.peek(1) == "{":
                self.i += 2
                self.stack.append(0)
                return False
            self.i += 1
        raise CountError("%s: template literal is never closed" % self.path)

    def regex(self):
        self.code()
        self.i += 1
        in_class = False
        while self.i < self.n:
            ch = self.text[self.i]
            if ch == "\n":
                return
            self.i += 1
            if ch == "\\":
                self.i += 1
            elif ch == "[":
                in_class = True
            elif ch == "]":
                in_class = False
            elif ch == "/" and not in_class:
                return

    def regex_allowed(self):
        if self.prev == "":
            return True
        if self.prev == ")":
            return self.paren_is_control
        if self.prev == "}":
            return True
        if self.prev in "+-" and self.prev2 == self.prev:
            return False
        if self.prev in REGEX_PRECEDERS:
            return True
        return self.word in REGEX_KEYWORDS

    def mark(self, ch):
        self.code()
        in_word = bool(self.prev) and (self.prev.isalnum() or self.prev in "_$")
        if ch == "(":
            self.parens.append(in_word and self.word in CONTROL_KEYWORDS)
        elif ch == ")":
            self.paren_is_control = self.parens.pop() if self.parens else False
        if ch.isalnum() or ch in "_$":
            word = self.word + ch if in_word else ch
        else:
            word = ""
        self.set_prev(ch, word)

    def run(self):
        in_template = False
        while self.i < self.n:
            if in_template:
                self.set_prev("`" if self.template() else "{")
                in_template = False
                continue
            ch = self.text[self.i]
            if ch == "\n":
                self.newline()
                self.i += 1
                continue
            if ch.isspace():
                self.i += 1
                continue
            nxt = self.peek(1)
            if ch == "/" and nxt == "/":
                self.line_comment()
            elif ch == "/" and nxt == "*":
                self.block_comment()
            elif ch in "'\"":
                self.string(ch)
                self.set_prev(ch)
            elif ch == "`":
                self.i += 1
                in_template = True
            elif ch == "/" and self.regex_allowed():
                self.regex()
                self.set_prev("/")
            elif ch == "#" and self.i == 0 and nxt == "!":
                self.line_comment()
            else:
                if self.stack and ch == "{":
                    self.stack[-1] += 1
                elif self.stack and ch == "}":
                    if self.stack[-1] == 0:
                        self.stack.pop()
                        self.i += 1
                        in_template = True
                        continue
                    self.stack[-1] -= 1
                self.mark(ch)
                self.i += 1
        if self.stack:
            raise CountError("%s: template expression is never closed" % self.path)

    def count(self):
        self.run()
        return sum(
            1
            for line, directive in self.comment_lines.items()
            if not directive and line not in self.code_lines
        )


def count_js(path, data):
    return JsScanner(path, decode(path, data)).count()


COUNTERS = {"sh": count_shell, "py": count_python, "js": count_js}


def count_file(path):
    data = read_bytes(path)
    lang = language_of(path, data)
    if lang is None:
        return None
    if any(ch in path for ch in "\t\n\r"):
        raise CountError("%r: a tab or newline in a path cannot be listed one file per line" % path)
    return COUNTERS[lang](path, data)


def tracked_files(repo):
    run = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True)
    if run.returncode != 0:
        detail = run.stderr.decode("utf-8", "replace").strip()
        raise CountError("git ls-files failed in %s (%s)" % (repo, detail))
    return [name for name in run.stdout.decode("utf-8", "surrogateescape").split("\0") if name]


def stat_or_none(path, follow):
    try:
        return (os.stat if follow else os.lstat)(path)
    except FileNotFoundError:
        return None
    except OSError as err:
        raise CountError("%s: cannot stat (%s)" % (path, err.strerror or err))


def is_countable_entry(path):
    info = stat_or_none(path, False)
    if info is not None and stat.S_ISLNK(info.st_mode):
        info = stat_or_none(path, True)
    return info is not None and stat.S_ISREG(info.st_mode)


def usage():
    print(
        "usage: comment-count.sh [--repo DIR] [FILE...]\n\n"
        "Prints \"<count><TAB><path>\" for each code file: the number of real comment\n"
        "lines in it. With no FILE, counts every tracked file under --repo (default: the\n"
        "checkout this script lives in) whose language it knows.\n\n"
        "A real comment is a full line that holds only a comment, found by a parser: shfmt\n"
        "for shell, tokenize for Python, a scanner for JS/TS. Not counted: a shebang, the\n"
        "exact directive forms (shellcheck disable=/source=/shell=, noqa, type: ignore,\n"
        "pragma:, @ts-expect-error, @ts-ignore, oxlint-disable), and anything inside a\n"
        "string or heredoc. A file it cannot read or parse, or a missing shfmt, is an\n"
        "error and exit 1, never a zero."
    )


def main(argv):
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = argv[1:]
    if args[:1] in (["-h"], ["--help"]):
        usage()
        return 0
    if args[:1] == ["--repo"]:
        if len(args) < 2:
            raise CountError("--repo needs a directory")
        repo = args[1]
        args = args[2:]
    if args:
        paths = args
    else:
        paths = tracked_files(repo)
        os.chdir(repo)
    rows = []
    failures = []
    for path in paths:
        try:
            if not args and not is_countable_entry(path):
                continue
            count = count_file(path)
        except CountError as err:
            failures.append(str(err))
            continue
        if count is not None:
            rows.append((path, count))
    if failures:
        for message in failures:
            print("comment-count: " + message, file=sys.stderr)
        return 1
    for path, count in sorted(rows, key=lambda row: row[0].encode("utf-8", "surrogateescape")):
        sys.stdout.write("%d\t%s\n" % (count, path))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except CountError as err:
        print("comment-count: " + str(err), file=sys.stderr)
        sys.exit(1)
