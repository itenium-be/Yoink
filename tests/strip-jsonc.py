#!/usr/bin/env python3
"""Strip // line and /* block */ comments from JSONC on stdin -> stdout.

Mirrors Remove-JsonComments in notify-lib.ps1 so the tests validate the shipped
settings.json exactly as the PowerShell runtime parses it. String-aware: comment
markers inside a "string" survive, and \\" does not end the string. Trailing
commas are not handled.
"""
import sys


def strip(t):
    out = []
    i, n = 0, len(t)
    in_str = esc = False
    while i < n:
        c = t[i]
        d = t[i + 1] if i + 1 < n else ''
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '/' and d == '/':
            while i < n and t[i] != '\n':
                i += 1
            continue
        if c == '/' and d == '*':
            i += 2
            while i < n and not (t[i] == '*' and i + 1 < n and t[i + 1] == '/'):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


if __name__ == '__main__':
    sys.stdout.write(strip(sys.stdin.read()))
