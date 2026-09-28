local socket = require('socket');

local HOST = '127.0.0.1';
local BASE_PORT = 59332;
local PORT_COUNT = 10;
local LINK_TIMEOUT = 6.0;
local HELLO_GAP = 2.0;
local PING_GAP = 2.0;
local MAX_DRAIN = 512;

local udp        = nil;
local apps       = {};
local epoch      = 0;
local last_hello = 0;
local last_ping  = 0;
local handlers   = {};

local function cprint(s) windower.add_to_chat(207, s); end

local function my_name()
    local p = windower.ffxi.get_player();
    return (p ~= nil and p.name) or '';
end

local function send_to(port, msg)
    if (udp and msg) then pcall(function() udp:sendto(msg, HOST, port); end); end
end

function comm_init()
    udp = socket.udp();
    udp:settimeout(0);
    udp:setsockname(HOST, 0);
    apps = {};
end

function comm_shutdown()
    if (udp) then pcall(function() udp:close(); end); udp = nil; end
    apps = {};
end

function comm_register(t, fn)
    handlers[t] = fn;
end

function comm_send(msg)
    if (udp == nil or msg == nil) then return; end
    for port, _ in pairs(apps) do send_to(port, msg); end
end

function comm_is_linked()
    local now = os.clock();
    for _, a in pairs(apps) do
        if (now - a.last_rx <= LINK_TIMEOUT) then return true; end
    end
    return false;
end

function comm_subscriber_epoch() return epoch; end

function comm_apps()
    local list = {};
    for port, a in pairs(apps) do list[#list + 1] = { port = port, name = a.name }; end
    table.sort(list, function(x, y) return x.port < y.port; end);
    return list;
end

local function drop(port, why)
    local a = apps[port];
    if (a == nil) then return; end
    apps[port] = nil;
    cprint('[cortana] ' .. a.name .. ' ' .. why .. '.');
end

local function hello()
    local p = windower.ffxi.get_player();
    return 'HELLO|' .. my_name() .. '|' .. tostring((p and p.id) or 0) .. '|0|1.0|state1|'
        .. tostring(windower.windower_path or '');
end

local function handle(data, port, now)
    local parts = {};
    for w in data:gmatch('[^|]+') do parts[#parts + 1] = w; end
    local t = parts[1];
    if (t == nil) then return; end
    local a = apps[port];

    if (t == 'WELCOME') then
        if (a == nil) then
            a = { name = parts[3] or ('port ' .. port) };
            apps[port] = a;
            epoch = epoch + 1;
            cprint('[cortana] linked to ' .. a.name .. '.');
        end
        a.last_rx = now;
        return;
    end

    if (a == nil) then
        if (t ~= 'BYE' and my_name() ~= '') then send_to(port, hello()); end
        return;
    end
    a.last_rx = now;

    if (t == 'BYE') then
        drop(port, 'disconnected');
    elseif (t == 'PONG') then
    elseif (t == 'ECHO') then
        send_to(port, 'ECHOR|' .. my_name() .. '|' .. (parts[2] or '0'));
    elseif (handlers[t] ~= nil) then
        pcall(handlers[t], parts);
    end
end

function comm_tick()
    if (udp == nil) then return; end
    local now = os.clock();

    local errors = 0;
    for _ = 1, MAX_DRAIN do
        local data, ip, port = udp:receivefrom();
        if (data == nil) then
            errors = errors + 1;
            if (ip == 'timeout' or errors > PORT_COUNT) then break; end
        elseif (ip == HOST and port >= BASE_PORT and port < BASE_PORT + PORT_COUNT) then
            handle(data, port, now);
        end
    end

    for port, a in pairs(apps) do
        if (now - a.last_rx > LINK_TIMEOUT) then drop(port, 'timed out'); end
    end

    local name = my_name();
    if (name == '') then return; end

    if (now - last_hello > HELLO_GAP) then
        last_hello = now;
        local msg = hello();
        for port = BASE_PORT, BASE_PORT + PORT_COUNT - 1 do
            if (apps[port] == nil) then send_to(port, msg); end
        end
    end
    if (next(apps) ~= nil and now - last_ping > PING_GAP) then
        last_ping = now;
        comm_send('PING|' .. name);
    end
end
