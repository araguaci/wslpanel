//! Installed Debian packages as this distro's "Programs and Features":
//! manual installs, libraries, updates and orphans. Strings live in `arena`
//! (slices of the status file, plus copied versions and dates).
const std = @import("std");

pub const Filter = enum { programs, manual, all, updates, orphans, libraries };
pub const SortKey = enum { name, size, installed };

pub const Package = struct {
    name: []const u8,
    version: []const u8,
    summary: []const u8,
    section: []const u8,
    arch: []const u8,
    maintainer: []const u8,
    depends: []const u8,
    pre_depends: []const u8,
    recommends: []const u8,
    provides: []const u8,
    priority: []const u8,
    size_kb: u64 = 0,
    /// `YYYY-MM-DD` from dpkg.log, or empty when the log has no record.
    installed_on: []const u8 = "",
    /// Empty when the installed version is the newest the lists know.
    upgrade: []const u8 = "",
    auto: bool = false,
    essential: bool = false,
    library: bool = false,
    orphan: bool = false,
};

pub const Catalog = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    items: []Package = &.{},
    owns_items: bool = false,
    updates: usize = 0,
    orphans: usize = 0,
    distro_buf: [96]u8 = undefined,
    distro_len: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Catalog {
        return .{ .gpa = gpa, .arena = .init(gpa) };
    }

    pub fn deinit(self: *Catalog) void {
        const gpa = self.gpa;
        if (self.owns_items) gpa.free(self.items);
        self.arena.deinit();
        self.* = .init(gpa);
    }

    pub fn distro(self: *const Catalog) []const u8 {
        return if (self.distro_len == 0) "WSL" else self.distro_buf[0..self.distro_len];
    }
};

pub const Source = struct {
    status: []const u8,
    extended: []const u8 = "",
    /// One `name version` candidate per line. Tests use this; the system
    /// load leaves it empty and reads the apt lists instead.
    candidates: []const u8 = "",
    system_files: bool = false,
    io: std.Io,
};

/// Parses `status` (the dpkg status file). With `system_files`, also reads
/// dpkg.log and `/var/lib/apt/lists/*_Packages`.
pub fn parse(gpa: std.mem.Allocator, src: Source) !Catalog {
    var cat = Catalog.init(gpa);
    errdefer cat.deinit();
    const aa = cat.arena.allocator();
    const raw = try aa.dupe(u8, src.status);

    var list: std.ArrayList(Package) = .empty;
    defer list.deinit(gpa);
    try collectInstalled(gpa, &list, raw);

    var by_name: std.StringHashMapUnmanaged(usize) = .empty;
    defer by_name.deinit(gpa);
    for (list.items, 0..) |p, i| try by_name.put(gpa, p.name, i);

    applyAuto(list.items, &by_name, src.extended);
    try applyCandidates(aa, list.items, &by_name, src.candidates);
    if (src.system_files) {
        try readDates(gpa, aa, src.io, list.items, &by_name);
        try readUpgrades(gpa, aa, src.io, list.items, &by_name);
        readDistro(gpa, src.io, &cat);
    }
    try markOrphans(gpa, list.items, &by_name);

    cat.items = try gpa.dupe(Package, list.items);
    cat.owns_items = true;
    for (cat.items) |p| {
        cat.updates += @intFromBool(p.upgrade.len > 0);
        cat.orphans += @intFromBool(p.orphan);
    }
    return cat;
}

pub fn loadSystem(gpa: std.mem.Allocator, io: std.Io) !Catalog {
    const status = try std.Io.Dir.cwd().readFileAlloc(io, "/var/lib/dpkg/status", gpa, .limited(32 << 20));
    defer gpa.free(status);
    const extended = std.Io.Dir.cwd().readFileAlloc(io, "/var/lib/apt/extended_states", gpa, .limited(8 << 20)) catch null;
    defer if (extended) |e| gpa.free(e);
    return parse(gpa, .{
        .status = status,
        .extended = extended orelse "",
        .system_files = true,
        .io = io,
    });
}

pub fn accept(p: Package, filter: Filter, query: []const u8) bool {
    if (!containsFold(p.name, query) and !containsFold(p.summary, query)) return false;
    return switch (filter) {
        .programs => !p.auto and !p.library and !p.essential,
        .manual => !p.auto,
        .all => true,
        .updates => p.upgrade.len > 0,
        .orphans => p.orphan,
        .libraries => p.library,
    };
}

pub const Sort = struct {
    items: []const Package,
    key: SortKey,
    desc: bool,
};

