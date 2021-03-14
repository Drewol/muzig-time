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
            const new_time = try self.timeAtTick(bpm.tick); //bad time complexity
            if (new_time > time) {
                break;
            }
            result = bpm.tick;
            remaining = time - new_time;
            prev = bpm;
        }
        return @intToFloat(f64, result) + ticksFromSecs(remaining, prev.bpm, self.resolution);
    }

    pub fn measureAtTick(self: *MusicTime, tick: i64) !i64 {
        try self.validate();

        var result: i64 = 0;
        var remainingTicks: i64 = tick;

        const firstSig = self.timeSigs.items[0];

        var prevMeasure = firstSig.measure;
        var prevTicksPerMeasure: i64 = self.resolution * 4 * firstSig.n / firstSig.d;
        if (prevTicksPerMeasure == 0) {
            return result;
        }
        for (self.timeSigs.items[1..self.timeSigs.items.len]) |current_sig| {
            const measureCount = current_sig.measure - prevMeasure;
            const tickCount = measureCount * prevTicksPerMeasure;
            if (tickCount > remainingTicks) {
                break;
            }
            result += measureCount;
            remainingTicks -= tickCount;
            prevMeasure = current_sig.measure;
            prevTicksPerMeasure = self.resolution * 4 * current_sig.n / current_sig.d;
            if (prevTicksPerMeasure == 0) {
                return result;
            }
        }
        result += @divFloor(remainingTicks, prevTicksPerMeasure);

        return result;
    }

    pub fn tickAtMeasure(self: *MusicTime, measure: i64) !i64 {
        try self.validate();

        var result: i64 = 0;
        var remainingMeasures: i64 = measure;
        const firstSig = self.timeSigs.items[0];

        var prevMeasure = firstSig.measure;
        var prevTicksPerMeasure = self.resolution * 4 * firstSig.n / firstSig.d;
        for (self.timeSigs.items[1..self.timeSigs.items.len]) |currentSig| {
            const measureCount = currentSig.measure - prevMeasure;
            if (measureCount > remainingMeasures) {
                break;
            }
            result += measureCount * prevTicksPerMeasure;
            remainingMeasures -= measureCount;
            prevMeasure = currentSig.measure;
            prevTicksPerMeasure = self.resolution * 4 * currentSig.n / currentSig.d;
        }
        result += remainingMeasures * prevTicksPerMeasure;

        return result;
    }

    pub fn bpmAtTick(self: *MusicTime, tick: i64) MusicError!f64 {
        if (self.bpms.items.len == 0) {
            return error.NoBPM;
        }

        var prev = self.bpms.items[0];

        for (self.bpms.items[1..self.bpms.items.len]) |b| {
            if (b.tick > tick) {
                break;
            }
            prev = b;
        }
        return prev.bpm;
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

test "tick to measure, simple" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    const calculatedMeasure = try times.measureAtTick(240 * (4 * 512 + 1));
    expect(calculatedMeasure == 512);
}

test "measure to tick, simple" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    const calculatedTick = try times.tickAtMeasure(50);
    expect(calculatedTick == 240 * 4 * 50);
}

test "bpm@tick /w bpm changes" {
    var times = try MusicTime.init(120.0, 4, 4, 240, test_allocator);
    defer times.deinit();

    try times.bpms.append(BpmChange{ .bpm = 124.0, .tick = 682 });
    try times.bpms.append(BpmChange{ .bpm = 182.0, .tick = 900 });
    try times.bpms.append(BpmChange{ .bpm = 100.0, .tick = 2400 });

    expect((try times.bpmAtTick(0)) == 120.0);
    expect((try times.bpmAtTick(690)) == 124.0);
    expect((try times.bpmAtTick(901)) == 182.0);
    expect((try times.bpmAtTick(2500)) == 100.0);
}
