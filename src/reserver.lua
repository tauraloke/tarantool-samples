-- patched http.server

local lib = require('http.lib')

local io = io
local require = require
local package = package
local mime_types = require('http.mime_types')
local codes = require('http.codes')

local log = require('log')
local socket = require('socket')
local json = require('json')
local errno = require 'errno'

local DETACHED = 101

local function errorf(fmt, ...)
    error(string.format(fmt, ...))
end

local function sprintf(fmt, ...)
    return string.format(fmt, ...)
end

local function uri_escape(str)
    local res = {}
    if type(str) == 'table' then
        for _, v in pairs(str) do
            table.insert(res, uri_escape(v))
        end
    else
        res = string.gsub(tostring(str), '[^a-zA-Z0-9_]',
            function(c)
                return string.format('%%%02X', string.byte(c))
            end
        )
    end
    return res
end

local function uri_unescape(str, unescape_plus_sign)
    local res = {}
    if type(str) == 'table' then
        for _, v in pairs(str) do
            table.insert(res, uri_unescape(v))
        end
    else
        if unescape_plus_sign ~= nil then
            str = string.gsub(str, '+', ' ')
        end

        res = string.gsub(str, '%%([0-9a-fA-F][0-9a-fA-F])',
            function(c)
                return string.char(tonumber(c, 16))
            end
        )
    end
    return res
end

local function extend(tbl, tblu, raise)
    local res = {}
    for k, v in pairs(tbl) do
        res[ k ] = v
    end
    for k, v in pairs(tblu) do
        if raise then
            if res[ k ] == nil then
                errorf("Unknown option '%s'", k)
            end
        end
        res[ k ] = v
    end
    return res
end

local function type_by_format(fmt)
    if fmt == nil then
        return 'application/octet-stream'
    end

    local t = mime_types[ fmt ]

    if t ~= nil then
        return t
    end

    return 'application/octet-stream'
end

local function reason_by_code(code)
    code = tonumber(code)
    if codes[code] ~= nil then
        return codes[code]
    end
    return sprintf('Unknown code %d', code)
end

local function ucfirst(str)
    return str:gsub("^%l", string.upper, 1)
end

local function cached_query_param(self, name)
    if name == nil then
        return self.query_params
    end
    return self.query_params[ name ]
end

local function cached_post_param(self, name)
    if name == nil then
        return self.post_params
    end
    return self.post_params[ name ]
end

local function request_tostring(self)
        local res = self:request_line() .. "\r\n"

        for hn, hv in pairs(self.headers) do
            res = sprintf("%s%s: %s\r\n", res, ucfirst(hn), hv)
        end

        return sprintf("%s\r\n%s", res, self.body)
end

local function request_line(self)
        local rstr = self.path
        if string.len(self.query) then
            rstr = rstr .. '?' .. self.query
        end
        return sprintf("%s %s HTTP/%d.%d",
            self.method, rstr, self.proto[1], self.proto[2])
end

local function query_param(self, name)
        if self.query == nil and string.len(self.query) == 0 then
            rawset(self, 'query_params', {})
        else
            local params = lib.params(self.query)
            local pres = {}
            for k, v in pairs(params) do
                pres[ uri_unescape(k) ] = uri_unescape(v)
            end
            rawset(self, 'query_params', pres)
        end

        rawset(self, 'query_param', cached_query_param)
        return self:query_param(name)
end

local function request_content_type(self)
    -- returns content type without encoding string
    if self.headers['content-type'] == nil then
        return nil
    end

    return string.match(self.headers['content-type'],
                        '^([^;]*)$') or
        string.match(self.headers['content-type'],
                     '^(.*);.*')
end

local function post_param(self, name)
    local content_type = self:content_type()

    if self:content_type() == 'multipart/form-data' then
       -- start of multipart parsing --
      local content_type = self.headers['content-type']
      local content_type, boundary = content_type:match('(multipart/form%-data); boundary=(.+)')
      local eradicator = 1000
      local next_chunk = ''
      local next_delimiter = boundary
      local eos = '\r\n'
      local res = {}
      local current_segment = {}
      local header_type = ''
      local header_value = ''
      while(eradicator>1) do
        eradicator = eradicator - 1
        chunk = self:read(next_delimiter)
        if(next_delimiter==boundary) then
          if chunk=='' then break end   -- end of transmission
          if not current_segment.initiated then
            current_segment.initiated = true
            next_delimiter = eos
          else
            chunk = chunk:gsub('\r\n'..boundary, '')
            current_segment.value = chunk
            if(current_segment.name) then
              if(current_segment.filename) then
                res[current_segment.name] = {}
                res[current_segment.name].filename = current_segment.filename
                res[current_segment.name].mime = current_segment.content_type
                res[current_segment.name].file = current_segment.value
