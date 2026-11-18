//! wslpanel: resources and installed packages for this WSL distro.
const nanoui = @import("nanoui");
const app_view = @import("app.zig");
const i18n = @import("i18n.zig");

pub const panic = nanoui.panic;
pub const std_options = nanoui.std_options;
pub const std_options_debug_threaded_io = nanoui.std_options_debug_threaded_io;

pub fn main(init: nanoui.Init) void {
    const lang = i18n.detect();
    const app = nanoui.App.create(init, .{ .name = "wslpanel" }) catch return;
    defer app.destroy();
    var state: app_view.State = .init(init.gpa, init.io);
    state.lang = lang;
    defer state.deinit();
    _ = app.newWindow(.{
        .title = i18n.t(lang, .app_title),
        .width = 1100,
        .height = 720,
        .min_width = 800,
        .min_height = 520,
        .content = .{ .view = .init(&state, app_view.State.view) },
    }) catch return;
    app.run() catch return;
}
