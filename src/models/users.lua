
local users = require('src.dbo.active_record').inherit('users')

users.fields = {
  id = { type='unsigned' },
  login = { type='string', is_nullable=true, validations={
    unique  = {model=users, index='login'},
    type    = 'string',
    min     = '4',
    max     = '64',
    pattern = "^[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+$",
  }, --[[ before_save=function(self)   -- not used after creating validation ways
    if self.data.id==nil and self:count(self.data.login, {index='logins'}) > 0 then
      return nil, {'already_occupied', 'login'}
    end
    return true
  end--]]},
  pwd = { type='string', is_nullable=true },
  salt = { type='string', is_nullable=true, default=function(self)
    if self.data.pwd~=nil and self.data.salt==nil then
      self.data.salt = require('src.helpers.common').random_string(8)
      self.data.pwd = require('crypto').digest.sha256(self.data.pwd .. self.data.salt)
    end
    return self.data.salt
  end},
  date_created = { type='unsigned', is_nullable=true, default = function(self)
    return require('os').time()
  end},
  date_last_login = { type='unsigned', is_nullable=true },
  username = { type='string', is_nullable=false, validations = {
    type   = "string",
    exists = true,
    min = 5,
    max = 30,
  }},
  avatar_url = { type='string', is_nullable=true},
  domain_name = { type='string', is_nullable=true, validations = {
    unique  = {model=users, index='domain_name'},
    type    = 'string',
    min     = 3,
    max     = 32,
    pattern = "^[%w_]+$",
  }},
  is_activated = { type='boolean', is_nullable=false, default=false},
  invited_by_user_id = { type='unsigned', is_nullable=true},
  verification_code = { type='string', is_nullable=true},
  date_last_visited = { type='unsigned', is_nullable=true},
}

users.indexes = {
  login = { type='tree', parts={'login'}, unique=false, if_not_exists=true },
  domain_name = { type='tree', parts={'domain_name'}, unique=false, if_not_exists=true },
  verification_code = { type='tree', parts={'verification_code'}, unique=false, if_not_exists=true },
}


-- usage: dbo.users:login('user-agent', '8.8.8.8', 'login', 'pwd')
function users:login(user_agent, ip, login, pwd)
  if not login then
    return nil, 'error.login.cannot_login_via_nil'
  end
  if not pwd then
      return nil, 'error.login.cannot_login_via_empty_password'
  end
  local user = self:select(login, {index='login'})
  if not user[1] then
    return nil, 'error.login.cannot_login_via_unmatching_login'
  end
  user = self(self.tomap(user[1]))
  if user.data.pwd ~= require('crypto').digest.sha256(pwd .. user.data.salt) then
    return nil, 'error.login.cannot_login_via_unmatching_password'
  end
  if not user.data.is_activated then
    return user, 'error.login.cannot_login_to_inactived_account'  -- sic! See ./src/controllers/user.lua#login
  end
  if err then
    return nil, err
  end
  return user:start_session(user_agent, ip)
end


-- usage: user_obj:start_session('user-agent', '8.8.8.8')
function users:start_session(user_agent, ip)
  if not self.data or not self.data.id then
    return nil, 'cannot_start_session_via_with_nil_user_id'
  end
  box.begin()
  local ctime = require('os').time()
  local _, err = self:update_fields{
    date_last_visited    = ctime,
    date_last_login = ctime,
  }:save()
  if err then
    box.rollback()
    return nil, err
  end
  local session, err = require('src.models.sessions'){
    user_id    = self.data.id, 
    user_agent = user_agent, 
    date_last_activity = ctime,
    ip        = ip,
  }:save()
  if err then
    box.rollback()
    return nil, err
  end
  self.session = session
  box.commit()
  return self
end



-- usage: user_obj:logout()
function users:logout()
  if not self.session then
    return nil, 'cannot_logout_session_is_not_found'
  end
  if not self.session.data.user_id and self.data.id then
    return nil, 'cannot_logout_user_id_does_not_match'
  end
  self.session:delete()
  return true
end



--  usage: dbo.users:auth(12, 'fdghthgrt5d')
function users:auth(session_hash)
  if not session_hash then
    return nil, 'cannot_auth_session_hash_is_empty'
  end
  local session, err = require('src.models.sessions'):get(session_hash, {index='hash'})
  if not session then
    return nil, err
  end
  local user, err = self:get(session.data.user_id)
  if not user then
    return nil, err
  end
  if user.data.id ~= session.data.user_id then
    return nil, 'cannot_login_via_nonmatching_user_id'
  end
  user.session = session
  local ctime = require('os').time()
  user:update_fields{
    date_last_visited = ctime,
  }:save()
  session:update_fields{
    date_last_activity = ctime,
  }:save()
  return user
end



-- usage: dbo.users:verify('fdfdfd')
function users:verify(verification_code)
  if verification_code == nil then
    return nil, 'error.wrong_request'
  end
  local user, err = self:get(verification_code, {index='verification_code'})
  if not user then
    return nil, err
  end
  user:update_fields{ verification_code=require('msgpack').NULL, is_activated=true }:save()
  return user
end



-- usage: user_obj:remove_sessions_except_current()
function users:remove_sessions_except_current()
  local sessions = require('src.models.sessions'):space()
  local success = true
  for _,v in sessions.index.user_id:pairs(self.data.id) do
    if v.id ~= self.session.data.id then
      if not sessions:delete(v.id) then
        success = false
      end
    end
  end
  return success
end



function users:delayed_upload_avatar(url)
  local fiber = require('fiber')
  fiber.create(function()
    fiber.name('Download avatar for'..self.data.id)
    local localpath, err = require('src.helpers.common').download_image_for_user(url, self.data.id)
    if not err then
      localpath = '/'..localpath:gsub('^static', 'resize_50x50')
      self:update_fields{
        avatar_url = localpath,
      }:save()
    end
  end)
end



return users















