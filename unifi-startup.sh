#!/bin/sh
#
# Version 1.0.2   3-8-2019
# (c)2019 - Rob Asher
#
# This is a startup script for UniFi controller on CentOS 7 x86_64 based Google Compute Engine instances.
# For questions and instructions:  https://www.reddit.com/r/nxfilter/
#
# Inspired by, derived from, and portions blatantly stolen from work by:
#        Petri Riihikallio Metis Oy  -  https://metis.fi/en/2018/02/unifi-on-gcp/
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#==============================================================================================


ENABLED=true
LOGFILE="/var/log/unifi/gcp-unifi.log"
LOGGER='/usr/bin/logger'
HEADER='########## UNIFI CONTROLLER STARTUP SCRIPT ##########'


# only do something if we're enabled
if ${ENABLED} ; then

#==============================================================================================
#
# Set up logging
#

    # CREATE LOG FOLDER IF NOT EXISTS
    mkdir -p $(dirname "${LOGFILE}")

    # TRY TO CREATE LOG FILE IF NOT EXISTS
    ( [ -e "$LOGFILE" ] || touch "$LOGFILE" ) && [ ! -w "$LOGFILE" ] && echo "Unable to create or write to $LOGFILE"

function logthis() {
    TAG='UNIFI'
    MSG="$1"
    $LOGGER -t "$TAG" "$MSG"
    echo "`date +%Y.%m.%d-%H:%M:%S` - $MSG"
    echo "`date +%Y.%m.%d-%H:%M:%S` - $MSG" >> $LOGFILE
}

logthis "$HEADER"

if [ ! -f /etc/logrotate.d/gcp-unifi.conf ]; then
	cat > /etc/logrotate.d/gcp-unifi.conf <<_EOF
$LOGFILE {
	monthly
	rotate 4
	compress
}
_EOF
	 logthis "$LOGFILE rotatation set up"
fi

MONGOLOG="/opt/UniFi/logs/mongod.log"
if [ ! -f /etc/logrotate.d/unifi-mongod.conf ]; then
	cat > /etc/logrotate.d/unifi-mongod.conf <<_EOF
$MONGOLOG {
	weekly
	rotate 10
	copytruncate
	delaycompress
	compress
	notifempty
	missingok
}
_EOF
	logthis "MongoDB logrotate set up"
fi

#==============================================================================================
#
# Turn off IPv6 for now
#
if [ ! -f /etc/sysctl.d/20-disableIPv6.conf ]; then
    echo "net.ipv6.conf.all.disable_ipv6=1" > /etc/sysctl.d/20-disableIPv6.conf
    sysctl --system > /dev/null
    logthis "IPv6 disabled"
fi

#==============================================================================================
#
# Update DynDNS as early in the script as possible
#
ddns=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ddns-url")
if [ ${ddns} ]; then
    curl -fs ${ddns}
    logthis "Dynamic DNS accessed and updated"
fi


#==============================================================================================
#
# Create a swap file for small memory instances and increase /run
#
if [ ! -f /swapfile ]; then
    memory=$(free -m | grep "^Mem:" | tr -s " " | cut -d " " -f 2)
    logthis "${memory} megabytes of memory detected"
    if [ -z ${memory} ] || [ "0${memory}" -lt "2048" ]; then
        fallocate -l 2G /swapfile
        dd if=/dev/zero of=/swapfile count=2048 bs=1MiB
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo 'tmpfs /run tmpfs rw,nodev,nosuid,size=400M 0 0' >> /etc/fstab
        mount -o remount,rw,nodev,nosuid,size=400M tmpfs /run
        logthis "Swap file created"
    fi
fi

#==============================================================================================
#
# Add repositories if they don't exist
#
if [ ! -f /etc/yum.repos.d/deepwoods.repo ]; then
    yum -y install http://deepwoods.net/repo/deepwoods/deepwoods-release-6-2.noarch.rpm
    logthis "DeepWoods repository added"
fi

if [ ! -f /etc/yum.repos.d/epel.repo ]; then
    yum -y install epel-release
    logthis "EPEL repository added"
fi

# mongodb-org > 3.0
if [ ! -f /etc/yum.repos.d/mongodb-org-3.6.repo ]; then
     cat > /etc/yum.repos.d/mongodb-org-3.6.repo << '_EOF'
[mongodb-org-3.6]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/3.6/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.6.asc
_EOF
fi


