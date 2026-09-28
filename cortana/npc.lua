local packets = require('packets');

local SHOP_TIMEOUT      = 5.0;
local APPRAISE_TIMEOUT  = 2.0;
local SOLD_TIMEOUT      = 2.5;

local shop_open_at = 0;
local appraised_at = 0;
local sold_at = 0;

windower.register_event('outgoing chunk', function(id, data, modified, injected)
    if (id ~= 0x05B or injected or not comm_is_linked()) then return; end
    pcall(function()
        local p = packets.parse('outgoing', data);
        local me = windower.ffxi.get_player();
        comm_send('DLGOPT|' .. ((me and me.name) or '?') .. '|' .. tostring(p['Menu ID'] or 0)
            .. '|' .. tostring(p['Option Index'] or 0) .. '|' .. tostring(p['_unknown1'] or 0)
            .. '|' .. (p['Automated Message'] and 1 or 0));
    end);
end);

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x03C or id == 0x03E) then
        shop_open_at = os.clock();
    elseif (id == 0x03D) then
        pcall(function()
            local p = packets.parse('incoming', data);
            if (p['Type'] == 1) then sold_at = os.clock(); else appraised_at = os.clock(); end
        end);
    end
end);

local function wait_until(pred, timeout)
    local deadline = os.clock() + timeout;
    while (os.clock() < deadline) do
        if (pred()) then return true; end
        coroutine.sleep(0.1);
    end
    return pred();
end

local function slot_item(slot)
    local bag = windower.ffxi.get_items(0);
    local it = bag and bag[slot];
    return (type(it) == 'table' and it.id) or 0;
end

local function do_sell(npc_index, wanted)
    local me = windower.ffxi.get_player();
    local name = (me and me.name) or '?';
    local function done(sold, reason)
        comm_send('SELLDONE|' .. name .. '|' .. sold .. '|' .. (reason or ''));
    end

    local npc = windower.ffxi.get_mob_by_index(npc_index);
    if (npc == nil or npc.id == nil or npc.id == 0) then return done(0, 'npc not found'); end
    if (me == nil or me.status ~= 0) then return done(0, 'character busy'); end
    if (npc.distance ~= nil and math.sqrt(npc.distance) > 6) then return done(0, 'npc out of range'); end

    local poked_at = os.clock();
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = npc.id, ['Target Index'] = npc_index, ['Category'] = 0x00, ['Param'] = 0,
        ['X Offset'] = 0, ['Y Offset'] = 0, ['Z Offset'] = 0,
    }));
    if (not wait_until(function() return shop_open_at >= poked_at; end, SHOP_TIMEOUT)) then
        return done(0, 'shop did not open');
    end
    coroutine.sleep(0.5);

    local sold = 0;
    local bag = windower.ffxi.get_items(0) or {};
    for slot = 1, (bag.max or 80) do
        local it = bag[slot];
        if (type(it) == 'table' and it.id ~= nil and wanted[it.id]) then
            local count = (it.count ~= nil and it.count > 0) and it.count or 1;
            local offered_at = os.clock();
            packets.inject(packets.new('outgoing', 0x084, {
                ['Count'] = count, ['Item'] = it.id, ['Inventory Index'] = slot,
            }));
            if (wait_until(function() return appraised_at >= offered_at; end, APPRAISE_TIMEOUT)) then
                local confirmed_at = os.clock();
                packets.inject(packets.new('outgoing', 0x085, {}));
                local id = it.id;
                if (wait_until(function() return sold_at >= confirmed_at or slot_item(slot) ~= id; end, SOLD_TIMEOUT)) then
                    sold = sold + 1;
                end
            end
            coroutine.sleep(0.4);
        end
    end

    windower.send_command('setkey escape down; wait 0.08; setkey escape up; wait 0.4; setkey escape down; wait 0.08; setkey escape up');
    done(sold, '');
end

comm_register('SELL', function(parts)
    local idx = tonumber(parts[2]);
    local wanted = {};
    for tok in string.gmatch(parts[3] or '', '([^,]+)') do
        local id = tonumber(tok);
        if (id ~= nil) then wanted[id] = true; end
    end
    if (idx == nil) then return; end
    coroutine.schedule(function() do_sell(idx, wanted); end, 0);
end);

local EVENT_TIMEOUT = 5.0;
local CHOICE_GAP    = 0.5;

local replay = nil;

local function hex(s)
    if (type(s) ~= 'string') then return ''; end
    return (s:gsub('.', function(c) return string.format('%02x', c:byte()); end));
end

local function me_name()
    local me = windower.ffxi.get_player();
    return (me and me.name) or '?';
