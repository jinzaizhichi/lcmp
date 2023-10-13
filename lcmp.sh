#!/bin/bash
#
# This is a Shell script for VPS initialization and
# LCMP (Linux + Caddy + MariaDB + PHP) rpm installation
# Supported OS: Enterprise Linux 7/8/9
#
# Copyright (C) 2023 Teddysun <i@teddysun.com>
#
trap _exit INT QUIT TERM

cur_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

[ ${EUID} -ne 0 ] && _red "This script must be run as root!\n" && exit 1

_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

_printargs() {
    printf -- "%s" "[$(date)] "
    printf -- "%s" "$1"
    printf "\n"
}

_info() {
    _printargs "$@"
}

_warn() {
    printf -- "%s" "[$(date)] "
    _yellow "$1"
    printf "\n"
}

_error() {
    printf -- "%s" "[$(date)] "
    _red "$1"
    printf "\n"
    exit 2
}

_exit() {
    printf "\n"
    _red "$0 has been terminated."
    printf "\n"
    exit 1
}

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

_error_detect() {
    local cmd="$1"
    _info "${cmd}"
    eval ${cmd} 1>/dev/null
    if [ $? -ne 0 ]; then
        _error "Execution command (${cmd}) failed, please check it and try again."
    fi
}

get_char() {
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2>/dev/null
    stty -raw
    stty echo
    stty ${SAVEDSTTY}
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

rhelversion() {
    local version=$(get_opsy)
    local code=$1
    local main_ver=$(echo ${version} | grep -oE "[0-9.]+")
    if [ "${main_ver%%.*}" == "${code}" ]; then
        return 0
    else
        return 1
    fi
}

version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

check_kernel_version() {
    local kernel_version=$(uname -r | cut -d- -f1)
    if version_ge ${kernel_version} 4.9; then
        return 0
    else
        return 1
    fi
}

check_bbr_status() {
    local param=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ x"${param}" == x"bbr" ]]; then
        return 0
    else
        return 1
    fi
}

# Check OS
if ! rhelversion 7 && ! rhelversion 8 && ! rhelversion 9; then
    _error "Not supported OS, please change OS to Enterprise Linux 7 or 8 or 9 and try again."
fi
# Set MariaDB root password
_info "Please input the root password of MariaDB:"
read -p "[$(date)] (Default password: Teddysun.com):" db_pass
if [ -z "${db_pass}" ]; then
    db_pass="Teddysun.com"
fi
_info "---------------------------"
_info "Password = $(_red ${db_pass})"
_info "---------------------------"

# Choose PHP version
while true; do
    _info "Please choose a version of the PHP:"
    _info "$(_green 1). PHP 7.4"
    _info "$(_green 2). PHP 8.0"
    _info "$(_green 3). PHP 8.1"
    _info "$(_green 4). PHP 8.2"
    read -p "[$(date)] Please input a number: (Default 4) " php_version
    [ -z "${php_version}" ] && php_version=4
    case "${php_version}" in
        1)
        if rhelversion 7; then
            remi_php="remi-php74"
        else
            remi_php="php:remi-7.4"
        fi
        break
        ;;
        2)
        if rhelversion 7; then
            remi_php="remi-php80"
        else
            remi_php="php:remi-8.0"
        fi
        break
        ;;
        3)
        if rhelversion 7; then
            remi_php="remi-php81"
        else
            remi_php="php:remi-8.1"
        fi
        break
        ;;
        4)
        if rhelversion 7; then
            remi_php="remi-php82"
        else
            remi_php="php:remi-8.2"
        fi
        break
        ;;
        *)
        _info "Input error! Please only input a number 1 2 3 4"
        ;;
    esac
done
_info "---------------------------"
_info "PHP version = $(_red ${php_version})"
_info "---------------------------"

_info "Press any key to start...or Press Ctrl+C to cancel"
char=$(get_char)

_info "VPS initialization start"

_error_detect "rm -f /etc/localtime"
_error_detect "ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
_error_detect "yum install -yq yum-utils epel-release"
_error_detect "yum-config-manager --enable epel"

if rhelversion 8; then
    yum-config-manager --enable powertools >/dev/null 2>&1 || yum-config-manager --enable PowerTools >/dev/null 2>&1
    _info "Set enable PowerTools Repository completed"
fi
if rhelversion 9; then
    _error_detect "yum-config-manager --enable crb"
    _info "Set enable CRB Repository completed"
    echo "set enable-bracketed-paste off" >>/etc/inputrc
