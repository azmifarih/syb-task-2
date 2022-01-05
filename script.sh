#!/bin/bash

## Creating user
while getopts u:g:p: flag
do
    case "${flag}" in
        u) username=${OPTARG};;
        g) groupname=${OPTARG};;
        p) publickey=${OPTARG};;
    esac
done

if [[ "$groupname" == "devops" ]]; then
        adduser --disabled-password --gecos "" $username
	usermod -a -G devops $username
	cp $publickey /tmp/
	chown $username:$username /tmp/$publickey
	su $username -c "if [ ! -d ~/.ssh ]; then
             	mkdir ~/.ssh
           fi
      	   chmod 700 ~/.ssh
      	   cat /tmp/$publickey >> ~/.ssh/authorized_keys
           chmod 0600 ~/.ssh/authorized_keys"
        rm -rf /tmp/$publickey
	pass=`openssl rand -base64 16`
	echo "$username:$pass" | chpasswd
	echo "$username'password is: $pass"
elif [[ "$groupname" == "dev" ]]; then
	adduser --disabled-password --gecos "" $username
	usermod -a -G dev $username
        pass=`openssl rand -base64 16`
        echo "$username:$pass" | chpasswd
        echo "$username'password is: $pass"
else
## Hardening
    if [ -f /etc/security/limits.d/custom.conf ]; then
	echo "That's good"
    else
	echo -e "* soft nofile 6400\n* hard nofile 64000\n* soft nproc 6400\n* hard nproc 64000" >> /etc/security/limits.d/custom.conf
    fi

    if [ -f /etc/sysctl.d/60-custom.conf ]; then
	echo "That's good"
    else
	echo -e \
"net.core.wmem_default= 8388608
net.core.rmem_default= 8388608
net.core.rmem_max= 16777216
net.core.wmem_max= 16777216
net.ipv4.tcp_rmem= 10240 87380 12582912
net.ipv4.tcp_wmem= 10240 87380 12582912
net.ipv4.tcp_window_scaling= 1
net.ipv4.tcp_timestamps= 1
net.ipv4.tcp_sack= 1" >> /etc/sysctl.d/60-custom.conf
    	sysctl -p
    fi
    if [ `grep -c \
"Match Group dev
        ForceCommand internal-sftp
        PasswordAuthentication yes
        ChrootDirectory /opt/sayurbox
        PermitTunnel no
        AllowAgentForwarding no
        AllowTcpForwarding no
        X11Forwarding no" /etc/ssh/sshd_config` == 1 ]; then
    echo "That's good"
    else
    	sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    fi
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 0/' /etc/ssh/sshd_config
    sed -i 's/#Port 22/Port 22000/' /etc/ssh/sshd_config
    sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i 's/#HostKey \/etc\/ssh\/ssh_host_ed25519_key/HostKey \/etc\/ssh\/ssh_host_ed25519_key/' /etc/ssh/sshd_config
    sed -i 's/#HostKey \/etc\/ssh\/ssh_host_rsa_key/HostKey \/etc\/ssh\/ssh_host_rsa_key/' /etc/ssh/sshd_config

    if grep -q "KexAlgorithms diffie-hellman-group-exchange-sha256
	    MACs hmac-sha2-512,hmac-sha2-256
	    Ciphers aes256-ctr,aes192-ctr,aes128-ctr" /etc/ssh/sshd_config; then
        echo "That's good"
    else
	echo -e \
"KexAlgorithms diffie-hellman-group-exchange-sha256
MACs hmac-sha2-512,hmac-sha2-256
Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
    fi

    systemctl restart sshd

    ufw default allow outgoing
    ufw allow 22000
    ufw allow 80
    ufw allow 27017
    ufw allow 443
    echo "y" | ufw enable

## Install Mongodb
    curl -fsSL https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -

    if [ -f /etc/apt/sources.list.d/mongodb-org-5.0.list ]; then
    	echo "That's good"
    else
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/5.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-5.0.list
    fi

    apt update
    apt install -y mongodb-org
    systemctl start mongod.service
    systemctl enable mongod.service

## Install HTTPD
    apt install -y apache2
    systemctl start apache2
    systemctl enable apache2

    mkdir -p /opt/sayurbox/sample-web-app
    chown dev:dev /opt/sayurbox/sample-web-app
    chmod 755 /opt/sayurbox/sample-web-app
    if [ -f /etc/apache2/sites-available/sayurbox.conf ]; then
   	echo "That's good"
    else
	echo -e \
"<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName sayurbox
    ServerAlias www.sayurbox.com
    DocumentRoot /opt/sayurbox/sample-web-app
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" >> /etc/apache2/sites-available/sayurbox.conf
    fi

    a2ensite sayurbox.conf
    a2dissite 000-default.conf
    systemctl restart apache2

## Manage Dev user
    chown root:root /opt/sayurbox
    chown dev:dev /opt/sayurbox/sample-web-app
    chmod 770 /opt/sayurbox/sample-web-app

    cd /opt/sayurbox/sample-web-app
    mount --bind /var/log/ log

    sed -i 's/\/usr\/lib\/openssh\/sftp\-server/internal\-sftp/' /etc/ssh/sshd_config
    if [ `grep -c \
"Match Group dev
        ForceCommand internal-sftp
        PasswordAuthentication yes
        ChrootDirectory /opt/sayurbox
        PermitTunnel no
        AllowAgentForwarding no
        AllowTcpForwarding no
        X11Forwarding no" /etc/ssh/sshd_config` == 1 ]; then
        echo "That's good"
    else
        echo -e \
"Match Group dev
	ForceCommand internal-sftp
	PasswordAuthentication yes
	ChrootDirectory /opt/sayurbox
	PermitTunnel no
	AllowAgentForwarding no
	AllowTcpForwarding no
	X11Forwarding no" >> /etc/ssh/sshd_config
        echo "Let's config"
    fi
    systemctl restart sshd

    if [[ -f /etc/logrotate.d/override ]]; then
	echo "That's good"
    else
	echo -e \
"rotate 14
compress
delaycompress
dateext" >> /etc/logrotate.d/override
	sed -i 's/}/        include \/etc\/logrotate.d\/override\n}/g' /etc/logrotate.d/*
    fi
fi
