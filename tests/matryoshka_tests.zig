test "matryoshka module loads" {
    const matryoshka = @import("matryoshka");
    _ = matryoshka.polynode;
    _ = matryoshka.mailbox;
    _ = matryoshka.pool;
}

test {
    _ = @import("layer1_polynode.zig");
    _ = @import("layer1_examples.zig");
}

const std = @import("std");
const testing = std.testing;
