pub const Event = struct {
    poly: polynode.PolyNode = .{},
    code: i32 = 0,
};

pub const Sensor = struct {
    poly: polynode.PolyNode = .{},
    value: f64 = 0.0,
};

pub const EventPolyHelper = polynode.PolyHelper(Event);
pub const SensorPolyHelper = polynode.PolyHelper(Sensor);

const polynode = @import("matryoshka").polynode;
