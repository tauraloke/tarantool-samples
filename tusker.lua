#! /usr/bin/env lua

local colors = require('ansicolors')
local json   = require('cjson')
local os     = require('os')
local lfs    = require('lfs')

local config = require('src.config')

local field  = arg[1] or 'all'        -- values: ngx, tnt, all
local action = arg[2] or 'restart'    -- values: start, stop, restart, recreate
local key    = arg[3] or 'dev'        -- values: dev or prod
local tarantool_in_console = false

---------- Helpers --------------

local function say(text)
  return print(colors(text))
end

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function cmd_capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end





--------  Basic commands -------------

local command = {}

command.tnt = {}

function command.tnt.start()
  say("Tarantool is starting...")
  os.execute('tarantool ./src/app.lua server start '..key..' '..tostring(tarantool_in_console))
  if not file_exists(config.tarantool.pidfile) then
    say('%{red}[FAIL]%{reset} Tarantool server have not created pid file! May be crashed. See ./planner.lua tnt log')
    return nil
  end
  -- local plist = cmd_capture('ps aux | grep `cat '..config.tarantool.pidfile..'`')
  os.execute('sleep 2')
  if file_exists(config.tarantool.pidfile) then
    say('%{green}[OK]%{green}')
  else
    say('%{red}[FAIL]%{reset} Tarantool server have not been started! See logs.')
    return nil
  end
end

function command.tnt.stop()
  say("Tarantool is stopping...")
  if(file_exists(config.tarantool.pidfile)) then
    cmd_capture('kill -9 `cat '..config.tarantool.pidfile..'`')
    os.remove(config.tarantool.pidfile)
  else
    say("%{red}[FAIL]%{reset} Cannot find pid file of tarantool process!")
  end
end

function command.tnt.drop()
  say("Drop Tarantool data...")
  cmd_capture('rm '..config.tarantool.data_dir..'/*')
  cmd_capture('rm '..config.tarantool.logfile)
end

function command.tnt.log()
  if(file_exists(config.tarantool.logfile)) then
    say(cmd_capture('tail -n 100 ./'..config.tarantool.logfile, true))
  else
    say("%{red}[FAIL]%{reset} Tnt log file is not found!")
  end
end

function command.tnt.repl()
  os.execute('tarantoolctl connect '..config.tarantool.user..':'..
    config.tarantool.password..'@'..config.tarantool.host..':'..
    config.tarantool.port..'')
end


command.migration = {}
function command.migration.make()
  if(file_exists(config.tarantool.pidfile)) then
    say("%{red}[FAIL]%{reset} Tarantool should be stopped before migrations.")
    return false
  end
  os.execute('tarantool ./src/app.lua migration make '..key .. ' true')
end

function command.migration.up()
  if(file_exists(config.tarantool.pidfile)) then
    say("%{red}[FAIL]%{reset} Tarantool should be stopped before migrations.")
    return false
  end
  os.execute('tarantool ./src/app.lua migration up '..key .. ' true')
end

function command.migration.uptop()
  if(file_exists(config.tarantool.pidfile)) then
    say("%{red}[FAIL]%{reset} Tarantool should be stopped before migrations.")
    return false
  end
  os.execute('tarantool ./src/app.lua migration uptop '..key .. ' true')
end

function command.migration.down()
  if(file_exists(config.tarantool.pidfile)) then
    say("%{red}[FAIL]%{reset} Tarantool should be stopped before migrations.")
    return false
  end
  os.execute('tarantool ./src/app.lua migration down '..key .. ' true')
end

function command.migration.clean()
  os.execute('rm '..config.tarantool.data_dir..'/*')
  os.execute('rm -rf ./src/migrations')
end



command.ngx = {}
function  command.ngx.start()
  say("Nginx is starting...")

  local template_path = './nginx.conf.template'
  local complied_path = './nginx.conf.compiled'
  if(not file_exists(template_path)) then
    say("%{red}[FAIL]%{reset} Cannot open template in path "..template_path)
    return nil
  end

  local f = io.open(template_path, 'rb')
  local template_body = f:read('*a')
  f:close()

  local options = {
    SSL_CRT_PATH  = lfs.currentdir()..'/'..config.ssl.crt_path,
    SSL_KEY_PATH  = lfs.currentdir()..'/'..config.ssl.key_path,
    ROOT          = lfs.currentdir()..'/',
    NGINX_PORT    = config.nginx.port,
    TNT_HTTP_PORT = config.webserver.port,
    SERVER_TITLE  = config.nginx.title,
    SERVER_NAME   = config.nginx.name,
  }

  for i, v in pairs(options) do
    template_body = template_body:gsub('{{'..i..'}}', v)
  end

  f = io.open(complied_path, 'w')
  f:write(template_body)
  f:close()

  cmd_capture('sudo cp '..complied_path..' /etc/nginx/sites-enabled/'..config.nginx.conf_name)
  cmd_capture('sleep 1')
  cmd_capture('sudo nginx')

  local url = "https://"..config.nginx.name
  if(config.nginx.port ~= 443 and config.nginx.port ~= 80) then
    url = url..":"..config.nginx.port
  end
  url = url..'/'
  say("Open "..url)