#==============================================================================================
#
# Install some stuff
#

# Run initial update
if [ ! -f /usr/share/misc/c7-updated ]; then
    yum -y update >/dev/null
    touch /usr/share/misc/c7-updated
    logthis "System updated"
fi

# yum-utils install
rpm -q yum-utils >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install yum-utils >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    logthis "yum-utils installed"
	else
        logthis "yum-utils installation failed"	
	fi
fi

# HAVEGEd install
rpm -q haveged >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install haveged >/dev/null 2>&1
	if [ $? -eq 0 ]; then
        systemctl reload-or-restart haveged
        systemctl enable haveged
	    logthis "HAVEGEd installed"
	else
        logthis "HAVEGEd installation failed"	
	fi
fi

# CertBot
rpm -q certbot >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install certbot >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    logthis "CertBot installed"
	else
        logthis "CertBot installation failed"	
	fi
fi

# UniFi install 
rpm -q unifi-controller >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install unifi-controller >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    logthis "UniFi controller installed"
        systemctl stop mongod
        systemctl disable mongod
        systemctl reload-or-restart unifi
        systemctl enable unifi
	else
        logthis "UniFi controller installation failed"	
	fi
fi

# Lighttpd needs a config file and a reload
rpm -q lighttpd >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install lighttpd >/dev/null 2>&1
	if [ $? -eq 0 ]; then
        cat > /etc/lighttpd/conf.d/unifi-redirect.conf <<_EOF
\$HTTP["scheme"] == "http" {
    \$HTTP["host"] =~ ".*" {
        url.redirect = (".*" => "https://%0:8443")
    }
}
_EOF
        sed -i '/ipv6/s/enable/disable/' /etc/lighttpd/lighttpd.conf
        sed -i '/mod_redirect/s/^#//' /etc/lighttpd/modules.conf
        echo "include \"conf.d/unifi-redirect.conf\"" >> /etc/lighttpd/lighttpd.conf 
        systemctl reload-or-restart lighttpd
        systemctl enable lighttpd
	    logthis "Lighttpd installed"
	else
        logthis "Lighttpd installation failed"	
	fi
fi

# Fail2Ban needs three files and a reload
rpm -q fail2ban >/dev/null 2>&1
if [ $? -ne 0 ]; then
    yum -y install fail2ban >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    logthis "Fail2ban installed"
	    if [ ! -f /etc/fail2ban/filter.d/unifi-controller.conf ]; then
		    cat > /etc/fail2ban/filter.d/unifi-controller.conf <<_EOF
[Definition]
failregex = ^.* Failed .* login for .* from <HOST>\s*$
_EOF
		    cat > /etc/fail2ban/jail.d/unifi-controller.conf <<_EOF
[unifi-controller]
filter   = unifi-controller
port     = 8443
logpath  = /opt/UniFi/logs/server.log
_EOF
	    fi
	    # The .local file will be installed in any case
	    cat > /etc/fail2ban/jail.d/unifi-controller.local <<_EOF
[unifi-controller]
enabled  = true
maxretry = 3
bantime  = 3600
findtime = 3600
_EOF
	    systemctl reload-or-restart fail2ban
        systemctl enable fail2ban
	else
        logthis "Fail2ban installation failed"	
	fi
fi


#==============================================================================================
#
# Set the time zone
#
tz=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/timezone")
if [ ${tz} ] && [ -f /usr/share/zoneinfo/${tz} ]; then
    if timedatectl set-timezone $tz; then logthis "Localtime set to ${tz}"; fi
    systemctl reload-or-restart rsyslog
fi


#==============================================================================================
#
# yum-cron already enabled for unattended updates in GC CentOS 7 base image
#

# check daily to see if installed updates require system reboot
if [ ! -f /usr/local/sbin/check-restart.sh ]; then
    cat > /usr/local/sbin/check-restart.sh <<_EOF
#!/bin/sh
/usr/bin/needs-restarting -r >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo >> $LOGFILE
    shutdown -r +10 "Updates require reboot. Restarting in 10 minutes"
    echo "=== Updates triggered system reboot in 10 minutes ===" >> $LOGFILE
    echo >> $LOGFILE
fi
_EOF
fi

if [ ! -f /etc/systemd/system/needs-restart.service ]; then
    cat > /etc/systemd/system/needs-restart.service <<_EOF
