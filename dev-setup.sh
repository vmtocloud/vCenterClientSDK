#!/bin/bash

# Copyright (c) 2016-2018 VMware, Inc. All rights reserved.
# ------------------------------------------------------------------------------------
# Shell script to setup a Web Client SDK development environment on Mac or Windows
#
# 1. Copy this script to your VCSA /root directory and make it executable
#
# 2. Run it. Three files are generated: webclient.properties, store.jks and ds.properties
#
# 3. Copy these files to your dev machine at the following locations:
#    a. webclient.properties
#       - Mac OS: /var/lib/vmware/vsphere-client/vsphere-client/
#       - Windows: C:\ProgramData\VMware\vCenterServer\cfg\vsphere-client\
#    b. store.jks
#       - Mac OS:  /var/lib/vmware/vsphere-client/
#       - Windows: C:\ProgramData\VMware\vCenterServer\cfg\
#    c. ds.properties
#       - Mac OS: /var/lib/vmware/vsphere-client/vsphere-client/config/
#       - Windows: C:\ProgramData\VMware\vCenterServer\cfg\vsphere-client\config\
#
# 4. Define the VMWARE_CFG_DIR environment variable pointing to the following location:
#    - Mac OS:  /var/lib/vmware/vsphere-client/
#    - Windows: C:\ProgramData\VMware\vCenterServer\cfg\
#
# 5. Edit server/configuration/tomcat-server.xml:
#      - replace compression="on" with compression="off" on <Connector port="9443" ...>
#
# 6. (Mac OS only) change keystore.jks. path in webclient.properties to use the Mac path
#
# 7. (Mac OS first time only) edit server/configuration/tomcat-server.xml:
#    - replace keystoreFile="C:/ProgramData/VMware/vCenterServer/cfg/store.jks" with
#              keystoreFile="/var/lib/vmware/vsphere-client/store.jks"
#
# 8. Start/restart the Virgo server on your dev machine.
#    You should be able to connect to your VCSA using the local server.
#    Check server/serviceability/logs/vsphere_client_virgo.log in case of problems.
#
# Repeat these steps for another VCSA or vCenter Server for Windows setup.
# -------------------------------------------------------------------------------------

# Path to vecs binary
VECS_CLI="/usr/lib/vmware-vmafd/bin/vecs-cli"

# Path to vmafd binary
VMAFD_CLI="/usr/lib/vmware-vmafd/bin/vmafd-cli"

# Trusted certificate store name
TRUSTED_STORE="TRUSTED_ROOTS"

# NGC certificate store name
NGC_STORE="vsphere-webclient"

# NGC certificate alias
NGC_ALIAS="vsphere-webclient"

# Keystore path
if [ -z "$KEYSTORE"  ] ; then
   KEYSTORE=C\:/ProgramData/VMware/vCenterServer/cfg/store.jks
fi

# Keystore Password
PASS=vmw@re

#
# Generating store.jks file
#
echo Generating store.jks file...

rm -f keyfile certfile store.p12 store.jks

$VECS_CLI entry getkey --store $NGC_STORE --alias $NGC_ALIAS > keyfile
$VECS_CLI entry getcert --store $NGC_STORE --alias $NGC_ALIAS > certfile

openssl pkcs12 -export -in certfile -inkey keyfile -name $NGC_ALIAS -out store.p12 -password pass:$PASS

keytool -importkeystore -srckeystore store.p12 --srcstoretype PKCS12 -srcstorepass $PASS -destkeystore store.jks -deststorepass $PASS

$VECS_CLI entry list --store $TRUSTED_STORE | awk '/Alias :/{ print $3 }' | while read line;
do
   $VECS_CLI entry getcert --store $TRUSTED_STORE --alias $line | keytool -importcert -keystore store.jks -storepass $PASS -trustcacerts -noprompt -alias $line
done

rm -f keyfile certfile store.p12

#
# Generating webclient.properties file
#
echo Generating webclient.properties file...

PROPFILE=webclient.properties
rm -f $PROPFILE

DNSNAME=`keytool -printcert -sslserver localhost | awk '/DNSName:/ { print $2 }'`
if [ -z "$DNSNAME" ]
then
   echo ERROR: DNS name not found! You will need to fix cm.url in webclient.properties
   DNSNAME=MISSING_DNS_NAME
fi

# Returns the ls url location
LSURL=`$VMAFD_CLI get-ls-location --server-name localhost`
if [ -z "$LSURL" ]
then
   echo ERROR: LS Url not found! You will need to fix ls.url in webclient.properties
   LSURL=MISSING_LS_URL
fi

echo '#' >> $PROPFILE
echo '# Generated webclient.properties for dev environments.' >> $PROPFILE
echo '# Copy this file to the right location along with the generated store.jks (see path below).' >> $PROPFILE
echo '#' >> $PROPFILE
echo '# The keystore and cm.url settings allow to connect your local Web Client server to your VCSA' >> $PROPFILE
echo '# or vCenter for Windows. For additional properties see the content of webclient.properties' >> $PROPFILE
echo '# in /etc/vmware/vsphere-client or C:\ProgramData\VMware\vCenterServer\cfg\vsphere-client\' >> $PROPFILE
echo '#' >> $PROPFILE
echo '# Do not change.' >> $PROPFILE
echo afd.disabled=true >> $PROPFILE
echo '#' >> $PROPFILE
echo keystore.jks.password=$PASS >> $PROPFILE
echo '#' >> $PROPFILE
echo '# Set the correct value of keystore.jks.path based on your dev OS.' >> $PROPFILE
echo '# Mac OS: /var/lib/vmware/vsphere-client/store.jks' >> $PROPFILE
echo '# Windows: C:/ProgramData/VMware/vCenterServer/cfg/store.jks' >> $PROPFILE
echo keystore.jks.path=$KEYSTORE >> $PROPFILE
echo '#' >> $PROPFILE
echo '# ComponentManager url with the DNS name of your VCSA host.' >> $PROPFILE
echo cm.url=https\://$DNSNAME/cm/sdk/ >> $PROPFILE
echo '# Lookup Service url with the DNS name of the VCSA deployment.' >> $PROPFILE
echo ls.url=$LSURL>> $PROPFILE
echo '#' >> $PROPFILE
echo '# Other useful webclient.properties flags for a local dev setup' >> $PROPFILE
echo show.allusers.tasks=true >> $PROPFILE
echo large.inventory.mode=true >> $PROPFILE
echo aggregationThreshold.VirtualMachine=100 >> $PROPFILE
echo local.development=true >> $PROPFILE

#
# Creating ds.properties file
#
echo Creating ds.properties file...
CLIENT_DIR=/etc/vmware/vsphere-client
DS_PROPFILE=ds.properties

IPADDR=`ifconfig eth0 | grep 'inet ' | awk '{print $2}' | sed 's/addr://'`
if [ -z "$IPADDR" ]
then
   echo ERROR: IP address not found! You will need to fix lookupService in ds.properties
   IPADDR=MISSING_IP_ADDRESS
fi

cp $CLIENT_DIR/config/$DS_PROPFILE .
echo solutionUser.keyStorePath=$KEYSTORE >> $DS_PROPFILE
echo solutionUser.keyStorePassword=$PASS >> $DS_PROPFILE
echo lookupService=https\://$IPADDR/lookupservice/sdk >> $DS_PROPFILE

echo Done.
