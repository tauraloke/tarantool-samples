local form = {
}
form.__index = form

-- rocket science
setmetatable(form, {
    __call = function (cls, ...)
        local self = setmetatable({}, cls)
        self:new(...)
        return self
    end,
})



-- constructor
function form:new(fields)
    self.fields = {}
    if type(fields)=='table' then self.fields = table.deepcopy(fields) end
    self.errors = {}
    self.error_opts = {}
    self.data = {}
    return self
end



function form:validate(data)
    if type(data)=='table' then
        self.data = data
    end
    local is_valid = true
    self.errors = {}
    self.error_opts = {}
    for field_name, validating_rules in pairs(self.fields) do
        for condition, attribute in pairs(validating_rules) do
            local status, err, opts = require('src.dbo.validate')(condition, attribute, self.data[field_name])
            if not status then
                is_valid = false
                self.errors[field_name] = err
                self.error_opts[field_name] = opts
            end
        end
    end
    return is_valid
end


return form