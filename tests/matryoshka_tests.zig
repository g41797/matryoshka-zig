test "matryoshka module loads" {
    const matryoshka = @import("matryoshka");
    _ = matryoshka.polynode;
    _ = matryoshka.mailbox;
    _ = matryoshka.pool;
}

test {
    _ = @import("layer1_polynode.zig");
    _ = @import("layer1_examples.zig");
    _ = @import("layer2_mailbox.zig");
    _ = @import("layer2_examples.zig");
    _ = @import("layer3_pool.zig");
    _ = @import("layer3_examples.zig");
    _ = @import("layer4_infra.zig");
    _ = @import("layer4_examples.zig");
    _ = @import("layer4_master.zig");
}

const std = @import("std");
const testing = std.testing;
