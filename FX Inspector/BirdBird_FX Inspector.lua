-- @description FX Inspector
-- @version 0.5.3
-- @author BirdBird
-- @provides
--    [nomain]fx_inspector_libraries/functions.lua
--    [nomain]fx_inspector_libraries/json.lua

--@changelog
--  + Early version

function p(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end
function reaper_do_file(file) local info = debug.getinfo(1,'S'); path = info.source:match[[^@?(.*[\/])[^\/]-$]]; dofile(path .. file); end
reaper_do_file('fx_inspector_libraries/functions.lua')

--DEPENDENCIES
if not reaper.APIExists('CF_GetSWSVersion') then
    local text = 'FX Inspector requires the SWS Extension to run, however it is unable to find it. \nWould you like to be redirected to the SWS Extension website to install it?'
    local ret = reaper.ShowMessageBox(text, 'Missing Dependency', 4)
    if ret == 6 then
        open_url('https://www.sws-extension.org/')
    end
    return
end

if not reaper.APIExists('ImGui_GetVersion') then
    local text = 'FX Inspector requires the ReaImGui extension to run. You can install it through ReaPack.'
    local ret = reaper.ShowMessageBox(text, 'Missing Dependency', 0)
    return
end

--GUI
local ctx = reaper.ImGui_CreateContext('Preset Menu', reaper.ImGui_ConfigFlags_DockingEnable())
local size = reaper.GetAppVersion():match('OSX') and 12 or 14
local font = reaper.ImGui_CreateFont('courier-new', size)
local dock = nil
local window_resize_flag = reaper.ImGui_Cond_Appearing()

--SETTINGS
local settings = get_settings()
function settings_popup()
    reaper.ImGui_SetNextWindowSize(ctx, 186, 291, window_resize_flag)
    if reaper.ImGui_BeginPopupModal(ctx, 'Settings', nil) then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x12BD993A)
        local save = false
        r, settings.enable_preset_edits = reaper.ImGui_Checkbox(ctx, 'Enable preset edits',
        settings.enable_preset_edits)
        if r then 
            save = true
        end

        r, settings.show_random_button = reaper.ImGui_Checkbox(ctx, 'Show random button',
        settings.show_random_button)
        if r then 
            save = true
        end

        r, settings.show_parameter_capture = reaper.ImGui_Checkbox(ctx, 'Show parameter capture',
        settings.show_parameter_capture)
        if r then 
            save = true
        end

        r, settings.show_presets = reaper.ImGui_Checkbox(ctx, 'Show presets',
        settings.show_presets)
        if r then 
            save = true
        end

        if reaper.ImGui_Button(ctx, 'Close') then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        if save then
            save_settings(settings)
            settings = get_settings()
        end
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_EndPopup(ctx)
    end
end

--SIDECHAIN POPUP
local sidechain_dat = get_empty_sidechain()
function sidechain_popup(fx)
    reaper.ImGui_SetNextWindowSize(ctx, 339, 379, window_resize_flag)
    if reaper.ImGui_BeginPopupModal(ctx, 'Create Sidechain', nil) then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x4296FA4F)

        --FILTER
        if reaper.ImGui_IsWindowAppearing(ctx) then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
        end
        local r, s = reaper.ImGui_InputText(ctx, 'Filter', sidechain_dat.filter)
        if s then sidechain_dat.filter = s end
        local filter = reaper.ImGui_CreateTextFilter(sidechain_dat.filter)
        
        --TRACKLIST
        local w, h = reaper.ImGui_GetWindowSize(ctx);
        local y, r = reaper.ImGui_GetCursorPosY( ctx ), false
        if reaper.ImGui_BeginListBox(ctx, '##listbox_1', -1, 300) then --h - 29 - y) then
            local tracklist = get_tracklist()
            for i = 1, #sidechain_dat.tracklist do 
                local t = sidechain_dat.tracklist[i]
                reaper.ImGui_PushID(ctx, i)
                if reaper.ImGui_TextFilter_PassFilter(filter, t.name) and t.track ~= fx.track then
                    local ret, sel = reaper.ImGui_Selectable(ctx, t.id .. ' - ' .. t.name, t.selected)
                    if ret then 
                        t.selected = sel 
                        table.insert(sidechain_dat.selected_tracks, t)
                    end
                end
                reaper.ImGui_PopID(ctx)
            end
            reaper.ImGui_EndListBox(ctx)
        end
        
        --BOTTOM
        if reaper.ImGui_Button(ctx, 'Ok') then
            reaper.Undo_BeginBlock()
            create_sidechain(sidechain_dat.selected_tracks, fx)
            reaper.Undo_EndBlock('Create sidechain routing', -1)
            
            sidechain_dat = get_empty_sidechain()
            reaper.ImGui_CloseCurrentPopup(ctx)
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, 'Cancel') then
            sidechain_dat = get_empty_sidechain()
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_EndPopup(ctx)
    end
