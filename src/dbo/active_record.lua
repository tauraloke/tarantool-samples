-- base object for inheritance in ./models/{...}.lua




local object = {}
object.__index = object


-- rocket science
setmetatable(object, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:new(...)
    return self
  end,
})


-- another rocket science
-- in model file just call:
-- > local modelname = require('src.dbo'):inherit()
function object.inherit(space_name)
  local new_class = {}
  new_class._name = space_name
  new_class.__index = new_class

  setmetatable(new_class, {
    __index = object, -- this is what makes the inheritance work
    __call = function (cls, ...)
      local self = setmetatable({}, cls)
      self:new(...)
      return self
    end,
  })

  return new_class
end


-- return Tarantool space
-- model loader can associate _name for each acting model over spaces
function object:space()
  return box.space[self._name]
end


-- helper function for parsing data
function object.tomap(db_response)
  if type(db_response)=='table' then
    local res = {}
    for i, v in pairs(db_response) do
      if type(v)=='cdata' then
        res[i] = object.tomap(v)
      end
    end
    return res
  elseif type(db_response)=='cdata' then
    local cleaned_hash = db_response:tomap()
    for i,_ in pairs(cleaned_hash) do    -- clear map from digit keys for :frommap() method
      if(type(i)=='number') then cleaned_hash[i] = nil end
    end
    return cleaned_hash
  else
    return nil, 'cannot_detect_type_of_input_data'
  end
end


-- constructor
function object:new(data)
  self.data = {}
  if type(data)=='table' then self.data = table.deepcopy(data) end
  return self
end


-- return dbo object
function object:get(id, opts)
  opts = opts or {}
  local index = opts.index or 'primary'
  local space = self:space()
  if not self._name then
    return nil, 'cannot_find_anything_by_empty_space_name'
  end
  if not space then
    return nil, 'cannot_find_space_'..self._name
  end
  local result = self:space().index[index]:select(id)
  if not result or not result[1] then
    return nil, 'cannot_find_object_in_'..self._name
  end
  return self(self.tomap(result[1]))
end


-- return unparsed array of CData from DB
function object:select(value, opts)
  opts = opts or {}
  local index = opts.index or 'primary'
  opts.index = nil  -- clear for space:select()
  local space = self:space()
  if not self._name then
    return nil, 'cannot_find_anything_by_empty_space_name'
  end
  if not space then
    return nil, 'cannot_find_space_'..self._name
  end
  local result = self:space().index[index]:select(value, opts)
  if not result then
    return nil, 'cannot_find_object_in_'..self._name
  end
  return result
end


function object:count(value, opts)
  opts = opts or {}
  local index = opts.index or 'primary'
  opts.index = nil
  return self:space().index[index]:count(value, opts)
end


-- update self.data without saving
function object:update_fields(data)
  for i,v in pairs(data) do
    self.data[i] = v
  end
  return self
end



-- return object if success
-- return nil, err string, space name if common fail
-- return nil, err table if fail validation
-- err structure: { { 'string_for_translate', 'arguments_of_string' }, ... }
function object:save(without_checks)
  if not self._name then return nil, 'cannot_find_anything_by_empty_space_name' end
  local space = self:space()
  if not space then return nil, 'cannot_find_space', self._name end
  
  if not without_checks then
    if type(self.fields)~='table' then return nil, 'cannot_find_schema_for_space', self._name end
  end

  if type(self.fields)=='table' then
    for name, field in pairs(self.fields) do
      if self.data[name]==nil then
        if type(field.default)=='function' then
          self.data[name] = field.default(self)
        else
          self.data[name] = field.default
        end
      end
    end
  end

  if not without_checks then
    local _, err = self:validate()
    if err then
      return nil, err
    end
  end

  if type(self.fields)=='table' then
    for name, _ in pairs(self.data) do  -- purify data from undeclared fields before do :frommap(data)
      if self.fields[name] == nil then
        self.data[name] = nil
      end
    end
  end

  local mnull = require('msgpack').NULL
  if type(self.fields)=='table' then
    for name, _ in pairs(self.fields) do  -- see nil problem: https://github.com/tarantool/tarantool/issues/1990    use msgpack.NULL, not nil
      if self.data[name]==nil then
        self.data[name] = mnull
      end
    end
  end
  self.data = self.tomap(space:replace(space:frommap(self.data)))
  return self
end



-- return true, if success
-- return nil, err string, space name if common fail
-- return nil, {{err_for_i18n, arguments}} if fail
-- @params
---- nihilize_field_if_not_valid remove field value if it is not valid.
-- Note: for checking uniqueness name of index must be equal to name of field.
function object:validate(nihilize_field_if_not_valid)
  if not self._name then return nil, 'cannot_find_anything_by_empty_space_name' end
  local space = self:space()
  local checking_errors = {}
  if not space then return nil, 'cannot_find_space', self._name end
  for field_name, field in pairs(self.fields) do
    if type(field.before_save)=='function' then
      local check, err = field.before_save(self)
      if not check then
        table.insert(checking_errors, err)
        if nihilize_field_if_not_valid then
          self.data[field_name] = nil
        end
      end
    end
    if type(field.validations)=='table' then
      for condition, attribute in pairs(field.validations) do
        if condition=='unique' then
          attribute.self_id = self.data.id
        end
        local status, err = require('src.dbo.validate')(condition, attribute, self.data[field_name])
        if not status then
          table.insert(checking_errors, {{err, condition, field_name}})
          if nihilize_field_if_not_valid then
            self.data[field_name] = nil
          end
        end
      end
    end
    if field_name~='id' and field.is_nullable==false and self.data[field_name]==nil then
      table.insert(checking_errors, {{'error.validation.field_cannot_be_empty', field_name}})
    end
  end

  if #checking_errors > 0 and not nihilize_field_if_not_valid then
    return nil, checking_errors
  end
  return self
end



-- remove the object from db
-- but self.data is not cleared
function object:delete()
  if not self.data.id then
    return nil, 'cannot_delete_unsaved_object_from_'..self._name
  end
  return self:space():delete(self.data.id)
end



-- migration: SPACE/CREATE
-- not used after creating of migration scripts
function object:create_space_if_not_exists()
  if not self._name then error('cannot_find_anything_by_empty_space_name') end
  if self:space() then return false end
  if not self.fields then error('cannot_find_schema_for_creating') end

  -- checking for required field `id`: it must exist for primary index
  if not self.fields.id or self.fields.id.type~='unsigned' then
    error('table_should_have_field_id_of_unsigned_type')
  end

  box.once('create_space_'..self._name, function()
    box.schema.space.create(self._name, { if_not_exists = true })
    local space = self:space()
    
    local format = {}
    for name, options in pairs(self.fields) do
      table.insert(format, {
        name = name,
        type = options.type,
        is_nullable = options.is_nullable,
      })
    end
    space:format(format)

    -- always create primary index
    box.schema.sequence.create(self._name..'_sequence', { min=1, start=1 })
    space:create_index('primary', {
      type          = 'hash', 
      parts         = {'id'}, 
      sequence      = self._name..'_sequence', 
      unique        = true, 
      if_not_exists = true 
    })

    if type(self.indexes)=='table' then
      for index, index_options in pairs(self.indexes) do
        space:create_index(index, index_options)
      end
    end
  end)
end




return object
