pub fn sortMatches(matches: []usize, ctx: Sort) void {
    std.mem.sort(usize, matches, ctx, less);
}

fn less(ctx: Sort, a: usize, b: usize) bool {
    const pa = ctx.items[a];
    const pb = ctx.items[b];
    const ord: std.math.Order = switch (ctx.key) {
        .name => std.mem.order(u8, pa.name, pb.name),
        .size => std.math.order(pa.size_kb, pb.size_kb),
        .installed => orderDate(pa.installed_on, pb.installed_on),
    };
    const tied = ord == .eq;
    const primary = if (tied) std.mem.order(u8, pa.name, pb.name) else ord;
    const keep_empty_last = ctx.key == .installed and (pa.installed_on.len == 0 or pb.installed_on.len == 0);
    const flip = ctx.desc and !tied and !keep_empty_last;
    return if (flip) primary == .gt else primary == .lt;
}

fn orderDate(a: []const u8, b: []const u8) std.math.Order {
    if (a.len == 0 and b.len == 0) return .eq;
    if (a.len == 0) return .gt;
    if (b.len == 0) return .lt;
    return std.mem.order(u8, a, b);
}

/// Debian version order: epoch, then upstream, then the revision.
pub fn versionCmp(a: []const u8, b: []const u8) i8 {
    const ae = epochOf(a);
    const be = epochOf(b);
    if (ae.n != be.n) return if (ae.n < be.n) -1 else 1;
    const au = revisionOf(ae.rest);
    const bu = revisionOf(be.rest);
    const up = cmpPart(au.upstream, bu.upstream);
    if (up != 0) return up;
    return cmpPart(au.revision, bu.revision);
}

pub fn fieldMentions(relations: []const u8, name: []const u8) bool {
    var it: DepIter = .{ .field = relations };
    while (it.next()) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

pub fn removable(p: Package) bool {
    return !p.essential and !std.mem.eql(u8, p.priority, "required");
}

fn collectInstalled(gpa: std.mem.Allocator, list: *std.ArrayList(Package), raw: []const u8) !void {
    var para = Paragraphs{ .text = raw };
    while (para.next()) |block| {
        const status = field(block, "Status");
        if (!std.mem.endsWith(u8, status, " installed")) continue;
        const name = field(block, "Package");
        if (name.len == 0) continue;
        const section = field(block, "Section");
        try list.append(gpa, .{
            .name = name,
            .version = field(block, "Version"),
            .summary = field(block, "Description"),
            .section = section,
            .arch = field(block, "Architecture"),
            .maintainer = field(block, "Maintainer"),
            .depends = field(block, "Depends"),
            .pre_depends = field(block, "Pre-Depends"),
            .recommends = field(block, "Recommends"),
            .provides = field(block, "Provides"),
            .priority = field(block, "Priority"),
            .size_kb = std.fmt.parseInt(u64, field(block, "Installed-Size"), 10) catch 0,
            .essential = std.mem.eql(u8, field(block, "Essential"), "yes"),
            .library = isLibrary(section),
        });
    }
}

fn isLibrary(section: []const u8) bool {
    return std.mem.startsWith(u8, section, "lib") or std.mem.eql(u8, section, "oldlibs");
}

fn applyAuto(items: []Package, by_name: *const std.StringHashMapUnmanaged(usize), extended: []const u8) void {
    var para = Paragraphs{ .text = extended };
    while (para.next()) |block| {
        if (!std.mem.eql(u8, field(block, "Auto-Installed"), "1")) continue;
        const name = field(block, "Package");
        if (by_name.get(name)) |i| items[i].auto = true;
    }
}

fn applyCandidates(aa: std.mem.Allocator, items: []Package, by_name: *const std.StringHashMapUnmanaged(usize), text: []const u8) !void {
    var lines: Lines = .{ .text = text };
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const sp = std.mem.indexOfScalar(u8, trimmed, ' ') orelse continue;
        try considerUpgrade(aa, items, by_name, trimmed[0..sp], std.mem.trim(u8, trimmed[sp + 1 ..], " "));
    }
}

fn considerUpgrade(aa: std.mem.Allocator, items: []Package, by_name: *const std.StringHashMapUnmanaged(usize), name: []const u8, ver: []const u8) !void {
    const i = by_name.get(name) orelse return;
    if (ver.len == 0 or versionCmp(ver, items[i].version) <= 0) return;
    if (items[i].upgrade.len > 0 and versionCmp(ver, items[i].upgrade) <= 0) return;
    items[i].upgrade = try aa.dupe(u8, ver);
}

const Provide = struct { virtual: []const u8, provider: []const u8 };

