local packets = require('packets');

local CAT_ENGAGE = 0x02;
local CAT_SWITCH = 0x0F;

local function u16(data, off) local b1, b2 = data:byte(off + 1, off + 2); return b1 + b2 * 256; end

local function send_action(server_id, index, category)
    local p = packets.new('outgoing', 0x01A, {
        ['Target']       = server_id,
        ['Target Index'] = index,
        ['Category']     = category,
        ['Param']        = 0,
        ['X Offset']     = 0,
        ['Y Offset']     = 0,
        ['Z Offset']     = 0,
    });
    packets.inject(p);
end

local function set_reticle(index)
    if (index == nil) then return; end
    local player = windower.ffxi.get_player();
    if (player == nil) then return; end
    local ent = windower.ffxi.get_mob_by_index(index);
    if (ent == nil or ent.id == nil or ent.id == 0) then return; end
    pcall(function()
        local lock = packets.new('incoming', 0x058, {
            ['Player']       = player.id,
            ['Target']       = ent.id,
            ['Player Index'] = player.index,
        });
        packets.inject(lock);
    end);
end

local function do_target(index)
    if (index == nil) then return; end
    local player = windower.ffxi.get_player();
    if (player == nil) then return; end

    local ent = windower.ffxi.get_mob_by_index(index);
    if (ent == nil or ent.id == nil or ent.id == 0 or ent.name == nil or ent.name == '') then
        return;
    end
    if (ent.hpp ~= nil and ent.hpp <= 0) then return; end
    if (ent.spawn_type ~= nil and ent.spawn_type ~= 16) then return; end
    if (ent.distance ~= nil and math.sqrt(ent.distance) > 30) then return; end
    local server_id = ent.id;

    set_reticle(index);

    local status = player.status;
    if (status == 1) then
        send_action(server_id, index, CAT_SWITCH);
    elseif (status == 0) then
        send_action(server_id, index, CAT_ENGAGE);
    else
        return;
    end
end

comm_register('TARGET', function(parts)
    local idx = tonumber(parts[2]);
    if (idx ~= nil) then do_target(idx); end
end);

comm_register('SMTARGET', function(parts)
    local idx = tonumber(parts[2]);
    if (idx ~= nil) then set_reticle(idx); end
end);

local CAT_INTERACT = 0x00;

comm_register('NPCPOKE', function(parts)
    local idx = tonumber(parts[2]);
    local name = parts[3];

    if (name ~= nil and name ~= '') then
        local ok, m = pcall(function() return windower.ffxi.get_mob_by_name(name); end);
        if (ok and m ~= nil and m.index ~= nil) then idx = m.index; end
    end
    if (idx == nil) then return; end

    local ent = windower.ffxi.get_mob_by_index(idx);
    local player = windower.ffxi.get_player();
    if (ent == nil or ent.id == nil or ent.id == 0) then
        if (comm_is_linked()) then comm_send('DLGFAIL|' .. ((player and player.name) or '?') .. '|no entity'); end
        return;
    end
    if (player == nil or player.status ~= 0) then
        if (comm_is_linked()) then comm_send('DLGFAIL|' .. ((player and player.name) or '?') .. '|busy'); end
        return;
    end

    set_reticle(idx);
    send_action(ent.id, idx, CAT_INTERACT);
end);

windower.register_event('incoming chunk', function(id, data)
    if (id ~= 0x032 and id ~= 0x033 and id ~= 0x034) then return; end
    pcall(function()
        local menu_id = tonumber(packets.parse('incoming', data)['Menu ID']) or 0;
        local p = windower.ffxi.get_player();
        if (comm_is_linked()) then
            comm_send('DLGOPEN|' .. ((p and p.name) or '?') .. '|' .. tostring(menu_id));
        end
    end);
end);

comm_register('RAISE', function(parts)
    local player = windower.ffxi.get_player();
    if (player == nil or player.id == nil or player.index == nil) then return; end
    send_action(player.id, player.index, 0x0D);
end);

local CAT_DISENGAGE = 0x04;
function targeting_send_disengage()
    local player = windower.ffxi.get_player();
    if (player == nil or player.id == nil or player.index == nil) then return; end
    if (player.status ~= 1) then return; end
    send_action(player.id, player.index, CAT_DISENGAGE);
end

comm_register('DISENGAGE', function(parts)
    targeting_send_disengage();
end);

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if (id ~= 0x029) then return; end
    if (injected) then return; end
    if (not comm_is_linked()) then return; end

    local ok, msg = pcall(u16, data, 0x18);
    if (not ok or msg == nil) then return; end
    if (msg % 0x8000 ~= 234) then return; end

    local player = windower.ffxi.get_player();
    if (player == nil) then return; end
    local t = windower.ffxi.get_mob_by_target('t');
    if (t == nil or t.index == nil or t.index == 0 or t.id == nil) then return; end

    local dist = (t.distance ~= nil) and math.sqrt(t.distance) or 0;
    comm_send(string.format('AUTOTARGET|%s|%d|%d|%.1f', player.name, t.id, t.index, dist));
end);