end

--EDIT POPUP
local edit_dat = {}
function edit_popup(pd, id)
    local ret, dat, id = false, nil, edit_dat.id
    reaper.ImGui_SetNextWindowSize(ctx, 260, 93, window_resize_flag)
    if reaper.ImGui_BeginPopupModal(ctx, 'Edit Preset', nil) then
        if reaper.ImGui_IsWindowAppearing(ctx) then
            local n = pd.presets[id].name
            edit_dat.name, edit_dat.default_name = n, n
            reaper.ImGui_SetKeyboardFocusHere(ctx)
        end
        local r, s = reaper.ImGui_InputText(ctx, 'Name', edit_dat.name)
        if r then edit_dat.name = s end
        
        local is_valid, err = validate_preset_name(pd, edit_dat.name)
        is_valid = is_valid or edit_dat.name == edit_dat.default_name
        if not is_valid then
            reaper.ImGui_Text(ctx, err)
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, 'Ok') then
            ret, dat = true, table.shallow_copy(edit_dat)
            edit_dat = {}
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if not is_valid then
            reaper.ImGui_EndDisabled(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, 'Cancel') then
            edit_dat = {}
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
    return ret, dat
end

function push_button_style(r,g,b,a)
    local c = rgba2num(r, g, b, a)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        c)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), c)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  c)
end

function automation_buttons(fx)
    --AUTOMATION, READ
    if fx.auto_mode == 0 then push_button_style(19, 189, 153, math.floor(255*0.3)) end
    if reaper.ImGui_Button(ctx, "R") then
        reaper.Undo_BeginBlock()
        reaper.SetTrackAutomationMode(fx.track, 0)
        reaper.Undo_EndBlock('Set track automation mode (Trim/Read)', -1)
    end
    if fx.auto_mode == 0 then reaper.ImGui_PopStyleColor(ctx, 3) end
    
    --TOUCH
    reaper.ImGui_SameLine(ctx)
    if fx.auto_mode == 2 then push_button_style(19, 189, 153, math.floor(255*0.3)) end
    if reaper.ImGui_Button(ctx, "T") then
        reaper.Undo_BeginBlock()
        reaper.SetTrackAutomationMode(fx.track, 2)
        reaper.Undo_EndBlock('Set track automation mode (Touch)', -1)
    end
    if fx.auto_mode == 2 then reaper.ImGui_PopStyleColor(ctx, 3) end
    
    --LATCH
    reaper.ImGui_SameLine(ctx)
    if fx.auto_mode == 4 then push_button_style(19, 189, 153, math.floor(255*0.3)) end
    if reaper.ImGui_Button(ctx, "L") then
        reaper.Undo_BeginBlock()
        reaper.SetTrackAutomationMode(fx.track, 4)
        reaper.Undo_EndBlock('Set track automation mode (Latch)', -1)
    end
    if fx.auto_mode == 4 then reaper.ImGui_PopStyleColor(ctx, 3) end
    
    --SIDECHAIN
    local retval, inputs, outputs = reaper.TrackFX_GetIOSize(fx.track, fx.id)
    if inputs > 2 or settings.show_random_button then
        reaper.ImGui_SameLine(ctx, 0, 9)
    end
    if inputs > 2 then
        if reaper.ImGui_Button(ctx, "SC") then
            sidechain_dat.tracklist = get_tracklist()
            reaper.ImGui_OpenPopup(ctx, "Create Sidechain")
        end
        if settings.show_random_button then
            reaper.ImGui_SameLine(ctx)
        end
    end
    
    --RANDOMIZE PARAMETERS
    if settings.show_random_button then
        if reaper.ImGui_Button(ctx, "RND") then
            reaper.Undo_BeginBlock()
            randomize_parameters(fx)
            reaper.Undo_EndBlock('Randomize plugin parameters', -1)
        end
    end
    reaper.ImGui_Separator(ctx)

    sidechain_popup(fx)
