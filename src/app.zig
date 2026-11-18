//! Programs installed in this WSL distro. Compared with Windows' Apps &
//! features: manual versus automatic, orphans, and a newer version from the
//! apt lists, beside name, size and install day.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const catalog = @import("catalog.zig");
const i18n = @import("i18n.zig");
const meta = @import("meta.zig");
const resources = @import("resources.zig");

pub const Page = enum { resources, programs };
pub const Pending = enum { none, remove, purge, upgrade, upgrade_all, autoremove, update_index };

pub const State = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    catalog: catalog.Catalog,
    query: ui.TextBuffer = .{},
    matches: std.ArrayList(usize) = .empty,
    filter: catalog.Filter = .programs,
    sort: catalog.SortKey = .name,
    descending: bool = false,
    selected: ?[]const u8 = null,
    pending: Pending = .none,
    want_reload: bool = false,
    loaded: bool = false,
    load_error: []const u8 = "",
    shown_kb: u64 = 0,
    status: []const u8 = "",
    status_owned: std.ArrayList(u8) = .empty,
    fixture: ?[]const u8 = null,
    fixture_auto: []const u8 = "",
    fixture_candidates: []const u8 = "",
    page: Page = .resources,
    lang: i18n.Lang = .pt_BR,
    meter: resources.Meter = .{},

    pub fn init(gpa: std.mem.Allocator, io: std.Io) State {
        return .{ .gpa = gpa, .io = io, .catalog = .init(gpa) };
    }

    pub fn deinit(s: *State) void {
        s.catalog.deinit();
        s.matches.deinit(s.gpa);
        s.query.deinit();
        s.status_owned.deinit(s.gpa);
    }

    pub fn view(s: *State, c: *ui.Context) void {
        if (s.page == .programs and (!s.loaded or s.want_reload)) s.reload();
        if (s.page == .programs) s.refill();
        const root = ui.div(c).column().sizeFull().bg(c.theme.background);
        defer root.end();
        s.pageBar(c);
        if (s.page == .resources) s.meter.panel(c, s.io, s.gpa, s.lang) else {
            s.toolbar(c);
            s.body(c);
        }
        s.footer(c);
    }

    fn reload(s: *State) void {
        s.want_reload = false;
        s.loaded = true;
        s.catalog.deinit();
        s.selected = null;
        s.pending = .none;
        const loaded = if (s.fixture) |status|
            catalog.parse(s.gpa, .{
                .status = status,
                .extended = s.fixture_auto,
                .candidates = s.fixture_candidates,
                .io = s.io,
            })
        else
            catalog.loadSystem(s.gpa, s.io);
        s.catalog = loaded catch |e| {
            s.load_error = @errorName(e);
            return;
        };
        s.load_error = "";
    }

    fn refill(s: *State) void {
        s.matches.clearRetainingCapacity();
        s.shown_kb = 0;
        const q = s.query.text();
        for (s.catalog.items, 0..) |p, i| {
            if (!catalog.accept(p, s.filter, q)) continue;
            s.matches.append(s.gpa, i) catch return;
            s.shown_kb += p.size_kb;
        }
        catalog.sortMatches(s.matches.items, .{ .items = s.catalog.items, .key = s.sort, .desc = s.descending });
    }

    fn pageBar(s: *State, c: *ui.Context) void {
        const bar = ui.div(c).row().wFull().px(20).pt(16).pb(8).gap(12).itemsCenter();
        const titles = ui.div(c).column().grow().gap(2);
        ui.text(c, i18n.t(s.lang, .app_title), .{ .size = 22, .weight = .bold });
        const sub = if (s.page == .resources)
            i18n.t(s.lang, .subtitle_resources)
        else
            i18n.distroSub(c.alloc(), s.lang, s.catalog.distro());
        ui.text(c, sub, .{ .size = 13, .color = c.theme.muted });
        titles.end();
        s.pageButton(c, i18n.t(s.lang, .tab_resources), .resources);
        s.pageButton(c, i18n.t(s.lang, .tab_programs), .programs);
        bar.end();
    }

    fn pageButton(s: *State, c: *ui.Context, label: []const u8, page: Page) void {
        const on = s.page == page;
        if (ui.button(c, label, .{ .variant = if (on) .primary else .ghost, .size = 13 }).clicked) {
            s.page = page;
            s.pending = .none;
            s.meter.confirm = null;
        }
    }

    fn toolbar(s: *State, c: *ui.Context) void {
        // End each box before the next sibling. A deferred end would nest them.
        const tools = ui.div(c).row().wFull().px(20).py(6).gap(8).itemsCenter();
        const search = ui.div(c).row().grow();
        _ = ui.textField(c, &s.query, .{ .placeholder = i18n.t(s.lang, .search), .width = .fill });
        search.end();
        if (ui.button(c, i18n.t(s.lang, .reload), .{ .variant = .ghost, .size = 13 }).clicked) s.want_reload = true;
        if (ui.button(c, i18n.t(s.lang, .indexes), .{ .variant = .ghost, .size = 13 }).clicked) s.pending = .update_index;
        if (ui.button(c, i18n.t(s.lang, .upgrade_all), .{ .variant = .secondary, .size = 13 }).clicked) s.pending = .upgrade_all;
        tools.end();

        const chips = ui.div(c).row().wFull().px(20).py(4).gap(6).itemsCenter();
        s.chip(c, i18n.t(s.lang, .filter_programs), .programs);
        s.chip(c, i18n.t(s.lang, .filter_manual), .manual);
        s.chip(c, i18n.t(s.lang, .filter_all), .all);
        s.chip(c, i18n.t(s.lang, .filter_updates), .updates);
        s.chip(c, i18n.t(s.lang, .filter_orphans), .orphans);
        s.chip(c, i18n.t(s.lang, .filter_libraries), .libraries);
        chips.end();

        const stats = ui.div(c).row().wFull().px(20).pb(8).gap(8).itemsCenter();
        ui.text(c, i18n.listStats(c.alloc(), s.lang, s.matches.items.len, kbText(c, s.shown_kb), s.catalog.updates, s.catalog.orphans), .{ .size = 12, .color = c.theme.muted });
        s.sortChip(c, i18n.t(s.lang, .sort_name), .name);
        s.sortChip(c, i18n.t(s.lang, .sort_size), .size);
        s.sortChip(c, i18n.t(s.lang, .sort_installed), .installed);
        stats.end();
    }

    fn chip(s: *State, c: *ui.Context, label: []const u8, f: catalog.Filter) void {
        const on = s.filter == f;
        if (ui.button(c, label, .{ .variant = if (on) .primary else .ghost, .size = 13 }).clicked) {
            s.filter = f;
            s.pending = .none;
        }
    }

    fn sortChip(s: *State, c: *ui.Context, label: []const u8, key: catalog.SortKey) void {
        const on = s.sort == key;
        if (ui.button(c, label, .{ .variant = if (on) .secondary else .ghost, .size = 12 }).clicked) {
            if (on) s.descending = !s.descending else {
                s.sort = key;
                s.descending = key != .name;
            }
        }
    }

    fn body(s: *State, c: *ui.Context) void {
        const th = c.theme;
        if (s.load_error.len > 0) {
            const box = ui.div(c).column().grow().p(24).gap(8);
            defer box.end();
            ui.text(c, i18n.t(s.lang, .load_failed), .{ .size = 16, .weight = .semibold });
            ui.text(c, s.load_error, .{ .color = th.danger });
            if (ui.button(c, i18n.t(s.lang, .reload), .{ .variant = .primary }).clicked) s.want_reload = true;
            return;
        }
        const row = ui.div(c).row().grow().wFull().itemsStretch();
        defer row.end();
        s.listPane(c);
        s.detail(c);
    }

    fn listPane(s: *State, c: *ui.Context) void {
        const col = ui.div(c).column().grow().hFull();
        defer col.end();
        if (s.matches.items.len == 0) {
            const empty = ui.div(c).grow().p(24);
            defer empty.end();
            ui.text(c, i18n.t(s.lang, .empty_filter), .{ .color = c.theme.muted });
            return;
        }
        var rows = ui.list(c, .{ .count = s.matches.items.len, .row_height = 44, .gap = 2, .padding = ui.Edges.all(8) });
        defer rows.end();
        while (rows.next()) |n| {
            const p = s.catalog.items[s.matches.items[n]];
            const on = if (s.selected) |name| std.mem.eql(u8, name, p.name) else false;
            var line = ui.div(c).row().wFull().h(44).px(12).itemsCenter().gap(10).rounded(8).control();
            if (on) line = line.bg(c.theme.accent.alpha(0.16));
            line = line.hover(c.theme.surface_hover);
            if (line.clicked()) {
                s.selected = p.name;
                s.pending = .none;
            }
            const name = ui.div(c).row().grow().itemsCenter().gap(8);
            ui.text(c, p.name, .{ .weight = .semibold, .truncate = .ellipsis });
            if (p.upgrade.len > 0) ui.text(c, i18n.t(s.lang, .badge_update), .{ .size = 12, .color = c.theme.success });
            if (p.orphan) ui.text(c, i18n.t(s.lang, .badge_orphan), .{ .size = 12, .color = c.theme.danger });
            name.end();
            ui.text(c, p.version, .{ .size = 12, .color = c.theme.muted, .mono = true });
            ui.text(c, kbText(c, p.size_kb), .{ .size = 12, .color = c.theme.muted });
            line.end();
        }
    }

    fn detail(s: *State, c: *ui.Context) void {
        const th = c.theme;
        ui.scroll(c, .{ .width = .{ .px = 340 }, .height = .fill, .padding = .all(16), .gap = 8, .background = th.surface });
        defer ui.end(c);
        const p = s.selectedPkg() orelse {
            ui.text(c, i18n.t(s.lang, .select_package), .{ .size = 16, .weight = .semibold });
            ui.text(c, i18n.t(s.lang, .select_hint), .{ .size = 13, .color = th.muted, .wrap = true });
            return;
        };
        ui.text(c, p.name, .{ .size = 18, .weight = .bold });
        ui.text(c, p.summary, .{ .size = 13, .color = th.muted, .wrap = true });
        s.fact(c, i18n.t(s.lang, .fact_version), p.version);
        if (p.upgrade.len > 0) s.fact(c, i18n.t(s.lang, .fact_update), c.print("{s}  →  {s}", .{ p.version, p.upgrade }));
        s.fact(c, i18n.t(s.lang, .fact_size), kbText(c, p.size_kb));
        s.fact(c, i18n.t(s.lang, .fact_origin), if (p.auto) i18n.t(s.lang, .origin_auto) else i18n.t(s.lang, .origin_manual));
        if (p.installed_on.len > 0) s.fact(c, i18n.t(s.lang, .fact_installed), p.installed_on);
        if (p.section.len > 0) s.fact(c, i18n.t(s.lang, .fact_section), p.section);
        if (p.arch.len > 0) s.fact(c, i18n.t(s.lang, .fact_arch), p.arch);
        if (p.maintainer.len > 0) s.fact(c, i18n.t(s.lang, .fact_maintainer), p.maintainer);
        const users = s.requiredBy(p.name);
        s.fact(c, i18n.t(s.lang, .fact_required), i18n.requiredCount(c.alloc(), s.lang, users));
        if (p.depends.len > 0) {
            ui.text(c, i18n.t(s.lang, .dependencies), .{ .size = 12, .weight = .semibold, .color = th.muted });
            ui.text(c, p.depends, .{ .size = 12, .wrap = true });
        }
        s.actions(c, p);
    }

    fn fact(s: *State, c: *ui.Context, k: []const u8, v: []const u8) void {
        _ = s;
        const row = ui.div(c).column().wFull().gap(1);
        defer row.end();
        ui.text(c, k, .{ .size = 11, .color = c.theme.muted });
        ui.text(c, v, .{ .size = 13, .wrap = true });
    }

    fn actions(s: *State, c: *ui.Context, p: *const catalog.Package) void {
        const th = c.theme;
        if (s.pending != .none) {
            ui.text(c, s.pendingText(c, p.name), .{ .size = 13, .wrap = true });
            const row = ui.div(c).row().gap(8);
            defer row.end();
            if (ui.button(c, i18n.t(s.lang, .confirm), .{ .variant = .danger, .size = 13 }).clicked) s.apply();
            if (ui.button(c, i18n.t(s.lang, .cancel), .{ .variant = .ghost, .size = 13 }).clicked) s.pending = .none;
            return;
        }
        const row = ui.div(c).row().gap(8);
        defer row.end();
        if (p.upgrade.len > 0 and ui.button(c, i18n.t(s.lang, .upgrade), .{ .variant = .primary, .size = 13 }).clicked)
            s.pending = .upgrade;
        if (catalog.removable(p.*)) {
            if (ui.button(c, i18n.t(s.lang, .remove), .{ .variant = .danger, .size = 13 }).clicked) s.pending = .remove;
        } else ui.text(c, if (p.essential) i18n.t(s.lang, .essential_blocked) else i18n.t(s.lang, .required_blocked), .{ .size = 12, .color = th.muted, .wrap = true });
        if (s.catalog.orphans > 0) {
            if (ui.button(c, i18n.t(s.lang, .clean_orphans), .{ .variant = .ghost, .size = 13 }).clicked) s.pending = .autoremove;
        }
    }

    fn footer(s: *State, c: *ui.Context) void {
        const bar = ui.div(c).row().wFull().px(20).py(8).gap(12).itemsCenter().bg(c.theme.surface);
        defer bar.end();
        const msg = if (s.status.len > 0) s.status else if (s.page == .resources)
            i18n.t(s.lang, .footer_resources)
        else
            i18n.t(s.lang, .footer_programs);
        const left = ui.div(c).row().grow();
        ui.text(c, msg, .{ .size = 12, .color = c.theme.muted, .wrap = true });
        left.end();
        s.langButton(c, "PT", .pt_BR);
        s.langButton(c, "EN", .en);
        s.langButton(c, "ES", .es);
        ui.text(c, c.print("wslpanel {s} · {s}", .{ meta.version, meta.date }), .{ .size = 12, .color = c.theme.muted, .mono = true });
    }

    fn langButton(s: *State, c: *ui.Context, label: []const u8, lang: i18n.Lang) void {
        const on = s.lang == lang;
        if (ui.button(c, label, .{ .variant = if (on) .primary else .ghost, .size = 12 }).clicked) s.lang = lang;
    }

    fn pendingText(s: *State, c: *ui.Context, name: []const u8) []const u8 {
        const a = c.alloc();
        return switch (s.pending) {
            .none => "",
            .remove => i18n.pendingRemove(a, s.lang, name),
            .purge => i18n.pendingPurge(a, s.lang, name),
            .upgrade => i18n.pendingUpgrade(a, s.lang, name),
            .upgrade_all => i18n.t(s.lang, .pending_upgrade_all),
            .autoremove => i18n.t(s.lang, .pending_autoremove),
            .update_index => i18n.t(s.lang, .pending_index),
        };
    }

    fn selectedPkg(s: *State) ?*catalog.Package {
        const name = s.selected orelse return null;
        for (s.catalog.items) |*p| if (std.mem.eql(u8, p.name, name)) return p;
        return null;
    }

    fn requiredBy(s: *State, name: []const u8) usize {
        var n: usize = 0;
        for (s.catalog.items) |p| {
            if (std.mem.eql(u8, p.name, name)) continue;
            if (catalog.fieldMentions(p.depends, name) or catalog.fieldMentions(p.pre_depends, name) or catalog.fieldMentions(p.recommends, name))
                n += 1;
        }
        return n;
    }

    fn apply(s: *State) void {
        const pending = s.pending;
        const name = s.selected;
        s.pending = .none;
        switch (pending) {
            .none => {},
            .remove => s.runApt(&.{ "remove", "-y", "--" }, name),
            .purge => s.runApt(&.{ "purge", "-y", "--" }, name),
            .upgrade => s.runApt(&.{ "install", "-y", "--only-upgrade", "--" }, name),
            .upgrade_all => s.runApt(&.{ "upgrade", "-y" }, null),
            .autoremove => s.runApt(&.{ "autoremove", "-y" }, null),
            .update_index => s.runApt(&.{"update"}, null),
        }
    }

    fn runApt(s: *State, op: []const []const u8, name: ?[]const u8) void {
        if (name) |n| if (!safeName(n)) {
            s.setStatus(i18n.t(s.lang, .bad_name));
            return;
        };
        var buf: [10][]const u8 = undefined;
        var n: usize = 0;
        buf[n] = "sudo";
        n += 1;
        buf[n] = "-n";
        n += 1;
        buf[n] = "apt-get";
        n += 1;
        for (op) |arg| {
            if (n >= buf.len) break;
            buf[n] = arg;
            n += 1;
        }
        if (name) |pkg| if (n < buf.len) {
            buf[n] = pkg;
            n += 1;
        };
        const r = std.process.run(s.gpa, s.io, .{
            .argv = buf[0..n],
            .stdout_limit = .limited(1 << 16),
            .stderr_limit = .limited(1 << 16),
        }) catch {
            s.note(op, name, i18n.t(s.lang, .apt_start_failed));
            return;
        };
        defer s.gpa.free(r.stdout);
        defer s.gpa.free(r.stderr);
        if (!r.term.success()) {
            const err = if (r.stderr.len > 0) r.stderr else r.stdout;
            if (err.len == 0 or std.mem.indexOf(u8, err, "password") != null)
                s.note(op, name, i18n.t(s.lang, .sudo_password))
            else
                s.note(op, name, err);
            return;
        }
        s.brief(if (r.stdout.len > 0) r.stdout else i18n.t(s.lang, .done));
        s.want_reload = true;
    }

    fn note(s: *State, op: []const []const u8, name: ?[]const u8, why: []const u8) void {
        var tmp: [360]u8 = undefined;
        var w: usize = copyInto(tmp[0..], 0, "sudo apt-get");
        for (op) |arg| {
            w = copyInto(tmp[0..], w, " ");
            w = copyInto(tmp[0..], w, arg);
        }
        if (name) |pkg| {
            w = copyInto(tmp[0..], w, " ");
            w = copyInto(tmp[0..], w, pkg);
        }
        w = copyInto(tmp[0..], w, " — ");
        w = copyInto(tmp[0..], w, why);
        s.brief(tmp[0..w]);
    }

    fn brief(s: *State, msg: []const u8) void {
        var tmp: [220]u8 = undefined;
        const n = @min(msg.len, tmp.len);
        for (msg[0..n], 0..) |ch, i| tmp[i] = if (ch == '\n' or ch == '\r' or ch == '\t') ' ' else ch;
        s.setStatus(tmp[0..n]);
    }

    fn setStatus(s: *State, msg: []const u8) void {
        s.status_owned.clearRetainingCapacity();
        s.status_owned.appendSlice(s.gpa, msg) catch return;
        s.status = s.status_owned.items;
    }
};

fn kbText(c: *ui.Context, kb: u64) []const u8 {
    if (kb < 1024) return c.print("{d} KB", .{kb});
    if (kb < 1024 * 1024) return c.print("{d:.1} MB", .{@as(f64, @floatFromInt(kb)) / 1024.0});
    return c.print("{d:.2} GB", .{@as(f64, @floatFromInt(kb)) / (1024.0 * 1024.0)});
}

fn copyInto(buf: []u8, w: usize, s: []const u8) usize {
    const n = @min(s.len, buf.len -| w);
    @memcpy(buf[w..][0..n], s[0..n]);
    return w + n;
}

fn safeName(name: []const u8) bool {
    if (name.len == 0 or name.len > 128 or !std.ascii.isAlphanumeric(name[0])) return false;
    for (name) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '+' or ch == '-' or ch == '.') continue;
        return false;
    }
    return true;
}
