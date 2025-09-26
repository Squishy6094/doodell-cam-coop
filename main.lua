-- name: Doodell Cam

--[[
TODO:
- FOV Slider
- Freelook Respects Mouse
- Freelook Angle Based
- Verticle Angle Slider
]]

local STORAGE_CAMERA_TOGGLE = "cameraOn"
local STORAGE_CAMERA_ANALOG = "cameraAnalog"
local STORAGE_CAMERA_MOUSE = "cameraAnalog"
local STORAGE_CAMERA_PAN = "cameraPan"

local function tobool(v)
    if type(v) == "number" then
        return v > 0
    end
end

local function convert_s16(num)
    local min = -32768
    local max = 32767
    while (num < min) do
        num = max + (num - min)
    end
    while (num > max) do
        num = min + (num - max)
    end
    return num
end

local function lerp(a, b, t)
    return a * (1 - t) + b * t
end

local function approach_vec3f_asymptotic(current, target, multX, multY, multZ)
    local output = {x = 0, y = 0, z = 0}
    output.x = current.x + ((target.x - current.x)*multX)
    output.y = current.y + ((target.y - current.y)*multY)
    output.z = current.z + ((target.z - current.z)*multZ)
    return output
end

local function round(num)
    return num < 0.5 and math.floor(num) or math.ceil(num)
end

local function clamp(num, min, max)
    return math.min(math.max(num, min), max)
end

local function clamp_soft(num, min, max, rate)
    if num < min then
        num = num + rate
        num = math.min(num, max)
    elseif num > max then
        num = num - rate
        num = math.max(num, min)
    end
    return num
end

local sOverrideCameraModes = {
    [CAMERA_MODE_BEHIND_MARIO]      = true,
    [CAMERA_MODE_WATER_SURFACE]     = true,
    [CAMERA_MODE_RADIAL]            = true,
    [CAMERA_MODE_OUTWARD_RADIAL]    = true,
    [CAMERA_MODE_CLOSE]             = true,
    [CAMERA_MODE_SLIDE_HOOT]        = true,
    [CAMERA_MODE_PARALLEL_TRACKING] = true,
    [CAMERA_MODE_FIXED]             = true,
    [CAMERA_MODE_FREE_ROAM]         = true,
    [CAMERA_MODE_SPIRAL_STAIRS]     = true,
    [CAMERA_MODE_ROM_HACK]          = true,
    [CAMERA_MODE_8_DIRECTIONS]      = true,
    [CAMERA_MODE_BOSS_FIGHT]        = true,
}

local function button_to_analog(m, negInput, posInput)
    local num = 0
    num = num - (m.controller.buttonDown & negInput ~= 0 and 127 or 0)
    num = num + (m.controller.buttonDown & posInput ~= 0 and 127 or 0)
    return num
end

local function omm_camera_enabled()
    if not _G.OmmEnabled then return false end
    return _G.OmmApi.omm_get_setting(gMarioStates[0], OMM_SETTING_CAMERA) == OMM_SETTING_CAMERA_ON
end

local camToggle = mod_storage_load_bool(STORAGE_CAMERA_TOGGLE)
local function doodell_cam_enabled()
    return camToggle
end

function doodell_cam_active()
    local m = gMarioStates[0]
    return doodell_cam_enabled() and
    not camera_is_frozen() and
    not camera_config_is_free_cam_enabled() and
    not omm_camera_enabled() and
    m.area.camera ~= nil and
    m.statusForCamera.cameraEvent ~= CAM_EVENT_DOOR and
    m.action ~= ACT_STAR_DANCE_EXIT
end

local eepyActs = {
    [ACT_SLEEPING] = true,
}

local camAnalog = mod_storage_load_bool(STORAGE_CAMERA_ANALOG)
local camMouse = mod_storage_load_bool(STORAGE_CAMERA_MOUSE)
local camAngleRaw = 0
local camAngle = 0
local camAngleInput = 0 
local camScale = 3
local camPitch = 0
local camPan = 0
local camTweenSpeed = 0.6
local camForwardDist = mod_storage_load_number(STORAGE_CAMERA_PAN)/100*3
local camPanSpeed = 25
local rawFocusPos = {x = 0, y = 0, z = 0}
local rawCamPos = {x = 0, y = 0, z = 0}
local focusPos = {x = 0, y = 0, z = 0}
local camPos = {x = 0, y = 0, z = 0}
local camFov = 50
local camSwitchHeld = 0

local doodellState = 0
local doodellTimer = 1
local doodellBlink = false
local eepyTimer = 0
local eepyStart = 390
local eepyCamOffset = 0
local prevPos = {x = 0, y = 0, z = 0}
local prevPosVel = {x = 0, y = 0, z = 0}

