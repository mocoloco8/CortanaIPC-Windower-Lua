local texts  = require('texts');
local images = require('images');

local DLG_PATH = windower.addon_path .. 'dialog.png';
local dlg_ok, dlg_found = pcall(windower.file_exists, DLG_PATH);
local have_dialog = (dlg_ok and dlg_found) and true or false;
local function make_panel()
    if (not have_dialog) then return nil; end
    local ok, img = pcall(images.new, {
        color   = { alpha = 255, red = 255, green = 255, blue = 255 },
        texture = { path = DLG_PATH, fit = false },
        draggable = false,
    });
    if (not ok or img == nil) then return nil; end
    img:visible(false);
    return img;
end
local hud_panel  = make_panel();
local verb_panel = make_panel();

local function panel_under(img, box, k, pw, ph, ix, iy)
    if (img == nil) then return false; end
    local ok = pcall(function()
        local x, y = box:pos();
        img:pos(x - ix, y - iy);
        img:size(pw, ph);
        img:alpha(math.floor(255 * k));
        img:visible(true);
    end);
    return ok;
end

local HUD_HOLD = 4.0;
local HUD_FADE = 1.5;
local TXT_A    = 255;
local BG_A     = 190;

local VERB_HOLD  = 6.0;
local VERB_FADE  = 1.5;
local VERB_TXT_A = 255;
local VERB_BG_A  = 210;
local verb_shownat = -100;

local verb_box = texts.new('', {
    pos     = { x = 62, y = 58 },
    text    = { font = 'Arial', size = 16, alpha = VERB_TXT_A, red = 255, green = 230, blue = 90,
                stroke = { width = 2, alpha = 255, red = 0, green = 0, blue = 0 } },
    bg      = { alpha = VERB_BG_A, red = 30, green = 24, blue = 4 },
    padding = 8,
    flags   = { draggable = false, bold = true },
});

