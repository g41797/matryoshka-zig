const block1 = @import("examples").block1;

test "21 - define a PolyNode type" {
    try block1.define_type.run();
}

test "22 - ownership transfer via Slot" {
    try block1.ownership_transfer.run();
}

test "23 - tag-dispatch consume loop" {
    try block1.tag_dispatch.run();
}

test "24 - builder pattern" {
    try block1.builder.run();
}

test "25 - produce-consume with defer cleanup" {
    try block1.produce_consume.run();
}
