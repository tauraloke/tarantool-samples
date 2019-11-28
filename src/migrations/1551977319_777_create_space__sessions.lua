return {

up = function()
  box.schema.space.create('sessions', { if_not_exists = true })
  local space = box.space.sessions
  space:format({
    {name = 'user_agent', type = 'string', is_nullable = true},
    {name = 'ip', type = 'string', is_nullable = true},
    {name = 'id', type = 'unsigned'},
    {name = 'user_id', type = 'unsigned', is_nullable = false},
    {name = 'hash', type = 'string', is_nullable = false},
    {name = 'date_last_activity', type = 'unsigned', is_nullable = true},
    {name = 'date_created', type = 'unsigned', is_nullable = true},
  })
  box.schema.sequence.create('sessions_sequence', { min=1, start=1 })
  space:create_index('primary', { type='hash', parts={'id'}, sequence='sessions_sequence', unique=true, if_not_exists=true })
  space:create_index('user_id', { type='tree', parts={ [1]='user_id' }, unique=false, if_not_exists=true })
  space:create_index('hash', { type='hash', parts={ [1]='hash' }, unique=true, if_not_exists=true })
end,



down = function()
  if box.space.sessions then
    box.space.sessions:drop()
  end
  if box.sequence.sessions_sequence then
    box.sequence.sessions_sequence:drop()
  end
end,

}
