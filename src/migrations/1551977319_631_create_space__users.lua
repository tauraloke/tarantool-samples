return {

up = function()
  box.schema.space.create('users', { if_not_exists = true })
  local space = box.space.users
  space:format({
    {name = 'date_created', type = 'unsigned', is_nullable = true},
    {name = 'salt', type = 'string', is_nullable = true},
    {name = 'date_last_login', type = 'unsigned', is_nullable = true},
    {name = 'id', type = 'unsigned'},
    {name = 'avatar_url', type = 'string', is_nullable = true},
    {name = 'verification_code', type = 'string', is_nullable = true},
    {name = 'date_last_visited', type = 'unsigned', is_nullable = true},
    {name = 'is_activated', type = 'boolean', is_nullable = false},
    {name = 'invited_by_user_id', type = 'unsigned', is_nullable = true},
    {name = 'login', type = 'string', is_nullable = true},
    {name = 'username', type = 'string', is_nullable = false},
    {name = 'pwd', type = 'string', is_nullable = true},
    {name = 'domain_name', type = 'string', is_nullable = true},
  })
  box.schema.sequence.create('users_sequence', { min=1, start=1 })
  space:create_index('primary', { type='hash', parts={'id'}, sequence='users_sequence', unique=true, if_not_exists=true })
  space:create_index('verification_code', { type='tree', parts={ [1]='verification_code' }, unique=false, if_not_exists=true })
  space:create_index('login', { type='tree', parts={ [1]='login' }, unique=false, if_not_exists=true })
  space:create_index('domain_name', { type='tree', parts={ [1]='domain_name' }, unique=false, if_not_exists=true })
end,



down = function()
  if box.space.users then
    box.space.users:drop()
  end
  if box.sequence.users_sequence then
    box.sequence.users_sequence:drop()
  end
end,

}
