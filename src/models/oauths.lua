
local users = require('src.dbo.active_record').inherit('oauths')

users.fields = {
  id = { type='unsigned'},
  user_id = { type='unsigned', is_nullable=false},
  provider = { type='string', is_nullable=false},  -- i.e.: deviantart
  social_id = { type='string', is_nullable=false},   -- user id in external service
  url = { type='string', is_nullable=true},   -- link to outer user page
  is_usable_for_login = { type='boolean', is_nullable=false, default=true},   -- cannot login via this record if false
  is_usable_in_profile = { type='boolean', is_nullable=false, default=true},  -- hide link in profile if false
  refresh_token = { type='string', is_nullable=true},
  access_token = { type='string', is_nullable=true},
  date_created = { type='unsigned', is_nullable=true, default=function(self)
    return require('os').time()
  end},
  date_last_activity = { type='unsigned', is_nullable=true},
}

users.indexes = {
  user_id = { type='tree', parts={'user_id'}, unique=false, if_not_exists=true },
  social = { type='tree', parts={'social_id', 'provider'}, unique=true, if_not_exists=true },
  user_n_provider = { type='tree', parts={'provider', 'user_id'}, unique=false, if_not_exists=true },
}


return users