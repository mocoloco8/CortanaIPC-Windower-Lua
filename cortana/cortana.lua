_addon.name     = 'cortana';
_addon.author   = 'CortanaXIHealer';
_addon.version  = '1.0.0';
_addon.commands = {'cortana'};

require('comm');
require('targeting');
require('combat');
require('buffs');
require('inventory');
require('hud');
require('keys');
require('jobchange');
require('state');
require('control');
require('npc');
require('treasure');
require('widescan');

local function cprint(s) windower.add_to_chat(207, s); end

local FEATURE_ALIASES = {
    ['follow']      = 'follow',
    ['ws']          = 'ws',
    ['weaponskill'] = 'ws',
    ['melee']       = 'melee',
    ['disengage']   = 'disengage',
    ['standdown']   = 'disengage',
    ['magic']       = 'magic',
    ['ma']          = 'magic',
    ['nuke']        = 'magic',
    ['autoattack']  = 'autoattack',
    ['aa']          = 'autoattack',
    ['attack']      = 'autoattack',
};

local PUMP_INTERVAL = 0.02;
local pump_running = false;

local function pump()
    pcall(comm_tick);
    pcall(state_tick);
    pcall(control_tick);
end

windower.register_event('load', function()
    comm_init();
    comm_register('NOTIFY', function(parts) cprint('[cortana] ' .. (parts[2] or '')); end);
    cprint('[cortana] loaded — looking for apps on 127.0.0.1:59332-59341.');
    pump_running = true;
    coroutine.schedule(function()
        while (pump_running) do
            pump();
            coroutine.sleep(PUMP_INTERVAL);
        end
    end, 0);
end);

windower.register_event('unload', function()
    pump_running = false;
    comm_shutdown();
end);

local follow_active = false;
local follow_naked = false;

comm_register('FOLLOW', function(parts)
    if (follow_naked) then return; end
    local idx = tonumber(parts[2]);
    if (idx == nil) then return; end
    local ok = pcall(function() windower.ffxi.follow(idx); end);
    local p = windower.ffxi.get_player();
    if (ok) then
        follow_active = true;
        if (comm_is_linked()) then comm_send('FOLLOWACK|' .. ((p and p.name) or '?')); end
    else
        follow_naked = true;
        if (comm_is_linked()) then comm_send('FOLLOWNAK|' .. ((p and p.name) or '?')); end
        cprint('[cortana] lua follow unavailable — app-side follow will be used.');
    end
end);
local function stop_follow()
    if (follow_active) then
        follow_active = false;
        pcall(function() windower.ffxi.follow(); end);
    end
end
comm_register('FOLLOWSTOP', function(parts) stop_follow(); end);

local typing_last = nil;
local typing_check_at = 0;
windower.register_event('prerender', function()
    pump();
    hud_tick();
    if (os.clock() - typing_check_at > 0.15) then
        typing_check_at = os.clock();
        pcall(function()
            local info = windower.ffxi.get_info();
            local v = (info ~= nil and info.chat_open) and 1 or 0;
            local refresh = (v == 1 and os.clock() - (typing_sent_at or 0) > 2.0);
            if ((v ~= typing_last or refresh) and comm_is_linked()) then
                typing_last = v;
                typing_sent_at = os.clock();
                local p = windower.ffxi.get_player();
                comm_send('TYPING|' .. ((p and p.name) or '?') .. '|' .. v);
            end
        end);
    end
end);