--                        file = io.open('./tmph/'..current_segment.filename, 'w*')
--                        file:write(current_segment.value)
--                        file:close()
              else
                res[current_segment.name] = current_segment.value
              end
              current_segment = {}
              current_segment.initiated = true
              next_delimiter = eos
            else
              break
            end
          end
        elseif(next_delimiter==eos) then
          header_type, header_value = chunk:match('([%w-]+):%s(.*)')
          if header_type then header_type = string.lower(header_type) end
          if header_type=='content-disposition' and header_value then
            current_segment.have_headers = true
            header_value = header_value:split('; ')
            current_segment.content_disposition = header_value[1]
            if header_value[2] then
              current_segment.name = header_value[2]:match('name="(.*)"')
            end
            if header_value[3] then
              current_segment.filename = header_value[3]:match('filename="(.*)"')
            end
          elseif header_type=='content-type' and header_value then
            current_segment.have_headers = true
            current_segment.content_type = header_value:gsub('[\r\n]', '')
          elseif not header_type or not header_value then
            if chunk == '--\r\n' then
              break
            end
            if current_segment.have_headers then
              next_delimiter = boundary
              current_segment.awaiting_boundary = true
            end
          end
        end
      end
  
      rawset(self, 'post_params', res)
      -- end of multipart parsing --
    elseif self:content_type() == 'application/json' then
        local params = self:json()
        rawset(self, 'post_params', params)
    elseif self:content_type() == 'application/x-www-form-urlencoded' then
        local params = lib.params(self:read_cached())
        local pres = {}
        for k, v in pairs(params) do
            pres[ uri_unescape(k) ] = uri_unescape(v, true)
        end
        rawset(self, 'post_params', pres)
    else
        local params = lib.params(self:read_cached())
        local pres = {}
        for k, v in pairs(params) do
            pres[ uri_unescape(k) ] = uri_unescape(v)
        end
        rawset(self, 'post_params', pres)
    end

    rawset(self, 'post_param', cached_post_param)
    return self:post_param(name)
end

local function param(self, name)
        if name ~= nil then
            local v = self:post_param(name)
            if v ~= nil then
                return v
            end
            return self:query_param(name)
        end

        local post = self:post_param()
        local query = self:query_param()
        return extend(post, query, false)
end

local function catfile(...)
    local sp = { ... }

    local path

    if #sp == 0 then
        return
    end

    for i, pe in pairs(sp) do
        if path == nil then
            path = pe
        elseif string.match(path, '.$') ~= '/' then
            if string.match(pe, '^.') ~= '/' then
                path = path .. '/' .. pe
            else
                path = path .. pe
            end
        else
            if string.match(pe, '^.') == '/' then
                path = path .. string.gsub(pe, '^/', '', 1)
            else
                path = path .. pe
            end
        end
    end

    return path
end

local response_mt
local request_mt

local function expires_str(str)

    local now = os.time()
    local gmtnow = now - os.difftime(now, os.time(os.date("!*t", now)))
    local fmt = '%a, %d-%b-%Y %H:%M:%S GMT'

    if str == 'now' or str == 0 or str == '0' then
        return os.date(fmt, gmtnow)
    end

    local diff, period = string.match(str, '^[+]?(%d+)([hdmy])$')
    if period == nil then
        return str
    end

    diff = tonumber(diff)
    if period == 'h' then
        diff = diff * 3600
    elseif period == 'd' then
        diff = diff * 86400
    elseif period == 'm' then
        diff = diff * 86400 * 30
    else
        diff = diff * 86400 * 365
    end

    return os.date(fmt, gmtnow + diff)
end

local function setcookie(resp, cookie)
    local name = cookie.name
    local value = cookie.value

    if name == nil then
        error('cookie.name is undefined')
    end
    if value == nil then
        error('cookie.value is undefined')
    end

    local str = sprintf('%s=%s', name, uri_escape(value))
    if cookie.path ~= nil then
        str = sprintf('%s;path=%s', str, uri_escape(cookie.path))
    else
        str = sprintf('%s;path=%s', str, '/')
    end
    if cookie.domain ~= nil then
        str = sprintf('%s;domain=%s', str, cookie.domain)
    end

    if cookie.expires ~= nil then
        str = sprintf('%s;expires="%s"', str, expires_str(cookie.expires))
    end

    if not resp.headers then
        resp.headers = {}
    end
    if resp.headers['set-cookie'] == nil then
        resp.headers['set-cookie'] = { str }
    elseif type(resp.headers['set-cookie']) == 'string' then
        resp.headers['set-cookie'] = {
            resp.headers['set-cookie'],
            str
        }
    else
        table.insert(resp.headers['set-cookie'], str)
    end
    return resp
