#!/bin/bash
# 맥에서 핵심 로직(Core/*.swift)만 따로 빌드해 검증한다. Xcode 없이 명령줄 도구만으로 돈다.
#   ./tools/test.sh selftest
#   ./tools/test.sh search "lofi"
#   ./tools/test.sh get https://youtu.be/xxxx p720
set -e
cd "$(dirname "$0")/.."
OUT=${TMPDIR:-/tmp}/yankcli
mkdir -p "$OUT"
swiftc -swift-version 5 -parse-as-library -O Yank/Core/Models.swift Yank/Core/Formatters.swift Yank/Core/YouTube.swift Yank/Core/Downloader.swift tools/cli.swift -o "$OUT/yankcli"
"$OUT/yankcli" "$@"