end

--Thank you cfillion!
function custom_close_button()
    local frame_padding_x, frame_padding_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
    local min_x, min_y = reaper.ImGui_GetWindowPos(ctx)
    min_x, min_y = min_x + frame_padding_x, min_y + frame_padding_y
    local max_x = min_x + reaper.ImGui_GetWindowSize(ctx) - frame_padding_x * 2
    local max_y = min_y + reaper.ImGui_GetFontSize(ctx)
    reaper.ImGui_PushClipRect(ctx, min_x, min_y, max_x, max_y, false)
    local pos_x, pos_y = reaper.ImGui_GetCursorPos(ctx)
    reaper.ImGui_SetCursorScreenPos(ctx, max_x - 14, min_y)
    if reaper.ImGui_SmallButton(ctx, 'x') then open = false end
    reaper.ImGui_SetCursorPos(ctx, pos_x, pos_y)
    reaper.ImGui_PopClipRect(ctx)
end

local l_dragging_envelope = false
function param_capture(fx, pd, param)
    local w, h = reaper.ImGui_GetWindowSize(ctx)
    local pd_x, pd_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
    if param then
        --RETROSPECTIVE PARAMETER CAPTURE
        reaper.ImGui_Text(ctx, param.par.name .. ': ' .. param.par.format_value)
        
        --DRAG BUTTON
        reaper.ImGui_SameLine(ctx, w - 2*pd_x - 10)
        if reaper.ImGui_SmallButton(ctx, '+') then
            --CREATE ENVELOPE
            local key_mods = reaper.ImGui_GetKeyMods(ctx)
            local ctrl = reaper.ImGui_KeyModFlags_Ctrl()
            if key_mods & ctrl > 0 then
                local par = param.par
                local env = toggle_fx_envelope_visibility(par.track, par.fx_id, par.id)
                local cur_pos =  reaper.GetCursorPosition()
                write_buffer_to_envelope(track, env, param, cur_pos)                
            else
                local par = param.par
                reaper.Undo_BeginBlock()
                toggle_fx_envelope_visibility(par.track, par.fx_id, par.id)        
                reaper.Undo_EndBlock('Show FX envelope', -1)
            end
        end

        --AUTOMATION
        if reaper.ImGui_BeginPopupContextItem(ctx) then
            if reaper.ImGui_MenuItem(ctx, 'Insert') then
                local par = param.par
                local env = toggle_fx_envelope_visibility(par.track, par.fx_id, par.id)
                local cur_pos =  reaper.GetCursorPosition()
                write_buffer_to_envelope(track, env, param, cur_pos)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        --MOUSE DRAG AND DROP
        local dragging_envelope = false
        if reaper.ImGui_BeginDragDropSource(ctx) then
            local window, segment, details = reaper.BR_GetMouseCursorContext()
            local pos = reaper.BR_GetMouseCursorContext_Position()
            
            --SNAP
            local key_mods = reaper.ImGui_GetKeyMods(ctx)
            local shift = reaper.ImGui_KeyModFlags_Shift()
            if not (key_mods & shift > 0) then
                pos = reaper.SnapToGrid(0, pos)
            end
            reaper.SetEditCurPos(pos, false, false)
            
            --DISPLAY
            local name = get_hovered_envelope_name()
            if name then
                reaper.ImGui_Text(ctx, name)
            else
                reaper.ImGui_Text(ctx, 'x')
            end
            dragging_envelope = true
            reaper.ImGui_EndDragDropSource(ctx)
        else
            if l_dragging_envelope then
                local x, y = reaper.GetMousePosition()
                local track, info = reaper.GetThingFromPoint(x, y)
                if info:match("envelope") then
                    local envidx = tonumber(info:match("%d+"))
                    local env = reaper.GetTrackEnvelope(track, envidx)
                    local cur_pos =  reaper.GetCursorPosition()
                    write_buffer_to_envelope(track, env, param, cur_pos)
                end
            end
            dragging_envelope = false
        end
        l_dragging_envelope = dragging_envelope
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),   0x1818188A)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), 0xBD1378FF)
        reaper.ImGui_PlotLines(ctx, '##Plot', reaper.new_array(param.values), 
        param.writer - 1, nil, 0.0, 1.0, w - 2*pd_x, 40.0)
        reaper.ImGui_PopStyleColor(ctx, 2)
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x6C6C6CFF)
        reaper.ImGui_Text(ctx, ': :')
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),   0x1818188A)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), 0xBD1378FF)
        reaper.ImGui_PlotLines(ctx, '##Plot', reaper.new_array({}), 
        0, nil, 0.0, 1.0, w - 2*pd_x, 40.0)
        reaper.ImGui_PopStyleColor(ctx, 2) 
    end
