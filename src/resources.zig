//! CPU, memory, disk, /tmp and /var/log, sampled about once a second.
//! The history is what a meter in htop keeps: the last minute, not a poll
//! of every refresh. Cleaning /tmp leaves the session sockets; cleaning
//! logs removes only rotated files.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const i18n = @import("i18n.zig");

pub const hist = 48;
pub const max_cores = 16;

pub const Kind = enum { tmp, logs };

pub const Times = struct { busy: u64 = 0, total: u64 = 0 };

pub const Memory = struct {
    total: u64 = 0,
    avail: u64 = 0,
    swap_total: u64 = 0,
    swap_free: u64 = 0,
};

const Point = struct { cpu: f32 = 0, ram: f32 = 0, disk: f32 = 0, tmp: u64 = 0, log: u64 = 0 };

pub const CleanResult = struct { removed: usize = 0, freed: u64 = 0, denied: bool = false };

pub const Meter = struct {
    cpu: f32 = 0,
    ram: f32 = 0,
    swap: f32 = 0,
    disk: f32 = 0,
    cores: [max_cores]f32 = @splat(0),
    core_n: usize = 0,
    load: f32 = 0,
    mem: Memory = .{},
    disk_used: u64 = 0,
    disk_total: u64 = 0,
    tmp_bytes: u64 = 0,
    log_bytes: u64 = 0,
    hist: [hist]Point = @splat(.{}),
    len: usize = 0,
    prev_all: Times = .{},
    prev_cores: [max_cores]Times = @splat(.{}),
    have_cpu: bool = false,
    ready: bool = false,
    last_fast: f64 = -1000,
    last_slow: f64 = -1000,
    confirm: ?Kind = null,
    note_buf: [280]u8 = undefined,
    note_len: usize = 0,

    pub fn note(m: *const Meter) []const u8 {
        return m.note_buf[0..m.note_len];
    }

    pub fn panel(m: *Meter, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang, toaster: *kit.Toaster) void {
        m.sample(io, gpa, c.time);
        // A clock's second, not a frame on every refresh.
        c.frameIn(1);
        ui.scroll(c, .{ .width = .fill, .height = .fill, .padding = ui.Edges.xy(20, 4), .gap = 12 });
        defer ui.end(c);
        const top = ui.div(c).row().wFull().gap(12).itemsStretch();
        m.cpuCard(c, lang);
        m.ramCard(c, lang);
        m.diskCard(c, lang);
        top.end();
        const bottom = ui.div(c).row().wFull().gap(12).itemsStretch();
        m.folderCard(c, io, gpa, lang, .tmp);
        m.folderCard(c, io, gpa, lang, .logs);
        bottom.end();
        m.confirmDialog(c, io, gpa, lang, toaster);
        if (m.note_len > 0) ui.text(c, m.note(), .{ .size = 12, .color = c.theme.muted, .wrap = true });
    }

    fn sample(m: *Meter, io: std.Io, gpa: std.mem.Allocator, now: f64) void {
        if (m.ready and now - m.last_fast < 0.9) return;
        m.last_fast = now;
        m.readCpu(io, gpa);
        m.readMem(io, gpa);
        m.readDisk();
        m.readLoad(io, gpa);
        if (!m.ready or now - m.last_slow >= 5) {
            m.last_slow = now;
            m.tmp_bytes = treeBytes(io, gpa, "/tmp");
            m.log_bytes = treeBytes(io, gpa, "/var/log");
        }
        m.push();
        m.ready = true;
    }

    fn cpuCard(m: *Meter, c: *ui.Context, lang: i18n.Lang) void {
        const card = openCard(c);
        head(c, i18n.t(lang, .cpu), percent(c, m.cpu), m.cpu);
        ui.progress(c, m.cpu, .fill);
        spark(c, m, .cpu, c.theme.accent);
        ui.text(c, i18n.loadCores(c.alloc(), lang, m.load, m.core_n), .{ .size = 12, .color = c.theme.muted });
        if (m.core_n > 0) cores(c, m.cores[0..@min(m.core_n, max_cores)]);
        card.end();
    }

    fn ramCard(m: *Meter, c: *ui.Context, lang: i18n.Lang) void {
        const card = openCard(c);
        head(c, i18n.t(lang, .ram), percent(c, m.ram), m.ram);
        ui.progress(c, m.ram, .fill);
        spark(c, m, .ram, c.theme.success);
        const used = m.mem.total -| m.mem.avail;
        ui.text(c, i18n.ofTotal(c.alloc(), lang, formatBytes(c, used), formatBytes(c, m.mem.total)), .{ .size = 12, .color = c.theme.muted });
        if (m.mem.swap_total > 0) {
            ui.text(c, i18n.swapOf(c.alloc(), lang, formatBytes(c, m.mem.swap_total -| m.mem.swap_free), formatBytes(c, m.mem.swap_total)), .{ .size = 12, .color = c.theme.muted });
            ui.progress(c, m.swap, .fill);
        }
        card.end();
    }

    fn diskCard(m: *Meter, c: *ui.Context, lang: i18n.Lang) void {
        const card = openCard(c);
        head(c, i18n.t(lang, .disk), percent(c, m.disk), m.disk);
        ui.progress(c, m.disk, .fill);
        spark(c, m, .disk, c.theme.accent);
        ui.text(c, i18n.diskLine(c.alloc(), lang, formatBytes(c, m.disk_used), formatBytes(c, m.disk_total)), .{ .size = 12, .color = c.theme.muted });
        card.end();
    }

    fn folderCard(m: *Meter, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang, kind: Kind) void {
        const card = openCard(c);
        const bytes = if (kind == .tmp) m.tmp_bytes else m.log_bytes;
        const title = if (kind == .tmp) "/tmp" else "/var/log";
        ui.text(c, title, .{ .size = 13, .color = c.theme.muted });
        ui.text(c, formatBytes(c, bytes), .{ .size = 22, .weight = .bold });
        spark(c, m, if (kind == .tmp) .tmp else .log, c.theme.muted);
        const hint = if (kind == .tmp) i18n.t(lang, .tmp_hint) else i18n.t(lang, .log_hint);
        ui.text(c, hint, .{ .size = 12, .color = c.theme.muted, .wrap = true });
        const label = if (kind == .tmp) i18n.t(lang, .clean_tmp) else i18n.t(lang, .clean_logs);
        if (ui.button(c, label, .{ .variant = .secondary, .size = 13 }).clicked) m.confirm = kind;
        card.end();
        _ = io;
        _ = gpa;
    }

    fn confirmDialog(m: *Meter, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang, toaster: *kit.Toaster) void {
        const kind = m.confirm orelse return;
        var open = true;
        if (kit.dialog(c, "clean", &open, .{
            .title = if (kind == .tmp) i18n.t(lang, .clean_tmp) else i18n.t(lang, .clean_logs),
            .description = if (kind == .tmp) i18n.t(lang, .confirm_tmp) else i18n.t(lang, .confirm_logs),
            .ok = i18n.t(lang, .confirm),
            .cancel = i18n.t(lang, .cancel),
            .ok_variant = .danger,
        })) |d| {
            switch (d.end()) {
                .ok => m.apply(io, gpa, lang, kind, toaster),
                .cancel => m.confirm = null,
                .none => {
                    if (!open) m.confirm = null;
                },
            }
        } else m.confirm = null;
    }

    fn apply(m: *Meter, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang, kind: Kind, toaster: *kit.Toaster) void {
        const path = if (kind == .tmp) "/tmp" else "/var/log";
        const result = clean(gpa, io, path, kind) catch {
            m.setNote(i18n.t(lang, .open_failed));
            m.confirm = null;
            return;
        };
        var buf: [180]u8 = undefined;
        const msg = if (result.removed == 0 and result.denied)
            i18n.t(lang, .nothing_denied)
        else if (result.denied)
            i18n.partialClean(&buf, lang, result.removed)
        else
            i18n.cleaned(&buf, lang, result.removed);
        m.setNote(msg);
        toaster.push(.{
            .status = if (result.removed == 0 and result.denied) .warning else .success,
            .title = if (kind == .tmp) i18n.t(lang, .clean_tmp) else i18n.t(lang, .clean_logs),
            .message = msg,
        });
        m.confirm = null;
        m.last_slow = -1000;
    }

    fn setNote(m: *Meter, msg: []const u8) void {
        const n = @min(msg.len, m.note_buf.len);
        @memcpy(m.note_buf[0..n], msg[0..n]);
        m.note_len = n;
    }

    fn push(m: *Meter) void {
        const p: Point = .{ .cpu = m.cpu, .ram = m.ram, .disk = m.disk, .tmp = m.tmp_bytes, .log = m.log_bytes };
        if (m.len == hist) {
            std.mem.copyForwards(Point, m.hist[0 .. hist - 1], m.hist[1..hist]);
            m.hist[hist - 1] = p;
        } else {
            m.hist[m.len] = p;
            m.len += 1;
        }
    }

    fn readCpu(m: *Meter, io: std.Io, gpa: std.mem.Allocator) void {
        _ = gpa;
        var buf: [8192]u8 = undefined;
        const text = readProc(io, "/proc/stat", &buf) orelse return;
        const now = parseStat(text);
        if (m.have_cpu) {
            m.cpu = usage(m.prev_all, now.all);
            m.core_n = now.n;
            for (0..now.n) |i| m.cores[i] = usage(m.prev_cores[i], now.cores[i]);
        } else m.core_n = now.n;
        m.prev_all = now.all;
        m.prev_cores = now.cores;
        m.have_cpu = true;
    }

    fn readMem(m: *Meter, io: std.Io, gpa: std.mem.Allocator) void {
        _ = gpa;
        var buf: [4096]u8 = undefined;
        const text = readProc(io, "/proc/meminfo", &buf) orelse return;
        m.mem = parseMeminfo(text);
        m.ram = fraction(m.mem.total -| m.mem.avail, m.mem.total);
        m.swap = fraction(m.mem.swap_total -| m.mem.swap_free, m.mem.swap_total);
    }

    fn readDisk(m: *Meter) void {
        var st: Statvfs = undefined;
        if (statvfs("/", &st) != 0 or st.frsize == 0 or st.blocks == 0) return;
        const fr: u64 = st.frsize;
        m.disk_total = st.blocks * fr;
        m.disk_used = (st.blocks -| st.bfree) * fr;
        const avail = st.bavail * fr;
        m.disk = fraction(m.disk_used, m.disk_used + avail);
    }

    fn readLoad(m: *Meter, io: std.Io, gpa: std.mem.Allocator) void {
        _ = gpa;
        var buf: [128]u8 = undefined;
        const text = readProc(io, "/proc/loadavg", &buf) orelse return;
        m.load = parseLoad(text);
    }
};