fn markOrphans(gpa: std.mem.Allocator, items: []Package, by_name: *const std.StringHashMapUnmanaged(usize)) !void {
    var links: std.ArrayList(Provide) = .empty;
    defer links.deinit(gpa);
    for (items) |p| {
        var it: DepIter = .{ .field = p.provides };
        while (it.next()) |v| try links.append(gpa, .{ .virtual = v, .provider = p.name });
    }

    var needed: std.StringHashMapUnmanaged(void) = .empty;
    defer needed.deinit(gpa);
    for (items) |p| {
        try needField(gpa, &needed, by_name, &links, p.depends);
        try needField(gpa, &needed, by_name, &links, p.pre_depends);
        try needField(gpa, &needed, by_name, &links, p.recommends);
    }
    for (items) |*p| {
        const base = p.auto and !p.essential and !std.mem.eql(u8, p.priority, "required");
        p.orphan = base and needed.get(p.name) == null;
    }
}

fn needField(gpa: std.mem.Allocator, needed: *std.StringHashMapUnmanaged(void), by_name: *const std.StringHashMapUnmanaged(usize), links: *const std.ArrayList(Provide), field_text: []const u8) !void {
    var it: DepIter = .{ .field = field_text };
    while (it.next()) |name| {
        if (by_name.get(name) != null) try needed.put(gpa, name, {});
        for (links.items) |l| if (std.mem.eql(u8, l.virtual, name)) try needed.put(gpa, l.provider, {});
    }
}

fn readDates(gpa: std.mem.Allocator, aa: std.mem.Allocator, io: std.Io, items: []Package, by_name: *const std.StringHashMapUnmanaged(usize)) !void {
    const paths = [_][]const u8{ "/var/log/dpkg.log.1", "/var/log/dpkg.log" };
    for (paths) |path| {
        const text = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20)) catch continue;
        defer gpa.free(text);
        var lines: Lines = .{ .text = text };
        while (lines.next()) |line| {
            const at = std.mem.indexOf(u8, line, " status installed ") orelse continue;
            if (line.len < 10) continue;
            const rest = line[at + " status installed ".len ..];
            const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
            var name = rest[0..end];
            if (std.mem.indexOfScalar(u8, name, ':')) |c| name = name[0..c];
            const i = by_name.get(name) orelse continue;
            items[i].installed_on = try aa.dupe(u8, line[0..10]);
        }
    }
}

fn readUpgrades(gpa: std.mem.Allocator, aa: std.mem.Allocator, io: std.Io, items: []Package, by_name: *const std.StringHashMapUnmanaged(usize)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, "/var/lib/apt/lists", .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, "_Packages")) continue;
        const text = dir.readFileAlloc(io, ent.name, gpa, .limited(96 << 20)) catch continue;
        defer gpa.free(text);
        var para = Paragraphs{ .text = text };
        while (para.next()) |block| {
            try considerUpgrade(aa, items, by_name, field(block, "Package"), field(block, "Version"));
        }
    }
}

fn readDistro(gpa: std.mem.Allocator, io: std.Io, cat: *Catalog) void {
    const text = std.Io.Dir.cwd().readFileAlloc(io, "/etc/os-release", gpa, .limited(4096)) catch return;
    defer gpa.free(text);
    var lines: Lines = .{ .text = text };
    while (lines.next()) |line| {
        const key = "PRETTY_NAME=";
        if (!std.mem.startsWith(u8, line, key)) continue;
        var v = line[key.len..];
        if (v.len >= 2 and v[0] == '"') {
            v = v[1..];
            if (std.mem.indexOfScalar(u8, v, '"')) |q| v = v[0..q];
        }
        const n = @min(v.len, cat.distro_buf.len);
        @memcpy(cat.distro_buf[0..n], v[0..n]);
        cat.distro_len = n;
        return;
    }
}

fn containsFold(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i..][0..needle.len], needle)) return true;
    }
    return false;
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
        return line;
    }
};

const Paragraphs = struct {
    text: []const u8,
    i: usize = 0,

    fn next(self: *Paragraphs) ?[]const u8 {
        while (self.i < self.text.len and self.text[self.i] == '\n') self.i += 1;
        if (self.i >= self.text.len) return null;
        const start = self.i;
        while (self.i + 1 < self.text.len) : (self.i += 1) {
            if (self.text[self.i] == '\n' and self.text[self.i + 1] == '\n') {
                const block = self.text[start..self.i];
                self.i += 2;
                return block;
            }
        }
        const block = self.text[start..];
        self.i = self.text.len;
        return block;
    }
};

