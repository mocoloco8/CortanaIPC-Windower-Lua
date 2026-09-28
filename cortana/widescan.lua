local packets = require('packets');

local function me_name()
    local p = windower.ffxi.get_player();
    return (p and p.name) or '?';
end

local function clean(s)
    return (tostring(s or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '));
end

windower.register_event('incoming chunk', function(id, data)
    if (id ~= 0x0F4) then return; end
    pcall(function()
        local p = packets.parse('incoming', data);
        if (p == nil) then return; end
        comm_send(string.format('WSMOB|%s|index=%d;level=%d;type=%s;x=%d;y=%d;name=%s',
            me_name(), tonumber(p['Index']) or 0, tonumber(p['Level']) or 0,
            clean(p['Type']), tonumber(p['X Offset']) or 0, tonumber(p['Y Offset']) or 0,
            clean(p['Name'])));
    end);
end);

comm_register('WIDESCAN', function(parts)
    packets.inject(packets.new('outgoing', 0x0F4, { ['Flags'] = 1 }));
end);
