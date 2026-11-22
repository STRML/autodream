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


def count_js(path, data):
    in_block = False
    count = 0
    for raw in decode(path, data).splitlines():
        text = raw.lstrip()
        if in_block:
            count += 1
            in_block = "*/" not in text
        elif text.startswith("//"):
            if not JS_DIRECTIVE.match(text[2:]):
                count += 1
        elif text.startswith("/*"):
            count += 1
            in_block = "*/" not in text[2:]
    return count


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
    names = run.stdout.decode("utf-8", "surrogateescape").split("\0")
    return list(dict.fromkeys(name for name in names if name))


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