end

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x032 or id == 0x033 or id == 0x034) then
        local ok, p = pcall(packets.parse, 'incoming', data);
        if (not ok or p == nil) then return; end
        local menu, npc_index = tonumber(p['Menu ID']) or 0, tonumber(p['NPC Index']) or 0;
        if (comm_is_linked()) then
            comm_send('EVT|' .. me_name() .. '|' .. id .. '|' .. menu .. '|' .. tostring(p['NPC'] or 0)
                .. '|' .. npc_index .. '|' .. hex(p['Menu Parameters']));
        end
        if (replay ~= nil and replay.event == nil and npc_index == replay.index
            and (replay.menu == 0 or menu == replay.menu)) then
            replay.event = { npc = p['NPC'], index = npc_index, zone = p['Zone'], menu = menu };
            if (replay.hide) then return true; end
        end
    elseif (id == 0x05C) then
        local ok, p = pcall(packets.parse, 'incoming', data);
        if (ok and p ~= nil and comm_is_linked()) then
            comm_send('EVTUPD|' .. me_name() .. '|' .. hex(p['Menu Parameters']));
        end
        if (replay ~= nil and replay.hide and replay.event ~= nil) then return true; end
    elseif (id == 0x113) then
        local ok, p = pcall(packets.parse, 'incoming', data);
        if (ok and p ~= nil and comm_is_linked()) then
            comm_send('CUR|' .. me_name() .. '|' .. tostring(p['Sparks of Eminence'] or 0)
                .. '|' .. tostring(p['Unity Accolades'] or 0));
        end
    elseif (id == 0x110) then
        local ok, p = pcall(packets.parse, 'incoming', data);
        if (ok and p ~= nil and comm_is_linked()) then
            comm_send('CUR|' .. me_name() .. '|' .. tostring(p['Sparks Total'] or 0) .. '|-1');
        end
    end
end);

local function do_replay(npc_index, menu, hide, choices)
    local me = windower.ffxi.get_player();
    local function done(ok, reason)
        replay = nil;
        comm_send('REPLAYDONE|' .. me_name() .. '|' .. (ok and 1 or 0) .. '|' .. (reason or ''));
    end

    if (#choices == 0) then return done(false, 'no choices to replay'); end
    local npc = windower.ffxi.get_mob_by_index(npc_index);
    if (npc == nil or npc.id == nil or npc.id == 0) then return done(false, 'npc not found'); end
    if (me == nil or me.status ~= 0) then return done(false, 'character busy'); end
    if (npc.distance ~= nil and math.sqrt(npc.distance) > 6) then return done(false, 'npc out of range'); end

    replay = { index = npc_index, menu = menu, hide = hide, event = nil };
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = npc.id, ['Target Index'] = npc_index, ['Category'] = 0x00, ['Param'] = 0,
        ['X Offset'] = 0, ['Y Offset'] = 0, ['Z Offset'] = 0,
    }));
    if (not wait_until(function() return replay ~= nil and replay.event ~= nil; end, EVENT_TIMEOUT)) then
        return done(false, 'npc event did not start (menu ' .. menu .. ')');
    end
    local ev = replay.event;
    coroutine.sleep(0.3);

    for _, c in ipairs(choices) do
        packets.inject(packets.new('outgoing', 0x05B, {
            ['Target'] = ev.npc, ['Option Index'] = c.option, ['_unknown1'] = c.unknown1,
            ['Target Index'] = ev.index, ['Automated Message'] = c.auto, ['Zone'] = ev.zone,
            ['Menu ID'] = ev.menu,
        }));
        coroutine.sleep(CHOICE_GAP);
    end

    if (hide) then
        packets.inject(packets.new('outgoing', 0x016, { ['Target Index'] = me.index }));
    end
    coroutine.sleep(0.3);
    done(true, '');
end

comm_register('NPCREPLAY', function(parts)
    local idx, menu = tonumber(parts[2]), tonumber(parts[3]) or 0;
    local hide = (parts[4] ~= '0');
    local choices = {};
    for rec in string.gmatch(parts[5] or '', '([^,]+)') do
        local o, u, a = rec:match('^(%d+):(%d+):(%d)$');
        if (o ~= nil) then
            choices[#choices + 1] = { option = tonumber(o), unknown1 = tonumber(u), auto = (a == '1') };
        end
    end
    if (idx == nil) then return; end
    coroutine.schedule(function() do_replay(idx, menu, hide, choices); end, 0);
end);

comm_register('CURREQ', function(parts)
    packets.inject(packets.new('outgoing', 0x10F, {}));
end);