end

local function cookie(tx, cookie)
    if tx.headers.cookie == nil then
        return nil
    end
    for k, v in string.gmatch(
                tx.headers.cookie, "([^=,; \t]+)=([^,; \t]+)") do
        if k == cookie then
            return uri_unescape(v)
        end
    end
    return nil
end

local function url_for_helper(tx, name, args, query)
    return tx:url_for(name, args, query)
end

local function load_template(self, r, format)
    if r.template ~= nil then
        return
    end

    if format == nil then
        format = 'html'
    end

    local file
    if r.file ~= nil then
        file = r.file
    elseif r.controller ~= nil and r.action ~= nil then
        file = catfile(
            string.gsub(r.controller, '[.]', '/'),
            r.action .. '.' .. format .. '.etlua')
    else
        errorf("Can not find template for '%s'", r.path)
    end

    if self.options.cache_templates then
        if self.cache.tpl[ file ] ~= nil then
            return self.cache.tpl[ file ]
        end
    end


    local tpl = catfile(self.options.app_dir, 'templates', file)
    local fh = io.input(tpl)
    local template = fh:read('*a')
    fh:close()

    if self.options.cache_templates then
        self.cache.tpl[ file ] = template
    end
    return template
end


local function set_session(req, opts)
    if not req.temporary_session or not req.temporary_session.data then
        return nil
    end
    if req.temporary_session.data.data==nil then
        req.temporary_session.data.data = {addr = req.peer.host}
    end
    for name, value in pairs(opts) do
        req.temporary_session.data.data[name] = value
    end
    req.temporary_session:save()
end


local function get_session(req, name)
    if not req.temporary_session or not req.temporary_session.data or req.temporary_session.data.data==nil then
        return nil
    end
    return req.temporary_session.data.data[name]
end


local function render(tx, opts, partial)
    if tx == nil then
        error("Usage: self:render({ ... })")
    end
-->>    
    if partial then
      tpl = load_template(tx.httpd, {file=partial})
      if tpl == nil then
        return nil, 'cannot_render_partial'
      end
      local vars = opts or {}
      for hname, sub in pairs(tx.httpd.helpers) do
        vars[hname] = function(...) return sub(tx, ...) end
      end
      vars.action = tx.endpoint.action
      vars.controller = tx.endpoint.controller
      vars.format = format
      vars.self = tx
      vars.i18n = tx.httpd.i18n
      local template, err = require('etlua').compile(tpl)
      if not template then
        return err
      end
      return template(vars)
    end
--<<
    local resp = setmetatable({ headers = {} }, response_mt)
    local vars = {}
    if opts ~= nil then
        if opts.text ~= nil then
            if tx.httpd.options.charset ~= nil then
                resp.headers['content-type'] =
                    sprintf("text/plain; charset=%s",
                        tx.httpd.options.charset
                    )
            else
                resp.headers['content-type'] = 'text/plain'
            end
            resp.body = tostring(opts.text)
            return resp
        end

        if opts.json ~= nil then
            if tx.httpd.options.charset ~= nil then
                resp.headers['content-type'] =
                    sprintf('application/json; charset=%s',
                        tx.httpd.options.charset
                    )
            else
                resp.headers['content-type'] = 'application/json'
            end
            resp.body = json.encode(opts.json)
            return resp
        end

        if opts.data ~= nil then
            resp.body = tostring(opts.data)
            return resp
        end

        vars = extend(tx.tstash, opts, false)
    end

    local tpl

    local format = tx.tstash.format
    if format == nil then
        format = 'html'
    end

    if tx.endpoint.template ~= nil then
        tpl = tx.endpoint.template
    else
        tpl = load_template(tx.httpd, tx.endpoint, format)
        if tpl == nil then
            errorf('template is not defined for the route')
        end
    end

    if type(tpl) == 'function' then
        tpl = tpl()
    end

    for hname, sub in pairs(tx.httpd.helpers) do
        vars[hname] = function(...) return sub(tx, ...) end
    end
    vars.action = tx.endpoint.action
    vars.controller = tx.endpoint.controller
    vars.format = format
    vars.self = tx
    local i18n_prefix = 'templates.'..tx.endpoint.controller..'.'..tx.endpoint.action..'.'
    vars.i18n = function(text, options, ...)
      options = options or {}
      options.prefix = i18n_prefix
      return tx.httpd.i18n(text, options)
    end
    vars.city_by_ip = function(...)
        return tx.httpd.i18n.city_by_ip(...)
    end


    --<<
    local page_top, page_bottom = '', ''
    if not tx.page_title then
      local translated_title, err = tx.httpd.i18n(i18n_prefix..'page_title')
      if err then
        tx.page_title = tx.httpd.options.page_title
      else
        tx.page_title = translated_title
      end
    end
    if tx.httpd.options.layout then
      local tpl_top = render(tx, opts, tx.httpd.options.layout..'/top.etlua')
      if tpl_top then
        tpl_top = require('etlua').compile(tpl_top)
        page_top = tpl_top(vars)
      end
      local tpl_bottom = render(tx, opts, tx.httpd.options.layout..'/bottom.etlua')
      if tpl_bottom then
        tpl_bottom = require('etlua').compile(tpl_bottom)
        page_bottom = tpl_bottom(vars)
      end
    end

    local template = require('etlua').compile(tpl)
    resp.body = template(vars)
    resp.body =  page_top .. resp.body .. page_bottom
    -->>
    --resp.body = lib.template(tpl, vars)
    
    
    resp.headers['content-type'] = type_by_format(format)

    if tx.httpd.options.charset ~= nil then
        if format == 'html' or format == 'js' or format == 'json' then
            resp.headers['content-type'] = resp.headers['content-type']
                .. '; charset=' .. tx.httpd.options.charset
        end
    end
    return resp
