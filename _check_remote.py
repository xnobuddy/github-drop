import urllib.request

def head(url: str, needle: str) -> None:
    d = urllib.request.urlopen(url, timeout=25).read().decode("utf-8", "replace")
    lines = [ln for ln in d.splitlines() if needle in ln][:2]
    print(url.split("/")[-1], "->", lines)

base = "https://raw.githubusercontent.com/xnobuddy/github-drop/main/"
head(base + "own_lib.ps1", "BUILD")
head(base + "own_mon.cmd", "BUILD")
head(base + "own_mon.cmd", "MONVER")
head(base + "tg_report.ps1", "BUILD")
head(base + "own.txt", "OWN BUILD")
