//! The end of a text log under /var/log. The line count steps by 50.
//! Compressed and binary account files (wtmp, lastlog, faillog) stay out.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const i18n = @import("i18n.zig");

const root = "/var/log";
const max_files = 80;
const max_bytes: u64 = 256 * 1024;
const max_lines: u16 = 2000;
const steps = [_]u16{ 50, 100, 150, 200, 250, 300, 400, 500 };

pub const Span = struct { start: usize, end: usize };

pub const LogFile = struct {
    path: [180]u8 = undefined,
    path_len: u8 = 0,
    size: u64 = 0,

    pub fn label(f: *const LogFile) []const u8 {
        const s = f.path[0..f.path_len];
        const prefix = root ++ "/";
        if (std.mem.startsWith(u8, s, prefix)) return s[prefix.len..];
        return s;
    }
};

pub const View = struct {
    files: std.ArrayList(LogFile) = .empty,
    text: std.ArrayList(u8) = .empty,
    spans: std.ArrayList(Span) = .empty,
    selected: usize = 0,
    lines: u16 = 50,
    shown_sel: usize = std.math.maxInt(usize),
    shown_lines: u16 = 0,
    binary: bool = false,
    denied: bool = false,
    last_read: f64 = -1000,
    last_scan: f64 = -1000,

    pub fn deinit(v: *View, gpa: std.mem.Allocator) void {
        v.files.deinit(gpa);
        v.text.deinit(gpa);
        v.spans.deinit(gpa);
    }

    pub fn panel(v: *View, c: *ui.Context, io: std.Io, gpa: std.mem.Allocator, lang: i18n.Lang) void {
        c.frameIn(1);
        v.refreshFiles(io, gpa, c.time);
        const col = ui.div(c).column().grow().wFull().px(20).gap(8);
        defer col.end();
        v.tools(c, lang);
        const body = ui.div(c).row().grow().wFull().gap(12).itemsStretch();
        v.fileList(c, lang);
        v.refreshTail(io, gpa, c.time);
        v.tail(c, lang);
        body.end();
    }

    fn tools(v: *View, c: *ui.Context, lang: i18n.Lang) void {
        const bar = ui.div(c).row().wFull().gap(6).itemsCenter();
        defer bar.end();
        for (steps) |n| {
            const on = v.lines == n;
            if (ui.button(c, c.print("{d}", .{n}), .{ .variant = if (on) .primary else .ghost, .size = 12 }).clicked)
                v.lines = n;
        }
        if (v.lines > 50 and ui.button(c, "−50", .{ .variant = .ghost, .size = 12 }).clicked) {
            v.lines = if (v.lines > 50) v.lines - 50 else 50;
        }
        if (v.lines < max_lines and ui.button(c, "+50", .{ .variant = .ghost, .size = 12 }).clicked)
            v.lines = @min(max_lines, v.lines + 50);
        ui.text(c, i18n.logCount(c.alloc(), lang, v.lines), .{ .size = 12, .color = c.theme.muted });
    }

    fn fileList(v: *View, c: *ui.Context, lang: i18n.Lang) void {
        const col = ui.div(c).column().w(280).hFull();
        defer col.end();
        if (v.files.items.len == 0) {
            ui.text(c, i18n.t(lang, .log_empty), .{ .size = 12, .color = c.theme.muted, .wrap = true });
            return;
        }
        ui.text(c, i18n.t(lang, .log_file), .{ .size = 12, .color = c.theme.muted });
        var list = ui.list(c, .{ .count = v.files.items.len, .row_height = 32, .gap = 2, .padding = ui.Edges.all(2) });
        defer list.end();
        while (list.next()) |n| {
            const f = &v.files.items[n];
            const on = n == v.selected;
            var line = ui.div(c).row().wFull().h(32).px(8).itemsCenter().rounded(8).control();
            if (on) line = line.bg(c.theme.accent.alpha(0.16));
            line = line.hover(c.theme.surface_hover);
            if (line.clicked()) v.selected = n;
            ui.text(c, f.label(), .{ .size = 12, .truncate = .ellipsis });
            line.end();
        }
    }

    fn tail(v: *View, c: *ui.Context, lang: i18n.Lang) void {
        const col = ui.div(c).column().grow().hFull();
        defer col.end();
        if (v.files.items.len == 0) return;
        if (v.denied) {
            ui.text(c, i18n.t(lang, .log_denied), .{ .color = c.theme.danger, .wrap = true });
            return;
        }
        if (v.binary) {
            ui.text(c, i18n.t(lang, .log_binary), .{ .color = c.theme.muted, .wrap = true });
            return;
        }
        if (v.spans.items.len == 0) return;
        var list = ui.list(c, .{ .count = v.spans.items.len, .row_height = 18, .padding = ui.Edges.all(4) });
        defer list.end();
        while (list.next()) |n| {
            const sp = v.spans.items[n];
            const slice = v.text.items[sp.start..sp.end];
            ui.text(c, if (slice.len == 0) " " else slice, .{ .size = 12, .mono = true, .truncate = .ellipsis });
        }
    }

    fn refreshFiles(v: *View, io: std.Io, gpa: std.mem.Allocator, now: f64) void {
        if (v.files.items.len > 0 and now - v.last_scan < 4) return;
        v.last_scan = now;
        var keep: [180]u8 = undefined;
        var keep_len: usize = 0;
        if (v.selected < v.files.items.len) {
            keep_len = v.files.items[v.selected].path_len;
            @memcpy(keep[0..keep_len], v.files.items[v.selected].path[0..keep_len]);
        }
        v.files.clearRetainingCapacity();
        scan(io, gpa, &v.files);
        std.mem.sort(LogFile, v.files.items, {}, fileLess);
        v.selected = 0;
        if (keep_len == 0) {
            for (v.files.items, 0..) |f, i| if (f.size > 0) {
                v.selected = i;
                break;
            };
            return;
        }
        for (v.files.items, 0..) |f, i| {
            if (f.path_len == keep_len and std.mem.eql(u8, f.path[0..keep_len], keep[0..keep_len])) {
                v.selected = i;
                return;
            }
        }
    }

    fn refreshTail(v: *View, io: std.Io, gpa: std.mem.Allocator, now: f64) void {
        if (v.files.items.len == 0) return;
        if (v.selected >= v.files.items.len) v.selected = 0;
        const fresh = v.selected == v.shown_sel and v.lines == v.shown_lines and now - v.last_read < 1.2 and v.shown_lines != 0;
        if (fresh) return;
        v.readTail(io, gpa);
        v.shown_sel = v.selected;
        v.shown_lines = v.lines;
        v.last_read = now;
    }

    fn readTail(v: *View, io: std.Io, gpa: std.mem.Allocator) void {
        v.binary = false;
        v.denied = false;
        v.spans.clearRetainingCapacity();
        v.text.clearRetainingCapacity();
        const path = v.files.items[v.selected].path[0..v.files.items[v.selected].path_len];
        var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
            v.denied = true;
            return;
        };
        defer file.close(io);
        const st = file.stat(io) catch {
            v.denied = true;
            return;
        };
        const off: u64 = if (st.size > max_bytes) st.size - max_bytes else 0;
        const want: usize = @intCast(st.size - off);
        v.text.resize(gpa, want) catch {
            v.denied = true;
            return;
        };
        const n = file.readPositional(io, &.{v.text.items}, off) catch {
            v.denied = true;
            return;
        };
        v.text.shrinkRetainingCapacity(n);
        if (std.mem.indexOfScalar(u8, v.text.items, 0) != null) {
            v.binary = true;
            v.text.clearRetainingCapacity();
            return;
        }
        var body = v.text.items;
        if (off > 0) if (std.mem.indexOfScalar(u8, body, '\n')) |i| {
            body = body[i + 1 ..];
        };
        var tmp: [max_lines]Span = undefined;
        const got = tailSpans(body, v.lines, &tmp);
        const base = @intFromPtr(body.ptr) - @intFromPtr(v.text.items.ptr);
        for (got) |sp| v.spans.append(gpa, .{ .start = sp.start + base, .end = sp.end + base }) catch break;
    }
};