end

local function iterate(tx, gen, param, state)
    return setmetatable({ body = { gen = gen, param = param, state = state } },
        response_mt)
end

local function redirect_to(tx, name, args, query)
    local location = '/'
    if name=='#restored_path' then
        if tx.temporary_session and tx.temporary_session.data
                and tx.temporary_session.data.data~=nil then
            if tx.user then
                if tx:session('savepath_for_user') then
                    location = tx:session('savepath_for_user')
                end
             end
            if location=='/' then
                if tx:session('savepath_for_unreg') then
                    location = tx:session('savepath_for_unreg')
                end
            end
        end
        if location=='/' then
            name = 'site/home'
            location = tx:url_for(name, args, query)
        end
    else
        location = tx:url_for(name, args, query)
    end
    return setmetatable({ status = 302, headers = { location = location } },
        response_mt)
end


local function display_message(tx, status, message)
    tx.method = 'GET'
    tx.path = '/error/403'
    tx.error_msg = message
    local r = tx.httpd:match(tx.method, tx.path)
    local stash = extend(r.stash, { format = 'html' })
    tx.endpoint = r.endpoint
    tx.tstash   = stash
    local resp = tx:render({
        error_msg = message,
    })
    resp.status = status
    return resp
end


local function access_stash(tx, name, ...)
    if type(tx) ~= 'table' then
        error("usage: ctx:stash('name'[, 'value'])")
    end
    if select('#', ...) > 0 then
        tx.tstash[ name ] = select(1, ...)
    end

    return tx.tstash[ name ]
end

local function url_for_tx(tx, name, args, query)
    if name == 'current' then
        return tx.endpoint:url_for(args, query)
    end
    return tx.httpd:url_for(name, args, query)
end

local function request_json(req)
    local data = req:read_cached()
    local s, json = pcall(json.decode, data)
    if s then
       return json
    else
       error(sprintf("Can't decode json in request '%s': %s",
           data, tostring(json)))
       return nil
    end
end

local function request_read(req, opts, timeout)
    local remaining = req._remaining
    if not remaining then
        remaining = tonumber(req.headers['content-length'])
        if not remaining then
            return ''
        end
    end

    if opts == nil then
        opts = remaining
    elseif type(opts) == 'number' then
        if opts > remaining then
            opts = remaining
        end
    elseif type(opts) == 'string' then
        opts = { size = remaining, delimiter = opts }
    elseif type(opts) == 'table' then
        local size = opts.size or opts.chunk
        if size and size > remaining then
            opts.size = remaining
            opts.chunk = nil
        end
    end

    local buf = req.s:read(opts, timeout)
    if buf == nil then
        req._remaining = 0
        return ''
    end
    remaining = remaining - #buf
    assert(remaining >= 0)
    req._remaining = remaining
    return buf
end

local function request_read_cached(self)
    if self.cached_data == nil then
        local data = self:read()
        rawset(self, 'cached_data', data)
        return data
    else
        return self.cached_data
    end
end

