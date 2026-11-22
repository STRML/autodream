"""Test HTTP servers that do not resolve their own address.

http.server.HTTPServer.server_bind calls socket.getfqdn(host), a reverse DNS lookup that stalls
for many seconds on the macOS CI runner (#223). A test fixture server never reads server_name.
"""
from http.server import HTTPServer, ThreadingHTTPServer
import socketserver


class NoLookupBind:
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class LoopbackHTTPServer(NoLookupBind, HTTPServer):
    pass


class ThreadingLoopbackHTTPServer(NoLookupBind, ThreadingHTTPServer):
    pass