pub fn acceptName(name: []const u8) bool {
    if (compressed(name) or binaryName(name)) return false;
    if (std.mem.indexOf(u8, name, "log") != null) return true;
    const plain = [_][]const u8{ "syslog", "messages", "debug", "daemon", "auth", "kern", "mail" };
    for (plain) |p| {
        if (std.mem.eql(u8, name, p)) return true;
        if (std.mem.startsWith(u8, name, p) and name.len > p.len and name[p.len] == '.') return true;
    }
    return false;
}

pub fn tailSpans(src: []const u8, n: usize, out: []Span) []const Span {
    if (n == 0 or out.len == 0 or src.len == 0) return out[0..0];
    var end = src.len;
    if (src[end - 1] == '\n') end -= 1;
    if (end == 0) return out[0..0];
    var mark: usize = 0;
    var seen: usize = 0;
    var i = end;
    while (i > 0) {
        i -= 1;
        if (src[i] == '\n') {
            seen += 1;
            if (seen == n) {
                mark = i + 1;
                break;
            }
        }
    }
    var w: usize = 0;
    var s = mark;
    while (s < end and w < out.len) {
        var e = s;
        while (e < end and src[e] != '\n') e += 1;
        out[w] = .{ .start = s, .end = e };
        w += 1;
        if (e >= end) break;
        s = e + 1;
    }
    return out[0..w];
}

