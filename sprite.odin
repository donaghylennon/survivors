package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"

import rl "vendor:raylib"

SpriteAnimation :: struct {
    texture: rl.Texture,
    current_frame: int,
    secs_since_last_frame: f32,
    frames: []SpriteFrame
}

SpriteSheet :: struct {
    frames: []SpriteFrame,
    animations: map[string][]SpriteFrame,
    //animations: [E][]SpriteFrame,
    texture: rl.Texture,
}

SpriteFrame :: struct {
    pos: [2]int,
    size: [2]int,
    duration_secs: f32
}

load_spritesheet :: proc(name: string) -> (SpriteSheet, bool) {
    image_filename := strings.concatenate({name, ".png\x00"})
    json_filename := strings.concatenate({name, ".json\x00"})
    defer delete(image_filename)
    defer delete(json_filename)

    image := rl.LoadImage(strings.unsafe_string_to_cstring(image_filename))
    texture := rl.LoadTextureFromImage(image)
    rl.UnloadImage(image)

    data, ok := os.read_entire_file(json_filename)
    if !ok {
        fmt.eprintfln("Failed to read spritesheet json file: %v", json_filename)
        return {}, false
    }
    defer delete(data)

    json_value, err := json.parse(data)
    if err != .None {
        fmt.eprintfln("Failed to parse spritesheet json file: %v", json_filename)
        return {}, false
    }
    defer json.destroy_value(json_value)

    sprite_frames, animations, parse_ok := parse_spritesheet_json(json_value)
    if !parse_ok {
        fmt.eprintfln("Failed to parse required spritesheet info from json file: %v", json_filename)
        return {}, false
    }
    return SpriteSheet {
            frames = sprite_frames,
            animations = animations,
            texture = texture
        }, true
}

parse_spritesheet_json :: proc(json_data: json.Value) -> (sprite_frames: []SpriteFrame, animations: map[string][]SpriteFrame, ok: bool) {
    root := json_data.(json.Object) or_return

    frames := root["frames"].(json.Array) or_return
    meta := root["meta"].(json.Object) or_return
    frameTags := meta["frameTags"].(json.Array) or_return

    sprite_frames = make([]SpriteFrame, len(frames))
    for frameValue, i in frames {
        frame := frameValue.(json.Object) or_return
        rect := frame["frame"].(json.Object) or_return
        sprite_frames[i].pos.x = int(rect["x"].(json.Float) or_return)
        sprite_frames[i].pos.y = int(rect["y"].(json.Float) or_return)
        sprite_frames[i].size.x = int(rect["w"].(json.Float) or_return)
        sprite_frames[i].size.y = int(rect["h"].(json.Float) or_return)
        sprite_frames[i].duration_secs = f32(frame["duration"].(json.Float) or_return) / 1000
    }

    animations = make(map[string][]SpriteFrame)
    for tagValue in frameTags {
        tag := tagValue.(json.Object) or_return
        name := strings.clone(tag["name"].(json.String) or_return)
        from := int(tag["from"].(json.Float) or_return)
        to := int(tag["to"].(json.Float) or_return)
        animations[name] = sprite_frames[from:to+1]
    }
    ok = true
    return
}

spritesheet_destroy :: proc(spritesheet: SpriteSheet) {
    for key in spritesheet.animations {
        delete(key)
    }
    delete(spritesheet.animations)
    delete(spritesheet.frames)
    rl.UnloadTexture(spritesheet.texture)
}

load_player_animations :: proc(spritesheet: SpriteSheet) -> [PlayerState]SpriteAnimation {
    results: [PlayerState]SpriteAnimation
    for state in PlayerState {
        state_name, _ := fmt.enum_value_to_string(state)
        results[state] = SpriteAnimation {
            frames = spritesheet.animations[state_name]
        }
    }

    return results
}

load_monster_animations :: proc(spritesheet: SpriteSheet) -> SpriteAnimation {
    result: SpriteAnimation
    result = SpriteAnimation {
        current_frame = 0,
        frames = spritesheet.animations["Idle"]
    }


    return result
}


