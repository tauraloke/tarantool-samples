
local sessions = require('src.dbo.active_record').inherit('sessions')

sessions.fields = {
  id = { type='unsigned'},
  hash = { type='string', is_nullable=false, default=function(self)
    return require('src.helpers.common').random_string(32)
  end},
  user_id = { type='unsigned', is_nullable=false},
  user_agent = { type='string', is_nullable=true, default='console'},
  ip = { type='string', is_nullable=true, default='127.0.0.1'},
  date_created = { type='unsigned', is_nullable=true, default=function(self)
    return require('os').time()
  end},
  date_last_activity = { type='unsigned', is_nullable=true},
}

sessions.indexes = {
  hash = { type='hash', parts={'hash'}, unique=true, if_not_exists=true },
  user_id = { type='tree', parts={'user_id'}, unique=false, if_not_exists=true },
}




return sessions