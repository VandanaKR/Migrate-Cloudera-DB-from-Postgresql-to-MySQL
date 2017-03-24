!/bin/bash

##################################################
# Script written by Vandana K R                  #
# Cloudera DB migration from Postgresql to MySQL #
##################################################

#gathering basic requirements
echo -e "\nLet us migrate cloudera-manager DB from embedded postgres to MySQL!!!!\n"
echo -e "Enter the Cloudera manager hostname/IP: "
read CM_host
echo -e "Enter CM UI username: "
read uname
echo -e "Enter CM UI password: "
read passwd

#invoking api call to export configuration
echo -e "\n####### Exporting service Configuration #######"
unset http_proxy 
unset https_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
mkdir -p /root/CMbackup
ret=curl -I -u $uname:$passwd http://$CM_host:7180/api/v9/cm/deployment 2>/dev/null | head -n 1 | cut -d$' ' -f2
if [ $ret=200 ]
then
curl -v -u $uname:$passwd http://$CM_host:7180/api/v9/cm/deployment > /root/CMbackup/cm-deployment.json
else 
echo "\nConfiguration export failed with http status code $ret"
exit
fi

#verifying whether config exported or not
if [ -f '/root/CMbackup/cm-deployment.json' ]
then
	if [ -s '/root/CMbackup/cm-deployment.json' ]
	then
	echo -e "\n####### Configurations exported #######\n"
	else
	echo -e "\n####### Error in exporting configuration #######\n"
	exit
	fi
else 
echo -e "\n####### Error in exporting configuration #######\n"
exit
fi

#stop the CM daemons
echo -e "\n####### Stopping all cloudera manager daemons #######\n"
ser_stat=`service cloudera-scm-server stop`
check=`echo $ser_stat|awk -F: '{print $2}'|awk '{print $2}'`
if [ $check == "OK" ]
then
while [[ $(netstat -lnp | grep ':7180') = *java* ]]; do sleep 1;done
chkconfig cloudera-scm-server off
else
echo -e "\n####### ERROR!! Cloudera server stop status: $check #######\n"
exit
fi

#Backing up the postgresql dump for safer side
echo -e "\n####### Backing up current postgresql DB and CM server config directory for a safer side #######\n"
scmpwd=`grep "com.cloudera.cmf.db.password" /etc/cloudera-scm-server/db.properties |awk -F= '{print $2}'`
#echo $scmpwd
puser=`grep "com.cloudera.cmf.db.user" /etc/cloudera-scm-server/db.properties |awk -F= '{print $2}'`
#echo $puser
dname=`grep "com.cloudera.cmf.db.name" /etc/cloudera-scm-server/db.properties |awk -F= '{print $2}'`
#echo $dname
PGPASSWORD=$scmpwd pg_dump -U $puser -p 7432 --column-inserts $dname > /root/CMbackup/scm_server_db_backup_$(date +%Y%m%d).sql

cmpwd=`sed -n 1p /var/lib/cloudera-scm-server-db/data/generated_password.txt`
#echo $cmpwd
PGPASSWORD=$cmpwd pg_dumpall -U cloudera-scm -p 7432 --column-inserts > /root/CMbackup/alldump_$(date +%Y%m%d).sql

VAR1=/root/CMbackup/scm_server_db_backup_$(date +%Y%m%d).sql
VAR2=/root/CMbackup/alldump_$(date +%Y%m%d).sql

if [ -f $VAR1 ] && [ -f $VAR2 ]
then
        if [ -s $VAR1 ] && [ -s $VAR2 ]
        then
        echo -e "\n####### Postgresql dump ready #######\n"
        else
        echo -e "\n####### Error in taking postgresql dump #######\n"
        exit
        fi
else
echo -e "\n####### Error in taking postgresql dump #######\n"
exit
fi

#Backup the contents of cloudera-scm-server config directory
tar -cvf /root/CMbackup/cmconf_$(date +%Y%m%d).tar /etc/cloudera-scm-server/

VAR3=/root/CMbackup/cmconf_$(date +%Y%m%d).tar
if [ -f $VAR3 ]
then
	if [ -s $VAR3 ]
        then
        echo -e "\n####### Config backup ready #######\n"
        else
        echo -e "\n####### Error in taking config directory backup #######\n"
        exit
        fi
else
echo -e "\n####### Error in taking config directory backup #######\n"
exit
fi

#Stopping the cloudera-server DB
echo -e "\n####### Stopping cloudera manager server DB #######\n"
service cloudera-scm-server-db stop > dbstop.out
check1=`sed -n 1p dbstop.out |awk '{print $7}'`
if [ $check1 == "done" ]
then
while [[ $(netstat -lnp | grep ':7432') = *postgres* ]]; do sleep 1;done
else
echo -e "\n####### ERROR!! Cloudera server db stop status obtained : $check1 #######\n"
exit
fi
chkconfig cloudera-scm-server-db off

#Stopping the cloudera agent daemons
echo -e "\n####### Stopping cloudera manager agent daemons on all hosts #######\n"
#required as agents are running on all hosts
echo -e "No of nodes in cluster:"
read a
curr=`pwd`
cat /dev/null > $curr/server_list
echo -e "Enter IP address of nodes seperated by new line:"
while [ $a -gt 0 ] ;
do
function inputIp()
  {
   read b
   if [[ $? -eq 0 ]]; then
   echo $b | cat >> server_list
   fi
  }
a=`expr $a - 1`
inputIp
done
for i in `cat $curr/server_list`; do ssh root@$i "echo $i; /etc/init.d/cloudera-scm-agent stop" ;done


