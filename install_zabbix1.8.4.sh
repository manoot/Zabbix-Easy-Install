#!/bin/bash

# ZABBIX INSTALL SCRIPT
# VER. 0.6.4 - http://blog.brendon.com
# Copyright (c) 2008-2010 Brendon Baumgartner
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#=====================================================================

# If necessary, edit these for your system
DBUSER='root'
DBPASS=''
DBHOST='localhost'

ZBX_VER='1.8.4'
#ZBX_VER='1.8'

# DO NOT EDIT BELOW THIS LINE

function checkReturn {
  if [ $1 -ne 0 ]; then
     echo "fail: $2"
     echo "$3"
     exit
  else
     echo "pass: $2"
  fi
  sleep 3
}

cat << "eof"

=== RUN AT YOUR OWN RISK ===

DO NOT RUN ON EXISTING INSTALLATIONS, YOU *WILL* LOSE DATA

This script:
 * Installs Zabbix 1.8.x on CentOS / Red Hat 5
 * Drops an existing database
 * Does not install MySQL; to install type "yum install mysql-server"
 * Assums a vanilla OS install, though it tries to work around it
 * Does not install zabbix packages, it uses source from zabbix.com

Press Ctrl-C now if you want to exit

Wait 20 seconds...
eof
sleep 20

# check selinux
if [ "`sestatus |grep status|awk '{ print $3 }'`" == "enabled" ]; then
   checkReturn 1 "Disable SELinux and then retry"
fi
  
# Start mysql if its on this box
if [ "`rpm -qa |grep mysql-server`" ]; then
  chkconfig mysqld on
  service mysqld restart
fi

# check mysql
mysql -h${DBHOST} -u${DBUSER} --password=${DBPASS} > /dev/null << eof
status
eof
RETVAL=$?
checkReturn $RETVAL "basic mysql access" "Install mysql server packages or fix mysql permissions"


if [ ! "`rpm -qa|grep fping`" ]; then
  if [ "`uname -m`" == "x86_64" ]; then
     rpm -Uhv http://apt.sw.be/redhat/el5/en/x86_64/rpmforge/RPMS/rpmforge-release-0.3.6-1.el5.rf.x86_64.rpm
  elif [ "`uname -m`" == "i686" ]; then
     rpm -Uhv http://apt.sw.be/redhat/el5/en/i386/rpmforge/RPMS/rpmforge-release-0.3.6-1.el5.rf.i386.rpm
  fi
fi

# dependenices for curl: e2fsprogs-devel zlib-devel libgssapi-devel krb5-devel openssl-devel
yum -y install gcc mysql-devel curl-devel httpd php php-mysql php-bcmath php-gd net-snmp-devel fping e2fsprogs-devel zlib-devel libgssapi-devel krb5-devel openssl-devel libidn-devel iksemel-devel php-xml php-mbstring
RETVAL=$?
checkReturn $RETVAL "Package install"

chmod 4755 /usr/sbin/fping

cd /tmp
rm -rf zabbix-$ZBX_VER
rm zabbix-$ZBX_VER.tar.gz
#wget http://superb-east.dl.sourceforge.net/sourceforge/zabbix/zabbix-$ZBX_VER.tar.gz
wget http://downloads.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/$ZBX_VER/zabbix-$ZBX_VER.tar.gz
RETVAL=$?
checkReturn $RETVAL "downloading source" "check ZBX_VER variable or mirror might be down"
tar xzf zabbix-$ZBX_VER.tar.gz
cd zabbix-$ZBX_VER

./configure --enable-agent  --enable-ipv6  --enable-proxy  --enable-server --with-mysql --with-libcurl --with-net-snmp --with-jabber
RETVAL=$?
checkReturn $RETVAL "Configure"
# --with-jabber
# ipmi
# ldap


make
RETVAL=$?
checkReturn $RETVAL "Compile"

make install
RETVAL=$?
checkReturn $RETVAL "make install"

echo "DROP DATABASE IF EXISTS zabbix;" | mysql -h${DBHOST} -u${DBUSER} --password=${DBPASS}

(
echo "CREATE DATABASE zabbix;"
echo "USE zabbix;"
cat /tmp/zabbix-$ZBX_VER/create/schema/mysql.sql
cat /tmp/zabbix-$ZBX_VER/create/data/data.sql
cat /tmp/zabbix-$ZBX_VER/create/data/images_mysql.sql
) | mysql -h${DBHOST} -u${DBUSER} --password=${DBPASS}


