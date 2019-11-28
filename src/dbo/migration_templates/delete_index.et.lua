return {

up = function()
  local space = box.space.<%- name %>
  if space.index.<%- index_name %> then
    space.index.<%- index_name %>:drop()
  end
end,



down = function()
  local space = box.space.<%- name %>
  space:create_index('<%- index_name %>', <%- index_row %>)
end,

}
