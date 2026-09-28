local res = require('resources');
local packets = require('packets');

local function me_name()
    local p = windower.ffxi.get_player();
    return (p and p.name) or '?';
end

local function clean(s)
    return (tostring(s or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '));
end

local function item_name(id)
    local n = '';
    pcall(function()
        local o = res.items[id];
        if (o ~= nil) then n = clean(o.en or o.name or ''); end
    end);
    return n;
end

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x0D2) then
        pcall(function()
            local p = packets.parse('incoming', data);
            if (p == nil) then return; end
            local item = tonumber(p['Item']) or 0;
            comm_send(string.format('TPOOL|%s|slot=%d;item=%d;count=%d;dropper=%d;old=%d;name=%s',
                me_name(), tonumber(p['Index']) or 0, item, tonumber(p['Count']) or 0,
                tonumber(p['Dropper']) or 0, (p['Old'] and 1) or 0, item_name(item)));
        end);
    elseif (id == 0x0D3) then
        pcall(function()
            local p = packets.parse('incoming', data);
            if (p == nil) then return; end
            comm_send(string.format('TLOTR|%s|slot=%d;drop=%d;lot=%d;winner=%s;lotter=%s;lotted=%d',
                me_name(), tonumber(p['Index']) or 0, tonumber(p['Drop']) or 0,
                tonumber(p['Highest Lot']) or 0, clean(p['Highest Lotter Name']),
                clean(p['Current Lotter Name']), tonumber(p['Current Lot']) or 0));
        end);
    end
end);

comm_register('LOT', function(parts)
    local slot = tonumber(parts[2]);
    if (slot == nil) then return; end
    packets.inject(packets.new('outgoing', 0x041, { ['Slot'] = slot }));
end);

comm_register('PASS', function(parts)
    local slot = tonumber(parts[2]);
    if (slot == nil) then return; end
    packets.inject(packets.new('outgoing', 0x042, { ['Slot'] = slot }));
end);
