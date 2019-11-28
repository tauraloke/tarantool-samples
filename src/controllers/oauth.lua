



local whoami = {
    deviantart = function(token, provider)

    end
}


return {

    connect = function(request)
        local provider = request:stash('provider')
        if not provider or not config.oauth or not config.oauth[provider] then
            return request:display_message(500, request.httpd.i18n('error.oauth.cannot_find_config_provider'))
        end
        math.randomseed(os.time())
        local state = math.random(1,1000000)
        request:set_session{state=state}
        local query_params = {
            response_type = "code",
            client_id     = config.oauth[provider].client_id,
            redirect_uri  = request:url_for('oauth/token', {provider=provider}),
            scope         = config.oauth[provider].scope,
            state         = state,
        }
        if(provider=='vk') then
            query_params['v'] = config.oauth.vk.api_version
            query_params['revoke_auth'] = 'true'
        end
        if(provider=='google') then
            query_params['access_type'] = "offline"
        end
        return request:redirect_to(config.oauth[provider].authorize.url, nil, query_params)
    end,


    token = function(request)
        if request:param('error') then
            return request:display_message(500, request.httpd.i18n('error.oauth.auth_rejected'))
        end
        if tostring(request:param('state'))~=tostring(request:session('state')) then
            return request:display_message(500, request.httpd.i18n('error.oauth.state_forgery'))
        end
        if not request:param('code') then
            return request:display_message(410, request.httpd.i18n('error.wrong_request'))
        end
        local provider = request:stash('provider')

        local token_response, err = require('src.helpers.common').rest_call(
                config.oauth[provider].token.url,
                config.oauth[provider].token.method,
                {
                    client_id     = config.oauth[provider].client_id,
                    client_secret = config.oauth[provider].client_secret,
                    code          = request:param('code'),
                    redirect_uri  = request:url_for('oauth/token',{provider=provider}),
                    grant_type    = "authorization_code",
                }
        )
        if type(token_response)~='table' or not token_response.access_token or token_response.error then
            --return request:display_message(500, require('json').encode(token_response)..err)
            return request:display_message(500, request.httpd.i18n('error.oauth.token_request_is_failed'))
        end

        local whoami_response, err = require('src.helpers.common').rest_call(
                config.oauth[provider].whoami.url,
                config.oauth[provider].whoami.method,
                config.oauth[provider].whoami.arguments(token_response),
                config.oauth[provider].whoami.bearer and token_response.access_token
        )
        if err then
            return request:display_message(500, request.httpd.i18n('error.oauth.whoami_request_is_failed'))
        end
        local whoami_fields = config.oauth[provider].whoami.response_rules(whoami_response, token_response)
        if whoami_fields.error then
            --return request:display_message(500, whoami_fields.error..'<br>'..require('json').encode(whoami_response))
            return request:display_message(500, request.httpd.i18n('error.oauth.whoami_request_is_failed'))
        end

        if false then
            return request:display_message(500, require('json').encode(whoami_response)..
                    '<br>'..require('json').encode(whoami_fields))
        end

        if not whoami_fields.username and not whoami_fields.social_id then
            return request:display_message(500, request.httpd.i18n('error.oauth.whoami_request_cannot_be_parsed'))
        end

        local redirect_response = request:redirect_to('#restored_path')
        whoami_fields.social_id = tostring(whoami_fields.social_id)
        local oauth = dbo.oauths:get({whoami_fields.social_id, provider}, {index='social'})

        if not request.user then
            if oauth then
                request.user = dbo.users:get(oauth.data.user_id)
                if not request.user then
                    return request:display_message(500, request.httpd.i18n('error.oauth.empty_user_id'))
                end
                oauth:update_fields{
                    date_last_activity = require('os').time(),
                }:save()
            else
                local err_user, err_oauth = false, false
                request.user, err_user = dbo.users{
                    username = whoami_fields.username,
                    domain_name = whoami_fields.domain,
                    login = whoami_fields.email,
                    is_activated = true,
                }:validate(true):save(true)
                oauth, err_oauth = dbo.oauths{
                    user_id = request.user.data.id,
                    provider = provider,
                    social_id = whoami_fields.social_id,
                    url = whoami_fields.url,
                    refresh_token = token_response.refresh_token,
                    access_token = token_response.access_token,
                    date_last_activity = require('os').time(),
                }:save()

                if not err_user and not err_oauth then
                    if whoami_fields.avatar then
                        request.user:delayed_upload_avatar(whoami_fields.avatar)
                    end
                else
                    return request:display_message(500, request.httpd.i18n('error.oauth.empty_user_id'))
                end
            end
            request.user:start_session(request.headers['user-agent'], request.peer.host)
            redirect_response:setcookie{
                name = 'ucs', -- user cookie session
                value = request.user.session.data.hash,
                expires = '+100y',
            }
        else
            if not oauth then
                if whoami_fields.email~=nil and request.user.data.login==nil then
                    request.user:update_fields{
                        login = whoami_fields.email,
                    }:save()
                end
                local err_oauth = false
                oauth, err_oauth = dbo.oauths{
                    user_id = request.user.data.id,
                    provider = provider,
                    social_id = whoami_fields.social_id,
                    url = whoami_fields.url,
                    refresh_token = token_response.refresh_token,
                    access_token = token_response.access_token,
                    date_last_activity = require('os').time(),
                }:save()
                if whoami_fields.avatar~=nil and request.user.avatar_url==nil then
                    request.user:delayed_upload_avatar(whoami_fields.avatar)
                end
            end
        end

        return redirect_response
    end,


    list = function(request)
        local socials = {}
        for _, soc in dbo.oauths:space().index.user_id:pairs(request.user.data.id) do
            socials[soc.provider] = soc
        end
        return request:render{
            socials = socials,
        }
    end,


    -- todo
    disconnect = function(request)

    end,


}