

local dbo = {}
dbo.__index = dbo
dbo.migrations = require('src.dbo.active_record').inherit('migrations')


function dbo:load_models()
  for file in lfs.dir[[./src/models/]] do
    local filename = file:match('(.*).lua')
    if(filename) then
      self[filename] = require('src.models.'..filename)
    end
  end
end



function dbo:create_spaces_if_not_exists()
  for _, model in pairs(self) do
    if type(model)=='table' and model.create_space_if_not_exists then
      model:create_space_if_not_exists()
    end
  end
end



function dbo:create_migration(name, code)
  local filename = '' .. require('os').time() .. '_' .. math.random(100,999) .. '_' .. name
  local dirpath = './src/migrations/'
  local path =  dirpath .. filename .. '.lua'
  if not require('lfs').touch(filename) then
    lfs.mkdir(dirpath)
  end
  local file = io.open(path, 'wb')
  print(require('ansicolors')('%{green}[+]%{reset} Create migration file '..path))
  file:write(code)
  file:close()
  dbo.migrations{name=filename, is_current=false, date_created=os.time()}:save(true)
end


function dbo:to_line(data, quotes)
  quotes = quotes or "'"
  local t = type(data)
  if t=='string' then
    return quotes .. data .. quotes
  elseif t=='boolean' then
    return tostring(data)
  elseif t=='number' then
    return tostring(data)
  elseif t=='table' then
    local res = '{ '
    local chunks = {}
    for i,v in pairs(data) do
      local parsed_i = -1
      if type(i) == 'number' then
        parsed_i = "["..tostring(i).."]"
      elseif type(i) == 'string' then
        if i:match('[^%w_]') then
          parsed_i = "['"..i.."']"
        else
          parsed_i = i
        end
      end
      if type(v) == 'function' then
        parsed_i = -1
      end
      if parsed_i ~= -1 then
        table.insert(chunks, parsed_i..'='..(self:to_line(v, quotes)))
      end
    end
    res = res .. table.concat(chunks, ', ')
    res = res .. ' }'
    return res
  end
  return data
end



function dbo:field_to_line(name, opts)
  local row = ''
  row = row .. "{name = '"..name.."'"
  for i, value in pairs(opts) do
    if i=='is_nullable' or i=='type' then
      row = row .. ", "..i.." = "..self:to_line(value)
    end
  end
  row = row .. "}"
  return row
end



function dbo:parse_template(path, vars)
  vars = vars or {}
  local file = io.open(path, 'r*')
  local tpl = file:read('a*')
  file:close()
  local template = require('etlua').compile(tpl)
  return template(vars)
end



function dbo:generate_code_for_create_space(model)
  local vars = {}
  vars.name = model._name
  vars.fields = {}
  for name, opts in pairs(model.fields) do
    table.insert(vars.fields, dbo:field_to_line(name, opts)..',')
  end
  vars.indexes = {}
  for index, opts in pairs(model.indexes) do
    table.insert(vars.indexes, "space:create_index('"..index.."', "..self:to_line(opts)..")")
  end

  return self:parse_template('./src/dbo/migration_templates/create_space.et.lua', vars)
end



function dbo:generate_code_for_create_field(space_name, field_name, field_options)
  local vars = {}
  vars.name = space_name
  vars.field_name = field_name
  vars.field_row = dbo:field_to_line(field_name, field_options)
  return self:parse_template('./src/dbo/migration_templates/add_field.et.lua', vars)
end



function dbo:generate_code_for_delete_field(space_name, field_name, field_options)
  local vars = {}
  vars.name = space_name
  vars.field_name = field_name
  vars.field_row = dbo:field_to_line(field_name, field_options)
  return self:parse_template('./src/dbo/migration_templates/delete_field.et.lua', vars)
end



function dbo:generate_code_for_create_index(space_name, index_name, index_options)
  local vars = {}
  vars.name = space_name
  vars.index_name = index_name
  vars.index_row = dbo:to_line(index_options)
  return self:parse_template('./src/dbo/migration_templates/add_index.et.lua', vars)
end



function dbo:generate_code_for_delete_index(space_name, index_name, index_options)
  local vars = {}
  vars.name = space_name
  vars.index_name = index_name
  index_options.id = nil  -- purify before serialize
  index_options.space_id = nil
  index_options.name = nil
  local fields = box.space[space_name]:format()
  local new_parts = {}
  for i,v in pairs(index_options.parts) do
    table.insert(new_parts, fields[v.fieldno].name)
  end
  index_options.parts = new_parts
  vars.index_row = dbo:to_line(index_options)
  return self:parse_template('./src/dbo/migration_templates/delete_index.et.lua', vars)
end



