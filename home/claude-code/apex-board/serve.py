"""apex-board server: the board's temp root, read-only, on 127.0.0.1 only.

usage: python3 serve.py --directory ROOT PORT

python's `-m http.server` never checks the Host header, so any web page can
rebind its own DNS name to 127.0.0.1 and read runs/ and budget/ on the fixed
port. This handler is SimpleHTTPRequestHandler (directory listing,
Last-Modified / If-Modified-Since, GET and HEAD) with two gates in front:

  host_allowed  the Host header is exactly 127.0.0.1:PORT or localhost:PORT,
                else 403 (a rebound name carries its own host)
  path_allowed  the real path of the request sits under the real path of the
                root, of runs/ or of budget/, and is not a directory link
                back onto its own parent chain, else 404 (closes a symlink out
                of a run and a link loop the page would list forever)

The bind address is fixed here, never an argument. checks/apex-board.nix
imports the two gates and runs this file through the built launcher.
"""

import argparse
import functools
import os
import sys
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

BIND = "127.0.0.1"


def host_allowed(host, port):
    """True when HOST (the Host header, or None) names this server on loopback."""
    return host in (f"127.0.0.1:{port}", f"localhost:{port}")


def _under(path, root):
    root = root.rstrip(os.sep) or os.sep
    return path == root or path.startswith(root + os.sep) or root == os.sep


def path_allowed(path, roots):
    """True when the file-system PATH resolves under one of ROOTS and is no link loop."""
    lexical = os.path.normpath(path)
    real = os.path.realpath(lexical)
    if not any(_under(real, os.path.realpath(r)) for r in roots):
        return False
    # A link to its own directory or an ancestor (`loop -> .`, `up -> ..`):
    # the page lists directories recursively and would walk it without end.
    parent = os.path.realpath(os.path.dirname(lexical))
    return not (lexical != os.path.dirname(lexical) and _under(parent, real))


class Handler(SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler behind the Host and path gates; GET and HEAD only."""

    def __init__(self, *args, roots, **kwargs):
        self.roots = roots
        super().__init__(*args, **kwargs)

    def _gate(self):
        hosts = self.headers.get_all("Host") or []
        if len(hosts) != 1 or not host_allowed(hosts[0], self.server.server_address[1]):
            self.send_error(HTTPStatus.FORBIDDEN, "Host not allowed")
            return False
        if not path_allowed(self.translate_path(self.path), self.roots):
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return False
        return True

    def do_GET(self):
        if self._gate():
            super().do_GET()

    def do_HEAD(self):
        if self._gate():
            super().do_HEAD()

    def _refuse(self):
        self.send_error(HTTPStatus.METHOD_NOT_ALLOWED, "Read-only: GET and HEAD only")

    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _refuse


def main(argv=None):
    parser = argparse.ArgumentParser(prog="apex-board-serve")
    parser.add_argument("--directory", required=True)
    parser.add_argument("port", type=int)
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("port must be in 1-65535")
    directory = os.path.realpath(args.directory)
    roots = [directory, os.path.join(directory, "runs"), os.path.join(directory, "budget")]
    handler = functools.partial(Handler, directory=directory, roots=roots)
    with ThreadingHTTPServer((BIND, args.port), handler) as httpd:
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
