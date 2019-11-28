return {
    login = function(request)
        local login, pwd, msg_without_form, msg_with_form = '', '', false, false
        if request.method=='POST' then
            login = request:post_param('login')
            pwd = request:post_param('pwd')
            local user, err = dbo.users:login(request.headers['user-agent'], request.peer.host, login, pwd)
            if not err then
                request.user = user
                local resp = request:redirect_to('#restored_path')
                resp:setcookie{
                    name = 'ucs', -- user cookie session
                    path = '/',
                    value = user.session.data.hash,
                    expires = '+100y',
                }
                return resp
            elseif user and err=='error.login.cannot_login_to_inactived_account' then
                user:update_fields{
                    verification_code = require('src.helpers.common').random_string(16)
                }:save()
                local response = require('src.helpers.common').send_mail(
                        login, request.httpd.i18n('mail.verify.page_header'),
                        request.httpd.i18n('mail.verify.message', {
                            link=request:url_for('user/verify', nil, {v=user.data.verification_code}),
                            code=user.data.verification_code,
                        })
                )
                if not response or response.status~=250 then
                    msg_without_form = request.httpd.i18n('error.cannot_send_mail', {system_mail=config.mail.system_address})
                else
                    msg_without_form = request.httpd.i18n('mail.verify.msg_after_sending')
                end
            else
                msg_with_form = request.httpd.i18n(err)
            end
        end
        return request:render{
            login = login,
            pwd = '',
            msg_without_form = msg_without_form,
            msg_with_form = msg_with_form,
        }
    end,



    logout = function(request)
        if request.user then
            request.user:logout()
            request.user = nil
        end
        local resp = request:redirect_to('#restored_path')
        resp:setcookie{
            name = 'ucs', -- user cookie session
            path = '/',
            value = '',
            expires = '0y',
        }
        return resp
    end,



    verify = function(request)
        if not request:param('v') then   -- something wrong
            return request:display_message(410, request.httpd.i18n('error.wrong_request'))
        end
        local user, err = dbo.users:verify(request:param('v'))
        if not err then
            user:start_session(request.headers['user-agent'], request.peer.host)
            request.user = user
            local resp = request:redirect_to('#restored_path')
            resp:setcookie{
                name = 'ucs', -- user cookie session
                path = '/',
                value = user.session.data.hash,
                expires = '+100y',
            }
            return resp
        else
            return request:display_message(500, request.httpd.i18n('error.login.cannot_find_user_by_vercode'))
        end
    end,



    register = function(request)
        local msg_without_form = false
        local form = require('src.dbo.form'){
            login = dbo.users.fields.login.validations,
            username = dbo.users.fields.username.validations,
            pwd = {exists = true, pattern = '^[0-9a-zA-Z]+$', min=8, max=32},
            pwd_again = { equal = request:post_param('pwd') },
            accept_terms = { exists = true },
        }
        form.fields.username.exists = true
        form.fields.login.exists = true

        if request.method=='POST' then
            if form:validate(request:post_param()) then
                form.data.verification_code = require('src.helpers.common').random_string(16)
                local user = dbo.users(form.data):save()
                if user then
                    local response = require('src.helpers.common').send_mail(
                            user.data.login, request.httpd.i18n('mail.verify.page_header'),
                            request.httpd.i18n('mail.verify.message', {
                                link=request:url_for('user/verify', nil, {v=user.data.verification_code}),
                                code=user.data.verification_code,
                            })
                    )
                    if not response or response.status~=250 then
                        msg_without_form = request.httpd.i18n('error.cannot_send_mail', {system_mail=config.mail.system_address})
                    else
                        msg_without_form = request.httpd.i18n('mail.verify.msg_after_sending')
                    end
                end
            else
                -- в форму будут переданы сообщения об ошибках
            end
        end
        return request:render{
            form = form,
            msg_without_form = msg_without_form,
        }
    end,


    -- todo: наполнить функционалом
    profile = function(request)
    end,
}