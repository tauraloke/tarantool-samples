
-- tweak for caching i18n files: import without loadFile 
local function custom_i18n_loadFile(code)
  local chunk = assert(require('src.i18n.'..code))
  res.lib.load(chunk)
end


local res = {}

  res.lib = require('i18n')
  res.default_lang = 'ru'
  res.fallback_lang = 'en'


  res.get_locale = function(...)
    return res.lib.getLocale(...)
  end
  
  

  res.translate = function(text, options)
    if not text then
      return nil
    end
    options = options or {}
    local prefix = options.prefix or ''

    if(config and config.show_i18n_code) then return text..':'..res.lib.translate(text, options) end
    local result = res.lib(prefix..text, options)
    if not result then
      if prefix~='' then
        options.prefix = nil
        return res.translate(text, options)
      else
        return ":"..text..":", 'missed translation'
      end
    end
    return result
  end
  
  
  res.lang_list = {}
  
  
  res.load = function(i18n_path, rel)
    if not rel then rel = '' end
    lfs = require 'lfs'
    if lfs.attributes(i18n_path).mode~= 'directory' then
      return nil, 'input parameter is not directory path', i18n_path
    end
    for file in lfs.dir(i18n_path) do
      local attr = lfs.attributes(i18n_path..'/'..file)
      if attr and attr.mode=='file' then
        local filename = file:match('(.*).lua')
        if filename then
          local chunk = require(i18n_path:gsub('^%.',''):gsub('^%/',''):gsub('%/$',''):gsub('/','.')..'.'..filename)
          local mchunk = {}
          for lang, dict in pairs(chunk) do
            if not mchunk[lang] then
              mchunk[lang] = {}
            end
            for key, value in pairs(dict) do
              mchunk[lang][rel..key] = value
              if key=='_title_' then
                res.lang_list[lang] = value
              end
            end
          end
          res.lib.load(mchunk)
        end
      elseif attr and attr.mode=='directory' and not file:match('^%.') then
        res.load(i18n_path..'/'..file, rel..file..'.')
      end
    end
  end
  
  
  -- detect language by headers
  res.detect_locale = function(request)
    local language_code = res.default_lang  -- default language
    res.lib.fallbackLocale  = res.fallback_lang

    if(request:cookie('locale')) then
      language_code = request:cookie('locale'):match('%w%w')  -- only two letters in locale code, for example: en, ru, ja
    elseif(request.headers and request.headers['accept-language']) then
      language_code = string.match(request.headers['accept-language'], '^([a-zA-Z-]+),')
    end

    res.lib.setLocale(language_code)
    if not res.translate('_title_') then
      language_code = string.match(language_code, '^([a-z]+)-')
      res.lib.setLocale(language_code)
      if not res.translate('_title_') then
        language_code = res.lib.fallbackLocale
        res.lib.setLocale(language_code)
      end
    end

    --[[
    pcall(function()
      os.setlocale(helper_i18n('_system_locale_'), 'time')  -- потенциально опасная строка - без указания области 'time' иногда возникает ошибка сериализации json: Expected comma or object end but found T_STRING at character 17. Следовательно, должно быть парное переключение в after_dispatch
    end)
    ==]]
  end


  
  res.city_by_ip = function(ip)
    if(ip=='127.0.0.1') then return 'Localhost' end
    local locale = res.lib.getLocale()
    local fallback = res.lib.fallbackLocale
    local record = mmdb_geodb:search_ipv4(ip)
    if(not record or not record.city or not record.city.names) then return res.translate('error.geoip_unknown_place') end
    if(record.city.names[locale]) then return record.city.names[locale] end
    if(record.city.names[fallback]) then return record.city.names[fallback] end
    return helper_i18n('geoip_unknown_place')
  end



setmetatable(res, {
  __call = function(self, ...) return self.translate(...) end
})

return res


