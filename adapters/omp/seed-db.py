"""Seed one of omp's SQLite databases into a confined worker's throwaway state directory.

usage: seed-db.py <source db> <destination db> [--drop-oauth]

The source is a live database: omp processes write it and checkpoint its WAL while this runs, so a
file copy of the .db, .db-wal and .db-shm taken one after another can pair an old database with a
newer log. SQLite's backup API reads one consistent snapshot, whatever else is writing.

--drop-oauth removes the OAuth credential rows from the COPY (the source is opened read-only and is
never written). A worker that refreshed an OAuth token in its copy would rotate the refresh token
there, the copy is deleted with its stage, and a provider that invalidates the old refresh token
would leave the real database holding a spent one: the login is lost. A worker with no OAuth rows
cannot rotate anything, and a call that needs one fails with a login error the runner classifies as a
provider failure (retried), not a lost login.

Exit 0 on success, 1 with a line on stderr otherwise.
"""
import pathlib
import sqlite3
import sys


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = [a for a in argv if a.startswith("--")]
    if len(args) != 2 or any(f != "--drop-oauth" for f in flags):
        print("usage: seed-db.py <source db> <destination db> [--drop-oauth]", file=sys.stderr)
        return 1
    source, destination = args
    try:
        src = sqlite3.connect(pathlib.Path(source).resolve().as_uri() + "?mode=ro", uri=True)
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