pub fn usage(prev: Times, next: Times) f32 {
    const dt = next.total -| prev.total;
    if (dt == 0) return 0;
    const db = next.busy -| prev.busy;
    return @min(1, @as(f32, @floatFromInt(db)) / @as(f32, @floatFromInt(dt)));
}

pub fn parseMeminfo(text: []const u8) Memory {
    var m: Memory = .{};
    var lines: Lines = .{ .text = text };
    while (lines.next()) |line| {
        const kb = memValue(line) orelse continue;
        const bytes = kb * 1024;
        if (std.mem.startsWith(u8, line, "MemTotal:")) m.total = bytes;
        if (std.mem.startsWith(u8, line, "MemAvailable:")) m.avail = bytes;
        if (std.mem.startsWith(u8, line, "SwapTotal:")) m.swap_total = bytes;
        if (std.mem.startsWith(u8, line, "SwapFree:")) m.swap_free = bytes;
    }
    return m;
}

const StatNow = struct { all: Times = .{}, cores: [max_cores]Times = @splat(.{}), n: usize = 0 };

pub fn parseStat(text: []const u8) StatNow {
    var out: StatNow = .{};
    var lines: Lines = .{ .text = text };
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "cpu ")) {
            out.all = timesOf(line) orelse out.all;
        } else if (std.mem.startsWith(u8, line, "cpu") and out.n < max_cores) {
            out.cores[out.n] = timesOf(line) orelse continue;
            out.n += 1;
        }
    }
    return out;
}

