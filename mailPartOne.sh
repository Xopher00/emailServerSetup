#!/bin/bash

#First argument is the domain name
domain = $0

#use second argument to send test emails
gmail_address = $1

# API key found in cloudflare account settings
auth_key = $2

#IP Address
ip=$(curl -s http://ipv4.icanhazip.com)

#our fully qualified domain name is the name of the node (mail) plus the domain
fqdn = "mail.${domain}"

#set the hostname as our filly qualified domain name
echo -n "setting hostname as ${fqdn}"
sudo hostnamectl set-hostname $fqdn

#use cloudflare api to modify DNS records with FQDN
zone_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" -H "X-Auth-Email: $gmail_address" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
record_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$fqdn" -H "X-Auth-Email: $gmail_address" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*')
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" -H "X-Auth-Email: $gmail_address" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" --data "{\"id\":\"$zone_identifier\",\"type\":\"MX\",\"name\":\"$fqdn\",\"content\":\"$ip\"}"

#install Postfix
sudo apt-get update && install postfix -y

#open port 25 inbound on firewall, open other email related ports
sudo ufw allow 25,80,110,443,587,465,143,993,995/tcp

#check if port 25 is blocked using telnet

#send test email
echo "test email" | sendmail $gmail_address

#install command line MUA
sudo apt-get install mailutils


#adjust attachment size
sudo postconf -e message_size_limit=52428800
postconf | grep mailbox_size_limit

#set postfix hostname
sed -i "s%myhostname = %myhostname = $fqdn #%" /etc/postfix/main.cf

#create postfix alias for user
sudo echo 'root: '$USER >> /etc/aliases
sudo newaliases

sudo postconf -e "inet_protocols = ipv4"

sudo systemctl restart postfix

#conigure dovecot imap server + tls certificate

#Install lets encrypt
sudo apt install certbot && apt install python3-certbot-nginx

#configure nginx server
sudo cat /etc/nginx/conf.d/$fqdn.conf<<EOF
server {
      listen 80;
      listen [::]:80;
      server_name $fqdn;

      root /var/www/html/;

      location ~ /.well-known/acme-challenge {
         allow all;
      }
}
EOF

sudo systemctl reload nginx

sudo certbot certonly -a nginx --agree-tos --no-eff-email --staple-ocsp --email $gmail_address -d $fqdn

sudo echo '
submission     inet     n    -    y    -    -    smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_tls_wrappermode=no
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
' >> /etc/postfix/master.cf





