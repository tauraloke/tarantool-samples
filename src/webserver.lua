

httpd = require('src.reserver').new(config.webserver.host, config.webserver.port, {
  cache_templates     = config.webserver.caching_web_files,
  cache_controllers   = config.webserver.caching_web_files,
  cache_static        = config.webserver.caching_web_files,
  layout = '_layout_',
  app_dir = './src',
  page_title = config.site_name,
})


httpd.i18n = require 'src.helpers.i18n'
httpd.i18n.load('./src/i18n/')


httpd:route({
  path = '/',
  name = 'site/home',
  method = 'GET',
  savepath_for_user = true,
  savepath_for_unreg = true,
}, 'site#home')

httpd:route({
  path = '/locale',
  name = 'site/locale',
  method = 'GET',
  rules = {'check_session'},
}, 'site#locale')

httpd:route({
  path = '/error/403',
  name = 'error/403',
}, 'error#e403')


httpd:route({
  path = '/oauth/:provider/connect',
  name = 'oauth/connect',
}, 'oauth#connect')

httpd:route({
  path = '/oauth/:provider/token',
  name = 'oauth/token',
}, 'oauth#token')

httpd:route({
  path = '/oauth/list',
  name = 'oauth/list',
  rules = {'only_for_reg'},
  savepath_for_user = true,
}, 'oauth#list')

httpd:route({
  path = '/oauth/:provider/disconnect',
  name = 'oauth/disconnect',
  rules = {'only_for_reg', 'check_session'},
}, 'oauth#disconnect')


httpd:route({
  path = '/register',
  name = 'user/register',
  rules = {'only_for_unreg', 'csrf_protect'},
}, 'user#register')

httpd:route({
  path = '/login',
  name = 'user/login',
  rules = {'only_for_unreg', 'csrf_protect'},
}, 'user#login')

httpd:route({
  path = '/verify',
  name = 'user/verify',
  rules = {'only_for_unreg'},
}, 'user#verify')

httpd:route({
  path = '/logout',
  name = 'user/logout',
  rules = {'check_session'},
}, 'user#logout')

httpd:route({
  path = '/u/:domain',
  name = 'user/profile',
  savepath_for_user = true,
  savepath_for_unreg = true,
}, 'user#profile')


httpd:route({
  path = '/sessions',
  name = 'sessions/list',
  rules = {'only_for_reg'},
  savepath_for_user = true,
}, 'session#list')

httpd:route({
  path = '/sessions/drop',
  method = 'POST',
  name = 'sessions/drop',
  rules = {'only_for_reg', 'check_session'},
}, 'session#drop')

httpd:route({
  path = '/sessions/drop_all_except_current',
  method = 'POST',
  name = 'sessions/drop_all_except_current',
  rules = {'only_for_reg', 'check_session'},
}, 'session#drop_all_except_current')


-- test routes. Can be deleted.
httpd:route({
  path = '/upload',
  name = 'site/upload',
  savepath_for_user = true,
  savepath_for_unreg = true,
}, 'site#upload')

--






httpd.hooks.before_dispatch = function(server, request)
  if not request:cookie('locale') then
    request.cookie_locale_changed = true
  end
  server.i18n.detect_locale(request)
  if not request:cookie('s') then
    request.temp_session_hash = require('src.helpers.common').random_string(16)
    request.temp_session_hash_created = true
  else
    request.temp_session_hash = request:cookie('s')
  end

  request.temporary_session = dbo.temporary_sessions:get(request.temp_session_hash, {index='hash'})
  if not request.temporary_session then
    request.temporary_session = dbo.temporary_sessions{
      hash = request.temp_session_hash,
    }
  end
  request.temporary_session:update_fields{
    date_last_activity = require('os').time(),
  }:save()   -- it saves session and create if not exists

  if request:cookie('ucs') then
    request.user = dbo.users:auth(request:cookie('ucs'))
  end
end

httpd.hooks.after_dispatch = function(request, response)
httpd.requ = request  -- todo: remove debug fields
httpd.resp = response  -- todo: remove debug fields
  if request.cookie_locale_changed then
    response:setcookie{
      name = 'locale',
      value = request.httpd.i18n.get_locale(),
      expires = '+100y',
    }
    request.cookie_locale_changed = nil
  end
  if request.temp_session_hash_created then
    response:setcookie{
      name = 's',
      value = request.temp_session_hash,
    }
    request.temp_session_hash_created = false
  end

  local savepath_for_user, savepath_for_unreg
  if not request.fullpath then
    request.fullpath = '/'
  end
  if request.user and request.endpoint.savepath_for_user then
    savepath_for_user = request.fullpath
  end
  if request.endpoint.savepath_for_unreg then
    savepath_for_unreg = request.fullpath
  end
  request:set_session{
    savepath_for_user = savepath_for_user,
    savepath_for_unreg = savepath_for_unreg,
  }
end


container = {}
httpd:start()

