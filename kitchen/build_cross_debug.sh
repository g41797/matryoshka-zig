#!/bin/bash

set -e

cd "$(dirname "$0")/.."

date

zig build --summary all -Dtarget=x86_64-macos -Doptimize=Debug
zig build --summary all -Dtarget=aarch64-macos -Doptimize=Debug
zig build --summary all -Dtarget=x86_64-windows -Doptimize=Debug

date