function dbo:make_migration()
  if not box.space.migrations then
    print(require('ansicolors')('%{green}[+]%{reset} Create space migrations'))
    box.once('create_space_migrations', function()
      box.schema.space.create('migrations', { if_not_exists = true })
      local space = box.space.migrations
      space:format({
        {name='id', type='unsigned'},
        {name='name', type='string', is_nullable=false},
        {name='is_current', type='boolean', is_nullable=false},
        {name='date_created', type='unsigned', is_nullable=false},
      })
      box.schema.sequence.create('migratons_sequence', { min=1, start=1 })
      space:create_index('primary', { type='tree', parts={'id'}, sequence='migratons_sequence', unique=true, if_not_exists=true })
      space:create_index('is_current', { type='tree', parts={'is_current'}, unique=false, if_not_exists=true })
    end)
  else
    -- checking for any migratons upon current one.
    local m = dbo.migrations
    local current_migration = m:select(true, {index='is_current', limit=1})
    if current_migration[1] then
      if m:count(current_migration[1].id, {iterator='GT', limit=1}) > 0 then
        local msg = 'Cannot create migration if current one is not on top of list. You can migrate to top or delete upper migrations by command.'
        print(require('ansicolors')('%{red}[FAIL]%{reset} '..msg))
        return nil, msg
      else
        -- no upper migrations, all ok
      end
    else
      if m:count() > 0 then
        local msg = 'Cannot create migration if current one is on bottom of list. You can migrate to top or delete upper migrations by command.'
        print(require('ansicolors')('%{red}[FAIL]%{reset} '..msg))
        return nil, msg
      else
        -- no migrations, no problems.
      end
    end
  end

  local is_touched = false
  for name, model in pairs(self) do
    if type(model)=='table' and name~='migrations' then
      if model.space and not model:space() then
        self:create_migration('create_space__'..name, self:generate_code_for_create_space(model))
        is_touched = true
      end

      --[[  do not want
      if not model.space and model:space() then
        self:create_migration('delete_space_'..name, self:generate_code_for_drop_space(model))
        is_touched = true
      end
      --]]

      if model.space and model:space() then
        -- checking indexes
        local schema_indexes = model.indexes
        local db_indexes = model:space().index
        
        for i,v in pairs(schema_indexes) do
          if db_indexes[i]==nil then
            self:create_migration('create_index__'..i..'__in__'..name, self:generate_code_for_create_index(name, i, v))
            is_touched = true
          end
        end
        
        for i,v in pairs(db_indexes) do
          if schema_indexes[i]==nil and type(i)~='number' and i~='primary' then
            self:create_migration('delete_index__'..i..'__in__'..name, self:generate_code_for_delete_index(name, i, v))
            is_touched = true
          end
        end
        -- end of checking indexes
        
        -- checking fields
        local schema_fields = model.fields   -- from schema in /models/...
        local space_format = model:space():format()   -- from database
        local db_fields = {}
        for i,v in pairs(space_format) do   -- for more pretty format...
          db_fields[v.name] = v 
        end

        for i,v in pairs(schema_fields) do
          if db_fields[i]==nil then
            self:create_migration('create_field__'..i..'__in__'..name, self:generate_code_for_create_field(name, i, v))
            is_touched = true
          end
        end

        for i,v in pairs(db_fields) do
          if schema_fields[i]==nil then
            self:create_migration('delete_field__'..i..'__in__'..name, self:generate_code_for_delete_field(name, i, v))
            is_touched = true
          end
        end
        -- end of checking fields
      end

    end 
  end

  if not is_touched then
    local msg = 'No change have been found. No migration have been created.'
    print(require('ansicolors')('%{bright}[x]%{reset} '..msg))
    return nil, msg
  end
  return true
end



function dbo:execute_migration(filename, action)
  if not filename then
    return nil, 'Cannot upload migration by nil'
  end
  print(require('ansicolors')('%{bright}[~]%{reset} Execute migration '..filename..'#'..action))
  local migration = require('src.migrations.'..filename)
  if type(migration[action])~='function' then
    local msg = 'Cannot find action "'..action..'" in migration file '..filename..'.lua'
    print(require('ansicolors')('%{red}[FAIL]%{reset} '..msg))
    return nil, msg
  end
  migration[action]()
  return true
end



function dbo:migrate_up()
  local m = dbo.migrations
  local current_migration = m:select(true, {index='is_current', limit=1})
  if current_migration[1] then
    local next_migration = m:select(current_migration[1].id, {iterator='GT', limit=1})
    if next_migration[1] then
      local status, msg = self:execute_migration(next_migration[1].name, 'up')
      if not status then
        return nil, msg
      end
      m(m.tomap(current_migration[1])):update_fields{is_current=false}:save(true)
      m(m.tomap(next_migration[1])):update_fields{is_current=true}:save(true)
      return true
    else
      local msg = 'Current migration already lay on top.'
      print(require('ansicolors')('%{bright}[!]%{reset} '..msg))
      return nil, msg
    end
  else
    local next_migration = m:select(0, {iterator='GT', limit=1})
    if next_migration[1] then
      local status, msg = self:execute_migration(next_migration[1].name, 'up')
      if not status then
       return nil, msg
      end
      m(m.tomap(next_migration[1])):update_fields{is_current=true}:save(true)
    else
      local msg = 'Cannot find any migrations in space'
      print(require('ansicolors')('%{red}[FAIL]%{reset} '..msg))
      return nil, msg
    end
  end

  return true
end



function dbo:migrate_uptop()
  local limiter = 10000
  while limiter>0 do
    limiter = limiter - 1
    if not self:migrate_up() then
      break
    end
  end
end



function dbo:migrate_down()
  local m = dbo.migrations
  local current_migration = m:select(true, {index='is_current', limit=1})
  if current_migration[1] then
    local prev_migration = m:select(current_migration[1].id, {iterator='LT', limit=1})
    if prev_migration[1] then
      local status, msg = self:execute_migration(current_migration[1].name, 'down')
      if not status then
        return nil, msg
      end
      m(m.tomap(current_migration[1])):update_fields{is_current=false}:save(true)
      m(m.tomap(prev_migration[1])):update_fields{is_current=true}:save(true)
    else
      local status, msg = self:execute_migration(current_migration[1].name, 'down')
      if not status then
        return nil, msg
      end
      m(m.tomap(current_migration[1])):update_fields{is_current=false}:save(true)
    end
  else
    local msg = 'Cannot find any current migration. Check your spaces and try to migrate up.'
    print(require('ansicolors')('%{red}[FAIL]%{reset} '..msg))
    return nil, msg
  end
  return true
end




return dbo












