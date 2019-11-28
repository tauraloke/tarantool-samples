return {

up = function()
  box.schema.space.create('<%- name %>', { if_not_exists = true })
  local space = box.space.<%- name %>
  space:format({<% for _, field in pairs(fields) do %>
    <%- field %><% end %>
  })
  box.schema.sequence.create('<%- name %>_sequence', { min=1, start=1 })
  space:create_index('primary', { type='hash', parts={'id'}, sequence='<%- name %>_sequence', unique=true, if_not_exists=true })<% for _, index in pairs(indexes) do %>
  <%- index %><% end %>
end,



down = function()
  if box.space.<%- name %> then
    box.space.<%- name %>:drop()
  end
  if box.sequence.<%- name %>_sequence then
    box.sequence.<%- name %>_sequence:drop()
  end
end,

}