#Create databases for all monitoring services of cloudera manager in MySQL
echo -e "\n####### Creating databases in MySQL #######\n"
echo -e "Enter the MySQL server IP/hostname :"
read myip
echo -e "Enter MysqlDB root password: "
read mypwd

###optional
echo -e "\n####### Backing up existing MySQL #######\n"
mysqldump -h $myip -u root -p$mypwd --all-databases > /root/CMbackup/existing_mysql_dump.sql
if [ -f '/root/CMbackup/existing_mysql_dump.sql' ]
then
	if [ -s '/root/CMbackup/existing_mysql_dump.sql' ]
        then
        echo -e "\n####### Existing MySQL backup ready #######\n"
        else
        echo -e "\n####### Error in taking existing mysql backup #######\n"
        exit
        fi
else
echo -e "\n####### Error in taking existing mysql backup #######\n"
exit
fi
###

mysql -h $myip -u root -p$mypwd -e "drop database if exists scm"
mysql -h $myip -u root -p$mypwd -e "drop database if exists amon"
mysql -h $myip -u root -p$mypwd -e 'create database amon DEFAULT CHARACTER SET utf8'
mysql -h $myip -u root -p$mypwd -e "grant all on amon.* to 'amon'@'%' identified by 'amonpb_1'"
mysql -h $myip -u root -p$mypwd -e "drop database if exists rman"
mysql -h $myip -u root -p$mypwd -e 'create database rman DEFAULT CHARACTER SET utf8'
mysql -h $myip -u root -p$mypwd -e "grant all on rman.* to 'rman'@'%' identified by 'rmanpb_1'"
mysql -h $myip -u root -p$mypwd -e "drop database if exists nav"
mysql -h $myip -u root -p$mypwd -e 'create database nav DEFAULT CHARACTER SET utf8'
mysql -h $myip -u root -p$mypwd -e "grant all on nav.* to 'nav'@'%' identified by 'navpb_1'"
mysql -h $myip -u root -p$mypwd -e "drop database if exists navms"
mysql -h $myip -u root -p$mypwd -e 'create database navms DEFAULT CHARACTER SET utf8'
mysql -h $myip -u root -p$mypwd -e "grant all on navms.* to 'navms'@'%' identified by 'navmspb_1'"
echo -e "\n####### Databases created in MySQL successfully #######\n"

#Create a temp user to import configurations
echo -e "\n####### Configuring Cloudera DB as MySQL  #######\n"
mysql -h $myip -u root -p$mypwd -e "CREATE USER 'temp'@'localhost' IDENTIFIED BY 'temp'"
mysql -h $myip -u root -p$mypwd -e "grant all on *.* to 'temp'@'%' identified by 'temp' with grant option"

#configure cloudera DB as mysql
sh /usr/share/cmf/schema/scm_prepare_database.sh mysql -h $CM_host -u temp -ptemp --scm-host $CM_host $dname $puser $scmpwd

#Removing temp user
mysql -h $myip -u root -p$mypwd -e "drop user 'temp'@'localhost'"
echo -e "\nConfigured Cloudera DB as MySQL successfully\n"

#start the cloudera server
echo -e "\n####### Starting the cloudera scm server #######\n"
strt_stat=`service cloudera-scm-server start`
check2=`echo $strt_stat|awk -F: '{print $2}'|awk '{print $2}'`
if [ $check2 == "OK" ]
then
echo -e "Waiting for cloudera manager UI port to listen....\n"
while [[ $(netstat -lnp | grep ':7180') != *java* ]]; do sleep 1;done
else
echo -e "\n####### ERROR!! Cloudera server start status obtained: $check2 #######\n"
exit
fi

echo -e "\nDo you use enterprise CDH [y/n]: "
read d
if [[ $d = [yY] ]]
then
echo -e "\n####### Please reload Enterprise license key in CM-UI #######\n"
echo -e "\nWaiting for you to reload the license via UI....\n"
echo -n " If reloaded, press y to proceed :"
read c
	if [[ $c = [yY] ]]
        then
	service cloudera-scm-server restart > comd.out
	check3=`sed -n 2p comd.out | awk -F: '{print $2}'|awk '{print $2}'`
		if [ $check3 == "OK" ]
		then
		echo -e "Waiting for cloudera manager UI port to listen...."
		while [[ $(netstat -lnp | grep ':7180') != *java* ]]; do sleep 1;done
		else
		echo -e "\n####### ERROR!! Cloudera server restart status obtained: $check3 #######\n"
		exit
		fi
fi
fi

chkconfig cloudera-scm-server on

#Starting the cloudera manager agent daemons
echo -e "\n####### Starting cloudera manager agent daemons on all hosts #######\n"
for i in `cat $curr/server_list`; do ssh root@$i "echo $i; /etc/init.d/cloudera-scm-agent start" ;done

#importing the cloudera manager configurations from dumpfile

echo -e "\n####### Importing Cloudera configurations back via api  #######\n"
rept=$(curl -H "Content-Type: application/json" --upload-file /root/CMbackup/cm-deployment.json -u admin:admin http://$CM_host:7180/api/v9/cm/deployment?deleteCurrentDeployment=true)
status=$?
if [ $status -eq 0 ]; then
    echo -e "\n####### Configurations imported successfully #######\n"
    echo -e "\t Postresql to MySQL migration Completed!!!! \n"
    echo -e "####### Please verify configurations in Cloudera UI #######\n"
else 
    echo "####### Import failed with status $status.Retry only upload curl command #######\n"
    exit
fi