local camSpawnAngles = {
    [LEVEL_BITDW] = 0x4000,
    [LEVEL_BITFS] = 0x4000,
    [LEVEL_BITS] = 0x4000,
    [LEVEL_WF] = 0x4000,
    [LEVEL_TTM] = 0x6000,
    [LEVEL_CCM] = -0x6000,
    [LEVEL_WDW] = 0x4000,
    [LEVEL_LLL] = 0x4000,
    [LEVEL_SSL] = 0x4000,
    [LEVEL_RR] = 0x4000,
}

local function doodell_cam_snap(levelInit)
    if levelInit ~= false then levelInit = true end
    local m = gMarioStates[0]
    local l = gLakituState
    local levelNum = gNetworkPlayers[0].currLevelNum
    local c = m.area.camera
    if levelInit then
        camAngleRaw = round(gMarioStates[0].faceAngle.y/0x2000)*0x2000 - 0x8000 + (camSpawnAngles[levelNum] ~= nil and camSpawnAngles[levelNum] or 0)
        camAngle = camAngleRaw
        camScale = 3
        camPitch = 0
    end
    rawFocusPos = {
        x = m.pos.x,
        y = m.pos.y + 150,
        z = m.pos.z,
    }
    rawCamPos = {
        x = m.pos.x + sins(camAngleRaw) * 500 * camScale,
        y = m.pos.y - 150 + 350 * camScale - eepyCamOffset,
        z = m.pos.z + coss(camAngleRaw) * 500 * camScale,
    }
    vec3f_copy(camPos, rawCamPos)
    vec3f_copy(focusPos, rawFocusPos)
    vec3f_copy(c.pos, camPos)
    vec3f_copy(l.pos, camPos)
    vec3f_copy(l.goalPos, camPos)

    vec3f_copy(c.focus, focusPos)
    vec3f_copy(l.focus, focusPos)
    vec3f_copy(l.goalFocus, focusPos)

    vec3f_copy(prevPos, m.pos)

    camera_set_use_course_specific_settings(0)
end