#### BEGIN ZABBIX SERVER & AGENT PROCESS INSTALL & START
adduser -r -d /var/run/zabbix-server -s /sbin/nologin zabbix
mkdir -p /etc/zabbix/alert.d
mkdir -p /var/log/zabbix-server
mkdir -p /var/log/zabbix-agent
mkdir -p /var/run/zabbix-server
mkdir -p /var/run/zabbix-agent
chown zabbix.zabbix /var/run/zabbix*
chown zabbix.zabbix /var/log/zabbix*
cp /tmp/zabbix-$ZBX_VER/misc/conf/zabbix_server.conf /etc/zabbix
cp /tmp/zabbix-$ZBX_VER/misc/conf/zabbix_agentd.conf /etc/zabbix

cp /tmp/zabbix-$ZBX_VER/misc/init.d/redhat/8.0/zabbix_server /etc/init.d
cp /tmp/zabbix-$ZBX_VER/misc/init.d/redhat/8.0/zabbix_agentd /etc/init.d


cd /etc/zabbix
patch -p0 -l << "eof"
--- zabbix_server.conf.orig     2009-12-23 10:06:48.000000000 -0800
+++ zabbix_server.conf  2009-12-23 10:09:45.000000000 -0800
@@ -35,7 +35,7 @@
 # Default:
 # LogFile=

-LogFile=/tmp/zabbix_server.log
+LogFile=/var/log/zabbix-server/zabbix_server.log

 ### Option: LogFileSize
 #      Maximum size of log file in MB.
@@ -63,6 +63,7 @@
 # Mandatory: no
 # Default:
 # PidFile=/tmp/zabbix_server.pid
+PidFile=/var/run/zabbix-server/zabbix_server.pid

 ### Option: DBHost
 #      Database host name.
@@ -88,7 +89,7 @@
 # Default:
 # DBUser=

-DBUser=root
+DBUser=_dbuser_

 ### Option: DBPassword
 #      Database password. Ignored for SQLite.
@@ -97,6 +98,7 @@
 # Mandatory: no
 # Default:
 # DBPassword=
+DBPassword=_dbpass_

 ### Option: DBSocket
 #      Path to MySQL socket.
@@ -316,6 +318,7 @@
 # Mandatory: no
 # Default:
 # AlertScriptsPath=/home/zabbix/bin/
+AlertScriptsPath=/etc/zabbix/alert.d/

 ### Option: ExternalScripts
 #      Location of external scripts
eof
sed "s/_dbuser_/${DBUSER}/g" /etc/zabbix/zabbix_server.conf > /tmp/mytmp393; mv /tmp/mytmp393 /etc/zabbix/zabbix_server.conf
sed "s/_dbpass_/${DBPASS}/g" /etc/zabbix/zabbix_server.conf > /tmp/mytmp393; mv /tmp/mytmp393 /etc/zabbix/zabbix_server.conf


patch -p0 -l << "eof"
--- zabbix_agentd.conf.orig     2009-12-23 10:20:25.000000000 -0800
+++ zabbix_agentd.conf  2009-12-23 10:22:17.000000000 -0800
@@ -9,6 +9,7 @@
 # Mandatory: no
 # Default:
 # PidFile=/tmp/zabbix_agentd.pid
+PidFile=/var/run/zabbix-agent/zabbix_agentd.pid

 ### Option: LogFile
 #      Name of log file.
@@ -17,8 +18,7 @@
 # Mandatory: no
 # Default:
 # LogFile=
-
-LogFile=/tmp/zabbix_agentd.log
+LogFile=/var/log/zabbix-agent/zabbix_agentd.log

 ### Option: LogFileSize
 #      Maximum size of log file in MB.
@@ -56,6 +56,7 @@
 # Mandatory: no
 # Default:
 # EnableRemoteCommands=0
+EnableRemoteCommands=1

 ### Option: LogRemoteCommands
 #      Enable logging of executed shell commands as warnings
@@ -187,6 +188,7 @@
 # Range: 1-30
 # Default:
 # Timeout=3
+Timeout=10

 ### Option: Include
 #      You may include individual files or all files in a directory in the configuration file.
eof

cd /etc/init.d
patch -p0 -l << "eof"
--- zabbix_server.orig  2008-11-13 22:59:49.000000000 -0800
+++ zabbix_server       2008-11-13 23:53:58.000000000 -0800
@@ -14,7 +14,7 @@
 [ "${NETWORKING}" = "no" ] && exit 0
 
 RETVAL=0
