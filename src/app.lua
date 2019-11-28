#!/usr/bin/env tarantool

os      = require('os')
crypto  = require('crypto')
msgpack = require('msgpack')
colors  = require('ansicolors')
json    = require('json')
lfs     = require('lfs')

config  = require('src.config')

mmdb_geodb = assert(require('mmdb').read("./geoip/GeoLite2-City.mmdb"))



local field      = arg[1]  -- server start env | migration make/up/down env
local command    = arg[2]
local key        = arg[3]
local in_console = arg[4] -- to daemonize or not


if(config[key]) then
  config = config[key]
else
  print(colors('%{red}[FAIL]%{reset} Cannot find config by key ' .. json.encode(key)))
  return false
end

if(in_console == 'true') then
  config.tarantool.is_daemon = true
end




-- Configure database
box.cfg {
   listen     = config.tarantool.port,
   background = not config.tarantool.is_daemon,
   log_level  = config.tarantool.log_level,
   work_dir   = './',
   wal_dir    = config.tarantool.data_dir,
   memtx_dir  = config.tarantool.data_dir,
   log        = config.tarantool.logfile,
   pid_file   = config.tarantool.pidfile,
}
-- end of config segment



-- basic part: grant
-- need grant access very early for executing other code
box.once('grant_access_for_user', function()-- todo: вынести пароль и ник юзера в переменные окружения
  box.schema.user.create(config.tarantool.user, {password=config.tarantool.password})
  box.schema.user.grant(config.tarantool.user, 'read,write,execute,create,drop,alter,usage,session', 'universe')
end)

box.session.su(config.tarantool.user)




if field=='migration' then
  dbo = require('src.dbo.manager')
  dbo:load_models()
  if command=='make' then
    dbo:make_migration()
  elseif command=='up' then
    dbo:migrate_up()
  elseif command=='uptop' then
    dbo:migrate_uptop()
  elseif command=='down' then
    dbo:migrate_down()
  end
  os.exit()
  return
end




dbo = require('src.dbo.manager')
dbo:load_models()




---  Seeding ---

if(key=='dev') then
  box.once('seed_some_users', function()
    dbo.users{login='admin@localhost', username='Администратор', pwd='secret', domain_name="admin"}:save(1)
    dbo.users{login='user@localhost', username='User', pwd='user', domain_name='user_the_cool'}:save(1)
    dbo.users{login='Юзарь@localhost', username='Юзарь', pwd='user', domain_name='Юзарь ъЖслое', is_activated=true}:save(1)
  end)
end





--- Web server ---

require('src.webserver')




local fiber   = require('fiber')
fiber.create(function()
    fiber.name('Cleaner for temporary sessions')
    while true do
        for _, v in box.space.temporary_sessions:pairs() do
            local date_last_activity = v.date_last_activity
            if date_last_activity==nil then
                date_last_activity = 0
            end
            if os.time() - date_last_activity > config.temporary_sessions.lifetime then
                box.space.temporary_sessions:delete(v.id)
            end
        end
        fiber.sleep(config.temporary_sessions.check_freq)
    end
end)







