package main

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:encoding/json"

import rl "vendor:raylib"

winsize :: [2]i32 {1800, 1200}

scale :: 5

PlayerState :: enum {
    Idle,
    Jump,
    Attack
}

Player :: struct {
    pos: [2]f32,
    size: [2]f32,
    vel: [2]f32,
    state: PlayerState,
    texture: rl.Texture,
    animations: [PlayerState]SpriteAnimation
}

SpriteAnimation :: struct {
    current_frame: int,
    secs_since_last_frame: f32,
    frames: []SpriteFrame
}

SpriteSheet :: struct {
    texture: rl.Texture,
}

SpriteFrame :: struct {
    pos: [2]int,
    size: [2]int,
    duration_secs: f32
}

Monster :: struct {
    pos: [2]f32,
    size: [2]f32,
    vel: [2]f32,
    texture: rl.Texture,
    animation: SpriteAnimation
}

main :: proc() {
    rl.InitWindow(winsize.x, winsize.y, "Survivors")
    rl.SetTargetFPS(144)
    rl.SetExitKey(.Q)

    slime_img := rl.LoadImage("slime.png")
    slime_txt := rl.LoadTextureFromImage(slime_img)

    ghost_img := rl.LoadImage("ghost.png")
    ghost_txt := rl.LoadTextureFromImage(ghost_img)

    slime_json_data, ghost_json_data: json.Value
    err: json.Error
    {
        slime_data, ok := os.read_entire_file("slime.json")
        if !ok {
            fmt.eprintfln("Failed to open slime.json")
            return
        }
        slime_json_data, err = json.parse(slime_data)
        if err != .None {
            fmt.eprintfln("Failed to load json")
            return
        }
        delete(slime_data)
    }
    defer json.destroy_value(slime_json_data)


    {
        ghost_data, ok := os.read_entire_file("ghost.json")
        if !ok {
            fmt.eprintfln("Failed to open ghost.json")
            return
        }
        ghost_json_data, err = json.parse(ghost_data)
        if err != .None {
            fmt.eprintfln("Failed to load json")
            return
        }
        delete(ghost_data)
    }
    defer json.destroy_value(ghost_json_data)

    fmt.printfln("tags: %v", slime_json_data.(json.Object)["meta"].(json.Object)["frameTags"])

    fmt.printfln("anim: %v", load_monster_animations(ghost_json_data))
    player := player_create(slime_txt, load_player_animations(slime_json_data))
    monster := monster_create(ghost_txt, load_monster_animations(ghost_json_data))

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()
        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            monster_update(&monster, &player, dt)
            monster_draw(&monster)
            player_update(&player, dt)
            player_draw(&player)
        rl.EndDrawing()

        move_directions: [2]f32
        speed := 75*dt
        if rl.IsKeyDown(.W) {
            move_directions.y = -1
        }
        if rl.IsKeyDown(.S) {
            move_directions.y = 1
        }
        if rl.IsKeyDown(.A) {
            move_directions.x = -1
        }
        if rl.IsKeyDown(.D) {
            move_directions.x = 1
        }
        move_directions = linalg.normalize0(move_directions)
        player.vel += move_directions
    }
}

load_player_animations :: proc(json_data: json.Value) -> [PlayerState]SpriteAnimation {
    results: [PlayerState]SpriteAnimation
    root := json_data.(json.Object)
    frames := root["frames"].(json.Array)
    meta := root["meta"].(json.Object)
    frameTags := meta["frameTags"].(json.Array)

    for tagValue in frameTags {
        tag := tagValue.(json.Object)
        name := tag["name"].(json.String)
        fmt.printfln("name: %v", name)
        from := int(tag["from"].(json.Float))
        to := int(tag["to"].(json.Float))

        state, ok := fmt.string_to_enum_value(PlayerState, name)

        sprite_frames := make([]SpriteFrame, to - from + 1)
        for i in 0..<len(sprite_frames) {
            frame := frames[from + i].(json.Object)
            rect := frame["frame"].(json.Object)
            sprite_frames[i].pos = {int(rect["x"].(json.Float)), int(rect["y"].(json.Float))}
            sprite_frames[i].size = {int(rect["w"].(json.Float)), int(rect["h"].(json.Float))}
            sprite_frames[i].duration_secs = f32(frame["duration"].(json.Float)) / 1000
        }
        results[state] = SpriteAnimation {
            current_frame = 0,
            frames = sprite_frames
        }
    }

    return results
}

