#!/usr/bin/env python3
import tarfile
import os
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--plist", required=True, help="Path to MacOS property list (.plist)")
    parser.add_argument("--icon", required=True, help="Path to PNG icon")
    parser.add_argument("--exe", required=True, help="Path to executable")
    parser.add_argument("--out", required=True, help="Path to the output archive (.tar)")

    args = parser.parse_args()
    args.plist

    plist_path = args.plist
    icon_path = args.icon
    exe_path = args.exe
    out_path = args.out

    if not os.path.exists(plist_path):
        raise RuntimeError("--plist path doesn't exist.")

    if not os.path.exists(icon_path):
        raise RuntimeError("--icon path doesn't exist.")
    
    if not icon_path.endswith(".png"):
        raise RuntimeError("--icon path must end with .png")

    if not os.path.exists(exe_path):
        raise RuntimeError("--exe path doesn't exist.")
    
    if not out_path.endswith(".tar"):
        raise RuntimeError("--out path must end with .tar")

    with tarfile.open(out_path, "w:") as tar:
        tar.add(plist_path, "/MVWidgets.app/Info.plist")
        tar.add(icon_path, "/MVWidgets.app/icon.png")
        tar.add(exe_path, "/MVWidgets.app/mv-widgets")
