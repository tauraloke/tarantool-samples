
return {


locale = function(request)
  local response = request:redirect_to('#restored_path')
  request.httpd.i18n.lib.setLocale(request:param('lang'))
  request.cookie_locale_changed = true
  return response
end,


home = function(request)

  local users_mapped = {}
  for _, v in box.space.users:pairs() do
    table.insert(users_mapped, require('src.dbo.active_record').tomap(v))
  end

  local mapped_sessions = {}
  for _, v in box.space.sessions:pairs() do
    table.insert(mapped_sessions, require('src.dbo.active_record').tomap(v))
  end

  local mapped_osessions = {}
  for _, v in box.space.oauths:pairs() do
    table.insert(mapped_osessions, require('src.dbo.active_record').tomap(v))
  end

  local mapped_tsessions = {}
  for _, v in box.space.temporary_sessions:pairs() do
    table.insert(mapped_tsessions, require('src.dbo.active_record').tomap(v))
  end

  request.page_title = 'Ururu'
  local response = request:render({
    users = users_mapped,
    sessions = mapped_sessions,
    osessions = mapped_osessions,
    tsessions = mapped_tsessions,
  })

  return response
end,


upload = function(request)


  local body = ''
  if(request.method=='POST') then
      local fff = request:post_param('secundus')
      if fff and fff.filename then 
        body = body .. fff.filename .. '<br>'
      end
      local fff = request:post_param('wakaru')
      if fff then 
        body = body .. fff .. '<br>'
      end
      --[[
                        file = io.open('./tmph/'..request:post_param('secundus').filename, 'w*')
                        file:write(request:post_param('secundus').file)
                        file:close()
      --]]
      
  end      
  request.page_title = 'Ороро'
  local response = request:render()
  response.body = body .. response.body 
  return response
end,

}