fn field(para: []const u8, name: []const u8) []const u8 {
    var i: usize = 0;
    while (i < para.len) {
        const start = i;
        while (i < para.len and para[i] != '\n') i += 1;
        const line = para[start..i];
        if (i < para.len) i += 1;
        if (line.len > name.len and std.mem.startsWith(u8, line, name) and line[name.len] == ':') {
            var v = line[name.len + 1 ..];
            if (v.len > 0 and v[0] == ' ') v = v[1..];
            return v;
        }
    }
    return "";
}

const DepIter = struct {
    field: []const u8,
    i: usize = 0,

    fn next(self: *DepIter) ?[]const u8 {
        while (self.i < self.field.len) {
            while (self.i < self.field.len and isSep(self.field[self.i])) self.i += 1;
            if (self.i >= self.field.len) return null;
            const start = self.i;
            while (self.i < self.field.len and self.field[self.i] != ',' and self.field[self.i] != '|') self.i += 1;
            const name = depName(std.mem.trim(u8, self.field[start..self.i], " \t"));
            if (name.len > 0) return name;
        }
        return null;
    }
};

fn isSep(c: u8) bool {
    return c == ',' or c == '|' or c == ' ' or c == '\t';
}

fn depName(s: []const u8) []const u8 {
    var n = s;
    if (std.mem.indexOfAny(u8, n, " (")) |k| n = n[0..k];
    if (std.mem.indexOfScalar(u8, n, ':')) |k| n = n[0..k];
    if (n.len == 0 or n[0] == '$') return "";
    return n;
}

const Epoch = struct { n: u64, rest: []const u8 };
const Rev = struct { upstream: []const u8, revision: []const u8 };

fn epochOf(v: []const u8) Epoch {
    const colon = std.mem.indexOfScalar(u8, v, ':') orelse return .{ .n = 0, .rest = v };
    const n = std.fmt.parseInt(u64, v[0..colon], 10) catch return .{ .n = 0, .rest = v };
    return .{ .n = n, .rest = v[colon + 1 ..] };
}

fn revisionOf(v: []const u8) Rev {
    const h = std.mem.lastIndexOfScalar(u8, v, '-') orelse return .{ .upstream = v, .revision = "" };
    return .{ .upstream = v[0..h], .revision = v[h + 1 ..] };
}

fn cmpPart(a: []const u8, b: []const u8) i8 {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len or j < b.len) {
        const nd = cmpNonDigit(a, &i, b, &j);
        if (nd != 0) return nd;
        const d = cmpDigit(a, &i, b, &j);
        if (d != 0) return d;
    }
    return 0;
}

fn cmpNonDigit(a: []const u8, i: *usize, b: []const u8, j: *usize) i8 {
    while (true) {
        const ac: u8 = if (i.* < a.len and !std.ascii.isDigit(a[i.*])) a[i.*] else 0;
        const bc: u8 = if (j.* < b.len and !std.ascii.isDigit(b[j.*])) b[j.*] else 0;
        if (ac == 0 and bc == 0) return 0;
        const ao = rank(ac);
        const bo = rank(bc);
        if (ao != bo) return if (ao < bo) -1 else 1;
        if (ac != 0) i.* += 1;
        if (bc != 0) j.* += 1;
    }
}

fn cmpDigit(a: []const u8, i: *usize, b: []const u8, j: *usize) i8 {
    while (i.* < a.len and a[i.*] == '0') i.* += 1;
    while (j.* < b.len and b[j.*] == '0') j.* += 1;
    var ia = i.*;
    var ib = j.*;
    while (ia < a.len and std.ascii.isDigit(a[ia])) ia += 1;
    while (ib < b.len and std.ascii.isDigit(b[ib])) ib += 1;
    const la = ia - i.*;
    const lb = ib - j.*;
    if (la != lb) {
        i.* = ia;
        j.* = ib;
        return if (la < lb) -1 else 1;
    }
    var k: usize = 0;
    while (k < la) : (k += 1) {
        if (a[i.* + k] != b[j.* + k]) {
            const r: i8 = if (a[i.* + k] < b[j.* + k]) -1 else 1;
            i.* = ia;
            j.* = ib;
            return r;
        }
    }
    i.* = ia;
    j.* = ib;
    return 0;
}

/// Tilde, then the end of the part, then letters, then the other characters.
fn rank(c: u8) i32 {
    if (c == 0) return 0;
    if (c == '~') return -1;
    if (std.ascii.isAlphabetic(c)) return c;
    return @as(i32, c) + 256;
}