local mousePullX = 0
local mousePullY = 0
local mousePullMax = 500
local function camera_update()
    local m = gMarioStates[0]
    local l = gLakituState
    local c = m.area.camera
    if c == nil then return end

    -- If turned off, restore camera mode
    local mode = l.mode
    if not doodell_cam_active() then
        if mode == CAMERA_MODE_NONE then
            set_camera_mode(c, CAMERA_MODE_OUTWARD_RADIAL, 0)
            l.roll = 0
            l.keyDanceRoll = 0
            camFov = 50
            set_override_fov(0)
            soft_reset_camera(m.area.camera)
        end
        return
    end

    -- Disable Lakitu
    if sOverrideCameraModes[mode] ~= nil or m.action == ACT_SHOT_FROM_CANNON then
        l.mode = CAMERA_MODE_NONE
    end

    if c.cutscene == 0 and l.mode == CAMERA_MODE_NONE then
        doodellState = doodellBlink and 1 or 0
        --camera_freeze()
        local controller = m.controller
        local camSwitch = (controller.buttonDown & R_TRIG ~= 0)
        if not (is_game_paused() or eepyTimer > eepyStart) then
            if camSwitch then
                camSwitchHeld = camSwitchHeld + 1
            end

            local invertXMultiply = camera_config_is_x_inverted() and -1 or 1
            local invertYMultiply = camera_config_is_y_inverted() and -1 or 1

            local camDigitalLeft  = camAnalog and (_G.OmmEnabled and 0 or L_JPAD) or L_CBUTTONS
            local camDigitalRight = camAnalog and (_G.OmmEnabled and 0 or R_JPAD) or R_CBUTTONS
            local camDigitalUp    = camAnalog and (_G.OmmEnabled and 0 or U_JPAD) or U_CBUTTONS
            local camDigitalDown  = camAnalog and (_G.OmmEnabled and 0 or D_JPAD) or D_CBUTTONS

            local camAnalogX = camAnalog and controller.extStickX or (_G.OmmEnabled and 0 or button_to_analog(m, L_JPAD, R_JPAD))
            local camAnalogY = camAnalog and controller.extStickY or (_G.OmmEnabled and 0 or button_to_analog(m, D_JPAD, U_JPAD))
            

            local mouseCamXDigital = 0
            local mouseCamYDigital = 0
            local rawMouseX = djui_hud_get_raw_mouse_x()
            local rawMouseY = djui_hud_get_raw_mouse_y()
            if camMouse then
                djui_hud_set_mouse_locked(true)
                mousePullX = clamp(clamp_soft(mousePullX + rawMouseX, 0, 0, 15), -mousePullMax*1.1, mousePullMax*1.1)
                mousePullY = clamp(clamp_soft(mousePullY + rawMouseY, 0, 0, 15), -mousePullMax*1.1, mousePullMax*1.1)
                if not (camAnalog or camSwitch) then
                    if mousePullX > mousePullMax then
                        mouseCamXDigital = 1
                        mousePullX = 0
                    end
                    if mousePullX < -mousePullMax then
                        mouseCamXDigital = -1
                        mousePullX = 0
                    end
                    if mousePullY > mousePullMax then
                        mouseCamYDigital = 1
                        mousePullY = 0
                    end
                    if mousePullY < -mousePullMax then
                        mouseCamYDigital = -1
                        mousePullY = 0
                    end
                else
                    camAnalogX = rawMouseX*camera_config_get_x_sensitivity()*0.03
                    camAnalogY = -rawMouseY*camera_config_get_y_sensitivity()*0.04
                end
            else
                djui_hud_set_mouse_locked(false)
            end

            if not camSwitch then
                if math.abs(camAnalogX) > 10 then
                    camAngleRaw = camAngleRaw + camAnalogX*10*invertXMultiply
                end
                if math.abs(camAnalogY) > 10 then
                    camScale = clamp(camScale - camAnalogY*0.001, 1, 7)
                end

                if controller.buttonPressed & camDigitalLeft ~= 0 or mouseCamXDigital < 0 then
                    camAngleRaw = camAngleRaw - 0x2000*invertXMultiply
                end
                if controller.buttonPressed & camDigitalRight ~= 0 or mouseCamXDigital > 0 then
                    camAngleRaw = camAngleRaw + 0x2000*invertXMultiply
                end
                if controller.buttonPressed & camDigitalDown ~= 0 or mouseCamYDigital > 0 then
                    camScale = camScale + 1
                end
                if controller.buttonPressed & camDigitalUp ~= 0 or mouseCamYDigital < 0 then
                    camScale = camScale - 1
                end
                camScale = clamp(camScale, 1, 7)
                camPitch = 0
                camPan = 0
            else
                if controller.buttonDown & L_CBUTTONS ~= 0 then
                    camPan = camPan - camPanSpeed*camScale
                end
                if controller.buttonDown & R_CBUTTONS ~= 0 then
                    camPan = camPan + camPanSpeed*camScale
                end
                if controller.buttonDown & D_CBUTTONS ~= 0 then
                    camPitch = camPitch - camPanSpeed*camScale
                end
                if controller.buttonDown & U_CBUTTONS ~= 0 then
                    camPitch = camPitch + camPanSpeed*camScale
                end
            end

            if m.controller.buttonReleased & R_TRIG ~= 0 then
                if camSwitchHeld < 5 then
                    if camAnalog then
                        camAngleRaw = m.faceAngle.y + 0x8000
                    else
                        camAngleRaw = round((m.faceAngle.y + 0x8000)/0x2000)*0x2000
                    end
                end
                camSwitchHeld = 0
            end
        end

        local posVelDist = vec3f_dist(prevPos, m.pos)
        if posVelDist > 500 then
            doodell_cam_snap(false)
        end
        local posVel = {
            x = lerp(prevPosVel.x, m.pos.x - prevPos.x, 0.3),
            y = lerp(prevPosVel.y, m.pos.y - prevPos.y, 0.3),
            z = lerp(prevPosVel.z, m.pos.z - prevPos.z, 0.3),
        }
        prevPosVel = {
            x = posVel.x,
            y = posVel.y,
            z = posVel.z,
        }

        local angle = camAngleRaw
        local roll = ((sins(atan2s(posVel.z, posVel.x) - camAngleRaw)*m.forwardVel/150)*0x800)
        if not camSwitch then
            if m.action == ACT_FLYING then
                angle = m.faceAngle.y - 0x8000
                if m.controller.buttonDown & L_CBUTTONS ~= 0 then
                    angle = angle - 0x2000
                end
                if m.controller.buttonDown & R_CBUTTONS ~= 0 then
                    angle = angle + 0x2000
                end
                camAngleRaw = round(angle/0x2000)*0x2000

                if m.action & ACT_FLAG_FLYING ~= 0 then
                    roll = m.faceAngle.z*0.1
                end
            end
        end

        local camPanX = sins(convert_s16(camAngleRaw + 0x4000))*camPan
        local camPanZ = coss(convert_s16(camAngleRaw + 0x4000))*camPan

        focusPos = approach_vec3f_asymptotic(l.focus, rawFocusPos, camTweenSpeed, camTweenSpeed, camTweenSpeed)
        camPos = approach_vec3f_asymptotic(l.pos, rawCamPos, camTweenSpeed, camTweenSpeed*0.5, camTweenSpeed)
        vec3f_copy(c.pos, camPos)
        vec3f_copy(l.pos, camPos)
        vec3f_copy(l.goalPos, camPos)

        vec3f_copy(c.focus, focusPos)
        vec3f_copy(l.focus, focusPos)
        vec3f_copy(l.goalFocus, focusPos)

        local distFromFloor = m.pos.y - m.floorHeight
        distFromFloor = (distFromFloor < 1000 and m.action & ACT_FLAG_SWIMMING_OR_FLYING == 0) and distFromFloor or 0

        rawFocusPos = {
            x = m.pos.x + camPanX + posVel.x*camForwardDist*camScale,
            y = m.pos.y + camPitch - distFromFloor*0.3 + 100 + 100*camScale*0.5 or 0 - eepyCamOffset,
            z = m.pos.z + camPanZ + posVel.z*camForwardDist*camScale,
        }
        rawCamPos = {
            x = m.pos.x + posVel.x*camForwardDist*camScale + sins(angle) * 500 * camScale,
            y = m.pos.y - distFromFloor*0.35 - 150 + 350*((m.action & ACT_FLAG_HANGING == 0) and 1 or -0.5) * camScale - eepyCamOffset,
            z = m.pos.z + posVel.z*camForwardDist*camScale + coss(angle) * 500 * camScale,
        }
        
        if camPitch >= 600*((camScale + 1)/3.5) and
            m.floor and m.floor.type == SURFACE_LOOK_UP_WARP and
            save_file_get_total_star_count(get_current_save_file_num() - 1, COURSE_MIN - 1, COURSE_MAX - 1) >= gLevelValues.wingCapLookUpReq and
            not is_game_paused() then

            level_trigger_warp(m, WARP_OP_LOOK_UP)
        end

        -- Doodell is eepy
        if eepyActs[m.action] then
            doodellState = 4
            eepyTimer = eepyTimer + 1
            local camFloor = collision_find_surface_on_ray(rawCamPos.x, rawCamPos.y + eepyCamOffset, rawCamPos.z, 0, -10000, 0).hitPos.y
            if eepyTimer > eepyStart then
                doodellState = 5
                if rawCamPos.y > (camFloor + 150) then
                    eepyCamOffset = eepyCamOffset + (math.sin(eepyTimer*0.1) + 1)*2
                end
            end
        else
            eepyCamOffset = eepyCamOffset * 0.9
            eepyTimer = 0
        end
        
        -- Set Other Cam shitt
        l.roll = math.floor(lerp(l.roll, roll, 0.1))
        l.keyDanceRoll = l.roll -- Required for applying rotation because sm64 is fuckin stupid
        camFov = lerp(camFov, 50 + math.abs(m.forwardVel)*0.1, 0.1)
        set_override_fov(camFov)

        if l.roll < -1000 then
            doodellState = 2
        end
        if l.roll > 1000 then
            doodellState = 3
        end
        vec3f_copy(prevPos, m.pos)
    end
    
    camAngle = atan2s(l.pos.z - l.focus.z, l.pos.x - l.focus.x)
    if camAnalog then
        camAngleInput = atan2s(rawCamPos.z - rawFocusPos.z, rawCamPos.x - rawFocusPos.x)
    else
        camAngleInput = atan2s(camPos.z - focusPos.z, camPos.x - focusPos.x)
    end
