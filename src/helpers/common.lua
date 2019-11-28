


local helper = {}

function helper.random_string(length)
  local result = ""
  math.randomseed(require('os').time() + math.random(1000))
  for _ = 1, length do
    result = result .. string.char(math.random(97, 122))
  end
  return result
end


function helper.send_mail(to, subj, message)
  client = require('smtp').new()
  return client:request("smtp://"..config.mail.connect_options.host..":"..config.mail.connect_options.port.."",
          config.mail.system_address,to,message,{
            timeout = 2,
            content_type = 'text/html',
            subject = subj,
          })
end


function helper.uri_escape(str)
  local res = {}
  if type(str) == 'table' then
    for _, v in pairs(str) do
      table.insert(res, uri_escape(v))
    end
  else
    res = string.gsub(str, '[^a-zA-Z0-9_]',
            function(c)
              return string.format('%%%02X', string.byte(c))
            end
    )
  end
  return res
end


function helper.table_to_query(the_table)
  endsymbol = endsymbol or ''
  if type(the_table)~='table' then
    return tostring(the_table)
  end
  local queries = {}
  for i,v in pairs(the_table) do
    table.insert(queries, helper.uri_escape(i)..'='..helper.uri_escape(v))
  end
  return table.concat(queries, '&')
end


function helper.rest_call(url, method, arguments, bearer)
  local http_client = require('http.client').new({max_connections = 5})
  local body = ''
  if method=='GET' then
    url = url .. '?' .. helper.table_to_query(arguments)
  elseif method=='POST' then
    if arguments and url:match('googleapis%.com') then
      local queries = {}
      for i,v in pairs(arguments) do
        table.insert(queries, i..'='..v)
      end
      body = table.concat(queries, '&')
    else
      body = helper.table_to_query(arguments)
    end
  end
  local headers = {["Content-Type"] = "application/x-www-form-urlencoded"}

  if bearer then
    headers["Authorization"] = "Bearer "..bearer
  end

  if config.webserver.log_rest_call then
    print(method, url, body, require('json').encode(headers))
  end

  local response
  local _, err = pcall(function()
    if url:match('googleapis%.com') then
      local cmd_request = ''
      if method=='POST' then
        cmd_request = 'curl -s -d "'..body..'" '..url
      else
        cmd_request = 'curl -s -H "Authorization: Bearer '..bearer..'" '..url
      end
      local f = assert(io.popen(cmd_request, 'r'))
      response = assert(f:read('*a'))
      if config.webserver.log_rest_call then
        print('response: ', response)
      end
      f:close()
    else
      response = http_client:request(method, url, body, {headers=headers})
      if config.webserver.log_rest_call then
        print('response: ', response.body)
        print('reason: ', response.reason)
      end
    end
  end)
  if err then
    return nil, err
  end
  if response.status~=nil and response.status > 399 then
    return nil, response.reason
  end
  local parsed_response = false
  local _, err = pcall(function()
    parsed_response = require('json').decode(response.body or response)
  end)
  return parsed_response, err
end


function helper.download_image_for_user(url, user_id)
  if not user_id then
    return nil, 'error.user_id_is_empty'
  end
  local imagepath = "static/images/u/"

  local response = require('http.client').new():request('GET',url)
  if response.status > 299 then
    return nil, response.reason
  end
  local ext = false
  local mime = response.headers['content-type']
  if mime=='image/jpeg' then
    ext = 'jpg'
  elseif mime=='image/png' then
    ext = 'png'
  elseif mime=='image/gif' then
    ext = 'gif'
  end
  if not ext then return
    nil, 'error.source_is_not_image'
  end
  local filename = require('src.helpers.common').random_string(16) .. '.' .. ext
  require('lfs').mkdir(imagepath..user_id)
  local filepath = imagepath..user_id..'/'..filename
  local file = io.open(filepath, 'wb')
  file:write(response.body)
  file:close()
  return filepath
end


return helper