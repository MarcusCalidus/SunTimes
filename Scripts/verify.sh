#!/bin/sh
# Compiles the shared solar code together with the verification script on macOS.
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/suntimes-verify"
swiftc -O -o "$OUT" Shared/SolarCalculator.swift Shared/SunEvents.swift Scripts/main.swift
"$OUT"