end

local TEX_DOODELL_CAM = get_texture_info("squishy-doodell-cam")
local MATH_DIVIDE_SHAKE = 1/1000

local doodellScale = 0
local function hud_render()
    if hud_is_hidden() then return end
    local m = gMarioStates[0]
    local l = gLakituState
    djui_hud_set_resolution(RESOLUTION_N64)
    local width = djui_hud_get_screen_width()
    local height = 240

    if doodell_cam_active() then
        doodellTimer = (doodellTimer + 1)%20
        local animFrame = math.floor(doodellTimer*0.1)

        if doodellTimer == 0 then
            doodellBlink = math.random(1, 10) == 1
        end

        doodellScale = lerp(doodellScale, (math.abs(camScale-8)/8)*0.2 + 0.4, 0.1)
        local shakeX = math.random(-1, 1)*math.max(math.abs(l.roll)-1000, 0)*MATH_DIVIDE_SHAKE
        local shakeY = math.random(-1, 1)*math.max(math.abs(l.roll)-1000, 0)*MATH_DIVIDE_SHAKE

        local x = width - 38 - 64*doodellScale + shakeX + (mousePullX/mousePullMax * 4)
        local y = height - 38 - 64*doodellScale + eepyCamOffset*0.1*doodellScale + shakeY + (mousePullY/mousePullMax * 4)
        djui_hud_set_color(255, 255, 255, 255)
        hud_set_value(HUD_DISPLAY_FLAG_CAMERA, 0)
        djui_hud_set_rotation(l.roll, 0.5, 0.8)
        djui_hud_render_texture_tile(TEX_DOODELL_CAM, x, y, doodellScale, doodellScale, animFrame*128, doodellState*128, 128, 128)
        djui_hud_set_rotation(0, 0, 0)
    else
        hud_set_value(HUD_DISPLAY_FLAG_CAMERA, 1)
    end