end

function preset_display(fx, pd, param)
    local reload = false
    local save = false
    local edit_menu, edit_id = false, i
    --PRESETS
    if pd and pd.presets and #pd.presets > 0 then
        local pending_removal = {}
        local pending_duplicate = {}
        
        if reaper.ImGui_CollapsingHeader(ctx, 'Presets', nil, reaper.ImGui_TreeNodeFlags_None()) then
            if reaper.ImGui_IsItemToggledOpen(ctx) then
                reaper.ImGui_SetKeyboardFocusHere(ctx)
            end
            local r, s = reaper.ImGui_InputText(ctx, 'Filter', preset_filter)
            if s then preset_filter = s end
            local filter = reaper.ImGui_CreateTextFilter(preset_filter)
            
            local w, h = reaper.ImGui_GetWindowSize(ctx);
            local y, r = reaper.ImGui_GetCursorPosY(ctx), false
            if reaper.ImGui_BeginListBox(ctx, '##listbox_2', -1, h - y - 10) then
                for i = 1, #pd.presets do
                    local preset = pd.presets[i]
                    reaper.ImGui_PushID(ctx, i)
                    
                    --SELECTABLES
                    if reaper.ImGui_TextFilter_PassFilter(filter, preset.name) then
                        local r, p_selected = reaper.ImGui_Selectable(ctx, preset.name, false)
                        if p_selected and fx.valid then
                            reaper.TrackFX_SetPreset(fx.track, fx.id, preset.name)
                        end
                        
                        if settings.enable_preset_edits then
                            --RIGHT CLICK CONTEXT MENU
                            if reaper.ImGui_BeginPopupContextItem(ctx) then
                                if reaper.ImGui_MenuItem(ctx, 'Rename') then
                                    edit_menu = true
                                    edit_id = i
                                end
                                --if reaper.ImGui_MenuItem(ctx, 'Duplicate') then
                                --    table.insert(pending_duplicate, i)
                                --end
                                if reaper.ImGui_MenuItem(ctx, 'Delete') then
                                    table.insert(pending_removal, i)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                    end
                    
                    reaper.ImGui_PopID(ctx)
                end
                reaper.ImGui_EndListBox(ctx)
            end

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), 0x77777762)
            reaper.ImGui_PopStyleColor(ctx)

            --REMOVE
            for i = 1, #pending_removal do
                table.remove(pd.presets, pending_removal[i])
                save = true
                reload = true
            end

            --DUPLICATE
            for i = 1, #pending_duplicate do
                local id = pending_duplicate[i]
                local preset = pd.presets[id]
                local preset_c = deepcopy(preset)
                preset_c.name = preset.name .. '-1'
                table.insert(pd.presets, id + 1, preset_c)
                save = true
                reload = true
            end

            --EDIT MODAL
            if edit_menu then 
                reaper.ImGui_OpenPopup(ctx, 'Edit Preset')
                edit_dat.id = edit_id
                edit_menu = false
            end
            local ret, dat = edit_popup(pd)
            if ret then
                pd.presets[dat.id].name = dat.name
                save = true
                reload = true
            end
        end
    else
        reaper.ImGui_Text(ctx, 'No presets to show.')
    end
    return reload, save
end

--MAIN GUI
reaper.ImGui_AttachFont(ctx, font)
local preset_filter = ''
function frame(fx, pd, param)
    local reload = false
    local save = false
    if fx.valid then
        --AUTOMATION
        automation_buttons(fx)
        if settings.show_parameter_capture then
            param_capture(fx, pd, param)
        end
        if settings.show_presets then
            reload, save = preset_display(fx, pd, param)
        end
    else
        reaper.ImGui_Text(ctx, 'No effects focused.')
    end
    return reload, save
