const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .cpu_model = .baseline,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // ZeroUI / NanoShell Application Executable Target
    const example_app_exe = b.addExecutable(.{
        .name = "example_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example_app_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    example_app_exe.root_module.addIncludePath(b.path("vendor/include"));
    example_app_exe.root_module.addLibraryPath(b.path("vendor/lib"));
    example_app_exe.root_module.linkSystemLibrary("Ultralight", .{});
    example_app_exe.root_module.linkSystemLibrary("AppCore", .{});
    example_app_exe.root_module.linkSystemLibrary("WebCore", .{});

    const target_os = target.result.os.tag;
    if (target_os == .windows) {
        example_app_exe.subsystem = .Windows;
        example_app_exe.root_module.linkSystemLibrary("user32", .{});
        example_app_exe.root_module.linkSystemLibrary("gdi32", .{});
        example_app_exe.root_module.linkSystemLibrary("shell32", .{});
        example_app_exe.root_module.linkSystemLibrary("comdlg32", .{});
        example_app_exe.root_module.linkSystemLibrary("opengl32", .{});
    }
    b.installArtifact(example_app_exe);

    // Install Dynamic WebKit & Shared Assets
    const install_ul_dll = b.addInstallFile(b.path("vendor/bin/Ultralight.dll"), "bin/Ultralight.dll");
    const install_ul_core_dll = b.addInstallFile(b.path("vendor/bin/UltralightCore.dll"), "bin/UltralightCore.dll");
    const install_webcore_dll = b.addInstallFile(b.path("vendor/bin/WebCore.dll"), "bin/WebCore.dll");
    const install_appcore_dll = b.addInstallFile(b.path("vendor/bin/AppCore.dll"), "bin/AppCore.dll");

    const install_icu_dat = b.addInstallFile(b.path("vendor/resources/icudt67l.dat"), "bin/resources/icudt67l.dat");
    const install_icu_dat_root = b.addInstallFile(b.path("vendor/resources/icudt67l.dat"), "bin/icudt67l.dat");
    const install_icu_dat_assets = b.addInstallFile(b.path("vendor/resources/icudt67l.dat"), "bin/assets/icudt67l.dat");

    const install_cacert_pem = b.addInstallFile(b.path("vendor/resources/cacert.pem"), "bin/resources/cacert.pem");
    const install_cacert_pem_root = b.addInstallFile(b.path("vendor/resources/cacert.pem"), "bin/cacert.pem");
    const install_cacert_pem_assets = b.addInstallFile(b.path("vendor/resources/cacert.pem"), "bin/assets/cacert.pem");

    b.getInstallStep().dependOn(&install_ul_dll.step);
    b.getInstallStep().dependOn(&install_ul_core_dll.step);
    b.getInstallStep().dependOn(&install_webcore_dll.step);
    b.getInstallStep().dependOn(&install_appcore_dll.step);

    b.getInstallStep().dependOn(&install_icu_dat.step);
    b.getInstallStep().dependOn(&install_icu_dat_root.step);
    b.getInstallStep().dependOn(&install_icu_dat_assets.step);

    b.getInstallStep().dependOn(&install_cacert_pem.step);
    b.getInstallStep().dependOn(&install_cacert_pem_root.step);
    b.getInstallStep().dependOn(&install_cacert_pem_assets.step);

    // NanoShell CLI Executable Target
    const cli_exe = b.addExecutable(.{
        .name = "nanoshell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(cli_exe);

    // Install Example App HTML/CSS/JS files to bin/assets/ and bin/app/
    const install_assets_html = b.addInstallFile(b.path("example_app/index.html"), "bin/assets/index.html");
    const install_assets_css = b.addInstallFile(b.path("example_app/styles.css"), "bin/assets/styles.css");
    const install_assets_js = b.addInstallFile(b.path("example_app/app.js"), "bin/assets/app.js");
    const install_assets_settings = b.addInstallFile(b.path("example_app/settings.html"), "bin/assets/settings.html");

    const install_app_html = b.addInstallFile(b.path("example_app/index.html"), "bin/app/index.html");
    const install_app_css = b.addInstallFile(b.path("example_app/styles.css"), "bin/app/styles.css");
    const install_app_js = b.addInstallFile(b.path("example_app/app.js"), "bin/app/app.js");
    const install_app_settings = b.addInstallFile(b.path("example_app/settings.html"), "bin/app/settings.html");

    b.getInstallStep().dependOn(&install_assets_html.step);
    b.getInstallStep().dependOn(&install_assets_css.step);
    b.getInstallStep().dependOn(&install_assets_js.step);
    b.getInstallStep().dependOn(&install_assets_settings.step);

    b.getInstallStep().dependOn(&install_app_html.step);
    b.getInstallStep().dependOn(&install_app_css.step);
    b.getInstallStep().dependOn(&install_app_js.step);
    b.getInstallStep().dependOn(&install_app_settings.step);

    const run_cmd = b.addRunArtifact(example_app_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the NanoShell native engine");
    run_step.dependOn(&run_cmd.step);
}