local function static_file(self, request, format)
        local file = catfile(self.options.app_dir, 'public', request.path)

        if self.options.cache_static and self.cache.static[ file ] ~= nil then
            return {
                code = 200,
                headers = {
                    [ 'content-type'] = type_by_format(format),
                },
                body = self.cache.static[ file ]
            }
        end

        local s, fh = pcall(io.input, file)

        if not s then
            return { status = 404 }
        end

        local body = fh:read('*a')
        io.close(fh)

        if self.options.cache_static then
            self.cache.static[ file ] = body
        end

        return {
            status = 200,
            headers = {
                [ 'content-type'] = type_by_format(format),
            },
            body = body
        }
end

request_mt = {
    __index = {
        render      = render,
        session     = get_session,
        set_session  = set_session,
        cookie      = cookie,
        redirect_to = redirect_to,
        display_message = display_message,
        iterate     = iterate,
        stash       = access_stash,
        url_for     = url_for_tx,
        content_type= request_content_type,
        request_line= request_line,
        read_cached = request_read_cached,
        query_param = query_param,
        post_param  = post_param,
        param       = param,
        read        = request_read,
        json        = request_json
    },
    __tostring = request_tostring;
}

response_mt = {
    __index = {
        setcookie = setcookie;
    }
}


local function check_rules(request)
    if not request.endpoint then
        return true
    end
    if request.endpoint and type(request.endpoint.rules)~='table' then
        return true
    else
        for _,restriction in pairs(request.endpoint.rules) do
            if restriction=='only_for_reg' then
                if not request.user or not request.user.data.id then
                    return nil, 'error.forbidden_page_for_unreg'
                end
            end
            if restriction=='only_for_unreg' then
                if request.user then
                    return nil, 'error.forbidden_page_for_reg'
                end
            end
            if restriction=='check_session' then
                print(require('json').encode(request.temporary_session.data))
                print(require('json').encode(request:param('s')))
                if not request.temporary_session or request.temporary_session.data.hash ~= request:param('s') then
                    return nil, 'error.session_forgery'
                end
            end
            if restriction=='csrf_protect' then
                if request.method=='POST' and request:post_param('csrf_token')~=request:session('csrf_token') then
                    return nil, 'error.csrf_token_forgery'
                end
                if request.method=='GET' then
                    request:set_session{
                        csrf_token = require('src.helpers.common').random_string(32)
                    }
                end
            end
        end
    end
    return true
end



local function handler(self, request)
    if self.hooks.before_dispatch ~= nil then
        self.hooks.before_dispatch(self, request)
    end

    local format = 'html'

    local pformat = string.match(request.path, '[.]([^.]+)$')
    if pformat ~= nil then
        format = pformat
    end


    local r = self:match(request.method, request.path)
    if r == nil then
        return static_file(self, request, format)
    end

    local stash = extend(r.stash, { format = format })

    request.endpoint = r.endpoint
    request.tstash   = stash

    local status, err = check_rules(request)
    if not status then
        request.method = 'GET'
        request.path = '/error/403'
        request.error_msg = self.i18n(err)
        r = self:match(request.method, request.path)
        stash = extend(r.stash, { format = format })
        request.endpoint = r.endpoint
        request.tstash   = stash
    end

    local resp = r.endpoint.sub(request)
    if self.hooks.after_dispatch ~= nil then
        self.hooks.after_dispatch(request, resp)
    end
    return resp
end

local function normalize_headers(hdrs)
    local res = {}
    for h, v in pairs(hdrs) do
        res[ string.lower(h) ] = v
    end
    return res
end

local function parse_request(req)
    local p = lib._parse_request(req)
    if p.error then
        return p
    end
    p.path = uri_unescape(p.path)
    if p.path:sub(1, 1) ~= "/" or p.path:find("./", nil, true) ~= nil then
        p.error = "invalid uri"
        return p
    end
    p.fullpath = req:match("^%w+ ([^ ]+) ")
    return p
end

