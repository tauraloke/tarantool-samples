Сначала поставить Tarantool 1.10:

* установить утилиты, если это необходимо
apt-get -y install sudo
sudo apt-get -y install gnupg2
sudo apt-get -y install curl

curl http://download.tarantool.org/tarantool/1.10/gpgkey | sudo apt-key add -

* установить утилиту lsb-release, чтобы узнать кодовое имя вашей ОС;
* также вы можете указать кодовое имя ОС вручную (например, xenial или bionic)
sudo apt-get -y install lsb-release
release=`lsb_release -c -s`

* установить средство загрузки https для APT
sudo apt-get -y install apt-transport-https

* добавить две строки в список репозиториев исходного кода
sudo rm -f /etc/apt/sources.list.d/*tarantool*.list
echo "deb http://download.tarantool.org/tarantool/1.10/ubuntu/ ${release} main" | sudo tee /etc/apt/sources.list.d/tarantool_1_10.list
echo "deb-src http://download.tarantool.org/tarantool/1.10/ubuntu/ ${release} main" | sudo tee -a /etc/apt/sources.list.d/tarantool_1_10.list

* установить tarantool
sudo apt-get -y update
sudo apt-get -y install tarantool



* Установиить недостающие пакеты:
sudo apt-get install nginx-core nginx-extra luarocks


* Установить модули lua:
sudo luarocks install compat53 
   luafilesystem 
   ansicolors 
   i18n 
   mmdblua 
   lua-cjson 
   etlua


