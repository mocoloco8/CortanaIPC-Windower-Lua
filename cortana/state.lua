local res = require('resources');
local packets = require('packets');

local CHECK_GAP    = 0.03;
local PLAYER_HB    = 0.25;
local PARTY_HB     = 0.50;
local HOT_HB       = 0.25;
local ENTITY_CHECK = 0.10;
local ENTITY_FULL  = 3.0;
local RECAST_CHECK = 0.10;
local RECAST_HB    = 1.0;
local SPELLS_RATE  = 30.0;
local INV_CHECK    = 1.0;
local INV_RATE     = 10.0;
local ENT_PER_PART = 40;
local EXTRAS_CHECK = 1.0;
local EXTRAS_HB    = 10.0;
local PET_HB       = 1.0;

local last_check, last_entity_check, last_entity_full, last_recast_check, last_spells = 0, 0, 0, 0, 0;
local last_inv_check, last_inv_sent, last_inv_body = 0, 0, nil;
local last_extras_check = 0;
local spx_body, spx_at = nil, 0;
local entity_frame = 0;
local was_linked = false;
local sent_epoch = -1;

local spl_body, spl_at = nil, 0;
local pet_body, pet_at = nil, 0;
local spt_body, spt_at = nil, 0;
local src_body, src_at = nil, 0;
local hot_sent = {};
local ent_seen = {};

local event_menu = 0;
local pet_info = nil;

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x032 or id == 0x033 or id == 0x034) then
        pcall(function()
            local p = packets.parse('incoming', data);
            event_menu = tonumber(p['Menu ID']) or 0;
        end);
    elseif (id == 0x052) then
        event_menu = 0;
    elseif (id == 0x067 or id == 0x068) then
        pcall(function()
            local p = packets.parse('incoming', data);
            if (p['Message Type'] ~= 4) then return; end
            local me = windower.ffxi.get_player();
            if (me == nil or p['Owner Index'] ~= me.index) then return; end
            local idx = p['Pet Index'] or 0;
            local target = 0;
            if (id == 0x068) then target = p['Target ID'] or 0;
            elseif (pet_info ~= nil and pet_info.index == idx) then target = pet_info.target; end
            pet_info = {
                index = idx, hpp = p['Current HP%'] or 0, mpp = p['Current MP%'] or 0,
                tp = p['Pet TP'] or 0, target = target, name = p['Pet Name'] or '', at = os.clock(),
            };
        end);
    end
end);

windower.register_event('zone change', function() event_menu = 0; pet_info = nil; end);

local function me_name()
    local p = windower.ffxi.get_player();
    return (p ~= nil and p.name) or nil;
end

local function f3(v) return string.format('%.3f', tonumber(v) or 0); end

local function clean(s)
    return (tostring(s or ''):gsub('[|;,]', ' '));
end

local function facing(m) return m and (m.facing or m.heading) or 0; end

local function mob_rec(m)
    if (m == nil or m.index == nil) then return nil; end
    local dist = (m.distance ~= nil) and math.sqrt(m.distance) or 0;
    return table.concat({
        m.index, m.id or 0, clean(m.name), m.hpp or 0,
        f3(m.x), f3(m.y), f3(m.z), f3(facing(m)), f3(dist),
        m.status or 0, m.claim_id or 0, m.spawn_type or 0, f3(m.model_size),
        m.pet_index or 0, m.target_index or 0, (m.valid_target and 1 or 0), m.race or 0,
    }, ',');
end

local cast_start, cast_len, cast_done_at = nil, 0, nil;

windower.register_event('action', function(act)
    local p = windower.ffxi.get_player();
    if (p == nil or act == nil or act.actor_id ~= p.id) then return; end
    local cat, param = act.category, act.param;
    local kind = (cat == 8 or cat == 4) and 'spell' or 'item';
    if (cat == 8 or cat == 9) then
        local id = act.targets and act.targets[1] and act.targets[1].actions
            and act.targets[1].actions[1] and act.targets[1].actions[1].param;
        if (param == 28787) then
            cast_start, cast_done_at = nil, nil;
            comm_send('CAST|' .. p.name .. '|interrupt|' .. kind .. '|' .. tostring(id or 0));
            return;
        end
        local r = (cat == 8) and res.spells[id] or res.items[id];
        cast_len = (r ~= nil and tonumber(r.cast_time)) or 3;
        if (cast_len <= 0) then cast_len = 0.5; end
        cast_start, cast_done_at = os.clock(), nil;
        comm_send('CAST|' .. p.name .. '|begin|' .. kind .. '|' .. tostring(id or 0));
    elseif (cat == 4 or cat == 5) then
        cast_start, cast_done_at = nil, os.clock();
        comm_send('CAST|' .. p.name .. '|finish|' .. kind .. '|' .. tostring(param or 0));
    end
end);

