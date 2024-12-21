#!/bin/bash
#VARIABLE GLOBAL A CHANGER
#########################

PORT_SSH=22
ROOT_USER="root"
ROOT_PASS=123456

NC_USER="nc"
NC_PASS="123456789"
NC_DB="nextcloud"

DOLI_USER="doli"
DOLI_PASS="123456789"
DOLI_DB="dolibarr"

SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEAm3UCvd6vS6Hp6Do4LZcUeUbTzDrPCV38DDj5eRMUw lucas@tardis-eavour"

DOLIVERSION=20.0.2 # ne pas changer sauf si on veut une auter vesion // faut check le site officiel avant

#########################
#VARIABLE GLOBAL A CHANGER

# verif root

if [ "$EUID" -ne 0 ]; then
  echo "Il faut être root"
  exit 1
fi

#réseau
INTERFACE=$(ip route | grep src | cut -d " " -f 3)
IP=$(ip route | grep src | cut -d " " -f 9)
GATEWAY=$(ip route | grep default | cut -d " " -f 3)

echo "auto lo" >>buffip
echo "iface lo inet loopback" >>buffip

echo "allow-hotplug ${INTERFACE}" >>buffip
echo "iface ${INTERFACE} inet static" >>buffip

echo "address ${IP}" >>buffip
echo "gateway ${GATEWAY}" >>buffip

rm /etc/network/interfaces
mv buffip /etc/network/interfaces

systemctl restart networking

#dependances
apt update
apt install -y zip unzip apache2 curl php mariadb-server ssh php8.2-{zip,mysql,dom,XMLWriter,XMLReader,xml,mbstring,GD,SimpleXML,cURL,intl,IMAP}

#SSH
#clef publique

mkdir ~/.ssh/authorized_keys
echo "${SSH_PUB_KEY}" >>~/.ssh/authorized_keys

echo "Port ${PORT_SSH}" >>buffssh
echo "PermitRootLogin prohibit-password" >>buffssh
echo "PubkeyAuthentication yes" >>buffssh
echo "PasswordAuthentication no" >>buffssh

mv buffssh /etc/ssh/sshd_config.d/main_ssh_conf
rm buffssh

systemctl restart ssh.service

wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip
wget https://sourceforge.net/projects/dolibarr/files/Dolibarr%20ERP-CRM/20.0.2/dolibarr-${DOLIVERSION}.zip/download -O dolibarr.zip

unzip dolibarr.zip -d /var/www/
unzip nextcloud.zip -d /var/www/

mv /var/www/dolibarr-${DOLIVERSION}/* /var/www/dolibarr/

rmdir /var/www/dolibarr-${DOLIVERSION}
rm nextcloud.zip
rm dolibarr.zip

chown -R www-data /var/www/nextcloud/
chown -R www-data /var/www/dolibarr/

chown -R www-data /var/ncdata/
chown -R www-data /var/dolidata/

#config apache dolibarr

APACHE_LOG_DIR=/var/log/apache2

echo "<VirtualHost *:80>" >>dolitmp
echo "  ServerName doli.mc.local" >>dolitmp
echo "  ServerAdmin webmaster@localhost" >>dolitmp
echo "  DocumentRoot /var/www/dolibarr/htdocs" >>dolitmp
echo "  ErrorLog ${APACHE_LOG_DIR}/error.log" >>dolitmp
echo "  CustomLog ${APACHE_LOG_DIR}/access.log combined" >>dolitmp
echo "</VirtualHost>" >>dolitmp

mv dolitmp /etc/apache2/sites-available/001-dolibarr.conf

#config apache nextcloud

echo "<VirtualHost *:80>" >>apachetmp
echo "  ServerName nc.mc.local" >>apachetmp
echo "  ServerAdmin webmaster@localhost" >>apachetmp
echo "  DocumentRoot /var/www/nextcloud" >>apachetmp
echo "  ErrorLog ${APACHE_LOG_DIR}/error.log" >>apachetmp
echo "  CustomLog ${APACHE_LOG_DIR}/access.log combined" >>apachetmp
echo "</VirtualHost>" >>apachetmp

mv apachetmp /etc/apache2/sites-available/002-nextcloud.conf

a2ensite 001-dolibarr.conf
a2ensite 002-nextcloud.conf

systemctl reload apache2

systemctl restart apache2.service

# DB !!

mysql -u "$ROOT_USER" -p"$ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS \`${NC_DB}\`;"
mysql -u "$ROOT_USER" -p"$ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS \`${DOLI_DB}\`;"

mysql -u "$ROOT_USER" -p"$ROOT_PASS" -e "
CREATE USER IF NOT EXISTS '${NC_USER}'@'localhost' IDENTIFIED BY '${NC_PASS}';
GRANT ALL PRIVILEGES ON \`${NC_DB}\`.* TO '${NC_USER}'@'localhost';
"

mysql -u "$ROOT_USER" -p"$ROOT_PASS" -e "
CREATE USER IF NOT EXISTS '${DOLI_USER}'@'localhost' IDENTIFIED BY '${DOLI_PASS}';
GRANT ALL PRIVILEGES ON \`${DOLI_DB}\`.* TO '${DOLI_USER}'@'localhost';
"

mysql -u "$ROOT_USER" -p"$ROOT_PASS" -e "FLUSH PRIVILEGES;"
#pour ce connaitre soit meme

echo "127.0.0.1 nc.mc.local" >>/etc/hosts
echo "127.0.0.1 doli.mc.local" >>/etc/hosts
echo "127.0.0.1 mc.local" >>/etc/hosts

# config nextcloud via OCC (comme artisan)
php /var/www/nextcloud/occ maintenance:install --database "mysql" --database-name "${NC_DB}" --database-user "${NC_USER}" --database-pass "${NC_PASS}" --admin-user "${NC_USER}" --admin-pass "${NC_PASS}" --data-dir "/var/ncdata"

sed -i "/0 => 'localhost',/a 1 => 'nc.mc.local'," /var/www/nextcloud/config/config.php

chown -R www-data /var/ncdata/
chown -R www-data /var/www/nextcloud/

# changer les droits
chown -R www-data /var/www/dolibarr/
chown -R www-data /var/dolidata

echo '
<?php
$dolibarr_main_url_root = "http://doli.mc.local";
$dolibarr_main_document_root = "/var/www/dolibarr/htdocs";
$dolibarr_main_data_root = "/var/dolidata";
$dolibarr_main_db_host = "localhost";
$dolibarr_main_db_port = "3306";
$dolibarr_main_db_name = "'${DOLI_DB}'";
$dolibarr_main_db_user = "'${DOLI_USER}'";
$dolibarr_main_db_pass = "'${DOLI_PASS}'";
$dolibarr_main_db_type = 'mysqli';
$dolibarr_main_prod = '1';
$dolibarr_main_use_javascript_ajax = '1';
?>
'

systemctl restart apache2.service