pub fn parseLoad(text: []const u8) f32 {
    const end = std.mem.indexOfScalar(u8, text, ' ') orelse text.len;
    return std.fmt.parseFloat(f32, text[0..end]) catch 0;
}

pub fn rotatedLog(name: []const u8) bool {
    if (std.mem.endsWith(u8, name, ".gz")) return true;
    if (std.mem.endsWith(u8, name, ".xz")) return true;
    if (std.mem.endsWith(u8, name, ".bz2")) return true;
    if (std.mem.endsWith(u8, name, ".old")) return true;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
    if (dot + 1 >= name.len) return false;
    for (name[dot + 1 ..]) |ch| if (!std.ascii.isDigit(ch)) return false;
    return true;
}

pub fn clean(gpa: std.mem.Allocator, io: std.Io, path: []const u8, kind: Kind) !CleanResult {
    var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var result: CleanResult = .{};
    try cleanDir(gpa, io, dir, kind, 0, &result);
    return result;
}

fn cleanDir(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, kind: Kind, depth: usize, result: *CleanResult) !void {
    if (depth > 8) return;
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (names.items.len >= 8000) break;
        try names.append(gpa, try gpa.dupe(u8, ent.name));
    }
    for (names.items) |name| {
        if (sessionDir(name)) continue;
        const st = dir.statFile(io, name, .{ .follow_symlinks = false }) catch {
            result.denied = true;
            continue;
        };
        switch (st.kind) {
            .directory => {
                var sub = dir.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch {
                    result.denied = true;
                    continue;
                };
                defer sub.close(io);
                try cleanDir(gpa, io, sub, kind, depth + 1, result);
                if (kind == .tmp) dir.deleteDir(io, name) catch {
                    result.denied = true;
                };
            },
            .file, .sym_link => {
                if (kind == .logs and !rotatedLog(name)) continue;
                if (kind == .tmp and st.kind != .file and st.kind != .sym_link) continue;
                dir.deleteFile(io, name) catch {
                    result.denied = true;
                    continue;
                };
                result.removed += 1;
                result.freed += st.size;
            },
            else => {},
        }
    }
}

