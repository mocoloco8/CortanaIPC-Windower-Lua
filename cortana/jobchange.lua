local packets = require('packets');

local JOBS = {
    war = 1,  mnk = 2,  whm = 3,  blm = 4,  rdm = 5,  thf = 6,
    pld = 7,  drk = 8,  bst = 9,  brd = 10, rng = 11, sam = 12,
    nin = 13, drg = 14, smn = 15, blu = 16, cor = 17, pup = 18,
    dnc = 19, sch = 20, geo = 21, run = 22,
};

local MOOGLE_RANGE = 6.0;

function cortana_job_id(name)
    if (name == nil) then return nil; end
    return JOBS[tostring(name):lower()];
end

local function nearest_moogle()
    local me = nil;
    pcall(function() me = windower.ffxi.get_mob_by_target('me'); end);
    if (me == nil or me.x == nil) then return -1; end

    local best = -1;
    for i = 0, 2303 do
        local ok, d = pcall(function()
            local m = windower.ffxi.get_mob_by_index(i);
            if (m == nil or m.x == nil or m.name == nil) then return nil; end
            if (not m.name:lower():find('moogle')) then return nil; end
            local dx, dy, dz = m.x - me.x, m.y - me.y, m.z - me.z;
            return math.sqrt(dx * dx + dy * dy + dz * dz);
        end);
        if (ok and d ~= nil and (best < 0 or d < best)) then best = d; end
    end

    if (best < 0) then
        pcall(function()
            local t = windower.ffxi.get_mob_by_target('t');
            if (t ~= nil and t.name ~= nil and t.name:lower():find('moogle') and t.x ~= nil) then
                local dx, dy, dz = t.x - me.x, t.y - me.y, t.z - me.z;
                best = math.sqrt(dx * dx + dy * dy + dz * dz);
            end
        end);
    end
    return best;
end

local function can_change()
    local p = windower.ffxi.get_player();
    if (p == nil) then return false, 'no player data'; end
    if (p.status ~= 0) then return false, 'busy (engaged/dead/in an event) — status ' .. tostring(p.status); end

    local d = nearest_moogle();
    if (d < 0) then return false, 'no Moogle found in this zone'; end
    if (d > MOOGLE_RANGE) then
        return false, string.format('nearest Moogle is %.1fy away (need %.0fy)', d, MOOGLE_RANGE);
    end
    return true, nil;
end

function cortana_do_jobchange(mainId, subId)
    local p = windower.ffxi.get_player();
    if (p == nil) then return; end
    mainId = tonumber(mainId) or 0;
    subId  = tonumber(subId) or 0;
    if (mainId == 0 and subId == 0) then return; end

    local newMain = (mainId ~= 0) and mainId or (p.main_job_id or 0);
    local newSub  = (subId ~= 0) and subId or (p.sub_job_id or 0);
    if (newMain ~= 0 and newMain == newSub) then
        windower.add_to_chat(207, '[cortana] job change refused: main and sub would both be the same job.');
        if (comm_is_linked()) then comm_send('JOBFAIL|' .. (p.name or '?') .. '|main and sub identical'); end
        return;
    end

    local ok, why = can_change();
    if (not ok) then
        windower.add_to_chat(207, '[cortana] job change refused: ' .. tostring(why) .. '.');
        if (comm_is_linked()) then comm_send('JOBFAIL|' .. (p.name or '?') .. '|' .. tostring(why)); end
        return;
    end

    local sent = pcall(function()
        local pk = packets.new('outgoing', 0x100, {
            ['Main Job']  = mainId,
            ['Sub Job']   = subId,
            ['_unknown1'] = 0,
            ['_unknown2'] = 0,
        });
        packets.inject(pk);
    end);
    if (sent) then
        windower.add_to_chat(207, '[cortana] job change sent (main ' .. mainId .. ', sub ' .. subId .. ').');
        if (comm_is_linked()) then comm_send('JOBSENT|' .. (p.name or '?') .. '|' .. mainId .. '|' .. subId); end
    else
        windower.add_to_chat(207, '[cortana] job change failed to build the packet.');
        if (comm_is_linked()) then comm_send('JOBFAIL|' .. (p.name or '?') .. '|packet build failed'); end
    end
end

comm_register('JOBCHANGE', function(parts)
    cortana_do_jobchange(parts[2], parts[3]);
end);