end

function push_theme()
    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(),     8, 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),       3, 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),          0x2A2A2AF0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),           0x2A2A2AF0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),            0xFFFFFF80)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),           0x4242428A)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(),           0x181818FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(),     0x181818FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),            0x1C1C1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),     0x2C2C2CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),      0x3D3D3DFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),     0x12BD994B)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),      0x12BD999E)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(),         0xFFFFFF81)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(),        0x12BD9933)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), 0x12BD99AB)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(),  0x12BD99F2)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(),    0x70C4C659)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),            0x12BD9914)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),         0x12BD99FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(),          0x0D0D0D87)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(),        0xFFFFFF1C)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), 0xFFFFFF2E)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(),  0xFFFFFF32)    
end

function pop_theme()
    reaper.ImGui_PopStyleVar(ctx, 4)
    reaper.ImGui_PopStyleColor(ctx, 18)
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopFont(ctx)
end

local show_style_editor = false
if show_style_editor then 
    demo = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/ReaImGui_Demo.lua')
end

local l_fx
local l_par = get_last_touched_parameter()
local current_parameter = get_new_retro_parameter(l_par)
local focused_presets
local open_settings = false
function loop()
    local reload = false
    local save = false
    
    --TRACK FOCUSED FX
    local fx = get_focused_fx()
    local par = get_last_touched_parameter()
    if ((not l_fx or l_fx.name ~= fx.name) or l_fx.track ~= fx.track) and fx.valid then
        --FOCUS CHANGE
        local preset_path = reaper.TrackFX_GetUserPresetFilename(fx.track, fx.id)
        focused_presets = parse_ini_file(preset_path)
        current_parameter = nil
        preset_filter = ''
    elseif l_fx and l_fx.num_presets ~= fx.num_presets then
        --PRESET UPDATE
        reload = true
    end
    l_fx = table.shallow_copy(fx)
    
    --LAST TOUCHED PARAMETER
    if par.valid and par.track == fx.track and par.fx_id == fx.id then
        if l_par.name ~= par.name or current_parameter == nil then
            current_parameter = get_new_retro_parameter(par)
        else
            --UPDATE VALUES
            if current_parameter then
                current_parameter.par = par
            end
        end
    end
    l_par = table.shallow_copy(par)

    --AUTOMATION CIRCULAR BUFFER
    if par.valid and not l_dragging_envelope and current_parameter then
        write_parameter_value(current_parameter)
    end
    
    --GUI
    push_theme()
    if show_style_editor then
        demo.PushStyle(ctx)
        demo.ShowDemoWindow(ctx)
    end
    
    if dock then 
        reaper.ImGui_SetNextWindowDockID(ctx, dock)
        dock = nil 
    end
    reaper.ImGui_SetNextWindowSize(ctx, 191, 560, reaper.ImGui_Cond_FirstUseEver())
    visible, open = reaper.ImGui_Begin(ctx, 'FX Inspector', false, reaper.ImGui_WindowFlags_NoCollapse())
    local window_is_docked = reaper.ImGui_IsWindowDocked(ctx)

    custom_close_button()
    --RIGHT CLICK CONTEXT
    if reaper.ImGui_BeginPopupContextItem(ctx) then
        if reaper.ImGui_MenuItem(ctx, 'Settings') then
            open_settings = true
        end
        if reaper.ImGui_MenuItem(ctx, window_is_docked and 'Undock' or 'Dock') then
            if window_is_docked then
                dock = 0
            else
                dock = -3
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
    
    --MAIN WINDOW
    if visible then
        if open_settings then 
            reaper.ImGui_OpenPopup(ctx, 'Settings')
            open_settings = false
        end
        local r, s = frame(fx, focused_presets, current_parameter)
        settings_popup()
        reload = reload or r; save = save or s
        if save then generate_preset_ini(focused_presets) end
        if reload then l_fx = nil end
        reaper.ImGui_End(ctx)
    end
    
    if show_style_editor then
        demo.PopStyle(ctx)
    end
    pop_theme()
    
    if open then
        reaper.defer(loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end
reaper.defer(loop)