fn treeBytes(io: std.Io, gpa: std.mem.Allocator, path: []const u8) u64 {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    var total: u64 = 0;
    sumDir(gpa, io, dir, 0, &total);
    return total;
}

fn sumDir(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, depth: usize, total: *u64) void {
    if (depth > 8) return;
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var it = dir.iterate();
    while (it.next(io) catch null) |ent| {
        if (names.items.len >= 8000) break;
        names.append(gpa, gpa.dupe(u8, ent.name) catch break) catch break;
    }
    for (names.items) |name| {
        const st = dir.statFile(io, name, .{ .follow_symlinks = false }) catch continue;
        switch (st.kind) {
            .file => total.* += st.size,
            .directory => {
                var sub = dir.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch continue;
                defer sub.close(io);
                sumDir(gpa, io, sub, depth + 1, total);
            },
            else => {},
        }
    }
}

fn sessionDir(name: []const u8) bool {
    return std.mem.eql(u8, name, ".X11-unix") or std.mem.eql(u8, name, ".ICE-unix") or std.mem.eql(u8, name, ".XIM-unix") or std.mem.eql(u8, name, ".font-unix");
}

fn timesOf(line: []const u8) ?Times {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null;
    var nums: [8]u64 = @splat(0);
    var n: usize = 0;
    while (it.next()) |tok| {
        if (n >= nums.len) break;
        nums[n] = std.fmt.parseInt(u64, tok, 10) catch 0;
        n += 1;
    }
    if (n < 4) return null;
    var total: u64 = 0;
    for (nums[0..n]) |v| total += v;
    const idle = nums[3] + if (n > 4) nums[4] else 0;
    return .{ .busy = total -| idle, .total = total };
}

fn memValue(line: []const u8) ?u64 {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    var rest = std.mem.trim(u8, line[colon + 1 ..], " \t");
    const sp = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    return std.fmt.parseInt(u64, rest[0..sp], 10) catch null;
}