player_create :: proc(texture: rl.Texture, animations: [PlayerState]SpriteAnimation) -> Player {
    return Player {
        size = 8,
        texture = texture,
        animations = animations
    }
}

player_update :: proc(p: ^Player, dt: f32) {
    player_update_animation(p, dt)
    p.pos += p.vel * dt
    max_vel := f32(50)
    p.vel.x = clamp(p.vel.x, -max_vel, max_vel)
    p.vel.y = clamp(p.vel.y, -max_vel, max_vel)

    p.vel.x -= 3*p.vel.x*dt
    p.vel.y -= 3*p.vel.y*dt
}

player_update_animation :: proc(p: ^Player, dt: f32) {
    animation := &p.animations[p.state]
    animation.secs_since_last_frame += dt
    duration := animation.frames[animation.current_frame].duration_secs
    if animation.secs_since_last_frame >= duration {
        animation.secs_since_last_frame = 0
        animation.current_frame = (animation.current_frame + 1) % len(animation.frames)
    }
}

player_draw :: proc(p: ^Player) {
    rl.DrawTexturePro(p.texture, player_spritesheet_rect(p), {p.pos.x*scale, p.pos.y*scale, scale*p.size.x, scale*p.size.y}, {0,0}, 0, rl.WHITE)
}

player_spritesheet_rect :: proc(p: ^Player) -> rl.Rectangle {
    animation := &p.animations[p.state]
    current_frame := animation.frames[animation.current_frame]
    pos := linalg.to_f32(current_frame.pos)
    size := linalg.to_f32(current_frame.size)
    return rl.Rectangle {pos.x, pos.y, size.x, size.y}
}

load_monster_animations :: proc(json_data: json.Value) -> SpriteAnimation {
    result: SpriteAnimation
    root := json_data.(json.Object)
    frames := root["frames"].(json.Array)
    meta := root["meta"].(json.Object)
    frameTags := meta["frameTags"].(json.Array)

    for tagValue in frameTags {
        tag := tagValue.(json.Object)
        name := tag["name"].(json.String)
        fmt.printfln("name: %v", name)
        from := int(tag["from"].(json.Float))
        to := int(tag["to"].(json.Float))

        sprite_frames := make([]SpriteFrame, to - from + 1)
        for i in 0..<len(sprite_frames) {
            frame := frames[from + i].(json.Object)
            rect := frame["frame"].(json.Object)
            sprite_frames[i].pos = {int(rect["x"].(json.Float)), int(rect["y"].(json.Float))}
            sprite_frames[i].size = {int(rect["w"].(json.Float)), int(rect["h"].(json.Float))}
            sprite_frames[i].duration_secs = f32(frame["duration"].(json.Float)) / 1000
        }
        result = SpriteAnimation {
            current_frame = 0,
            frames = sprite_frames
        }
    }

    return result
}

monster_create :: proc(texture: rl.Texture, animation: SpriteAnimation) -> Monster {
    return Monster {
        size = 8,
        texture = texture,
        animation = animation
    }
}

monster_update :: proc(m: ^Monster, p: ^Player, dt: f32) {
    monster_update_animation(m, dt)
    speed := f32(20)
    direction := linalg.normalize0(p.pos - m.pos)
    m.vel = speed * direction
    m.pos += m.vel * dt
    max_vel := f32(50)
    m.vel.x = clamp(m.vel.x, -max_vel, max_vel)
    m.vel.y = clamp(m.vel.y, -max_vel, max_vel)

    m.vel.x -= 3*m.vel.x*dt
    m.vel.y -= 3*m.vel.y*dt
}

monster_update_animation :: proc(m: ^Monster, dt: f32) {
    animation := &m.animation
    animation.secs_since_last_frame += dt
    duration := animation.frames[animation.current_frame].duration_secs
    if animation.secs_since_last_frame >= duration {
        animation.secs_since_last_frame = 0
        animation.current_frame = (animation.current_frame + 1) % len(animation.frames)
    }
}

monster_draw :: proc(m: ^Monster) {
    rl.DrawTexturePro(m.texture, monster_spritesheet_rect(m), {m.pos.x*scale, m.pos.y*scale, scale*m.size.x, scale*m.size.y}, {0,0}, 0, rl.WHITE)
}

monster_spritesheet_rect :: proc(m: ^Monster) -> rl.Rectangle {
    animation := &m.animation
    current_frame := animation.frames[animation.current_frame]
    pos := linalg.to_f32(current_frame.pos)
    size := linalg.to_f32(current_frame.size)
    return rl.Rectangle {pos.x, pos.y, size.x, size.y}
}