local function cast_percent()
    local now = os.clock();
    if (cast_done_at ~= nil) then
        if (now - cast_done_at < 0.6) then return 1.0; end
        cast_done_at = nil;
    end
    if (cast_start == nil) then return 0; end
    local pct = (now - cast_start) / cast_len;
    if (pct > 3) then cast_start = nil; return 0; end
    return math.max(0.01, math.min(0.95, pct));
end

local function send_upserts(name, recs)
    local i = 1;
    while (i <= #recs) do
        local chunk = {};
        for j = i, math.min(#recs, i + ENT_PER_PART - 1) do chunk[#chunk + 1] = recs[j]; end
        comm_send('SEN|' .. name .. '|0|1|1|' .. table.concat(chunk, ';'));
        i = i + ENT_PER_PART;
    end
end

local function send_pet(name, pet, now)
    local idx, hpp, mpp, tp, target, pname = 0, 0, -1, -1, 0, '';
    if (pet ~= nil and pet.index ~= nil) then
        idx, hpp, pname = pet.index, pet.hpp or 0, pet.name or '';
        if (pet_info ~= nil and pet_info.index == idx) then
            mpp, tp, target = pet_info.mpp, pet_info.tp, pet_info.target;
            if (pname == '') then pname = pet_info.name; end
        end
    elseif (pet_info ~= nil and now - pet_info.at > 2.0) then
        pet_info = nil;
    end
    local body = table.concat({ 'PET', name, idx, hpp, mpp, tp, target, clean(pname) }, '|');
    if (body ~= pet_body or now - pet_at >= PET_HB) then
        comm_send(body);
        pet_body, pet_at = body, now;
    end
end

local function send_player(name, now)
    local p = windower.ffxi.get_player();
    local info = windower.ffxi.get_info();
    if (p == nil or info == nil) then return; end
    local m = windower.ffxi.get_mob_by_index(p.index);
    local v = p.vitals or {};
    local login = (info.logged_in and m ~= nil) and 2 or (info.logged_in and 1 or 0);
    local t   = windower.ffxi.get_mob_by_target('t');
    local st  = windower.ffxi.get_mob_by_target('st');
    local pet = windower.ffxi.get_mob_by_target('pet');
    local buffs = table.concat(p.buffs or {}, ',');

    local body = table.concat({
        'SPL', name, p.id or 0, p.index or 0,
        v.hp or 0, v.hpp or 0, v.mp or 0, v.mpp or 0, v.max_mp or 0, v.tp or 0,
        f3(m and m.x), f3(m and m.y), f3(m and m.z), f3(facing(m)),
        p.status or 0, info.zone or 0,
        p.main_job_id or 0, p.main_job_level or 0, p.sub_job_id or 0, p.sub_job_level or 0,
        login, string.format('%.2f', cast_percent()),
        (pet and pet.index) or 0, (t and t.index) or 0, (st and st.index) or 0,
        (p.target_locked and 1 or 0), buffs,
        (p.status == 4) and event_menu or 0,
    }, '|');
    if (body ~= spl_body or now - spl_at >= PLAYER_HB) then
        comm_send(body);
        spl_body, spl_at = body, now;
    end
    send_pet(name, pet, now);

    local recs = {};
    local function add(mob)
        local r = mob_rec(mob);
        if (r == nil) then return; end
        local last = hot_sent[mob.index];
        if (last == nil or last.rec ~= r or now - last.at >= HOT_HB) then
            recs[#recs + 1] = r;
            hot_sent[mob.index] = { rec = r, at = now };
        end
    end
    add(m); add(t); add(st); add(pet);
    local party = windower.ffxi.get_party();
    if (party ~= nil) then
        for _, key in ipairs({'p1', 'p2', 'p3', 'p4', 'p5'}) do
            local pm = party[key];
            if (pm ~= nil and pm.mob ~= nil) then add(pm.mob); end
        end
    end
    if (#recs > 0) then send_upserts(name, recs); end
end

local function entity_changed(m)
    local s = ent_seen[m.index];
    local fac = facing(m);
    local dist = (m.distance ~= nil) and math.sqrt(m.distance) or 0;
    if (s ~= nil and s.id == m.id and s.hpp == m.hpp and s.status == m.status and s.claim == m.claim_id
        and s.tidx == m.target_index and s.valid == m.valid_target and s.pet == m.pet_index
        and math.abs(s.x - (m.x or 0)) < 0.05 and math.abs(s.y - (m.y or 0)) < 0.05
        and math.abs(s.z - (m.z or 0)) < 0.05 and math.abs(s.f - fac) < 0.02
        and math.abs(s.d - dist) < 0.1) then
        return false;
    end
    ent_seen[m.index] = {
        id = m.id, hpp = m.hpp, status = m.status, claim = m.claim_id, tidx = m.target_index,
        valid = m.valid_target, pet = m.pet_index, x = m.x or 0, y = m.y or 0, z = m.z or 0, f = fac, d = dist,
    };
    return true;
end

local function send_entities(name, now, full)
    local arr = windower.ffxi.get_mob_array();
    if (arr == nil) then return; end
    local recs, present = {}, {};
    for _, m in pairs(arr) do
        if (m.index ~= nil) then
            present[m.index] = true;
            if (entity_changed(m) or full) then
                local r = mob_rec(m);
                if (r ~= nil) then recs[#recs + 1] = r; end
            end
        end
    end

    local gone = {};
    for idx in pairs(ent_seen) do
        if (not present[idx]) then gone[#gone + 1] = idx; ent_seen[idx] = nil; hot_sent[idx] = nil; end
    end
    if (#gone > 0) then comm_send('SEX|' .. name .. '|' .. table.concat(gone, ',')); end

    if (not full) then
        if (#recs > 0) then send_upserts(name, recs); end
        return;
    end
    entity_frame = (entity_frame % 1000000) + 1;
    local parts = math.max(1, math.ceil(#recs / ENT_PER_PART));
    for part = 1, parts do
        local a = (part - 1) * ENT_PER_PART + 1;
        local b = math.min(#recs, part * ENT_PER_PART);
        local chunk = {};
        for i = a, b do chunk[#chunk + 1] = recs[i]; end
        comm_send('SEN|' .. name .. '|' .. entity_frame .. '|' .. part .. '|' .. parts .. '|' .. table.concat(chunk, ';'));
    end
end

local PARTY_KEYS = {
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5',
    'a10', 'a11', 'a12', 'a13', 'a14', 'a15',
    'a20', 'a21', 'a22', 'a23', 'a24', 'a25',
};

local function send_party(name, now)
    local party = windower.ffxi.get_party();
    if (party == nil) then return; end
    local me = windower.ffxi.get_player();
    local recs = {};
    for slot, key in ipairs(PARTY_KEYS) do
        local pm = party[key];
        if (pm ~= nil and pm.name ~= nil and pm.name ~= '') then
            local mob = pm.mob;
            local mj, ml, sj, sl = 0, 0, 0, 0;
            if (key == 'p0' and me ~= nil) then
                mj, ml, sj, sl = me.main_job_id or 0, me.main_job_level or 0, me.sub_job_id or 0, me.sub_job_level or 0;
            end
            recs[#recs + 1] = table.concat({
                slot - 1, clean(pm.name), (mob and mob.id) or 0, (mob and mob.index) or 0,
                pm.hp or 0, pm.hpp or 0, pm.mp or 0, pm.mpp or 0, pm.tp or 0, pm.zone or 0,
                mj, ml, sj, sl,
            }, ',');
        end
    end
    local body = 'SPT|' .. name .. '|' .. table.concat(recs, ';');
    if (body ~= spt_body or now - spt_at >= PARTY_HB) then
        comm_send(body);
        spt_body, spt_at = body, now;
    end
end

local function send_recasts(name, now)
    local ab, sp = {}, {};
    local ar = windower.ffxi.get_ability_recasts() or {};
    local rids = {};
    for rid in pairs(ar) do rids[#rids + 1] = rid; end
    table.sort(rids);
    for _, rid in ipairs(rids) do ab[#ab + 1] = rid .. '=' .. math.ceil(ar[rid] or 0); end
    local sr = windower.ffxi.get_spell_recasts() or {};
    local sids = {};
    for sid, frames in pairs(sr) do if (frames ~= nil and frames > 0) then sids[#sids + 1] = sid; end end
    table.sort(sids);
    for _, sid in ipairs(sids) do sp[#sp + 1] = sid .. '=' .. (math.ceil(sr[sid] / 60) * 60); end
    local body = 'SRC|' .. name .. '|' .. table.concat(ab, ',') .. '|' .. table.concat(sp, ',');
    if (body ~= src_body or now - src_at >= RECAST_HB) then
        comm_send(body);
        src_body, src_at = body, now;
    end
end

local function send_inventory(name, now)
    if (build_inventory_body == nil) then return; end
    local body, _, max = build_inventory_body();
    if (body == last_inv_body and now - last_inv_sent < INV_RATE) then return; end
    last_inv_body, last_inv_sent = body, now;
    comm_send('SIV|' .. name .. '|' .. tostring(max or 0) .. '|' .. body);
end

local function send_spells(name)
    local known = windower.ffxi.get_spells() or {};
    local ids = {};
    for id, has in pairs(known) do if (has) then ids[#ids + 1] = id; end end
    comm_send('SSP|' .. name .. '|' .. table.concat(ids, ','));
end

local function send_abilities(name)
    local known = windower.ffxi.get_abilities() or {};
    local ids = {};
    for k, v in pairs(known.job_abilities or {}) do
        local id = (v == true) and k or v;
        if (type(id) == 'number') then ids[#ids + 1] = id; end
    end
    table.sort(ids);
    comm_send('SAB|' .. name .. '|' .. table.concat(ids, ','));
end

local STAT_KEYS = {'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR'};

local function char_stats()
    local raw = windower.packets.last_incoming(0x061);
    if (raw == nil) then return '', ''; end
    local ok, p = pcall(packets.parse, 'incoming', raw);
    local base, added = {}, {};
    for i, k in ipairs(STAT_KEYS) do
        local b = ok and p and tonumber(p['Base ' .. k]);
        local a = ok and p and tonumber(p['Added ' .. k]);
        if (b == nil) then b = raw:unpack('H', 0x14 + (i - 1) * 2 + 1) or 0; end
        if (a == nil) then a = raw:unpack('h', 0x22 + (i - 1) * 2 + 1) or 0; end
        base[i], added[i] = b, a;
    end
    return table.concat(base, ','), table.concat(added, ',');
end

local function extras_body(name)
    local p = windower.ffxi.get_player();
    if (p == nil) then return nil; end

    local jp = {};
    if (type(p.job_points) == 'table') then
        local ids = {};
        for id in pairs(res.jobs) do ids[#ids + 1] = id; end
        table.sort(ids);
        for _, id in ipairs(ids) do
            local e = p.job_points[(res.jobs[id].ens or ''):lower()];
            if (type(e) == 'table' and (tonumber(e.jp_spent) or 0) > 0) then jp[#jp + 1] = id .. '=' .. e.jp_spent; end
        end
    end

    local skills = {};
    if (type(p.skills) == 'table') then
        local keys = {};
        for k, v in pairs(p.skills) do if (type(v) == 'number') then keys[#keys + 1] = k; end end
        table.sort(keys);
        for _, k in ipairs(keys) do skills[#skills + 1] = k .. '=' .. p.skills[k]; end
    end

    local temp = {};
    local bag = windower.ffxi.get_items(3);
    if (bag ~= nil) then
        local counts, ids = {}, {};
        for slot = 1, (bag.max or 80) do
            local it = bag[slot];
            if (type(it) == 'table' and it.id ~= nil and it.id > 0) then
                if (counts[it.id] == nil) then ids[#ids + 1] = it.id; counts[it.id] = 0; end
                counts[it.id] = counts[it.id] + ((it.count ~= nil and it.count > 0) and it.count or 1);
            end
        end
        table.sort(ids);
        for _, id in ipairs(ids) do temp[#temp + 1] = id .. ':' .. counts[id]; end
    end

    local base, added = char_stats();
    return table.concat({ 'SPX', name, table.concat(jp, ','), base, added,
        table.concat(skills, ','), table.concat(temp, ',') }, '|');
end

local eqp_body, eqp_at = nil, 0;

local function equip_slot(all, eq, slot)
    local idx = eq[slot];
    if (idx == nil or idx == 0) then return 0, '', 0, 0; end
    local bag = all[eq[slot .. '_bag'] or 0];
    local it = (bag ~= nil) and bag[idx] or nil;
    if (it == nil or it.id == nil or it.id == 0) then return 0, '', 0, 0; end
    local nm, skill = '', 0;
    pcall(function()
        local o = res.items[it.id];
        if (o ~= nil) then
            nm = (o.en or o.name or ''):gsub('[^\32-\126]', ''):gsub('[;|=]', ' ');
            skill = tonumber(o.skill) or 0;
        end
    end);
    return it.id, nm, (it.count ~= nil and it.count > 0) and it.count or 1, skill;
end

local function send_equip(name, now)
    local body = nil;
    pcall(function()
        local all = windower.ffxi.get_items();
        if (all == nil or all.equipment == nil) then return; end
        local eq = all.equipment;
        local mid, mname, _, mskill = equip_slot(all, eq, 'main');
        local sid, sname = equip_slot(all, eq, 'sub');
        local rid, rname, _, rskill = equip_slot(all, eq, 'range');
        local aid, aname, acount = equip_slot(all, eq, 'ammo');
        body = string.format('EQP|%s|main=%d;mainname=%s;mainskill=%d;sub=%d;subname=%s;range=%d;rangename=%s;rangeskill=%d;ammo=%d;ammoname=%s;ammocount=%d',
            name, mid, mname, mskill, sid, sname, rid, rname, rskill, aid, aname, acount);
    end);
    if (body ~= nil and (body ~= eqp_body or now - eqp_at >= EXTRAS_HB)) then
        comm_send(body);
        eqp_body, eqp_at = body, now;
    end
end

local function send_extras(name, now)
    local body = extras_body(name);
    if (body ~= nil and (body ~= spx_body or now - spx_at >= EXTRAS_HB)) then
        comm_send(body);
        spx_body, spx_at = body, now;
    end
end

local function strip_codes(s)
    s = s:gsub('\30.', ''):gsub('\31.', ''):gsub('\127\49', ''):gsub('[\r\n]+', ' ');
    return s;
end

windower.register_event('incoming text', function(original, modified, original_mode)
    if (not comm_is_linked()) then return; end
    local name = me_name();
    if (name == nil) then return; end
    local ok, text = pcall(function()
        return windower.from_shift_jis(windower.convert_auto_trans(original or ''));
    end);
    if (not ok or text == nil) then text = original or ''; end
    text = strip_codes(text);
    if (text == '') then return; end
    comm_send('SCH|' .. name .. '|' .. tostring(original_mode or 0) .. '|' .. text:gsub('|', '/'));
end);

windower.register_event('job change', function() last_spells = 0; end);

local function reset_sent()
    spl_body, spt_body, src_body, spx_body, pet_body = nil, nil, nil, nil, nil;
    hot_sent, ent_seen = {}, {};
    last_spells, last_inv_body, last_entity_full = 0, nil, 0;
end

windower.register_event('zone change', function() reset_sent(); end);

function state_tick()
    local linked = comm_is_linked();
    if (not linked) then was_linked = false; return; end
    local name = me_name();
    if (name == nil) then return; end
    local now = os.clock();
    local epoch = comm_subscriber_epoch();
    if (not was_linked or epoch ~= sent_epoch) then was_linked = true; sent_epoch = epoch; reset_sent(); end

    if (now - last_check >= CHECK_GAP) then
        last_check = now;
        pcall(send_player, name, now);
        pcall(send_party, name, now);
    end
    if (now - last_entity_check >= ENTITY_CHECK) then
        last_entity_check = now;
        local full = (now - last_entity_full >= ENTITY_FULL);
        if (full) then last_entity_full = now; end
        pcall(send_entities, name, now, full);
    end
    if (now - last_recast_check >= RECAST_CHECK) then last_recast_check = now; pcall(send_recasts, name, now); end
    if (last_spells == 0 or now - last_spells > SPELLS_RATE) then
        last_spells = now;
        pcall(send_spells, name);
        pcall(send_abilities, name);
    end
    if (now - last_extras_check >= EXTRAS_CHECK) then last_extras_check = now; pcall(send_extras, name, now); pcall(send_equip, name, now); end
    if (now - last_inv_check > INV_CHECK) then last_inv_check = now; pcall(send_inventory, name, now); end
end
