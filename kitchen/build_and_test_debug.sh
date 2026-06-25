#!/bin/bash

set -e

cd "$(dirname "$0")/.."

date

zig build --summary all
zig build test -freference-trace --summary all -Doptimize=Debug

date
