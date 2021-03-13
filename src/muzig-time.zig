const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;

pub fn beatToSecs(bpm: f64) callconv(.Inline) f64 {
    return 60.0 / bpm;
}
pub fn tickInSecs(bpm: f64, resolution: i64) callconv(.Inline) f64 {
    return beatToSecs(bpm) / @intToFloat(f64, resolution);
}
pub fn ticksFromSecs(secs: f64, bpm: f64, resolution: u32) callconv(.Inline) f64 {
    return secs / tickInSecs(bpm, resolution);
}
pub fn secsFromTicks(ticks: i64, bpm: f64, resolution: u32) callconv(.Inline) f64 {
    return tickInSecs(bpm, resolution) * @intToFloat(f64, ticks);
}

const BpmChange = struct {
    bpm: f64,
    tick: i64,
};

const TimeSigChange = struct {
    n: u32,
    d: u32,
    measure: i64,
};

pub const MusicError = error{
    InvalidResolution,
    NoBPM,
    NoTimeSig,
};

pub const MusicTime = struct {
    bpms: std.ArrayList(BpmChange),
    timeSigs: std.ArrayList(TimeSigChange),
    resolution: u32,

    pub fn tickToTime(self: *MusicTime, tick: u64) f64 {
        try self.validate();
    }

    fn validate(self: *MusicTime) MusicError!void {
        if (self.resolution == 0) {
            return error.InvalidResolution;
        }
        if (self.timeSigs.items.len == 0) {
            return error.NoTimeSig;
        }
        if (self.bpms.items.len == 0) {
            return error.NoBPM;
        }
    }

    pub fn init(startBpm: f64, d: u32, n: u32, resolution: u32, allocator: *Allocator) !MusicTime {
        var newTime = MusicTime{ .resolution = resolution, .bpms = std.ArrayList(BpmChange).init(allocator), .timeSigs = std.ArrayList(TimeSigChange).init(allocator) };
        try newTime.bpms.append(BpmChange{
            .bpm = startBpm,
            .tick = 0,
        });
        try newTime.timeSigs.append(TimeSigChange{ .d = d, .n = n, .measure = 0 });
        return newTime;
    }

    pub fn deinit(self: *MusicTime) void {
        self.bpms.deinit();
        self.timeSigs.deinit();
    }

    pub fn timeAtTick(self: *MusicTime, tick: i64) !f64 {
        try self.validate();
        var result: f64 = 0.0;
        var lastBpm = self.bpms.items[0];

        for (self.bpms.items[1..self.bpms.items.len]) |bpm| {
            if (bpm.tick > tick) {
                break;
            }
            result += secsFromTicks(bpm.tick - lastBpm.tick, lastBpm.bpm, self.resolution);
            lastBpm = bpm;
        }
        result += secsFromTicks(tick - lastBpm.tick, lastBpm.bpm, self.resolution);
        return result;
    }

    pub fn tickAtTime(self: *MusicTime, time: f64) !f64 {
        try self.validate();
        var remaining = time;
        var result: i64 = 0;
        var prev = self.bpms.items[0];

        for (self.bpms.items) |bpm| {
            const new_time = try self.timeAtTick(bpm.tick);
            if (new_time > time) {
                break;
            }
            result = bpm.tick;
            remaining = time - new_time;
            prev = bpm;
        }
        return @intToFloat(f64, result) + ticksFromSecs(remaining, prev.bpm, self.resolution);
    }
};

test "tick #240 @ 120bpm" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    const calculatedTime = try times.timeAtTick(240);
    expect(calculatedTime == 0.5);
}

test "time 0.5s @ 120bpm" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    const calculatedTick = try times.tickAtTime(0.5);
    expect(calculatedTick == 240.0);
}

test "tick conversion equality" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    const test_tick = 123456;
    const calculatedTime = try times.timeAtTick(test_tick);
    const calculatedTick = try times.tickAtTime(calculatedTime);
    expect(@floatToInt(i64, calculatedTick) == test_tick);
}

test "tick /w bpm changes" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    try times.bpms.append(BpmChange{ .bpm = 240.0, .tick = 4 * 240 });
    const calculatedTime = try times.timeAtTick(240 * 6);
    expect(calculatedTime == 2.5);
}

test "time /w bpm changes" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    try times.bpms.append(BpmChange{ .bpm = 240.0, .tick = 4 * 240 });
    const calculatedTick = try times.tickAtTime(2.5);
    expect(calculatedTick == 240.0 * 6.0);
}

test "tick conversion equality /w bpm changes" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    try times.bpms.append(BpmChange{ .bpm = 124.0, .tick = 682 });
    try times.bpms.append(BpmChange{ .bpm = 182.0, .tick = 900 });
    try times.bpms.append(BpmChange{ .bpm = 100.0, .tick = 2400 });

    const test_tick = 123456;
    const calculatedTime = try times.timeAtTick(test_tick);
    const calculatedTick = try times.tickAtTime(calculatedTime);

    expect(@floatToInt(i64, @round(calculatedTick)) == test_tick);
}
