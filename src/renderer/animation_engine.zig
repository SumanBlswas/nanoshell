const std = @import("std");

pub const SpringConfig = struct {
    stiffness: f32 = 170.0,
    damping: f32 = 26.0,
    mass: f32 = 1.0,
};

pub const SpringAnimation = struct {
    current_val: f32,
    target_val: f32,
    velocity: f32,
    config: SpringConfig,

    pub fn init(initial_val: f32, target_val: f32, config: SpringConfig) SpringAnimation {
        return .{
            .current_val = initial_val,
            .target_val = target_val,
            .velocity = 0.0,
            .config = config,
        };
    }

    pub fn tick(self: *SpringAnimation, delta_sec: f32) f32 {
        const spring_force = -self.config.stiffness * (self.current_val - self.target_val);
        const damping_force = -self.config.damping * self.velocity;
        const accel = (spring_force + damping_force) / self.config.mass;

        self.velocity += accel * delta_sec;
        self.current_val += self.velocity * delta_sec;

        return self.current_val;
    }
};

pub const AnimationEngine = struct {
    allocator: std.mem.Allocator,
    springs: std.ArrayList(SpringAnimation),

    pub fn init(allocator: std.mem.Allocator) AnimationEngine {
        return .{
            .allocator = allocator,
            .springs = std.ArrayList(SpringAnimation).empty,
        };
    }

    pub fn deinit(self: *AnimationEngine) void {
        self.springs.deinit(self.allocator);
    }

    pub fn addSpring(self: *AnimationEngine, spring: SpringAnimation) !void {
        try self.springs.append(self.allocator, spring);
    }

    pub fn processFrame(self: *AnimationEngine, delta_sec: f32) void {
        for (self.springs.items) |*spring| {
            _ = spring.tick(delta_sec);
        }
    }
};
