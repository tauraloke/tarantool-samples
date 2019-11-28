
local sessions = require('src.dbo.active_record').inherit('temporary_sessions')

sessions.fields = {
  id = { type='unsigned'},
  hash = { type='string', is_nullable=false, default=function(self)
    return require('src.helpers.common').random_string(32)
  end},
  data = { type='map', is_nullable=true },
  date_created = { type='unsigned', is_nullable=true, default=function(self)
    return require('os').time()
  end},
  date_last_activity = { type='unsigned', is_nullable=true},
}

sessions.indexes = {
  hash = { type='hash', parts={'hash'}, unique=true, if_not_exists=true },
}




return sessions