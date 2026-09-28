local res = require('resources');

local function u16(data, off) local b1, b2 = data:byte(off + 1, off + 2); return b1 + b2 * 256; end
local function u32(data, off)
    local b1, b2, b3, b4 = data:byte(off + 1, off + 4);
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216;
end

local function res_name(cat, param)
    local n = nil;
    pcall(function()
        local o = nil;
        if (cat == 3) then
            o = res.spells[param];
        elseif (cat == 7) then
            o = res.weapon_skills[param];
        elseif (cat == 9) then
            o = res.job_abilities[param] or res.job_abilities[param - 0x200];
        end
        if (o ~= nil) then n = o.en or o.name; end
    end);
    if (n ~= nil) then n = n:gsub('[^\32-\126]', ''); end
    return (n ~= nil and n ~= '') and n or ('#' .. tostring(param));
end

local OWN_RESULT_CATS = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true };

local function own_action_name(cat, id)
    local n = '';
    pcall(function()
        local o = nil;
        if (cat == 4) then o = res.spells[id];
        elseif (cat == 3) then o = res.weapon_skills[id];
        elseif (cat == 6) then o = res.job_abilities[id] or res.job_abilities[id - 0x200];
        elseif (cat == 5) then o = res.items[id];
        end
        if (o ~= nil) then n = (o.en or o.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '); end
    end);
    return n;
end

local function party_ids()
    local ids = {};
    pcall(function()
        local pt = windower.ffxi.get_party();
        local slots = { 'p0','p1','p2','p3','p4','p5','a10','a11','a12','a13','a14','a15','a20','a21','a22','a23','a24','a25' };
        for _, s in ipairs(slots) do
            local m = pt[s];
            if (m ~= nil and m.mob ~= nil and m.mob.id ~= nil and m.mob.id ~= 0) then ids[m.mob.id] = true; end
        end
    end);
    return ids;
end

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if (id ~= 0x1A) then return; end
    if (not comm_is_linked()) then return; end
    local target = u32(data, 0x04);
    local index  = u16(data, 0x08);
    local cat    = u16(data, 0x0A);
    local param  = u16(data, 0x0C);
    if (cat == 3 or cat == 7 or cat == 9 or cat == 16) then
        local p = windower.ffxi.get_player();
        comm_send(string.format('COMBAT|%s|type=USE;cat=%d;param=%d;name=%s;target=%d;index=%d',
            (p and p.name) or '?', cat, param, res_name(cat, param), target, index));
    end
end);

local function read_bits(data, bitpos, n)
    local v = 0;
    for i = 0, n - 1 do
        local bi = bitpos + i;
        local byte = data:byte(math.floor(bi / 8) + 1) or 0;
        if (math.floor(byte / 2 ^ (bi % 8)) % 2 == 1) then v = v + (2 ^ i); end
    end
    return v, bitpos + n;
end

local SC_NAMES = {
    [288] = 'Light', [289] = 'Darkness', [290] = 'Gravitation', [291] = 'Fragmentation', [292] = 'Distortion',
    [293] = 'Fusion', [294] = 'Compression', [295] = 'Liquefaction', [296] = 'Induration', [297] = 'Reverberation',
    [298] = 'Transfixion', [299] = 'Scission', [300] = 'Detonation', [301] = 'Impaction' };
local function sc_from_msg(m)
    if (m == nil or m == 0) then return nil; end
    if (SC_NAMES[m]) then return SC_NAMES[m]; end
    if (m >= 385 and m <= 398) then return SC_NAMES[m - 97]; end
    if (m == 767 or m == 769) then return 'Radiance'; end
    if (m == 768 or m == 770) then return 'Umbra'; end
    return nil;
end

local function parse_action(data)
    local maxbits = #data * 8;
    local pos = 40;
    local actor;  actor, pos  = read_bits(data, pos, 32);
    local tcount; tcount, pos = read_bits(data, pos, 6);
    local rsum;   rsum, pos    = read_bits(data, pos, 4);
    local cat;    cat, pos     = read_bits(data, pos, 4);
    local param;  param, pos   = read_bits(data, pos, 32);
    local info;   info, pos     = read_bits(data, pos, 32);

    local r = { actor = actor, cat = cat, param = param, tcount = tcount,
                tid = 0, msg = 0, addmsg = 0, procflag = 0, react = 0, val0 = 0 };
    if (tcount < 1 or tcount > 32) then return r; end

    for t = 1, tcount do
        if (pos + 36 > maxbits) then break; end
        local tid;    tid, pos    = read_bits(data, pos, 32);
        local rcount; rcount, pos = read_bits(data, pos, 4);
        if (t == 1) then r.tid = tid; end
        if (rcount < 1 or rcount > 8) then break; end
        for i = 1, rcount do
            if (pos + 90 > maxbits) then break; end
            local react; react, pos = read_bits(data, pos, 3);
            pos = pos + 2 + 12 + 5 + 5;
            local value; value, pos = read_bits(data, pos, 17);
            local msg;   msg, pos   = read_bits(data, pos, 10);
            if (t == 1 and i == 1) then r.val0 = value; end
            r.dmgsum = (r.dmgsum or 0) + value;
            pos = pos + 31;
            local proc;  proc, pos  = read_bits(data, pos, 1);
            if (proc == 1) then
                pos = pos + 6 + 4 + 17;
                local pmsg; pmsg, pos = read_bits(data, pos, 10);
                if (r.addmsg == 0 and sc_from_msg(pmsg) ~= nil) then
                    r.addmsg = pmsg; r.tid = tid; r.msg = msg; r.react = react; r.procflag = 1;
                end
            end
            local rflag; rflag, pos = read_bits(data, pos, 1);
            if (rflag == 1) then
                pos = pos + 6 + 4 + 14 + 10;
            end
        end
    end
    return r;
