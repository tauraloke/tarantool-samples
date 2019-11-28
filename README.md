

# Для установки
см. INSTALL.md

# Для развёртывания
* Написана консольная утилита tusker.lua
* Для подключения SSL положить server.crt, server.csr, server.key, server.key.secure в папки ./security, ./security-dev

## tusker.lua
* ./tusker tnt start - запуск сервера Tarantool на снэпшоте базы проекта.
* ./tusker tnt stop - останов сервера Tarantool
* ./tusker tnt drop - уничтожение снэпшота базы
* ./tusker tnt recreate - пересоздание базы проекта на основе миграций
* ./tusker tnt log - вывод последних строчек лог-файла Tarantool
* ./tusker tnt repl - быстрый доступ к консоли сервера Tarantool
* ./tusker ngx start - запуск сервера Nginx. Создаёт файл конфигурации из шаблона nginx.conf.template
* ./tusker ngx stop - останов сервера Nginx
* ./tusker ngx drop - удаление конфигурации сервера Nginx из /etc/nginx/sites-enabled/
* ./tusker ngx log - доступ к хвосту лога Nginx
* ./tusker migration make - создать файл миграции на основе новой таблицы в Tarantool
* ./tusker migration up - выполнить следующую миграцию
* ./tusker migration down - откатиться к предыдущей миграции. Данные могут быть потеряны.
* ./tusker migration clean - стереть все созданные скрипты миграций.



