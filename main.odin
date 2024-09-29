package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

import rl "vendor:raylib"

winsize :: [2]i32 {1800, 1200}

scale :: 5

Game :: struct {
    player: Player,
    monsters: [dynamic]Monster,
    projectiles: [dynamic]Projectile,
    spritesheets: [dynamic]SpriteSheet
}

PlayerState :: enum {
    Idle,
    Jump,
    Attack
}

ProjectileState :: enum {
    Travel,
    Impact
}

Player :: struct {
    health: int,
    pos: [2]f32,
    size: [2]f32,
    vel: [2]f32,
    attack_timer: f32,
    attack_threshold: f32,
    state: PlayerState,
    animations: [PlayerState]SpriteAnimation
}

Projectile :: struct {
    pos: [2]f32,
    size: [2]f32,
    vel: [2]f32,
    impact_timer: f32,
    target: ^Monster,
    state: ProjectileState,
    animations: [ProjectileState]SpriteAnimation
}

Monster :: struct {
    health: int,
    pos: [2]f32,
    size: [2]f32,
    vel: [2]f32,
    animation: SpriteAnimation
}

TileType :: enum {
    Grass,
    GrassFlower
}

Tileset :: struct {
    rows: int,
    cols: int,
    tile_width: int,
    tile_height: int,
    texture: rl.Texture
}

main :: proc() {
    rl.InitWindow(winsize.x, winsize.y, "Survivors")
    rl.SetTargetFPS(60)
    rl.SetExitKey(.Q)

    grass_img := rl.LoadImage("grass.png")
    grass_txt := rl.LoadTextureFromImage(grass_img)

    tileset := Tileset {
        rows = 2,
        cols = 1,
        tile_width = 8,
        tile_height = 8,
        texture = grass_txt
    }

    game, ok := game_create()
    if !ok {
        fmt.eprintln("Error starting game")
        return
    }

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()

        game_update(&game, dt)

        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            background_draw(tileset)
            game_draw(&game)

            rl.DrawFPS(10, 10)
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
        game.player.vel += move_directions*speed

        free_all(context.temp_allocator)
    }
}

game_create :: proc() -> (game: Game, ok: bool) {
    spritesheets := make([dynamic]SpriteSheet)
    slime_spritesheet := load_spritesheet("slime") or_return
    append(&spritesheets, slime_spritesheet)
    ghost_spritesheet := load_spritesheet("ghost") or_return
    append(&spritesheets, ghost_spritesheet)
    magic_missile_spritesheet := load_spritesheet("magic-missile") or_return
    append(&spritesheets, magic_missile_spritesheet)

    player := player_create(slime_spritesheet)
    monster := monster_create(ghost_spritesheet)
    monsters := make([dynamic]Monster)
    append(&monsters, monster)
    projectiles := make([dynamic]Projectile)
    
    return Game {
        player,
        monsters,
        projectiles,
        spritesheets
    }, true
}

game_destroy :: proc(game: ^Game) {
    for spritesheet in game.spritesheets {
        spritesheet_destroy(spritesheet)
    }
}

game_update :: proc(game: ^Game, dt: f32) {
    for &monster in game.monsters {
        monster_update(&monster, &game.player, dt)
    }
    for &projectile in game.projectiles {
        projectile_update(&projectile, game, dt)
    }
    player_update(&game.player, game, dt)
}

game_draw :: proc(game: ^Game) {
    for &monster in game.monsters {
        monster_draw(&monster)
    }
    for &projectile in game.projectiles {
        projectile_draw(&projectile)
    }
    player_draw(&game.player)
}

player_create :: proc(spritesheet: SpriteSheet) -> Player {
    animations: [PlayerState]SpriteAnimation
    for state in PlayerState {
        state_name, _ := fmt.enum_value_to_string(state)
        animations[state] = SpriteAnimation {
            texture = spritesheet.texture,
            frames = spritesheet.animations[state_name]
        }
    }
    return Player {
        size = 8,
        attack_threshold = 3,
        animations = animations
    }
}