end

function command.ngx.stop()
  say "Nginx is stopping..."
  cmd_capture('sudo nginx -s stop')
end

function command.ngx.log()
  say(cmd_capture('tail -n 100 /var/log/nginx/error.log', true))
end

function command.ngx.drop()
  say("Drop Nginx config at /etc/nginx/sites-enabled/"..config.nginx.conf_name.."...")
  cmd_capture('sudo rm /etc/nginx/sites-enabled/'..config.nginx.conf_name)
end



--- Configuration ---

local actions = {
  tnt = {
    start = {
      {'tnt', 'start'},
    },
    stop = {
      {'tnt', 'stop'},
    },
    drop = {
      {'tnt', 'stop'},
      {'tnt', 'drop'},
    },
    restart = {
      {'tnt', 'stop'},
      {'tnt', 'start'},
    },
    recreate = {
      {'tnt', 'stop'},
      {'tnt', 'drop'},
      {'migration', 'clean'},
      {'migration', 'make'},
      {'migration', 'uptop'},
      {'tnt', 'start'},
    },
    log = {
      {'tnt', 'log'},
    },
    repl = {
      {'tnt', 'repl'},
    },
  },
  ngx = {
    start = {
      {'ngx', 'start'},
    },
    stop = {
      {'ngx', 'stop'},
    },
    drop = {
      {'ngx', 'stop'},
      {'ngx', 'drop'},
    },
    restart = {
      {'ngx', 'stop'},
      {'ngx', 'start'},
    },
    log = {
      {'ngx', 'log'},
    },
  },
  all = {
    start = {
      {'ngx', 'start'},
      {'tnt', 'start'},
    },
    stop = {
      {'tnt', 'stop'},
      {'ngx', 'stop'},
    },
    restart = {
      {'ngx', 'stop'},
      {'tnt', 'stop'},
      {'ngx', 'start'},
      {'tnt', 'start'},
    },
    recreate = {
      {'ngx', 'stop'},
      {'tnt', 'stop'},
      {'tnt', 'drop'},
      {'ngx', 'start'},
      {'tnt', 'start'},
    },
  },
  migration = {
    make = {
      {'migration', 'make'},
    },
    up = {
      {'migration', 'up'},
    },
    down = {
      {'migration', 'down'},
    },
    clean = {
      {'tnt', 'stop'},
      {'migration', 'clean'},
    },
  }
}




------------ Executing --------------

if(key=='d') then
  key = 'dev'
  tarantool_in_console = true
end

if(config[key]) then
  config = config[key]
else
  say('%{red}[FAIL]%{reset} Cannot find config by key ' .. json.encode(key))
  return false
end

local function main(_commands, _actions, _field, _action)
  local keys
  if not _actions[_field] then
    keys = {}
    for i, _ in pairs(_actions) do
      table.insert(keys, i)
    end
    say("%{red}[FAIL]%{reset} Unknown field. List of possible fields: "..table.concat(keys, ', '))
    return nil
  end
  if type(_actions[_field][_action]) ~= 'table' then
    keys = {}
    for i, _ in pairs(_actions[_field]) do
      table.insert(keys, i)
    end
    say("%{red}[FAIL]%{reset} Unknown action. List of possible actions in ".._field..": "..table.concat(keys, ', '))
    return nil
  end
  for _, v in pairs(_actions[_field][_action]) do
    say("%{bright}[~]%{reset} "..v[1].."#"..v[2])
    if not v[1] or not v[2] then
      say("%{red}[FAIL]%{reset} Invalid format in command ".._field.."#".._action)
      return nil
    end
    if not _commands[v[1]] or type(_commands[v[1]][v[2]])~='function' then
      say("%{red}[FAIL]%{reset} Unknown command in ".._field.."#".._action)
      return nil
    end
    _commands[v[1]][v[2]]()
  end
end



--- Entry point ---
main(command, actions, field, action)



