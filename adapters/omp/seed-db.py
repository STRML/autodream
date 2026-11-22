"""Seed one of omp's SQLite databases into a confined worker's throwaway state directory.

usage: seed-db.py <source db> <destination db> [--drop-oauth] [--provider NAME]

The source is a live database: omp processes write it and checkpoint its WAL while this runs, so a
file copy of the .db, .db-wal and .db-shm taken one after another can pair an old database with a
newer log. SQLite's backup API reads one consistent snapshot, whatever else is writing.

--drop-oauth removes the OAuth credential rows from the COPY (the source is opened read-only and is
never written). A worker that refreshed an OAuth token in its copy would rotate the refresh token
there, the copy is deleted with its stage, and a provider that invalidates the old refresh token
would leave the real database holding a spent one: the login is lost. A worker with no OAuth rows
cannot rotate anything.

--provider NAME (with --drop-oauth) refuses, exit 4, when the source holds OAuth credentials for that
provider and no other kind: leaving the OAuth rows out would leave the worker with nothing to log in
with, and the failure would read as a provider problem night after night. The caller runs the engine
unconfined instead and says so. A provider with no rows at all passes: its key comes from the
environment. An EMPTY name means the model selector carried no provider (omp resolves a bare or fuzzy
selector such as "opus" itself), so which credential the worker will use is unknown: any live OAuth
credential refuses, because it may be the one the selector resolves to. With no OAuth credential there is
nothing to lose and it passes.

Exit 0 on success, 4 for the OAuth-only refusal, 1 with a line on stderr for anything else.
"""
import pathlib
import sqlite3
import sys


def main(argv):
    argv = list(argv)
    provider = None  # None: no check. "": the selector named no provider. Otherwise the provider id.
    if "--provider" in argv:
        i = argv.index("--provider")
        if i + 1 >= len(argv):
            print("seed-db: --provider needs a name", file=sys.stderr)
            return 1
        provider = argv[i + 1]
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    flags = [a for a in argv if a.startswith("--")]
    if len(args) != 2 or any(f != "--drop-oauth" for f in flags):
        print("usage: seed-db.py <source db> <destination db> [--drop-oauth] [--provider NAME]", file=sys.stderr)
        return 1
    source, destination = args
    try:
        src = sqlite3.connect(pathlib.Path(source).resolve().as_uri() + "?mode=ro", uri=True)
        if provider is not None and "--drop-oauth" in flags:
            try:
                if provider:
                    kinds = {r[0] for r in src.execute(
                        "SELECT credential_type FROM auth_credentials WHERE provider = ? AND disabled_cause IS NULL", (provider,))}
                    refuse = kinds == {"oauth"}
                    what = "the %s provider authenticates with OAuth only" % provider
                else:
                    refuse = src.execute(
                        "SELECT 1 FROM auth_credentials WHERE credential_type = 'oauth' AND disabled_cause IS NULL LIMIT 1").fetchone() is not None
                    what = "the model selector names no provider and an OAuth credential exists, which it may resolve to"
            except sqlite3.OperationalError as exc:
                if "no such table" not in str(exc):
                    raise
                refuse = False
            if refuse:
                print("seed-db: %s, which a worker on a throwaway copy cannot refresh without losing the rotated token" % what,
                      file=sys.stderr)
                return 4
        dst = sqlite3.connect(destination)
        src.backup(dst)
        if "--drop-oauth" in flags:
            try:
                dropped = dst.execute("DELETE FROM auth_credentials WHERE credential_type = 'oauth'").rowcount
                dst.commit()
                if dropped:
                    print("seed-db: %d OAuth credential row(s) left out of the worker's copy" % dropped, file=sys.stderr)
            except sqlite3.OperationalError as exc:
                if "no such table" not in str(exc):
                    raise
        dst.close()
        src.close()
    except (sqlite3.Error, OSError) as exc:
        print("seed-db: %s: %s" % (source, exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
