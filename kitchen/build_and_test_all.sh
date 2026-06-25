#!/bin/bash

set -e

cd "$(dirname "$0")/.."

date

zig build --summary all

zig build test -freference-trace --summary all -Doptimize=Debug
zig build test -freference-trace --summary all -Doptimize=ReleaseSafe
zig build test -freference-trace --summary all -Doptimize=ReleaseFast
zig build test -freference-trace --summary all -Doptimize=ReleaseSmall

date
