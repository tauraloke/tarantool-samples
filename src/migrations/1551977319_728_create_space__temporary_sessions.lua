return {

up = function()
  box.schema.space.create('temporary_sessions', { if_not_exists = true })
  local space = box.space.temporary_sessions
  space:format({
    {name = 'date_created', type = 'unsigned', is_nullable = true},
    {name = 'data', type = 'map', is_nullable = true},
    {name = 'id', type = 'unsigned'},
    {name = 'hash', type = 'string', is_nullable = false},
    {name = 'date_last_activity', type = 'unsigned', is_nullable = true},
  })
  box.schema.sequence.create('temporary_sessions_sequence', { min=1, start=1 })
  space:create_index('primary', { type='hash', parts={'id'}, sequence='temporary_sessions_sequence', unique=true, if_not_exists=true })
  space:create_index('hash', { type='hash', parts={ [1]='hash' }, unique=true, if_not_exists=true })
end,



down = function()
  if box.space.temporary_sessions then
    box.space.temporary_sessions:drop()
  end
  if box.sequence.temporary_sessions_sequence then
    box.sequence.temporary_sessions_sequence:drop()
  end
end,

}