fn scan(io: std.Io, gpa: std.mem.Allocator, out: *std.ArrayList(LogFile)) void {
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return;
    defer dir.close(io);
    walk(io, gpa, dir, root, 0, out);
}

fn walk(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, prefix: []const u8, depth: usize, out: *std.ArrayList(LogFile)) void {
    if (out.items.len >= max_files) return;
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var it = dir.iterate();
    while (it.next(io) catch null) |ent| {
        if (names.items.len >= 2000) break;
        names.append(gpa, gpa.dupe(u8, ent.name) catch break) catch break;
    }
    for (names.items) |name| {
        if (out.items.len >= max_files or name.len == 0 or name[0] == '.') continue;
        const st = dir.statFile(io, name, .{ .follow_symlinks = false }) catch continue;
        var path_buf: [180]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ prefix, name }) catch continue;
        switch (st.kind) {
            .directory => {
                if (depth >= 1 or skipDir(name)) continue;
                var sub = dir.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch continue;
                defer sub.close(io);
                walk(io, gpa, sub, path, depth + 1, out);
            },
            .file => {
                if (!acceptName(name)) continue;
                var probe = dir.openFile(io, name, .{}) catch continue;
                probe.close(io);
                var row: LogFile = .{};
                if (path.len > row.path.len) continue;
                @memcpy(row.path[0..path.len], path);
                row.path_len = @intCast(path.len);
                row.size = st.size;
                out.append(gpa, row) catch return;
            },
            else => {},
        }
    }
}

fn skipDir(name: []const u8) bool {
    return std.mem.eql(u8, name, "journal") or std.mem.eql(u8, name, "private");
}

fn compressed(name: []const u8) bool {
    const ext = [_][]const u8{ ".gz", ".xz", ".bz2", ".zst" };
    for (ext) |e| if (std.mem.endsWith(u8, name, e)) return true;
    return false;
}

fn binaryName(name: []const u8) bool {
    const bad = [_][]const u8{ "wtmp", "btmp", "lastlog", "faillog" };
    for (bad) |b| {
        if (std.mem.eql(u8, name, b)) return true;
        if (std.mem.startsWith(u8, name, b) and name.len > b.len and name[b.len] == '.') return true;
    }
    return false;
}

fn fileLess(_: void, a: LogFile, b: LogFile) bool {
    return std.mem.order(u8, a.label(), b.label()) == .lt;
}