fi
_error_detect "yum install -yq vim tar zip unzip net-tools bind-utils screen git virt-what wget whois firewalld mtr traceroute iftop htop jq tree"
_error_detect "yum-config-manager --add-repo https://dl.lamp.sh/linux/rhel/teddysun_linux.repo"
_info "Teddysun's Linux Repository installation completed"

_error_detect "yum makecache"
# Replaced local curl from teddysun linux Repository
_error_detect "yum install -yq curl libcurl libcurl-devel"

if [ -s "/etc/selinux/config" ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's@^SELINUX.*@SELINUX=disabled@g' /etc/selinux/config
    setenforce 0
    _info "Disable SElinux completed"
fi

if [ -s "/etc/motd.d/cockpit" ]; then
    rm -f /etc/motd.d/cockpit
    _info "Delete /etc/motd.d/cockpit completed"
fi

# if systemctl status postfix >/dev/null 2>&1; then
    # _error_detect "systemctl stop postfix"
    # _error_detect "systemctl disable postfix"
    # _info "Disable postfix completed"
# fi

# if systemctl status rngd >/dev/null 2>&1; then
    # _error_detect "systemctl stop rngd"
    # _error_detect "systemctl disable rngd"
    # _info "Disable rngd completed"
# fi

# if systemctl status rpcbind >/dev/null 2>&1; then
    # _error_detect "systemctl stop rpcbind"
    # _error_detect "systemctl stop rpcbind.socket"
    # _error_detect "systemctl disable rpcbind"
    # _error_detect "systemctl disable rpcbind.socket"
    # _info "Disable rpcbind completed"
# fi

# if systemctl status sssd >/dev/null 2>&1; then
    # _error_detect "systemctl stop sssd"
    # _error_detect "systemctl stop sssd-kcm"
    # _error_detect "systemctl stop sssd-kcm.socket"
    # _error_detect "systemctl disable sssd"
    # _error_detect "systemctl disable sssd-kcm"
    # _error_detect "systemctl disable sssd-kcm.socket"
    # _info "Disable sssd completed"
# fi

if systemctl status firewalld >/dev/null 2>&1; then
    default_zone="$(firewall-cmd --get-default-zone)"
    firewall-cmd --permanent --add-service=https --zone=${default_zone} >/dev/null 2>&1
    firewall-cmd --permanent --add-service=http --zone=${default_zone} >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    sed -i 's@AllowZoneDrifting=yes@AllowZoneDrifting=no@' /etc/firewalld/firewalld.conf
    _error_detect "systemctl restart firewalld"
    _info "Set firewall completed"
else
    _warn "firewalld looks like not running, skip setting up firewall"
fi

if [ -f "/etc/resolv.conf" ]; then
    [ -f "/etc/resolv.conf.bak" ] && rm -f /etc/resolv.conf.bak
    _error_detect "cp -pv /etc/resolv.conf /etc/resolv.conf.bak"
    cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    chattr +i /etc/resolv.conf
    # cat /etc/resolv.conf
    _info "Set resolver completed"
fi

if [ -f "/etc/ssh/sshd_config" ]; then
    _error_detect "cp -pv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak"
    if rhelversion 9; then
        cat >/etc/ssh/sshd_config <<EOF
Port 8888
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
PermitRootLogin yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
GSSAPIAuthentication no
GSSAPICleanupCredentials no
UsePAM yes
X11Forwarding yes
UseDNS no
PrintMotd no
Subsystem sftp /usr/libexec/openssh/sftp-server
Include /etc/crypto-policies/back-ends/opensshserver.config
EOF
    else
        cat >/etc/ssh/sshd_config <<EOF
Port 8888
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
PermitRootLogin yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
GSSAPIAuthentication no
GSSAPICleanupCredentials no
UsePAM yes
X11Forwarding yes
UseDNS no
AcceptEnv LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv LC_IDENTIFICATION LC_ALL LANGUAGE
AcceptEnv XMODIFIERS
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF
    fi
    _error_detect "systemctl restart sshd"
    # systemctl status sshd > /dev/null 2>&1
    _info "Set sshd completed"
fi

if check_kernel_version; then
    if ! check_bbr_status; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
        echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
        echo "net.core.rmem_max=2500000" >>/etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
        _info "Set bbr completed"
    fi
fi

# Add 2GB SWAP if not exist
# SWAP=$(LANG=C; free -m | awk '/Swap/ {print $2}')
# if [ "${SWAP}" == "0" ]; then
    # _error_detect "dd if=/dev/zero of=/swapfile bs=1024 count=2048k"
    # _error_detect "chmod 600 /swapfile"
    # _error_detect "mkswap /swapfile"
    # _error_detect "swapon /swapfile"
    # echo "/swapfile   swap        swap    defaults        0   0" >> /etc/fstab
    # _info "Set Swap completed"
# fi

if systemctl status systemd-journald >/dev/null 2>&1; then
    sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
    sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=16M/' /etc/systemd/journald.conf
    sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=16M/' /etc/systemd/journald.conf
    _error_detect "systemctl restart systemd-journald"
    _info "Set systemd-journald completed"
fi

echo
netstat -nxtulpe
echo
_info "VPS initialization completed"
sleep 3
clear
_info "LCMP (Linux + Caddy + MariaDB + PHP) rpm installation start"
if rhelversion 7; then
    _error_detect "yum install -yq yum-plugin-copr"
    _error_detect "yum copr enable -yq @caddy/caddy"
    _error_detect "yum install -yq caddy"
fi
if rhelversion 8 || rhelversion 9; then
    _error_detect "yum install -yq dnf-plugins-core"
    _error_detect "yum copr enable -yq @caddy/caddy"
    _error_detect "yum install -yq caddy"
fi
_info "Caddy installation completed"

_error_detect "mkdir -p /data/www/default"
_error_detect "mkdir -p /var/log/caddy/"
_error_detect "mkdir -p /etc/caddy/conf.d/"
_error_detect "chown -R caddy:caddy /data/www/default"
_error_detect "chown -R caddy:caddy /var/log/caddy/"
cat >/etc/caddy/Caddyfile <<EOF
{
	admin off
}
import /etc/caddy/conf.d/*.conf
EOF

cat >/etc/caddy/conf.d/default.conf <<EOF
:80 {
	header {
		Strict-Transport-Security "max-age=31536000; preload"
		X-Content-Type-Options nosniff
		X-Frame-Options SAMEORIGIN
	}
	root * /data/www/default
	encode gzip
	php_fastcgi unix//run/php-fpm/www.sock
	file_server {
		index index.html
	}
	log {
		output file /var/log/caddy/access.log {
			roll_size 100mb
			roll_keep 3
			roll_keep_for 7d
		}
	}
}
EOF

_error_detect "cp -f ${cur_dir}/conf/favicon.ico /data/www/default/"
_error_detect "cp -f ${cur_dir}/conf/index.html /data/www/default/"
_error_detect "cp -f ${cur_dir}/conf/lcmp.png /data/www/default/"
_error_detect "chown -R caddy:caddy /data/www"
_info "Set Caddy completed"

_error_detect "wget -qO mariadb_repo_setup.sh https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
_error_detect "chmod +x mariadb_repo_setup.sh"
_info "./mariadb_repo_setup.sh --mariadb-server-version=mariadb-10.11"
./mariadb_repo_setup.sh --mariadb-server-version=mariadb-10.11 >/dev/null 2>&1
_error_detect "rm -f mariadb_repo_setup.sh"
_error_detect "yum install -y MariaDB-common MariaDB-server MariaDB-client MariaDB-shared MariaDB-backup"
_info "MariaDB installation completed"

lnum=$(sed -n '/\[mysqld\]/=' /etc/my.cnf.d/server.cnf)
sed -i "${lnum}ainnodb_buffer_pool_size = 100M\nmax_allowed_packet = 1024M\nnet_read_timeout = 3600\nnet_write_timeout = 3600" /etc/my.cnf.d/server.cnf
lnum=$(sed -n '/\[mariadb\]/=' /etc/my.cnf.d/server.cnf)
sed -i "${lnum}acharacter-set-server = utf8mb4\n\n\[client-mariadb\]\ndefault-character-set = utf8mb4" /etc/my.cnf.d/server.cnf
_error_detect "systemctl start mariadb"
/usr/bin/mysql -e "grant all privileges on *.* to root@'127.0.0.1' identified by \"${db_pass}\" with grant option;"
/usr/bin/mysql -e "grant all privileges on *.* to root@'localhost' identified by \"${db_pass}\" with grant option;"
/usr/bin/mysql -uroot -p${db_pass} 2>/dev/null <<EOF
drop database if exists test;
delete from mysql.db where user='';
delete from mysql.db where user='PUBLIC';
delete from mysql.user where user='';
delete from mysql.user where user='mysql';
delete from mysql.user where user='PUBLIC';
flush privileges;
exit
EOF
_error_detect "cd /data/www/default"
# Install phpMyAdmin
_error_detect "wget -q https://dl.lamp.sh/files/pma.tar.gz"
_error_detect "tar zxf pma.tar.gz"
_error_detect "rm -f pma.tar.gz"
_error_detect "cd ${cur_dir}"
_info "/usr/bin/mysql -uroot -p 2>/dev/null < /data/www/default/pma/sql/create_tables.sql"
/usr/bin/mysql -uroot -p${db_pass} 2>/dev/null < /data/www/default/pma/sql/create_tables.sql
_info "Set MariaDB completed"

if rhelversion 7; then
    _error_detect "yum install -yq https://rpms.remirepo.net/enterprise/remi-release-7.rpm"
    _error_detect "yum-config-manager --disable 'remi-php*'"
    _error_detect "yum-config-manager --enable ${remi_php}"
fi
if rhelversion 8; then
    _error_detect "yum install -yq https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
    _error_detect "yum module reset -yq php"
    _error_detect "yum module install -yq ${remi_php}"
fi
if rhelversion 9; then
    _error_detect "yum install -yq https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
    _error_detect "yum module reset -yq php"
    _error_detect "yum module install -yq ${remi_php}"
fi
_error_detect "yum install -yq php-common php-fpm php-cli php-bcmath php-embedded php-gd php-imap php-mysqlnd php-dba php-pdo php-pdo-dblib"
_error_detect "yum install -yq php-pgsql php-odbc php-enchant php-gmp php-intl php-ldap php-snmp php-soap php-tidy php-opcache php-process"
_error_detect "yum install -yq php-pspell php-shmop php-sodium php-ffi php-brotli php-lz4 php-xz php-zstd php-pecl-rar"
_error_detect "yum install -yq php-pecl-imagick-im7 php-pecl-zip php-pecl-mongodb php-pecl-grpc php-pecl-yaml php-pecl-uuid composer"
_info "PHP installation completed"

sed -i "s@^user.*@user = caddy@" /etc/php-fpm.d/www.conf
sed -i "s@^group.*@group = caddy@" /etc/php-fpm.d/www.conf
sed -i "s@^listen.acl_users.*@listen.acl_users = apache,nginx,caddy@" /etc/php-fpm.d/www.conf
sed -i "s@^;php_value\[opcache.file_cache\].*@php_value\[opcache.file_cache\] = /var/lib/php/opcache@" /etc/php-fpm.d/www.conf
_error_detect "chown root:caddy /var/lib/php/session"
_error_detect "chown root:caddy /var/lib/php/wsdlcache"
_error_detect "chown root:caddy /var/lib/php/opcache"
sed -i "s@^disable_functions.*@disable_functions = passthru,exec,shell_exec,system,chroot,chgrp,chown,proc_open,proc_get_status,ini_alter,ini_alter,ini_restore@" /etc/php.ini
sed -i "s@^max_execution_time.*@max_execution_time = 300@" /etc/php.ini
sed -i "s@^max_input_time.*@max_input_time = 300@" /etc/php.ini
sed -i "s@^post_max_size.*@post_max_size = 128M@" /etc/php.ini
sed -i "s@^upload_max_filesize.*@upload_max_filesize = 128M@" /etc/php.ini
sed -i "s@^expose_php.*@expose_php = Off@" /etc/php.ini
sed -i "s@^short_open_tag.*@short_open_tag = On@" /etc/php.ini
sock_location="/var/lib/mysql/mysql.sock"
sed -i "s#mysqli.default_socket.*#mysqli.default_socket = ${sock_location}#" /etc/php.ini
sed -i "s#pdo_mysql.default_socket.*#pdo_mysql.default_socket = ${sock_location}#" /etc/php.ini
_info "Set PHP completed"

_error_detect "systemctl start php-fpm"
_error_detect "systemctl start caddy"
sleep 1
_info "systemctl enable mariadb"
systemctl enable mariadb >/dev/null 2>&1
_info "systemctl enable php-fpm"
systemctl enable php-fpm >/dev/null 2>&1
_info "systemctl enable caddy"
systemctl enable caddy >/dev/null 2>&1
pkill -9 gpg-agent
_info "ps -ef | grep -v grep | grep \"/usr/bin/caddy\""
ps -ef | grep -v grep | grep "/usr/bin/caddy"
_info "ps -ef | grep -v grep | grep php-fpm"
ps -ef | grep -v grep | grep php-fpm
_info "ps -ef | grep -v grep | grep mariadbd"
ps -ef | grep -v grep | grep mariadbd
echo
_info "LCMP (Linux + Caddy + MariaDB + PHP) rpm installation completed"
