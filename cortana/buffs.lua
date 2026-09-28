local packets = require('packets');

local BUFF_GAP  = 0.25;
local PBUFF_GAP = 0.25;

local epoch_ticks = 10;
local server_delta = 0;
local last_send = 0;
local last_pbuff = 0;
local pending_buffs = nil;
local pending_party = nil;

local function send_party_buffs(data)
    for k = 0, 4 do
        local o = 5 + k * 48;
        local idx = (data:byte(o + 4) or 0) + (data:byte(o + 5) or 0) * 256;
        local mob = (idx ~= 0) and windower.ffxi.get_mob_by_index(idx) or nil;
        local nm = mob and mob.name or nil;
        if (nm ~= nil and nm ~= '') then
            local ids = {};
            for i = 0, 31 do
                local maskb = data:byte(o + 8 + math.floor(i / 4)) or 0;
                local high = math.floor(maskb / (4 ^ (i % 4))) % 4;
                local low = data:byte(o + 16 + i) or 255;
                local buff = low + high * 256;
                if (buff ~= 255 and buff ~= 0) then ids[#ids + 1] = buff; end
            end
            comm_send('PBUFF|' .. nm .. '|' .. table.concat(ids, ','));
        end
    end
end

local function send_own_buffs(data)
    local ok, p = pcall(packets.parse, 'incoming', data);
    if (not ok or not p) then return; end

    local me = windower.ffxi.get_player();
    if (me == nil) then return; end

    local parts = {};
    for i = 1, 32 do
        local bid = p['Buffs ' .. i];
        if (bid ~= nil and bid ~= 255 and bid ~= 0) then
            local tfield = p['Time ' .. i] or 0;
            local end_unix = 1009810800 + (4294967296 * epoch_ticks + tfield) / 60 - server_delta;
            local rem = math.floor(end_unix - os.time());
            if (rem < 0) then rem = 0; end
            if (rem > 60000) then rem = 60000; end
            parts[#parts + 1] = bid .. ':' .. rem;
        end
    end

    comm_send('BUFFS|' .. (me.name or '?') .. '|' .. table.concat(parts, ','));
end

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x076) then
        if (not comm_is_linked()) then return; end
        local now = os.clock();
        if (now - last_pbuff < PBUFF_GAP) then pending_party = data; return; end
        pending_party = nil;
        last_pbuff = now;
        pcall(send_party_buffs, data);
        return;
    end
    if (id == 0x037) then
        local ok, p = pcall(packets.parse, 'incoming', data);
        if (ok and p and p['Timestamp'] and p['Time offset?']) then
            local server_time = p['Timestamp'] - p['Time offset?'] / 60;
            epoch_ticks = math.floor(server_time / (4294967296 / 60));
            server_delta = 1009810800 + server_time - os.time();
        end
        return;
    end

    if (id ~= 0x063) then return; end
    if (data:byte(0x05) ~= 0x09) then return; end
    if (not comm_is_linked()) then return; end

    local now = os.clock();
    if (now - last_send < BUFF_GAP) then pending_buffs = data; return; end
    pending_buffs = nil;
    last_send = now;
    send_own_buffs(data);
end);

-- A packet that arrived inside the rate window is HELD, not dropped: buff timers are what confirm a
-- song or buff landed, and losing the confirming packet made the caster wait for the next one.
windower.register_event('prerender', function()
    local now = os.clock();
    if (pending_buffs ~= nil and now - last_send >= BUFF_GAP) then
        local d = pending_buffs;
        pending_buffs = nil;
        last_send = now;
        pcall(send_own_buffs, d);
    end
    if (pending_party ~= nil and now - last_pbuff >= PBUFF_GAP) then
        local d = pending_party;
        pending_party = nil;
        last_pbuff = now;
        pcall(send_party_buffs, d);
    end
end);