fn fraction(used: u64, total: u64) f32 {
    if (total == 0) return 0;
    return @min(1, @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(total)));
}

/// /proc files report a size of 0, so a size-based read comes back empty.
fn readProc(io: std.Io, path: []const u8, buf: []u8) ?[]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    const n = file.readPositional(io, &.{buf}, 0) catch return null;
    if (n == 0) return null;
    return buf[0..n];
}

const Series = enum { cpu, ram, disk, tmp, log };

fn spark(c: *ui.Context, m: *const Meter, which: Series, color: ui.Color) void {
    var vals: [hist]f32 = undefined;
    const n = series(m, which, &vals);
    const box = ui.div(c).row().wFull().h(36).itemsEnd().gap(2);
    for (vals[0..n]) |v| {
        const col = ui.div(c).column().grow().h(36).justifyEnd();
        ui.div(c).wFull().h(@max(@as(f32, 2), std.math.clamp(v, 0, 1) * 36)).rounded(2).bg(color).end();
        col.end();
    }
    box.end();
}

fn series(m: *const Meter, which: Series, out: []f32) usize {
    const n = @min(out.len, m.len);
    var max: u64 = 1;
    if (which == .tmp or which == .log) {
        for (m.hist[0..n]) |p| max = @max(max, if (which == .tmp) p.tmp else p.log);
    }
    for (m.hist[0..n], 0..) |p, i| {
        out[i] = switch (which) {
            .cpu => p.cpu,
            .ram => p.ram,
            .disk => p.disk,
            .tmp => @as(f32, @floatFromInt(p.tmp)) / @as(f32, @floatFromInt(max)),
            .log => @as(f32, @floatFromInt(p.log)) / @as(f32, @floatFromInt(max)),
        };
    }
    return n;
}

fn cores(c: *ui.Context, values: []const f32) void {
    const row = ui.div(c).row().wFull().h(28).itemsEnd().gap(3);
    for (values) |v| {
        const col = ui.div(c).column().grow().h(28).justifyEnd();
        ui.div(c).wFull().h(@max(@as(f32, 2), std.math.clamp(v, 0, 1) * 28)).rounded(2).bg(c.theme.accent).end();
        col.end();
    }
    row.end();
}

fn openCard(c: *ui.Context) ui.Div {
    return ui.div(c).column().grow().minW(220).p(14).gap(6).bg(c.theme.surface).rounded(12);
}

fn head(c: *ui.Context, title: []const u8, big: []const u8, fraction_value: f32) void {
    ui.text(c, title, .{ .size = 13, .color = c.theme.muted });
    const hot = fraction_value >= 0.85;
    ui.text(c, big, .{ .size = 22, .weight = .bold, .color = if (hot) c.theme.danger else c.theme.text });
}

fn percent(c: *ui.Context, v: f32) []const u8 {
    return c.print("{d:.0}%", .{v * 100});
}

pub fn formatBytes(c: *ui.Context, n: u64) []const u8 {
    const f: f64 = @floatFromInt(n);
    if (n < 1024) return c.print("{d} B", .{n});
    if (n < 1024 * 1024) return c.print("{d:.1} KB", .{f / 1024.0});
    if (n < 1024 * 1024 * 1024) return c.print("{d:.1} MB", .{f / (1024.0 * 1024.0)});
    return c.print("{d:.2} GB", .{f / (1024.0 * 1024.0 * 1024.0)});
}

const Lines = struct {
    text: []const u8,
    i: usize = 0,
    fn next(self: *Lines) ?[]const u8 {
        if (self.i >= self.text.len) return null;
        const start = self.i;
        while (self.i < self.text.len and self.text[self.i] != '\n') self.i += 1;
        const line = self.text[start..self.i];
        if (self.i < self.text.len) self.i += 1;
        return if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
    }
};

const Statvfs = extern struct {
    bsize: u64,
    frsize: u64,
    blocks: u64,
    bfree: u64,
    bavail: u64,
    files: u64,
    ffree: u64,
    favail: u64,
    fsid: u64,
    flag: u64,
    namemax: u64,
    spare: [6]i32,
};

extern "c" fn statvfs(path: [*:0]const u8, buf: *Statvfs) c_int;
