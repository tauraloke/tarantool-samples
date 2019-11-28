-- see errcodes in src/dbo/validate.lua

return {
    ru = {
        field_cannot_be_empty = 'не может быть пустым',
        field_is_already_occupied = 'уже занято',
        field_type_dismatch = 'некорректный тип',
        field_is_too_short = 'недостаточная длина (меньше %{count} символов)',
        field_is_too_long = 'избыточная длина (больше %{count} символов)',
        field_is_too_small = 'значение слишком мало (меньше %{count})',
        field_is_too_big = 'значение слишком велико (больше %{count})',
        field_pattern_is_not_valid = 'недопустимые символы',
        unequal_values = 'не совпадает',
    }
}