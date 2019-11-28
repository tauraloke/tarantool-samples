

return {
    list = function(request)
        local sessions = dbo.sessions:select(request.user.data.id, {
            index='user_id',
            iterator='REQ',
            limit=config.items_per_list,
        })
        return request:render{
            sessions = sessions,
        }
    end,



    drop = function(request)
        local sid = tonumber(request:post_param('sid'))
        if not sid then
            request:set_session{error_msg=request.httpd.i18n('error.wrong_request')}
            return request:redirect_to('#restored_path')
        end
        local resp = request:redirect_to('#restored_path')
        local session = dbo.sessions:get(sid)
        if not session or session.data.user_id ~= request.user.data.id then
            request:set_session{error_msg=request.httpd.i18n('error.wrong_request')}
            return request:redirect_to('#restored_path')
        end
        if session:delete() then
            request:set_session{notice_msg=request.httpd.i18n('templates.session.list.drop_done')}
            if session.data.id == request.user.session.data.id then
                request.user = nil
                resp:setcookie{
                    name = 'ucs', -- user cookie session
                    path = '/',
                    value = '',
                    expires = '0y',
                }
                request:set_session{notice_msg=request.httpd.i18n('templates.session.list.drop_done_and_logout')}
            end
        else
            request:set_session{error_msg=request.httpd.i18n('error.wrong_delete_object')}
        end
        return resp
    end,



    drop_all_except_current = function(request)
        if request.user:remove_sessions_except_current() then
            request:set_session{notice_msg=request.httpd.i18n('templates.session.list.mass_drop_done')}
        else
            request:set_session{error_msg=request.httpd.i18n('error.wrong_delete_object')}
        end
        return request:redirect_to('#restored_path')
    end,
}