end

---@param m MarioState
local function input_update(m)
    if m.playerIndex ~= 0 then return end
    if doodell_cam_active() and m.action ~= ACT_FLYING and gLakituState.mode == CAMERA_MODE_NONE then
        local intAngle = m.intendedYaw - camAngleInput
        if (intAngle > 0x3000 and intAngle < 0x5000) or (intAngle > -0x3000 and intAngle < -0x5000) then
            camAngle = camAngleRaw
        end
        if not camAnalog then
            camAngle = (camAngle/0x1000)*0x1000
        else
            local turnRate = camera_config_get_aggression()*m.forwardVel*0.3
            camAngleRaw = (m.faceAngle.y + 0x8000) - approach_s32(convert_s16((m.faceAngle.y + 0x8000) - camAngleRaw), 0, turnRate, turnRate)
        end
        m.area.camera.yaw = camAngle
        m.intendedYaw = atan2s(-m.controller.stickY, m.controller.stickX) + camAngleInput
    end
end

local function on_level_init()
    if not doodell_cam_active() then return end
    timerPerLevel = 0
    doodell_cam_snap(true)
end

local function set_camera_mode(_, mode, _)
    if mode == CAMERA_MODE_NONE or camera_config_is_free_cam_enabled() or not doodell_cam_enabled() then
        return true
    end
    if sOverrideCameraModes[mode] ~= nil or gMarioStates[0].action == ACT_SHOT_FROM_CANNON then
        gLakituState.mode = CAMERA_MODE_NONE
        return false
    end
end

local function change_camera_angle(angle)
    if angle == CAM_ANGLE_MARIO and not camera_config_is_free_cam_enabled() and doodell_cam_enabled() then
        return false
    end
end

hook_event(HOOK_ON_HUD_RENDER_BEHIND, hud_render)
hook_event(HOOK_BEFORE_MARIO_UPDATE, input_update)
hook_event(HOOK_UPDATE, camera_update)
hook_event(HOOK_ON_LEVEL_INIT, on_level_init)
hook_event(HOOK_ON_SET_CAMERA_MODE, set_camera_mode)
hook_event(HOOK_ON_CHANGE_CAMERA_ANGLE, change_camera_angle)

local function menu_cam_toggle(index, value)
    camToggle = value
    mod_storage_save_bool(STORAGE_CAMERA_TOGGLE, value)
end

local function menu_cam_analog(index, value)
    camAnalog = value
    mod_storage_save_bool(STORAGE_CAMERA_ANALOG, value)
end

local function menu_cam_mouse(index, value)
    camMouse = value
    mod_storage_save_bool(STORAGE_CAMERA_MOUSE, value)
end

local function menu_cam_pan_level(index, value)
    camForwardDist = value/100*3
    mod_storage_save_number(STORAGE_CAMERA_PAN, value)
end
hook_mod_menu_text("Camera made by Squishy6094")
hook_mod_menu_checkbox("Toggle Camera", mod_storage_load_bool(STORAGE_CAMERA_TOGGLE), menu_cam_toggle)
hook_mod_menu_text("(Requires Freecam to be Disabled)")
hook_mod_menu_checkbox("Analog Cam", mod_storage_load_bool(STORAGE_CAMERA_ANALOG), menu_cam_analog)
hook_mod_menu_checkbox("Mouse Cam", mod_storage_load_bool(STORAGE_CAMERA_MOUSE), menu_cam_mouse)
hook_mod_menu_slider("Pan Level", mod_storage_load_number(STORAGE_CAMERA_PAN) ~= 0 and mod_storage_load_number(STORAGE_CAMERA_PAN) or 0 , 1, 100, menu_cam_pan_level)