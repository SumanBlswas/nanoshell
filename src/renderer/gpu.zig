const std = @import("std");

pub const gl = struct {
    pub const GLenum = u32;
    pub const GLboolean = u8;
    pub const GLbitfield = u32;
    pub const GLbyte = i8;
    pub const GLshort = i16;
    pub const GLint = i32;
    pub const GLsizei = i32;
    pub const GLubyte = u8;
    pub const GLushort = u16;
    pub const GLuint = u32;
    pub const GLfloat = f32;
    pub const GLclampf = f32;
    pub const GLdouble = f64;
    pub const GLclampd = f64;
    pub const GLchar = u8;

    pub const TRIANGLES: GLenum = 0x0004;
    pub const UNSIGNED_INT: GLenum = 0x5125;
    pub const FLOAT: GLenum = 0x5126;
    pub const ARRAY_BUFFER: GLenum = 0x8892;
    pub const ELEMENT_ARRAY_BUFFER: GLenum = 0x8893;
    pub const STREAM_DRAW: GLenum = 0x88E0;
    pub const STATIC_DRAW: GLenum = 0x88E4;
    pub const DYNAMIC_DRAW: GLenum = 0x88E8;
    pub const FRAGMENT_SHADER: GLenum = 0x8B30;
    pub const VERTEX_SHADER: GLenum = 0x8B31;
    pub const COMPILE_STATUS: GLenum = 0x8B81;
    pub const LINK_STATUS: GLenum = 0x8B82;
    pub const COLOR_BUFFER_BIT: GLbitfield = 0x00004000;
    pub const BLEND: GLenum = 0x0BE2;
    pub const SRC_ALPHA: GLenum = 0x0302;
    pub const ONE_MINUS_SRC_ALPHA: GLenum = 0x0303;

    pub const PROJECTION: GLenum = 0x1701;
    pub const MODELVIEW: GLenum = 0x1700;
    pub const QUADS: GLenum = 0x0007;

    pub const TEXTURE_2D: GLenum = 0x0DE1;
    pub const TEXTURE_MIN_FILTER: GLenum = 0x2801;
    pub const TEXTURE_MAG_FILTER: GLenum = 0x2800;
    pub const LINEAR: GLenum = 0x2601;
    pub const RGBA: GLenum = 0x1908;
    pub const UNSIGNED_BYTE: GLenum = 0x1401;

    pub extern "opengl32" fn glClear(mask: GLbitfield) callconv(.winapi) void;
    pub extern "opengl32" fn glClearColor(red: GLclampf, green: GLclampf, blue: GLclampf, alpha: GLclampf) callconv(.winapi) void;
    pub extern "opengl32" fn glEnable(cap: GLenum) callconv(.winapi) void;
    pub extern "opengl32" fn glDisable(cap: GLenum) callconv(.winapi) void;
    pub extern "opengl32" fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) callconv(.winapi) void;
    pub extern "opengl32" fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) callconv(.winapi) void;
    pub extern "opengl32" fn glMatrixMode(mode: GLenum) callconv(.winapi) void;
    pub extern "opengl32" fn glLoadIdentity() callconv(.winapi) void;
    pub extern "opengl32" fn glOrtho(left: GLdouble, right: GLdouble, bottom: GLdouble, top: GLdouble, zNear: GLdouble, zFar: GLdouble) callconv(.winapi) void;
    pub extern "opengl32" fn glBegin(mode: GLenum) callconv(.winapi) void;
    pub extern "opengl32" fn glEnd() callconv(.winapi) void;
    pub extern "opengl32" fn glColor4f(r: GLfloat, g: GLfloat, b: GLfloat, a: GLfloat) callconv(.winapi) void;
    pub extern "opengl32" fn glVertex2f(x: GLfloat, y: GLfloat) callconv(.winapi) void;
    pub extern "opengl32" fn glTexCoord2f(s: GLfloat, t: GLfloat) callconv(.winapi) void;
    pub extern "opengl32" fn glGenTextures(n: GLsizei, textures: [*]GLuint) callconv(.winapi) void;
    pub extern "opengl32" fn glBindTexture(target: GLenum, texture: GLuint) callconv(.winapi) void;
    pub extern "opengl32" fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) callconv(.winapi) void;
    pub extern "opengl32" fn glTexImage2D(target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, type_enum: GLenum, pixels: ?*const anyopaque) callconv(.winapi) void;
    pub extern "opengl32" fn wglGetProcAddress(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
};

// Shader Program Handle
pub const ShaderProgram = struct {
    program_id: u32,
    u_resolution_loc: i32,

    pub fn init(vert_code: [*:0]const u8, frag_code: [*:0]const u8, get_proc: *const fn ([*:0]const u8) ?*anyopaque) !ShaderProgram {
        _ = get_proc;
        _ = vert_code;
        _ = frag_code;
        // In full GPU pipeline, compiles vertex + fragment shaders into program_id
        return ShaderProgram{
            .program_id = 1,
            .u_resolution_loc = 0,
        };
    }

    pub fn bind(self: ShaderProgram) void {
        _ = self;
    }

    pub fn setResolution(self: ShaderProgram, width: f32, height: f32) void {
        _ = self;
        _ = width;
        _ = height;
    }
};

pub const GpuContext = struct {
    width: u32,
    height: u32,
    shader: ShaderProgram,

    pub fn init(width: u32, height: u32) !GpuContext {
        const vert_src = @embedFile("shaders/quad.vert");
        const frag_src = @embedFile("shaders/css_primitives.frag");
        _ = vert_src;
        _ = frag_src;

        return GpuContext{
            .width = width,
            .height = height,
            .shader = ShaderProgram{ .program_id = 1, .u_resolution_loc = 0 },
        };
    }

    pub fn resize(self: *GpuContext, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
    }

    pub fn beginFrame(self: *GpuContext) void {
        gl.glViewport(0, 0, @intCast(self.width), @intCast(self.height));
        gl.glMatrixMode(gl.PROJECTION);
        gl.glLoadIdentity();
        gl.glOrtho(0.0, @floatFromInt(self.width), @floatFromInt(self.height), 0.0, -1.0, 1.0);
        gl.glMatrixMode(gl.MODELVIEW);
        gl.glLoadIdentity();

        gl.glClearColor(0.05, 0.05, 0.08, 1.0);
        gl.glClear(gl.COLOR_BUFFER_BIT);
        gl.glEnable(gl.BLEND);
        gl.glBlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    }
};
