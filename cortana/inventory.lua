local res_items = nil;

function build_inventory_body()
    local bag = windower.ffxi.get_items(0);
    if (bag == nil) then return '', 0, 0; end

    local parts = {};
    local max = bag.max or 80;
    for slot = 1, max do
        local it = bag[slot];
        if (type(it) == 'table' and it.id ~= nil and it.id > 0) then
            local count = (it.count ~= nil and it.count > 0) and it.count or 1;
            parts[#parts + 1] = string.format('%d:%d:%d', slot, it.id, count);
        end
    end
    return table.concat(parts, ','), #parts, max;
end

function cortana_send_inventory()
    local pl = windower.ffxi.get_player();
    if (pl == nil or pl.name == nil or pl.name == '') then return 0; end

    local body, n = build_inventory_body();
    comm_send('INV|' .. pl.name .. '|' .. body);
    return n;
end

comm_register('GETINV', function(parts)
    cortana_send_inventory();
end);

function cortana_print_inventory()
    local bag = windower.ffxi.get_items(0);
    if (bag == nil) then windower.add_to_chat(207, '[cortana] inventory not available.'); return; end
    if (res_items == nil) then
        local ok, res = pcall(require, 'resources');
        if (ok and res ~= nil) then res_items = res.items; end
    end

    local shown = 0;
    local max = bag.max or 80;
    for slot = 1, max do
        local it = bag[slot];
        if (type(it) == 'table' and it.id ~= nil and it.id > 0) then
            local name = '#' .. tostring(it.id);
            if (res_items ~= nil and res_items[it.id] ~= nil) then name = res_items[it.id].name; end
            local count = (it.count ~= nil and it.count > 0) and it.count or 1;
            if (count > 1) then
                windower.add_to_chat(207, string.format('[cortana] inv: %s [%d]', name, count));
            else
                windower.add_to_chat(207, string.format('[cortana] inv: %s', name));
            end
            shown = shown + 1;
        end
    end

    local sent = cortana_send_inventory();
    windower.add_to_chat(207, string.format('[cortana] Inventory: %d item(s) -> CortanaXIHealer (%d sent).', shown, sent));
end
