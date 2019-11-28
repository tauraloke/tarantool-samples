
local r = {}

r.validating_rules = {
    exists = function(attribute, value)
        if (value==nil or value=='') and attribute then
            return nil, 'error.validation.field_cannot_be_empty'
        end
        return true
    end,


    -- attribute is table with fields:
    --  model: link to model
    --  index: string name of field index, setting in model declaration
    --  self_id: id of current object, sending via active_record:validate()
    unique = function(attribute, value)
        if value==nil then
            return true
        end
        local objs = attribute.model:select(value, {index=attribute.index})
        if #objs==0 then
            return true
        end
        if #objs > 1 or objs[1].id ~= attribute.self_id then
            return nil, 'error.validation.field_is_already_occupied'
        end
        return true
    end,


    type = function(attribute, value)
        if value==nil then
            return true
        end
        if not type(value)==attribute then
            return nil, 'error.validation.field_type_dismatch'
        end
        return true
    end,


    min = function(attribute, value)
        if value==nil or value=='' then
            return true
        end
        if type(value) == 'string' then
            if require('utf8').len(value) < tonumber(attribute) then
                return nil, 'error.validation.field_is_too_short', {count=attribute}
            end
        elseif type(value) == 'number' then
            if value < tonumber(attribute) then
                return nil, 'error.validation.field_is_too_small', {count=attribute}
            end
        end
        return true
    end,


    max = function(attribute, value)
        if value==nil or value=='' then
            return true
        end
        if type(value) == 'string' then
            if require('utf8').len(value)> tonumber(attribute) then
                return nil, 'error.validation.field_is_too_long', {count=attribute}
            end
        elseif type(value) == 'number' then
            if value > tonumber(attribute) then
                return nil, 'error.validation.field_is_too_big', {count=attribute}
            end
        end
        return true
    end,


    pattern = function(attribute, value)
        if not value or value=='' then
            return true
        end
        if not value:match(attribute) then
            return nil, 'error.validation.field_pattern_is_not_valid'
        end
        return true
    end,

    equal = function(attribute, value)
        if attribute~=value then
            return nil, 'error.validation.unequal_values'
        end
        return true
    end,
}

function r.validate(condition, attribute, value)
    if type(r.validating_rules[condition])~='function' then
        return true
    else
        return r.validating_rules[condition](attribute, value)
    end
end

-- rocket science
setmetatable(r, {
    __call = function (cls, ...)
        return r.validate(...)
    end,
})

return r


