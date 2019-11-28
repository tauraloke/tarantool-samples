return {

up = function()
  local space = box.space.<%- name %>
  local fields = table.deepcopy(space:format())
  table.insert(fields, <%- field_row %>)
  local temp_space_name = "<%- name %>___"..math.random(100,999)
  box.schema.space.create(temp_space_name, { if_not_exists = true })
  local temp_space = box.space[temp_space_name]
  temp_space:format(fields)

  temp_space:create_index('primary', { type='hash', parts={'id'}, sequence='<%- name %>_sequence', unique=true, if_not_exists=true })
  for i,v in pairs(dbo.<%- name %>.indexes) do
    temp_space:create_index(i, v)
  end

  for _,v in space:pairs() do
    local record = dbo.<%- name %>(dbo.<%- name %>.tomap(v))
    local default = record.fields.<%- field_name %>.default
    if type(default) == 'function' then
      default = default(record)
    end
    record.data.<%- field_name %> = default
    temp_space:insert(temp_space:frommap(record.data))
  end

  space:drop()
  temp_space:rename("<%- name %>")
end,



down = function()
  local space = box.space.<%- name %>
  local fields = table.deepcopy(space:format())
  for i,v in pairs(fields) do
    if v.name == "<%- field_name %>" then
      fields[i] = nil
    end
  end
  local temp_space_name = "<%- name %>___"..math.random(100,999)
  box.schema.space.create(temp_space_name, { if_not_exists = true })
  local temp_space = box.space[temp_space_name]
  temp_space:format(fields)

  temp_space:create_index('primary', { type='hash', parts={'id'}, sequence='<%- name %>_sequence', unique=true, if_not_exists=true })
  for i,v in pairs(dbo.<%- name %>.indexes) do
    temp_space:create_index(i, v)
  end

  for _,v in space:pairs() do
    local data = dbo.<%- name %>.tomap(v)
    data.<%- field_name %> = nil
    temp_space:insert(temp_space:frommap(data))
  end

  space:drop()
  temp_space:rename("<%- name %>")
end,

}
