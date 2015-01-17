#!/bin/bash -x

mkdir -p /srv/mail

# Set SpamAssassin options
cat > /etc/mail/spamassassin/local.cf <<EOF
add_header all Status _YESNO_, score=_SCORE_ required=_REQD_ tests=_TESTS_ autolearn=_AUTOLEARN_ version=_VERSION_
EOF

# for postgresql mapping
sed -i "s/PGSQL_HOST/${PGSQL_HOST}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/PGSQL_USER/${PGSQL_USER}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/PGSQL_PASSWORD/${PGSQL_PASSWORD}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/PGSQL_DBNAME/${PGSQL_DBNAME}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf.ext

# (re-)build postfix queue
for queue in {active,bounce,corrupt,defer,deferred,flush,hold,incoming,private,saved,trace}; do
  install -d -o postfix -g postfix /var/spool/postfix/$queue
  chmod 700 /var/spool/postfix/$queue
done

# ensure proper permissions
chmod 730 /var/spool/postfix/maildrop
chmod 710 /var/spool/postfix/public
chown -R root /etc/postfix
chown -R vmail: /srv/mail
chmod 755 /usr/local/bin/spam_filter.sh
chown root: /usr/local/bin/spam_filter.sh

# setup grossd
mkdir -p /var/db/gross
chown -R gross: /var/run/gross /var/db/gross
/usr/sbin/grossd -u gross -C 2>/dev/null

# debugging
[ ! -z $DEBUG ] && \
  echo "auth_verbose = yes" | tee -a /etc/dovecot/dovecot.conf && \
  echo "auth_debug = yes" | tee -a /etc/dovecot/dovecot.conf

# mailgun support
[ ! -z $MAILGUN_SMTP_PASSWORD ] && [ ! -z $MAILGUN_SMTP_USERNAME ] && \
  postconf -e \
    smtp_sasl_password_maps="static:$MAILGUN_SMTP_USERNAME:$MAILGUN_SMTP_PASSWORD" \
    relayhost="[smtp.mailgun.org]:587"

# remove SSL config if no certificate or private key found
test -f /etc/ssl/certs/mail.crt   || rm -f /etc/dovecot/conf.d/10-ssl.conf
test -f /etc/ssl/private/mail.key || rm -f /etc/dovecot/conf.d/10-ssl.conf

# build system aliases
/usr/bin/newaliases

exec /usr/bin/supervisord -c /etc/supervisord.conf