player_update :: proc(p: ^Player, game: ^Game, dt: f32) {
    player_update_animation(p, dt)
    p.pos += p.vel * dt
    max_vel := f32(50)
    p.vel.x = clamp(p.vel.x, -max_vel, max_vel)
    p.vel.y = clamp(p.vel.y, -max_vel, max_vel)

    p.vel.x -= 3*p.vel.x*dt
    p.vel.y -= 3*p.vel.y*dt

    p.attack_timer += dt
    if p.attack_timer >= p.attack_threshold {
        p.attack_timer = 0
        append(&game.projectiles, projectile_create(game.spritesheets[2], p.pos, &game.monsters[0]))
    }
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

projectile_create :: proc(spritesheet: SpriteSheet, pos: [2]f32, target: ^Monster, size: [2]f32={8,8}) -> Projectile {
    animations: [ProjectileState]SpriteAnimation
    for state in ProjectileState {
        state_name, _ := fmt.enum_value_to_string(state)
        animations[state] = SpriteAnimation {
            texture = spritesheet.texture,
            frames = spritesheet.animations[state_name]
        }
    }
    return Projectile {
        pos, size, 20, 0, target, .Travel, animations
    }
}

projectile_update :: proc(p: ^Projectile, game: ^Game, dt: f32) {
    p.vel = linalg.normalize0(p.target.pos - p.pos) * linalg.length(p.vel)
    p.pos += p.vel * dt
    max_vel := f32(50)
    p.vel.x = clamp(p.vel.x, -max_vel, max_vel)
    p.vel.y = clamp(p.vel.y, -max_vel, max_vel)

    if linalg.length2(p.target.pos - p.pos) < 4 {
        p.state = .Impact
    }
    if p.state == .Impact {
        p.impact_timer += dt
        if p.impact_timer >= 0.5 {
            unordered_remove(&game.projectiles, 0)
            p.target.health -= 5
        }
    }
}

projectile_draw :: proc(p: ^Projectile) {
    dst := rl.Rectangle{math.floor(p.pos.x)*scale, math.floor(p.pos.y)*scale, scale*p.size.x, scale*p.size.y}
    sprite_animation_draw(p.animations[p.state], dst)
}

sprite_animation_draw :: proc(sprite_animation: SpriteAnimation, dst: rl.Rectangle) {
    frame := sprite_animation.frames[sprite_animation.current_frame]
    rect := rl.Rectangle {
        f32(frame.pos.x), f32(frame.pos.y), f32(frame.size.x), f32(frame.size.y)
    }
    rl.DrawTexturePro(sprite_animation.texture, rect, dst, {}, 0, rl.WHITE)
}

player_draw :: proc(p: ^Player) {
    dst := rl.Rectangle{math.floor(p.pos.x)*scale, math.floor(p.pos.y)*scale, scale*p.size.x, scale*p.size.y}
    sprite_animation_draw(p.animations[p.state], dst)
}

player_spritesheet_rect :: proc(p: ^Player) -> rl.Rectangle {
    animation := &p.animations[p.state]
    current_frame := animation.frames[animation.current_frame]
    pos := linalg.to_f32(current_frame.pos)
    size := linalg.to_f32(current_frame.size)
    return rl.Rectangle {pos.x, pos.y, size.x, size.y}
}

monster_create :: proc(spritesheet: SpriteSheet) -> Monster {
    animation := SpriteAnimation {
        texture = spritesheet.texture,
        frames = spritesheet.animations["Idle"]
    }
    return Monster {
        size = 8,
        animation = animation
    }
}

monster_update :: proc(m: ^Monster, p: ^Player, dt: f32) {
    monster_update_animation(m, dt)
    speed := 40*dt
    direction := linalg.normalize0(p.pos - m.pos)
    m.vel += speed * direction
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
    dst := rl.Rectangle {math.floor(m.pos.x)*scale, math.floor(m.pos.y)*scale, scale*m.size.x, scale*m.size.y}
    sprite_animation_draw(m.animation, dst)
}

monster_spritesheet_rect :: proc(m: ^Monster) -> rl.Rectangle {
    animation := &m.animation
    current_frame := animation.frames[animation.current_frame]
    pos := linalg.to_f32(current_frame.pos)
    size := linalg.to_f32(current_frame.size)
    return rl.Rectangle {pos.x, pos.y, size.x, size.y}
}

background_draw :: proc(t: Tileset) {
    rand.reset(42069)
    for x in 0..<winsize.x/i32(t.tile_width*scale) {
        for y in 0..<winsize.y/i32(t.tile_height*scale) {
            r := rand.int_max(10)
            tile_type: TileType
            if r > 8 {
                tile_type = .GrassFlower
            } else {
                tile_type = .Grass
            }
            rl.DrawTexturePro(t.texture, tile_texture_rect(t, tile_type), {f32(int(x)*t.tile_width*scale), f32(int(y)*t.tile_height*scale), f32(t.tile_width*scale), f32(t.tile_height*scale)}, {0,0}, 0, rl.WHITE)
        }
    }
}

tile_texture_rect :: proc(t: Tileset, tile_type: TileType) -> rl.Rectangle {
    index := int(tile_type)
    col := index % t.cols
    row := index / t.cols
    pos := [2]f32 {f32(col*t.tile_width), f32(row*t.tile_height)}
    return rl.Rectangle {pos.x, pos.y, f32(t.tile_width), f32(t.tile_height)}
}