[Unit]
Description=Daily check if reboot is required
[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/local/sbin/check-restart.sh
_EOF

    cat > /etc/systemd/system/needs-restart.timer <<_EOF
[Unit]
Description=Daily check if reboot is required timer
[Timer]
OnCalendar=*-*-* 04:15:00
Persistent=true
[Install]
WantedBy=timers.target
_EOF
    
    systemctl daemon-reload
    systemctl start needs-restart.timer
    logthis "Daily check if reboot required set up"
fi

#==============================================================================================
#
# Set up automatic repair for broken MongoDB on boot
#
if [ ! -f /usr/local/sbin/unifidb-repair.sh ]; then
	cat > /usr/local/sbin/unifidb-repair.sh <<_EOF
#! /bin/sh
if ! pgrep mongod; then
	if [ -f /opt/UniFi/data/db/mongod.lock ] \
	|| [ -f /opt/UniFi/data/db/WiredTiger.lock ] \
	|| [ -f /opt/UniFi/data/db.needsRepair ] \
	|| [ -f /opt/UniFi/data/launcher.looping ]; then
		if [ -f /opt/UniFi/data/db/mongod.lock ]; then rm -f /opt/UniFi/data/db/mongod.lock; fi
		if [ -f /opt/UniFi/data/db/WiredTiger.lock ]; then rm -f /opt/UniFi/data/db/WiredTiger.lock; fi
		if [ -f /opt/UniFi/data/db.needsRepair ]; then rm -f /opt/UniFi/data/db.needsRepair; fi
		if [ -f /opt/UniFi/data/launcher.looping ]; then rm -f /opt/UniFi/data/launcher.looping; fi
		echo >> $LOGFILE
		echo "Repairing Unifi DB on \$(date)" >> $LOGFILE
		echo >> $LOGFILE
		su -c "/usr/bin/mongod --repair --dbpath /opt/UniFi/data/db --smallfiles --logappend --logpath ${MONGOLOG} 2>>$LOGFILE" unifi
	fi
else
	echo "MongoDB is running. Exiting..."
	exit 1
fi
exit 0
_EOF
	chmod a+x /usr/local/sbin/unifidb-repair.sh

	cat > /etc/systemd/system/unifidb-repair.service <<_EOF
[Unit]
Description=Repair UniFi MongoDB database at boot
Before=unifi.service mongodb.service
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/unifidb-repair.sh
[Install]
WantedBy=multi-user.target
_EOF
	systemctl enable unifidb-repair.service
	logthis "Unifi DB autorepair set up"
fi

#==============================================================================================
#
# Set up daily backup to a bucket after 01:00
#
bucket=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/bucket")
if [ ${bucket} ]; then
    cat > /etc/systemd/system/unifi-backup.service <<_EOF
[Unit]
Description=Daily backup to ${bucket} service
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/gsutil rsync -r -d /opt/UniFi/data/backup gs://$bucket
_EOF

    cat > /etc/systemd/system/unifi-backup.timer <<_EOF
[Unit]
Description=Daily backup to ${bucket} timer
[Timer]
OnCalendar=1:00
RandomizedDelaySec=30m
[Install]
WantedBy=timers.target
_EOF
    
    systemctl daemon-reload
    systemctl start unifi-backup.timer
    logthis "Backups to ${bucket} set up"
fi


###########################################################
#
# Adjust Java heap (advanced setup)
#
# xms=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/xms")
# xmx=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/xmx")
# if [ ${xms} ] || [ ${xmx} ]; then touch /usr/share/misc/java-heap-adjusted; fi
#
# if [ -e /usr/share/misc/java-heap-adjusted ]; then
#	 if [ "0${xms}" -lt 100 ]; then xms=1024; fi
#	 if grep -e "^\s*unifi.xms=[0-9]" /opt/UniFi/data/system.properties >/dev/null; then
#	 	sed -i -e "s/^[[:space:]]*unifi.xms=[[:digit:]]\+/unifi.xms=${xms}/" /opt/UniFi/data/system.properties
#	 else
#	 	echo "unifi.xms=${xms}" >>/opt/UniFi/data/system.properties
#	 fi
#	 message=" xms=${xms}"
#	 
#	 if [ "0${xmx}" -lt "${xms}" ]; then xmx=${xms}; fi
#	 if grep -e "^\s*unifi.xmx=[0-9]" /opt/UniFi/data/system.properties >/dev/null; then
#	 	sed -i -e "s/^[[:space:]]*unifi.xmx=[[:digit:]]\+/unifi.xmx=${xmx}/" /opt/UniFi/data/system.properties
#	 else
#	 	echo "unifi.xmx=${xmx}" >>/opt/UniFi/data/system.properties
#	 fi
#	 message="${message} xmx=${xmx}"
#	 
#	 if [ -n "${message}" ]; then
#	 	echo "Java heap set to:${message}"
#	 fi
#	 systemctl restart unifi
# fi


###########################################################
#
# Set up Let's Encrypt
#
dnsname=$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/dns-name")
if [ -z ${dnsname} ]; then 
    logthis "########## STARTUP SCRIPT FINISHED ##########"
    exit 0; 
fi
privkey=/etc/letsencrypt/live/${dnsname}/privkey.pem
pubcrt=/etc/letsencrypt/live/${dnsname}/cert.pem
chain=/etc/letsencrypt/live/${dnsname}/chain.pem
caroot=/usr/share/misc/ca_root.pem

# Write the cross signed root certificate to disk
if [ ! -f $caroot ]; then
	cat > $caroot <<_EOF
-----BEGIN CERTIFICATE-----
MIIDSjCCAjKgAwIBAgIQRK+wgNajJ7qJMDmGLvhAazANBgkqhkiG9w0BAQUFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTAwMDkzMDIxMTIxOVoXDTIxMDkzMDE0MDExNVow
PzEkMCIGA1UEChMbRGlnaXRhbCBTaWduYXR1cmUgVHJ1c3QgQ28uMRcwFQYDVQQD
Ew5EU1QgUm9vdCBDQSBYMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
AN+v6ZdQCINXtMxiZfaQguzH0yxrMMpb7NnDfcdAwRgUi+DoM3ZJKuM/IUmTrE4O
rz5Iy2Xu/NMhD2XSKtkyj4zl93ewEnu1lcCJo6m67XMuegwGMoOifooUMM0RoOEq
OLl5CjH9UL2AZd+3UWODyOKIYepLYYHsUmu5ouJLGiifSKOeDNoJjj4XLh7dIN9b
xiqKqy69cK3FCxolkHRyxXtqqzTWMIn/5WgTe1QLyNau7Fqckh49ZLOMxt+/yUFw
7BZy1SbsOFU5Q9D8/RhcQPGX69Wam40dutolucbY38EVAjqr2m7xPi71XAicPNaD
aeQQmxkqtilX4+U9m5/wAl0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNV
HQ8BAf8EBAMCAQYwHQYDVR0OBBYEFMSnsaR7LHH62+FLkHX/xBVghYkQMA0GCSqG
SIb3DQEBBQUAA4IBAQCjGiybFwBcqR7uKGY3Or+Dxz9LwwmglSBd49lZRNI+DT69
ikugdB/OEIKcdBodfpga3csTS7MgROSR6cz8faXbauX+5v3gTt23ADq1cEmv8uXr
AvHRAosZy5Q6XkjEGB5YGV8eAlrwDPGxrancWYaLbumR9YbK+rlmM6pZW87ipxZz
R8srzJmwN0jP41ZL9c8PDHIyh8bwRLtTcm1D9SZImlJnt1ir/md2cXjbDaJWFBM5
JDGFoqgCWjBH4d1QB7wCCZAA62RjYJsWvIjJEubSfZGL+T0yjWW06XyxV3bqxbYo
Ob8VZRzI9neWagqNdwvYkQsEjgfbKbYK7p2CNTUQ
-----END CERTIFICATE-----
_EOF
fi

# Write pre and post hooks to stop Lighttpd for the renewal
if [ ! -d /etc/letsencrypt/renewal-hooks/pre ]; then
	mkdir -p /etc/letsencrypt/renewal-hooks/pre
fi
cat > /etc/letsencrypt/renewal-hooks/pre/lighttpd <<_EOF
#! /bin/sh
systemctl stop lighttpd
_EOF
chmod a+x /etc/letsencrypt/renewal-hooks/pre/lighttpd

if [ ! -d /etc/letsencrypt/renewal-hooks/post ]; then
	mkdir -p /etc/letsencrypt/renewal-hooks/post
fi
cat > /etc/letsencrypt/renewal-hooks/post/lighttpd <<_EOF
#! /bin/sh
systemctl start lighttpd
_EOF
chmod a+x /etc/letsencrypt/renewal-hooks/post/lighttpd

# Write the deploy hook to import the cert into Java
if [ ! -d /etc/letsencrypt/renewal-hooks/deploy ]; then
	mkdir -p /etc/letsencrypt/renewal-hooks/deploy
fi
cat > /etc/letsencrypt/renewal-hooks/deploy/unifi <<_EOF
#! /bin/sh

if [ -e $privkey ] && [ -e $pubcrt ] && [ -e $chain ]; then

	echo >> $LOGFILE
	echo "Importing new certificate on \$(date)" >> $LOGFILE
	p12=\$(mktemp)
	
	if ! openssl pkcs12 -export \\
	-in $pubcrt \\
	-inkey $privkey \\
	-CAfile $chain \\
	-out \${p12} -passout pass:aircontrolenterprise \\
	-caname root -name unifi >/dev/null ; then
		echo "OpenSSL export failed" >> $LOGFILE
		exit 1
	fi
	
	if ! keytool -delete -alias unifi \\
	-keystore /opt/UniFi/data/keystore \\
	-deststorepass aircontrolenterprise >/dev/null ; then
		echo "KeyTool delete failed" >> $LOGFILE
	fi
	
	if ! keytool -importkeystore \\
	-srckeystore \${p12} \\
	-srcstoretype pkcs12 \\
	-srcstorepass aircontrolenterprise \\
	-destkeystore /opt/UniFi/data/keystore \\
	-deststorepass aircontrolenterprise \\
	-destkeypass aircontrolenterprise \\
	-alias unifi -trustcacerts >/dev/null; then
		echo "KeyTool import failed" >> $LOGFILE
		exit 2
	fi
	
	systemctl stop unifi
	if ! java -jar /opt/UniFi/lib/ace.jar import_cert \\
	$pubcrt $chain $caroot >/dev/null; then
		echo "Java import_cert failed" >> $LOGFILE
		systemctl start unifi
		exit 3
	fi
	systemctl start unifi
	rm -f \${p12}
	echo "Success" >> $LOGFILE
else
	echo "Certificate files missing" >> $LOGFILE
	exit 4
fi
_EOF
chmod a+x /etc/letsencrypt/renewal-hooks/deploy/unifi

# Write a script to acquire the first certificate (for a systemd timer)
cat > /usr/local/sbin/certbotrun.sh <<_EOF
#! /bin/sh
extIP=\$(curl -fs -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip")
dnsIP=\$(getent hosts ${dnsname} | cut -d " " -f 1)

echo >> $LOGFILE
echo "CertBot run on \$(date)" >> $LOGFILE
if [ x\${extIP} = x\${dnsIP} ]; then
	if [ ! -d /etc/letsencrypt/live/${dnsname} ]; then
		systemctl stop lighttpd
		if certbot certonly -d $dnsname --standalone --agree-tos --register-unsafely-without-email >> $LOGFILE; then
			echo "Received certificate for ${dnsname}" >> $LOGFILE
		fi
		systemctl start lighttpd
	fi
	if /etc/letsencrypt/renewal-hooks/deploy/unifi; then
		systemctl stop certbotrun.timer
		echo "Certificate installed for ${dnsname}" >> $LOGFILE
	fi
else
	echo "No action because ${dnsname} doesn't resolve to ${extIP}" >> $LOGFILE
fi
_EOF
chmod a+x /usr/local/sbin/certbotrun.sh

# Write the systemd unit files
if [ ! -f /etc/systemd/system/certbotrun.timer ]; then
	cat > /etc/systemd/system/certbotrun.timer <<_EOF
[Unit]
Description=Run CertBot hourly until success
[Timer]
OnCalendar=hourly
RandomizedDelaySec=15m
[Install]
WantedBy=timers.target
_EOF
	systemctl daemon-reload

	cat > /etc/systemd/system/certbotrun.service <<_EOF
[Unit]
Description=Run CertBot hourly until success
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/certbotrun.sh
_EOF
fi

# Start the above
if [ ! -d /etc/letsencrypt/live/${dnsname} ]; then
	if ! /usr/local/sbin/certbotrun.sh; then
		echo "Installing hourly CertBot run"
		systemctl start certbotrun.timer
	fi
fi

#==============================================================================================

    logthis "########## STARTUP SCRIPT FINISHED ##########"
fi
