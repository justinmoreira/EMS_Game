#!/usr/bin/env python3
"""Finds the first available TCP port starting from 8080."""
import socket

for p in range(8080, 9000):
    try:
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", p))
        s.close()
        print(p)
        break
    except OSError:
        pass