end

if (cortana_debug == nil) then cortana_debug = false; end

local WEAR_MSGS = {
    [64] = true, [204] = true, [206] = true, [321] = true, [322] = true, [341] = true, [342] = true,
    [343] = true, [344] = true, [350] = true, [351] = true, [378] = true, [531] = true, [647] = true };

local desync_count = 0;
local desync_at = 0;

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if (injected) then return; end

    if (id == 0x037) then
        pcall(function()
            local me = windower.ffxi.get_player();
            if (me == nil or me.status ~= 1) then desync_count = 0; return; end
            local pkt = windower.packets.parse('incoming', data);
            if (pkt == nil or pkt['Status'] == nil) then return; end
            if (pkt['Status'] ~= 0) then desync_count = 0; return; end

            desync_count = desync_count + 1;
            if (desync_count >= 3 and (os.time() - desync_at) > 5) then
                desync_at = os.time();
                desync_count = 0;
                comm_send('DESYNC|' .. (me.name or '?'));
            end
        end);
        return;
    end

    if (not comm_is_linked()) then return; end

    if (id == 0x38) then
        local me = windower.ffxi.get_player();
        if (me ~= nil and u32(data, 0x04) == me.id and data:find('hov1', 1, true) ~= nil) then
            comm_send('HOVER|' .. (me.name or '?') .. '|particle=1');
        end
        return;
    end

    if (id == 0x29) then
        local msgid = u16(data, 0x18) % 32768;
        do
            -- Only messages our own party is part of: an alliance's full message stream is noise.
            local me = windower.ffxi.get_player();
            local actor, target = u32(data, 0x04), u32(data, 0x08);
            local ours = party_ids();
            if (me ~= nil and (actor == me.id or target == me.id or ours[actor] or ours[target])) then
                comm_send(string.format('AMSG|%s|msg=%d;actor=%d;target=%d;aindex=%d;tindex=%d;p1=%d;p2=%d',
                    me.name or '?', msgid, actor, target,
                    u16(data, 0x14), u16(data, 0x16), u32(data, 0x0C), u32(data, 0x10)));
            end
        end
        if (WEAR_MSGS[msgid]) then
            local tid   = u32(data, 0x08);
            local tidx  = u16(data, 0x16);
            local buff  = u32(data, 0x0C);
            local sname = '';
            pcall(function()
                local b = res.buffs[buff];
                if (b ~= nil) then sname = (b.en or b.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '); end
            end);
            local me = windower.ffxi.get_player();
            comm_send(string.format('DEBUFFWEAR|%s|target=%d;tindex=%d;buff=%d;msg=%d;name=%s',
                (me and me.name) or '?', tid, tidx, buff, msgid, sname));
        end
        return;
    end

    if (id ~= 0x28) then return; end

    local p = windower.ffxi.get_player();
    local myname = (p and p.name) or '?';

    local ok, a = pcall(parse_action, data);
    if (not ok or a == nil) then return; end

    if (p ~= nil and a.actor == p.id) then
        if (a.cat == 2) then comm_send('HOVER|' .. myname .. '|kind=shot'); end
        if (a.cat == 3) then comm_send('HOVER|' .. myname .. '|kind=ws'); end

        if (OWN_RESULT_CATS[a.cat]) then
            local aid = (a.cat == 4 or a.cat == 3 or a.cat == 6 or a.cat == 5) and (a.param or 0) or 0;
            local msg, prm = a.msg or 0, a.val0 or 0;
            pcall(function()
                local lib = windower.packets.parse_action(data);
                if (lib == nil or lib.targets == nil or lib.targets[1] == nil) then return; end
                local act = lib.targets[1].actions and lib.targets[1].actions[1];
                if (act == nil) then return; end
                if (act.message ~= nil) then msg = act.message; end
                if (act.param ~= nil) then prm = act.param; end
            end);
            comm_send(string.format('CASTRES|%s|cat=%d;id=%d;target=%d;targets=%d;msg=%d;param=%d;sum=%d;name=%s',
                myname, a.cat, aid, a.tid or 0, a.tcount or 0, msg, prm, a.dmgsum or 0, own_action_name(a.cat, aid)));
        end

        if (a.cat == 6) then
            local aid = a.param or 0;
            local total = a.val0 or 0;
            pcall(function()
                local lib = windower.packets.parse_action(data);
                if (lib == nil or lib.targets == nil) then return; end
                local t1 = lib.targets[1];
                if (t1 == nil or t1.actions == nil or t1.actions[1] == nil) then return; end
                if (lib.param ~= nil) then aid = lib.param; end
                if (t1.actions[1].param ~= nil) then total = t1.actions[1].param; end
            end);

            local an = '';
            pcall(function()
                local o = res.job_abilities[aid] or res.job_abilities[aid - 0x200];
                if (o ~= nil and o.english ~= nil) then an = o.english; end
            end);
            comm_send(string.format('ROLL|%s|%d|%d|%s', myname, aid, total, an));
        end
    end

    if ((a.cat == 7 or a.cat == 8) and party_ids()[a.actor] == nil) then
        local aid = a.val0 or 0;
        local an = '';
        pcall(function()
            local o = nil;
            if (a.cat == 8) then o = res.spells[aid];
            else o = res.monster_abilities[aid - 256] or res.job_abilities[aid]; end
            if (o ~= nil) then an = (o.en or o.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '); end
        end);
        comm_send(string.format('MOBACT|%s|cat=%d;id=%d;actor=%d;name=%s', myname, a.cat, aid, a.actor, an));
    end

    if ((a.cat == 8 or a.cat == 4) and a.actor < 0x01000000 and (a.tid or 0) >= 0x01000000) then
        local aid = (a.cat == 8) and (a.val0 or 0) or (a.param or 0);
        local an = '';
        pcall(function()
            local o = res.spells[aid];
            if (o ~= nil) then an = (o.en or o.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '); end
        end);
        comm_send(string.format('PLRACT|%s|cat=%d;id=%d;actor=%d;target=%d;name=%s', myname, a.cat, aid, a.actor, a.tid or 0, an));
    end

    if ((a.cat == 11 or a.cat == 4) and party_ids()[a.actor] == nil) then
        local aid = a.param or 0;
        local an = '';
        pcall(function()
            local o = nil;
            if (a.cat == 4) then o = res.spells[aid];
            else o = res.monster_abilities[aid - 256] or res.job_abilities[aid]; end
            if (o ~= nil) then an = (o.en or o.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' '); end
        end);
        comm_send(string.format('MOBRES|%s|cat=%d;id=%d;actor=%d;targets=%d;dmg=%d;name=%s',
            myname, a.cat, aid, a.actor, a.tcount or 0, a.dmgsum or 0, an));
    end

    local sc = sc_from_msg(a.addmsg);
    if (sc ~= nil) then
        comm_send('COMBAT|' .. myname .. '|type=SC;name=' .. sc .. ';target=' .. a.tid .. ';src=pkt');
    end

    if (cortana_debug) then
        local total = #data;
        if (total >= 24) then
            local n = (total < 128) and total or 128;
            local hex = {};
            for i = 1, n do hex[i] = string.format('%02X', data:byte(i)); end
            comm_send(string.format('COMBAT|%s|type=ACT;len=%d;actor=%d;cat=%d;param=%d;target=%d;react=%d;msg=%d;proc=%d;addmsg=%d;hex=%s',
                myname, total, a.actor, a.cat, a.param, a.tid, a.react, a.msg, a.procflag, a.addmsg, table.concat(hex)));
        end
    end
end);

local sc_words = { 'skillchain', 'additional effect', 'miss', 'light', 'darkness', 'gravitation',
    'fragmentation', 'distortion', 'fusion', 'compression', 'liquefaction', 'induration',
    'reverberation', 'transfixion', 'scission', 'detonation', 'impaction', 'radiance', 'umbra' };

windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, blocked)
    if (blocked or not comm_is_linked()) then return; end

    local clean = (original or ''):gsub('[^\32-\126]', ''):gsub('[;|]', ' '):gsub('%s+', ' ');
    clean = clean:gsub('^%s+', ''):gsub('%s+$', '');
    if (clean == '') then return; end

    local p = windower.ffxi.get_player();
    local myname = (p and p.name) or '?';

    local scprop = clean:match('[Ss]killchain:%s*([%a]+)');
    if (scprop ~= nil) then
        comm_send('COMBAT|' .. myname .. '|type=SC;name=' .. scprop .. ';src=text');
    else
        local low = clean:lower();
        for _, w in ipairs(sc_words) do
            if (low:find(w, 1, true)) then
                comm_send('COMBAT|' .. myname .. '|type=TEXT;mode=' .. tostring(original_mode) .. ';text=' .. clean);
                break;
            end
        end
    end
end);
