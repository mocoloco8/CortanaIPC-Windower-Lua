local RUN_LEASE = 2.0;

local running = false;
local run_expires = 0;

local function stop_run()
    if (running) then
        running = false;
        pcall(function() windower.ffxi.run(false); end);
    end
end

comm_register('RUN', function(parts)
    local ang = tonumber(parts[2]);
    if (ang == nil) then return; end
    local p = windower.ffxi.get_player();
    if (p == nil or (p.status ~= 0 and p.status ~= 1)) then stop_run(); return; end
    running = true;
    run_expires = os.clock() + RUN_LEASE;
    pcall(function() windower.ffxi.run(ang); end);
end);

comm_register('RUNSTOP', function(parts)
    stop_run();
end);

comm_register('TURN', function(parts)
    local ang = tonumber(parts[2]);
    if (ang ~= nil) then pcall(function() windower.ffxi.turn(ang); end); end
end);

comm_register('KEYRAW', function(parts)
    local key, mode = parts[2], parts[3] or 'press';
    if (key == nil or not key:match('^[%w_]+$')) then return; end
    if (mode == 'down' or mode == 'up') then
        windower.send_command('setkey ' .. key .. ' ' .. mode);
    else
        local hold = tonumber(parts[4]) or 80;
        if (hold < 30) then hold = 30; end
        if (hold > 1000) then hold = 1000; end
        windower.send_command('setkey ' .. key .. ' down; wait ' .. string.format('%.2f', hold / 1000)
            .. '; setkey ' .. key .. ' up');
    end
end);

comm_register('CHATIN', function(parts)
    local text = table.concat(parts, '|', 2);
    if (text == nil or text == '') then return; end
    if (text:sub(1, 2) == '//') then
        windower.send_command(text:sub(3));
    else
        pcall(function() windower.chat.input(windower.to_shift_jis(text)); end);
    end
end);

function control_tick()
    if (running and (os.clock() > run_expires or not comm_is_linked())) then stop_run(); end
end

windower.register_event('zone change', function() stop_run(); end);
windower.register_event('unload', function() stop_run(); end);