local function word_wrap(text, maxlen)
    local out = {};
    for line in (text .. '\n'):gmatch('(.-)\n') do
        local cur = '';
        for word in line:gmatch('%S+') do
            if (cur == '') then cur = word;
            elseif (#cur + 1 + #word <= maxlen) then cur = cur .. ' ' .. word;
            else out[#out + 1] = cur; cur = word; end
        end
        out[#out + 1] = cur;
    end
    while (#out > 0 and out[#out] == '') do out[#out] = nil; end
    return table.concat(out, '\n');
end

function hud_verbose(text)
    verb_box:text(word_wrap(text:gsub('~', '\n'), 38));
    verb_shownat = os.clock();
end

local hud_show  = false;
local hud_pin   = false;
local hud_drag  = false;
local hud_last  = 0;
local hud_key   = '';
local hud_shownat = -100;

local SLIDE_SECS = 0.45;
local hud_home_x,  hud_sliding  = 0, false;
local verb_home_x, verb_sliding = 0, false;

local function slide_x(home_x, panel_w, t)
    local e = t * t;
    local screen_w = 1920;
    pcall(function()
        local ws = windower.get_windower_settings();
        local w = ws and (ws.ui_x_res or ws.x_res);
        if (w ~= nil and w > 0) then screen_w = w; end
    end);
    local target;
    if (home_x + panel_w / 2 < screen_w / 2) then target = -(panel_w + 80);
    else target = screen_w + 80; end
    return math.floor(home_x + (target - home_x) * e);
end

local hud_box = texts.new('', {
    pos     = { x = 20, y = 220 },
    text    = { font = 'Consolas', size = 10, alpha = TXT_A, red = 150, green = 220, blue = 255,
                stroke = { width = 1, alpha = 200, red = 0, green = 0, blue = 0 } },
    bg      = { alpha = BG_A, red = 12, green = 18, blue = 44 },
    padding = 6,
    flags   = { draggable = false, bold = false },
});

local function make_title(size)
    local ok, t = pcall(texts.new, 'CortanaXI', {
        pos     = { x = 0, y = 0 },
        text    = { font = 'Arial', size = size, alpha = 255, red = 255, green = 228, blue = 160,
                    stroke = { width = 1, alpha = 200, red = 0, green = 0, blue = 0 } },
        bg      = { alpha = 0 },
        padding = 0,
        flags   = { draggable = false, bold = true },
    });
    if (not ok or t == nil) then return nil; end
    t:visible(false);
    return t;
end
local verb_title = make_title(12);
local hud_title  = make_title(10);

local function title_under(tbox, box, ix, iy, ox, oy, alpha, show)
    if (tbox == nil) then return; end
    if (not show or not have_dialog) then pcall(function() tbox:visible(false); end); return; end
    pcall(function()
        local x, y = box:pos();
        tbox:pos(x - ix + ox, y - iy + oy);
        tbox:alpha(alpha);
        tbox:visible(true);
    end);
end

function hud_command(action)
    if (action == 'pin') then
        hud_pin = not hud_pin;
        windower.add_to_chat(207, '[cortana] HUD pinned: ' .. tostring(hud_pin) .. (hud_pin and ' (always visible)' or ' (notification mode: shows on change, then fades)'));
    elseif (action == 'drag' or action == 'move' or action == 'unlock') then
        hud_drag = not hud_drag;
        pcall(function() hud_box:draggable(hud_drag); end);
        pcall(function() verb_box:draggable(hud_drag); end);
        if (hud_drag) then hud_verbose('VERBOSE BANNER — drag me'); end
        windower.add_to_chat(207, '[cortana] HUD drag mode: ' .. tostring(hud_drag) .. (hud_drag and ' — drag it into place, then //cortana hud drag again to lock' or ' (locked, click-through)'));
    elseif (action == 'on') then
        hud_show = true;  windower.add_to_chat(207, '[cortana] HUD on');
    elseif (action == 'off') then
        hud_show = false; windower.add_to_chat(207, '[cortana] HUD off');
    else
        hud_show = not hud_show;
        windower.add_to_chat(207, '[cortana] HUD ' .. (hud_show and 'on' or 'off'));
    end
end

comm_register('HUD', function(parts)
    local text = parts[2] or '';
    for i = 3, #parts do text = text .. '|' .. parts[i]; end
    hud_box:text((text:gsub('~', '\n')));
    hud_last = os.clock();
    local key = text:gsub('%d', '');
    if (key ~= hud_key) then
        hud_key = key;
        hud_shownat = os.clock();
    end
end);

comm_register('VERBOSE', function(parts)
    local text = parts[2] or '';
    for i = 3, #parts do text = text .. '|' .. parts[i]; end
    hud_verbose(text);
    windower.add_to_chat(8, '[cortana] ' .. text);
end);

function hud_tick()
    do
        local age = os.clock() - verb_shownat;
        local show = false;
        if (hud_drag or age < VERB_HOLD) then
            if (verb_sliding) then pcall(function() verb_box:pos_x(verb_home_x); end); verb_sliding = false; end
            pcall(function() verb_home_x = (verb_box:pos()); end);
            show = true;
        elseif (age < VERB_HOLD + SLIDE_SECS) then
            if (not verb_sliding) then pcall(function() verb_home_x = (verb_box:pos()); end); verb_sliding = true; end
            pcall(function() verb_box:pos_x(slide_x(verb_home_x, 498, (age - VERB_HOLD) / SLIDE_SECS)); end);
            show = true;
        else
            if (verb_sliding) then pcall(function() verb_box:pos_x(verb_home_x); end); verb_sliding = false; end
        end
        if (show) then
            local textured = panel_under(verb_panel, verb_box, 1.0, 498, 126, 52, 48);
            pcall(function()
                verb_box:alpha(VERB_TXT_A);
                verb_box:bg_alpha(textured and 0 or VERB_BG_A);
            end);
            verb_box:visible(true);
            title_under(verb_title, verb_box, 52, 48, 54, 8, 255, textured);
        else
            verb_box:visible(false);
            if (verb_panel ~= nil) then pcall(function() verb_panel:visible(false); end); end
            title_under(verb_title, verb_box, 0, 0, 0, 0, 0, false);
        end
    end

    local fresh = (os.clock() - hud_last) < 10;
    if (not hud_show or not fresh or not comm_is_linked()) then
        if (hud_sliding) then pcall(function() hud_box:pos_x(hud_home_x); end); hud_sliding = false; end
        hud_box:visible(false);
        if (hud_panel ~= nil) then pcall(function() hud_panel:visible(false); end); end
        title_under(hud_title, hud_box, 0, 0, 0, 0, 0, false);
        return;
    end

    local age = os.clock() - hud_shownat;
    if (hud_pin or hud_drag or age < HUD_HOLD) then
        if (hud_sliding) then pcall(function() hud_box:pos_x(hud_home_x); end); hud_sliding = false; end
        pcall(function() hud_home_x = (hud_box:pos()); end);
    elseif (age < HUD_HOLD + SLIDE_SECS) then
        if (not hud_sliding) then pcall(function() hud_home_x = (hud_box:pos()); end); hud_sliding = true; end
        pcall(function() hud_box:pos_x(slide_x(hud_home_x, 396, (age - HUD_HOLD) / SLIDE_SECS)); end);
    else
        if (hud_sliding) then pcall(function() hud_box:pos_x(hud_home_x); end); hud_sliding = false; end
        hud_box:visible(false);
        if (hud_panel ~= nil) then pcall(function() hud_panel:visible(false); end); end
        title_under(hud_title, hud_box, 0, 0, 0, 0, 0, false);
        return;
    end

    local textured = panel_under(hud_panel, hud_box, 1.0, 396, 100, 42, 26);
    pcall(function()
        hud_box:alpha(TXT_A);
        hud_box:bg_alpha(textured and 0 or BG_A);
    end);
    hud_box:visible(true);
    title_under(hud_title, hud_box, 42, 26, 43, 6, 255, textured);
end
