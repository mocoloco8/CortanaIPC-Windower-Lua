local KEY_MAP = {
    up = 'up', down = 'down', left = 'left', right = 'right',
    enter = 'enter', ['return'] = 'enter', escape = 'escape', esc = 'escape',
    space = 'space', tab = 'tab', backspace = 'back',
    numpad0 = 'numpad0', numpad1 = 'numpad1', numpad2 = 'numpad2', numpad3 = 'numpad3',
    numpad4 = 'numpad4', numpad5 = 'numpad5', numpad6 = 'numpad6', numpad7 = 'numpad7',
    numpad8 = 'numpad8', numpad9 = 'numpad9',
    w = 'w', a = 'a', s = 's', d = 'd',
};

local keys_naked = false;

local function press(name, hold)
    local k = KEY_MAP[(name or ''):lower()];
    if (k == nil) then return false; end
    hold = tonumber(hold) or 80;
    if (hold < 30) then hold = 30; end
    if (hold > 1000) then hold = 1000; end
    local secs = string.format('%.2f', hold / 1000);
    local ok = pcall(function()
        windower.send_command('setkey ' .. k .. ' down; wait ' .. secs .. '; setkey ' .. k .. ' up');
    end);
    return ok;
end

comm_register('KEY', function(parts)
    if (keys_naked) then return; end
    local p = windower.ffxi.get_player();
    if (not press(parts[2], parts[3])) then
        keys_naked = true;
        if (comm_is_linked()) then comm_send('KEYNAK|' .. ((p and p.name) or '?')); end
        windower.add_to_chat(207, '[cortana] lua key presses unavailable — app-side keys will be used.');
        return;
    end
    if (comm_is_linked()) then comm_send('KEYACK|' .. ((p and p.name) or '?')); end
end);

comm_register('KEYSEQ', function(parts)
    if (keys_naked) then return; end
    local hold = parts[3];
    for name in string.gmatch(parts[2] or '', '([^,]+)') do
        if (not press(name, hold)) then return; end
        coroutine.sleep(0.12);
    end
    local p = windower.ffxi.get_player();
    if (comm_is_linked()) then comm_send('KEYACK|' .. ((p and p.name) or '?')); end
end);