windower.register_event('addon command', function(sub, ...)
    sub = (sub or ''):lower();
    local rest = {...};
    local action = (rest[1] ~= nil) and tostring(rest[1]):lower() or 'toggle';

    if (sub == 'status') then
        local list = comm_apps();
        if (#list == 0) then
            cprint('[cortana] linked: false (no app on 127.0.0.1:59332-59341).');
        end
        for _, a in ipairs(list) do
            cprint('[cortana] linked: ' .. a.name .. ' (port ' .. a.port .. ')');
        end
    elseif (sub == 'inv' or sub == 'inventory') then
        cortana_print_inventory();
    elseif (sub == 'hud' or sub == 'overlay') then
        hud_command(action == 'toggle' and '' or action);
    elseif (sub == 'debug') then
        cortana_debug = not cortana_debug;
        cprint('[cortana] debug (RX rows): ' .. tostring(cortana_debug));
    elseif (sub == 'verbose' or sub == 'msg' or sub == 'announce') then
        local vtext = table.concat(rest, ' '):gsub('^%s*"?(.-)"?%s*$', '%1');
        if (vtext == '') then
            cprint('[cortana] usage: //cortana verbose "<message>"   (~ = line break)');
        else
            hud_verbose(vtext);
            windower.add_to_chat(8, '[cortana] ' .. vtext);
        end
    elseif (sub == 'profile' or sub == 'team' or sub == 'teamsetup') then
        local pname = table.concat(rest, ' '):gsub('^%s*"?(.-)"?%s*$', '%1');
        if (pname == '') then
            cprint('[cortana] usage: //cortana profile "<team setup name>"');
        elseif (not comm_is_linked()) then
            cprint('[cortana] not linked to CortanaXIHealer.');
        else
            local p = windower.ffxi.get_player();
            local name = (p ~= nil and p.name) or '';
            comm_send('CMD|' .. name .. '|profile|' .. pname);
            cprint('[cortana] team setup "' .. pname .. '" -> CortanaXIHealer');
        end
    elseif (sub == 'qc' or sub == 'quick' or sub == 'quickcommand') then
        local qcname = table.concat(rest, ' '):gsub('^%s*"?(.-)"?%s*$', '%1');
        if (qcname == '') then
            cprint('[cortana] usage: //cortana qc "<name>"');
        elseif (not comm_is_linked()) then
            cprint('[cortana] not linked to CortanaXIHealer.');
        else
            local p = windower.ffxi.get_player();
            local name = (p ~= nil and p.name) or '';
            comm_send('CMD|' .. name .. '|qc|' .. qcname);
            cprint('[cortana] qc "' .. qcname .. '" -> CortanaXIHealer');
        end
    elseif (sub == 'job' or sub == 'jobchange' or sub == 'jc') then
        local spec = rest[1];
        local who  = (rest[2] ~= nil) and tostring(rest[2]) or '';
        if (spec == nil) then
            cprint('[cortana] usage: //cortana job <MAIN>[/<SUB>] [character]   ("/SUB" alone changes only the sub job)');
        else
            local mj, sj = tostring(spec):match('^([^/]*)/(.+)$');
            if (mj == nil) then mj = tostring(spec); sj = nil; end
            local mid = (mj ~= nil and mj ~= '') and cortana_job_id(mj) or 0;
            local sid = (sj ~= nil) and cortana_job_id(sj) or 0;
            if ((mj ~= '' and mid == nil) or (sj ~= nil and sid == nil)) then
                cprint('[cortana] unknown job in "' .. tostring(spec) .. '" — use the 3-letter code (WHM, RDM, ...).');
            elseif (who == '') then
                cortana_do_jobchange(mid, sid);
            elseif (not comm_is_linked()) then
                cprint('[cortana] not linked to CortanaXIHealer — cannot change another character.');
            else
                local p = windower.ffxi.get_player();
                comm_send('CMD|' .. ((p and p.name) or '') .. '|jobchange|' .. mid .. '/' .. sid .. '|' .. who);
                cprint('[cortana] job change ' .. mj .. (sj and ('/' .. sj) or '') .. ' -> ' .. who);
            end
        end
    elseif ((sub == 'ws' or sub == 'weaponskill') and rest[1] ~= nil
            and action ~= 'on' and action ~= 'off' and action ~= 'toggle') then
        local wsname, who = '', '';
        if (rest[1] ~= nil and tostring(rest[1]):find(' ') and rest[2] ~= nil) then
            wsname = tostring(rest[1]);
            who    = tostring(rest[2]);
        else
            wsname = table.concat(rest, ' ');
        end
        wsname = (wsname or ''):gsub('^%s*(.-)%s*$', '%1');
        who = (who or ''):gsub('^%s*(.-)%s*$', '%1');
        if (wsname == '') then
            cprint('[cortana] usage: //cortana ws "<weapon skill>" [character]');
        elseif (not comm_is_linked()) then
            cprint('[cortana] not linked to CortanaXIHealer.');
        else
            local p = windower.ffxi.get_player();
            comm_send('CMD|' .. ((p and p.name) or '') .. '|wsname|' .. wsname .. '|' .. who);
        end
    elseif (FEATURE_ALIASES[sub] ~= nil) then
        if (not comm_is_linked()) then
            cprint('[cortana] not linked to CortanaXIHealer — cannot send "' .. sub .. '".');
        else
            local p = windower.ffxi.get_player();
            local name = (p ~= nil and p.name) or '';
            local target = (rest[2] ~= nil) and tostring(rest[2]) or '';
            comm_send('CMD|' .. name .. '|' .. FEATURE_ALIASES[sub] .. '|' .. action .. '|' .. target);
            cprint('[cortana] ' .. sub .. ' ' .. action .. (target ~= '' and (' (' .. target .. ')') or '') .. ' -> CortanaXIHealer');
        end
    else
        cprint('[cortana] commands: status | debug | inv | hud | job <MAIN>[/<SUB>] [name] | follow | ws [on|off] | ws "<weapon skill>" [name] | magic | autoattack [on|off] | melee on|off [name] | disengage [name] | qc "<name>" | profile "<name>" | verbose "<message>"');
    end
end);