-progdir="/usr/local/zabbix/bin/"
+progdir="/usr/local/sbin/"
 prog="zabbix_server"
 
 start() {
--- zabbix_agentd.orig  2008-11-14 00:15:24.000000000 -0800
+++ zabbix_agentd       2008-11-14 00:15:32.000000000 -0800
@@ -14,7 +14,7 @@
 [ "${NETWORKING}" = "no" ] && exit 0
 
 RETVAL=0
-progdir="/usr/local/zabbix/bin/"
+progdir="/usr/local/sbin/"
 prog="zabbix_agentd"
 
 start() {
eof


chkconfig zabbix_server on
chkconfig zabbix_agentd on
chmod +x /etc/init.d/zabbix_server
chmod +x /etc/init.d/zabbix_agentd
service zabbix_server restart
service zabbix_agentd restart

#### END ZABBIX SERVER & AGENT PROCESS INSTALL & START

#### BEGIN WEB

rm -rf /usr/local/share/zabbix
mkdir -p /usr/local/share/zabbix
cp -r /tmp/zabbix-$ZBX_VER/frontends/php/* /usr/local/share/zabbix

echo "Alias /zabbix /usr/local/share/zabbix" > /etc/httpd/conf.d/zabbix.conf
chkconfig httpd on
service httpd restart

#sed "s/max_execution_time = 30/max_execution_time = 300/g" /etc/php.ini > /tmp/mytmp393; mv /tmp/mytmp393 /etc/php.ini

#touch /usr/local/share/zabbix/conf/zabbix.conf.php
#chmod 666 /usr/local/share/zabbix/conf/zabbix.conf.php

cd /usr/local/share/zabbix
patch -p0 -l << "eof"
--- include/setup.inc.php.orig  2009-12-23 10:32:58.000000000 -0800
+++ include/setup.inc.php       2009-12-23 10:34:24.000000000 -0800
@@ -210,7 +210,7 @@
                                        $final_result,
                                        'PHP max execution time:',
                                        ini_get('max_execution_time').' sec',
-                                       ini_get('max_execution_time') >= 300,
+                                       ini_get('max_execution_time') >= 30,
                                        '300 sec is a minimal limitation on execution time of PHP scripts'));

                        if(version_compare(phpversion(), '5.1.0', '>=')){
@@ -220,7 +220,7 @@
                                                $final_result,
                                                'PHP Timezone:',
                                                empty($tmezone) ? 'n/a' : $tmezone,
-                                               !empty($tmezone),
+                                               empty($tmezone),
                                                'Timezone for PHP is not set. Please set "date.timezone" option in php.ini.'));
                                unset($tmezone);
                        }
--- include/page_header.php.orig        2009-12-23 10:36:53.000000000 -0800
+++ include/page_header.php     2009-12-23 10:37:55.000000000 -0800
@@ -444,8 +444,8 @@
        if(version_compare(phpversion(), '5.1.0RC1', '>=') && $page['type'] == PAGE_TYPE_HTML){
                $tmezone = ini_get('date.timezone');
                if(empty($tmezone)) {
-                       info('Timezone for PHP is not set. Please set "date.timezone" option in php.ini.');
-                       date_default_timezone_set('UTC');
+                       //info('Timezone for PHP is not set. Please set "date.timezone" option in php.ini.');
+                       //date_default_timezone_set('UTC');
                }
                unset($tmezone);
        }
eof

cat > /usr/local/share/zabbix/conf/zabbix.conf.php << "eof"
<?php
global $DB;

$DB["TYPE"]             = "MYSQL";
$DB["SERVER"]           = "_dbhost_";
$DB["PORT"]             = "0";
$DB["DATABASE"]         = "zabbix";
$DB["USER"]             = "_dbuser_";
$DB["PASSWORD"]         = "_dbpass_";
$ZBX_SERVER             = "127.0.0.1";
$ZBX_SERVER_PORT        = "10051";


$IMAGE_FORMAT_DEFAULT   = IMAGE_FORMAT_PNG;
?>
eof

sed "s/_dbhost_/${DBHOST}/g" /usr/local/share/zabbix/conf/zabbix.conf.php > /tmp/mytmp393; mv /tmp/mytmp393 /usr/local/share/zabbix/conf/zabbix.conf.php
sed "s/_dbuser_/${DBUSER}/g" /usr/local/share/zabbix/conf/zabbix.conf.php > /tmp/mytmp393; mv /tmp/mytmp393 /usr/local/share/zabbix/conf/zabbix.conf.php
sed "s/_dbpass_/${DBPASS}/g" /usr/local/share/zabbix/conf/zabbix.conf.php > /tmp/mytmp393; mv /tmp/mytmp393 /usr/local/share/zabbix/conf/zabbix.conf.php


cd 
echo "Load http://localhost/zabbix/"
echo "username: admin"
echo "password: zabbix"

