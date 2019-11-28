return {

up = function()
  box.schema.space.create('oauths', { if_not_exists = true })
  local space = box.space.oauths
  space:format({
    {name = 'date_created', type = 'unsigned', is_nullable = true},
    {name = 'social_id', type = 'string', is_nullable = false},
    {name = 'id', type = 'unsigned'},
    {name = 'is_usable_in_profile', type = 'boolean', is_nullable = false},
    {name = 'date_last_activity', type = 'unsigned', is_nullable = true},
    {name = 'refresh_token', type = 'string', is_nullable = true},
    {name = 'is_usable_for_login', type = 'boolean', is_nullable = false},
    {name = 'user_id', type = 'unsigned', is_nullable = false},
    {name = 'access_token', type = 'string', is_nullable = true},
    {name = 'provider', type = 'string', is_nullable = false},
    {name = 'url', type = 'string', is_nullable = true},
  })
  box.schema.sequence.create('oauths_sequence', { min=1, start=1 })
  space:create_index('primary', { type='hash', parts={'id'}, sequence='oauths_sequence', unique=true, if_not_exists=true })
  space:create_index('user_id', { type='tree', parts={ [1]='user_id' }, unique=false, if_not_exists=true })
  space:create_index('social', { type='tree', parts={ [1]='social_id', [2]='provider' }, unique=true, if_not_exists=true })
  space:create_index('user_n_provider', { type='tree', parts={ [1]='provider', [2]='user_id' }, unique=false, if_not_exists=true })
end,



down = function()
  if box.space.oauths then
    box.space.oauths:drop()
  end
  if box.sequence.oauths_sequence then
    box.sequence.oauths_sequence:drop()
  end
end,

}