local function process_client(self, s, peer)

    while true do
        local hdrs = ''

        local is_eof = false
        while true do
            local chunk = s:read{
                delimiter = { "\n\n", "\r\n\r\n" }
            }

            if chunk == '' then
                is_eof = true
                break -- eof
            elseif chunk == nil then
                log.error('failed to read request: %s', errno.strerror())
                return
            end

            hdrs = hdrs .. chunk

            if string.endswith(hdrs, "\n\n") or string.endswith(hdrs, "\r\n\r\n") then
                break
            end
        end

        if is_eof then
            break
        end

        log.debug("request:\n%s", hdrs)
        local p = parse_request(hdrs)
        if p.error ~= nil then
            log.error('failed to parse request: %s', p.error)
            s:write(sprintf("HTTP/1.0 400 Bad request\r\n\r\n%s", p.error))
            break
        end
        p.httpd = self
        p.s = s
        p.peer = peer
        setmetatable(p, request_mt)

        if p.headers['expect'] == '100-continue' then
            s:write('HTTP/1.0 100 Continue\r\n\r\n')
        end

        local logreq = self.options.log_requests and log.info or log.debug
        logreq("%s %s%s", p.method, p.path,
            p.query ~= "" and "?"..p.query or "")

        local res, reason = pcall(self.options.handler, self, p)
        --print(require('json').encode(reason))
        --reason.body = 'value of reason'

        p:read() -- skip remaining bytes of request body
        local status, hdrs, body

        if not res then
            status = 500
            hdrs = {}
            local trace = debug.traceback()
            local logerror = self.options.log_errors and log.error or log.debug
            logerror('unhandled error: %s\n%s\nrequest:\n%s',
                tostring(reason), trace, tostring(p))
            if self.options.display_errors then
            body =
                  "Unhandled error: " .. tostring(reason) .. "\n"
                .. trace .. "\n\n"
                .. "\n\nRequest:\n"
                .. tostring(p)
            else
                body = "Internal Error"
            end
       elseif type(reason) == 'table' then
            if reason.status == nil then
                status = 200
            elseif type(reason.status) == 'number' then
                status = reason.status
            else
                error('response.status must be a number')
            end
            if reason.headers == nil then
                hdrs = {}
            elseif type(reason.headers) == 'table' then
                hdrs = normalize_headers(reason.headers)
            else
                error('response.headers must be a table')
            end
            body = reason.body
        elseif reason == nil then
            status = 200
            hdrs = {}
        elseif type(reason) == 'number' then
            if reason == DETACHED then
                break
            end
        else
            error('invalid response')
        end

        local gen, param, state
        if type(body) == 'string' then
            -- Plain string
            hdrs['content-length'] = #body
        elseif type(body) == 'function' then
            -- Generating function
            gen = body
            hdrs['transfer-encoding'] = 'chunked'
        elseif type(body) == 'table' and body.gen then
            -- Iterator
            gen, param, state = body.gen, body.param, body.state
            hdrs['transfer-encoding'] = 'chunked'
        elseif body == nil then
            -- Empty body
            hdrs['content-length'] = 0
        else
            body = tostring(body)
            hdrs['content-length'] = #body
        end

        if hdrs.server == nil then
            hdrs.server = sprintf('Tarantool http (tarantool v%s)', _TARANTOOL)
        end

        if p.proto[1] ~= 1 then
            hdrs.connection = 'close'
        elseif p.broken then
            hdrs.connection = 'close'
        elseif rawget(p, 'body') == nil then
            hdrs.connection = 'close'
        elseif p.proto[2] == 1 then
            if p.headers.connection == nil then
                hdrs.connection = 'keep-alive'
            elseif string.lower(p.headers.connection) ~= 'keep-alive' then
                hdrs.connection = 'close'
            else
                hdrs.connection = 'keep-alive'
            end
        elseif p.proto[2] == 0 then
            if p.headers.connection == nil then
                hdrs.connection = 'close'
            elseif string.lower(p.headers.connection) == 'keep-alive' then
                hdrs.connection = 'keep-alive'
            else
                hdrs.connection = 'close'
            end
        end

        local response = {
            "HTTP/1.1 ";
            status;
            " ";
            reason_by_code(status);
            "\r\n";
        };
        for k, v in pairs(hdrs) do
            if type(v) == 'table' then
                for i, sv in pairs(v) do
                    table.insert(response, sprintf("%s: %s\r\n", ucfirst(k), sv))
                end
            else
                table.insert(response, sprintf("%s: %s\r\n", ucfirst(k), v))
            end
        end
        table.insert(response, "\r\n")

        if type(body) == 'string' then
            table.insert(response, body)
            response = table.concat(response)
            if not s:write(response) then
                break
            end
        elseif gen then
            response = table.concat(response)
            if not s:write(response) then
                break
            end
            response = nil
            -- Transfer-Encoding: chunked
            for _, part in gen, param, state do
                part = tostring(part)
                if not s:write(sprintf("%x\r\n%s\r\n", #part, part)) then
                    break
                end
            end
            if not s:write("0\r\n\r\n") then
                break
            end
        else
            response = table.concat(response)
            if not s:write(response) then
                break
            end
        end

        if p.proto[1] ~= 1 then
            break
        end

        if hdrs.connection ~= 'keep-alive' then
            break
        end
    end
end

local function httpd_stop(self)
   if type(self) ~= 'table' then
       error("httpd: usage: httpd:stop()")
    end
    if self.is_run then
        self.is_run = false
    else
        error("server is already stopped")
    end

    if self.tcp_server ~= nil then
        self.tcp_server:close()
        self.tcp_server = nil
    end
    return self
end

local function match_route(self, method, route)
    -- route must have '/' at the begin and end
    if string.match(route, '.$') ~= '/' then
        route = route .. '/'
    end
    if string.match(route, '^.') ~= '/' then
        route = '/' .. route
    end

    method = string.upper(method)

    local fit
    local stash = {}

    for k, r in pairs(self.routes) do
        if r.method == method or r.method == 'ANY' then
            local m = { string.match(route, r.match)  }
            local nfit
            if #m > 0 then
                if #r.stash > 0 then
                    if #r.stash == #m then
                        nfit = r
                    end
                else
                    nfit = r
                end

                if nfit ~= nil then
                    if fit == nil then
                        fit = nfit
                        stash = m
                    else
                        if #fit.stash > #nfit.stash then
                            fit = nfit
                            stash = m
                        elseif r.method ~= fit.method then
                            if fit.method == 'ANY' then
                                fit = nfit
                                stash = m
                            end
                        end
                    end
                end
            end
        end
    end

    if fit == nil then
        return fit
    end
    local resstash = {}
    for i = 1, #fit.stash do
        resstash[ fit.stash[ i ] ] = stash[ i ]
    end
    return  { endpoint = fit, stash = resstash }
end

local function set_helper(self, name, sub)
    if sub == nil or type(sub) == 'function' then
        self.helpers[ name ] = sub
        return self
    end
    errorf("Wrong type for helper function: %s", type(sub))
end

local function set_hook(self, name, sub)
    if sub == nil or type(sub) == 'function' then
        self.hooks[ name ] = sub
        return self
    end
    errorf("Wrong type for hook function: %s", type(sub))
end

local function url_for_route(r, args, query)
    if args == nil then
        args = {}
    end
    local name = r.path
    for i, sn in pairs(r.stash) do
        local sv = args[sn]
        if sv == nil then
            sv = ''
        end
        name = string.gsub(name, '[*:]' .. sn, sv, 1)
    end

    if query ~= nil then
        if type(query) == 'table' then
            local sep = '?'
            for k, v in pairs(query) do
                name = name .. sep .. uri_escape(k) .. '=' .. uri_escape(v)
                sep = '&'
            end
        else
            name = name .. '?' .. query
        end
    end

    if string.match(name, '^/') == nil then
        name = '/' .. name
    end

    local root_addr = "https://" .. config.nginx.name
    if config.nginx.port~=80 and config.nginx.port~=443 then
        root_addr = root_addr .. ':' .. config.nginx.port
    end

    return root_addr .. name
end

local function ctx_action(tx)
    local ctx = tx.endpoint.controller
    local action = tx.endpoint.action
    if tx.httpd.options.cache_controllers then
        if tx.httpd.cache[ ctx ] ~= nil then
            if type(tx.httpd.cache[ ctx ][ action ]) ~= 'function' then
                errorf("Controller '%s' doesn't contain function '%s'",
                    ctx, action)
            end
            return tx.httpd.cache[ ctx ][ action ](tx)
        end
    end

    local ppath = package.path
    package.path = catfile(tx.httpd.options.app_dir, 'controllers', '?.lua')
                .. ';'
                .. catfile(tx.httpd.options.app_dir,
                    'controllers', '?/init.lua')
    if ppath ~= nil then
        package.path = package.path .. ';' .. ppath
    end

    local st, mod = pcall(require, ctx)
    package.path = ppath
    package.loaded[ ctx ] = nil

    if not st then
        errorf("Can't load module '%s': %s'", ctx, tostring(mod))
    end

    if type(mod) ~= 'table' then
        errorf("require '%s' didn't return table", ctx)
    end

    if type(mod[ action ]) ~= 'function' then
        errorf("Controller '%s' doesn't contain function '%s'", ctx, action)
    end

    if tx.httpd.options.cache_controllers then
        tx.httpd.cache[ ctx ] = mod
    end

    return mod[action](tx)
end

local possible_methods = {
    GET    = 'GET',
    HEAD   = 'HEAD',
    POST   = 'POST',
    PUT    = 'PUT',
    DELETE = 'DELETE',
    PATCH  = 'PATCH',
}

local function add_route(self, opts, sub)
    if type(opts) ~= 'table' or type(self) ~= 'table' then
        error("Usage: httpd:route({ ... }, function(cx) ... end)")
    end

    opts = extend({method = 'ANY'}, opts, false)

    local ctx
    local action

    if sub == nil then
        sub = render
    elseif type(sub) == 'string' then

        ctx, action = string.match(sub, '(.+)#(.*)')

        if ctx == nil or action == nil then
            errorf("Wrong controller format '%s', must be 'module#action'", sub)
        end

        sub = ctx_action

    elseif type(sub) ~= 'function' then
        errorf("wrong argument: expected function, but received %s",
            type(sub))
    end

    opts.method = possible_methods[string.upper(opts.method)] or 'ANY'

    if opts.path == nil then
        error("path is not defined")
    end

    opts.controller = ctx
    opts.action = action
    opts.match = opts.path
    opts.match = string.gsub(opts.match, '[-]', "[-]")

    local estash = {  }
    local stash = {  }
    while true do
        local name = string.match(opts.match, ':([%a_][%w_]*)')
        if name == nil then
            break
        end
        if estash[name] then
            errorf("duplicate stash: %s", name)
        end
        estash[name] = true
        opts.match = string.gsub(opts.match, ':[%a_][%w_]*', '([^/]-)', 1)

        table.insert(stash, name)
    end
    while true do
        local name = string.match(opts.match, '[*]([%a_][%w_]*)')
        if name == nil then
            break
        end
        if estash[name] then
            errorf("duplicate stash: %s", name)
        end
        estash[name] = true
        opts.match = string.gsub(opts.match, '[*][%a_][%w_]*', '(.-)', 1)

        table.insert(stash, name)
    end

    if string.match(opts.match, '.$') ~= '/' then
        opts.match = opts.match .. '/'
    end
    if string.match(opts.match, '^.') ~= '/' then
        opts.match = '/' .. opts.match
    end

    opts.match = '^' .. opts.match .. '$'

    estash = nil

    opts.stash = stash
    opts.sub = sub
    opts.url_for = url_for_route

    if opts.name ~= nil then
        if opts.name == 'current' then
            error("Route can not have name 'current'")
        end
        if self.iroutes[ opts.name ] ~= nil then
            errorf("Route with name '%s' is already exists", opts.name)
        end
        table.insert(self.routes, opts)
        self.iroutes[ opts.name ] = #self.routes
    else
        table.insert(self.routes, opts)
    end
    return self
end

local function url_for_httpd(httpd, name, args, query)
    local idx = httpd.iroutes[ name ]
    if idx ~= nil then
        return httpd.routes[ idx ]:url_for(args, query)
    else
        if name:match('^http') then
            if type(query)=='table' then
                local query_chunks = {}
                for i,v in pairs(query) do
                    table.insert(query_chunks, i..'='..uri_escape(v))
                end
                return name .. '?' .. table.concat(query_chunks, '&')
            elseif type(query)=='string' then
                return name .. '?' .. query
            end
        end
    end

    if string.match(name, '^/') == nil then
        if string.match(name, '^https?://') ~= nil then
            return name
        else
            return '/' .. name
        end
    else
        return name
    end
end

local function httpd_start(self)
    if type(self) ~= 'table' then
        error("httpd: usage: httpd:start()")
    end

    local server = socket.tcp_server(self.host, self.port,
                     { name = 'http',
                       handler = function(...)
                           local res = process_client(self, ...)
                     end})
    if server == nil then
        error(sprintf("Can't create tcp_server: %s", errno.strerror()))
    end

    rawset(self, 'is_run', true)
    rawset(self, 'tcp_server', server)
    rawset(self, 'stop', httpd_stop)

    return self
end

local exports = {
    DETACHED = DETACHED,

    new = function(host, port, options)
        if options == nil then
            options = {}
        end
        if type(options) ~= 'table' then
            errorf("options must be table not '%s'", type(options))
        end
        local default = {
            max_header_size     = 4096,
            header_timeout      = 100,
            handler             = handler,
            app_dir             = '.',
            charset             = 'utf-8',
            cache_templates     = true,
            cache_controllers   = true,
            cache_static        = true,
            log_requests        = true,
            log_errors          = true,
            display_errors      = true,
            page_title          = 'The page',
            layout              = '_layout_',
        }

        local self = {
            host    = host,
            port    = port,
            is_run  = false,
            stop    = httpd_stop,
            start   = httpd_start,
            options = extend(default, options, true),

            routes  = {  },
            iroutes = {  },
            helpers = {
                url_for = url_for_helper,
            },
            hooks   = {  },

            -- methods
            route   = add_route,
            match   = match_route,
            helper  = set_helper,
            hook    = set_hook,
            url_for = url_for_httpd,

            -- caches
            cache   = {
                tpl         = {},
                ctx         = {},
                static      = {},
            },
        }

        return self
    end
}

return exports
