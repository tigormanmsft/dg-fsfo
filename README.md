## Azure CLI script to configure Oracle DataGuard FSFO

This bash script includes Azure CLI commands to fully automate the following steps, given a subscription and a resource group...

1. Create a storage account in the specified Azure region
2. Create a virtual network (vnet) and subnet
3. Create a network security group (NSG) and rules to permit access by SSH
4. Create two "database" VMs and one "observer" VM, using an Oracle database Enterprise Edition URN from the marketplace
5. Create a data disk on each "database" VM using the specified managed disk
6. Label, paritition, and format the data disk into an EXT4 filesystem mounted at "/u02" on each "database" VM
7. Use the Oracle Database Creation Assistant (DBCA) to create an Oracle database and listener on the primary "database" VM
8. Configure the primary database for DataGuard
9. Duplicate the primary database to the standby "database" VM using DBCA
10. Configuration the standby database for DataGuard
11. Finish the DataGuard FSFO configuration using the DataGuard DGMGRL utility
12. Configure the "observer" VM and start the "observer" process

Each of the three VMs have public IP addresses with SSH public-key authentication (PKA) established, so the public IP addresses can be viewed either through the Azure Portal or displayed in the output from the "cr_oradg.sh" script.

## How to call the Azure CLI script

The script has command-line parameters, all of which have default values.  To display the usage message, enter "./cr_oradg.sh -h"...

	Usage: $0 -I val -O val -P val -S val -i val -p val -r val -s val -u val -v
	where:
		-I obsvr-instance-type	name of the Azure VM instance type for DataGuard observer node (default: Standard_DS1_v2)
		-O owner-tag		      name of the owner to use in Azure resource tags (no default)
		-P project-tag	      	name of the project to use in Azure resource tags (no default)
		-S subscription		   name of the Azure subscription (no default)
		-i db-instance-type	   name of the Azure VM instance type for database nodes (default: Standard_DS11-1_v2)
		-p Oracle-port		      port number of the Oracle TNS Listener (default: 1521)
		-r region		         name of Azure region (default: westus2)
		-s ORACLE_SID		      Oracle System ID (SID) value (default: oradb01)
		-u urn			         Azure URN for the VM from the marketplace (default: Oracle:Oracle-Database-Ee:12.2.0.1:12.2.20180725)
		-v			               set verbose output is true (default: terse)

## What to expect in the output from the Azure CLI script

Sample output from a run with verbose mode enabled...

Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _azureOwner is "tigorman"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _azureProject is "oradg"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _azureSubscription is "TIGORMAN-CET subscription"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _vmDbInstanceType is "Standard_DS11-1_v2"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _vmObsvrInstanceType is "Standard_DS1_v2"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _oraLsnrPort is "1521"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _azureRegion is "westus2"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _oraSid is "oradg01"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: parameter _vmUrn is "Oracle:Oracle-Database-Ee:12.2.0.1:12.2.20180725"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: variable _workDir is "/home/tim/clouddrive/scripts"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: variable _logFile is "/home/tim/clouddrive/scripts/tigorman-oradg.log"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: variable _saName is "tigormanoradgsa"
Sat Apr 25 17:27:26 UTC 2020 - DBUG: variable _rgName is "tigorman-oradg-rg"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vnetName is "tigorman-oradg-vnet"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _subnetName is "tigorman-oradg-subnet"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _nsgName is "tigorman-oradg-nsg"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _nicName1 is "tigorman-oradg-nic01"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _pubIpName1 is "tigorman-oradg-public-ip01"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vmName1 is "tigorman-oradg-vm01"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _nicName2 is "tigorman-oradg-nic02"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _pubIpName2 is "tigorman-oradg-public-ip02"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vmName2 is "tigorman-oradg-vm02"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _nicName3 is "tigorman-oradg-nic03"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _pubIpName3 is "tigorman-oradg-public-ip03"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vmName3 is "tigorman-oradg-vm03"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vmDomain is "internal.cloudapp.net"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _vmOsDiskSize is "32"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraHome is "/u01/app/oracle/product/12.2.0/dbhome_1"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraInvDir is "/u01/app/oraInventory"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraOsAcct is "oracle"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraOsGroup is "oinstall"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraCharSet is "WE8ISO8859P15"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraScsiDevice is "/dev/sdc"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraScsiPartition is "/dev/sdc1"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraMntDir is "/u02"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraDataDir is "/u02/oradata"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraFRADir is "/u02/orarecv"
Sat Apr 25 17:27:27 UTC 2020 - DBUG: variable _oraRedoSizeMB is "500"
Sat Apr 25 17:27:27 UTC 2020 - INFO: az account set...
Sat Apr 25 17:27:28 UTC 2020 - INFO: az configure --defaults group location...
Sat Apr 25 17:27:29 UTC 2020 - INFO: az storage account create tigormanoradgsa...
Sat Apr 25 17:27:58 UTC 2020 - INFO: az network vnet create tigorman-oradg-vnet...
Sat Apr 25 17:28:14 UTC 2020 - INFO: az network nsg create tigorman-oradg-nsg...
Sat Apr 25 17:28:20 UTC 2020 - INFO: az network nsg rule create default-all-ssh...
Sat Apr 25 17:28:32 UTC 2020 - INFO: az network public-ip create tigorman-oradg-public-ip01...
Sat Apr 25 17:28:36 UTC 2020 - INFO: az network nic create tigorman-oradg-nic01...
Sat Apr 25 17:29:08 UTC 2020 - INFO: az vm create tigorman-oradg-vm01...
Sat Apr 25 17:30:15 UTC 2020 - INFO: az vm disk attach...
Sat Apr 25 17:30:50 UTC 2020 - INFO: az network public-ip create tigorman-oradg-public-ip02...
Sat Apr 25 17:30:55 UTC 2020 - INFO: az network nic create tigorman-oradg-nic02...
Sat Apr 25 17:31:27 UTC 2020 - INFO: az vm create tigorman-oradg-vm02...
Sat Apr 25 17:33:01 UTC 2020 - INFO: az vm disk attach...
Sat Apr 25 17:33:35 UTC 2020 - INFO: az network public-ip create tigorman-oradg-public-ip03...
Sat Apr 25 17:33:39 UTC 2020 - INFO: az network nic create tigorman-oradg-nic03...
Sat Apr 25 17:34:11 UTC 2020 - INFO: az vm create tigorman-oradg-vm03...
Sat Apr 25 17:35:46 UTC 2020 - INFO: az network public-ip show tigorman-oradg-public-ip01...
Sat Apr 25 17:35:48 UTC 2020 - INFO: public IP 52.158.238.191 for tigorman-oradg-vm01...
Sat Apr 25 17:35:48 UTC 2020 - INFO: az network public-ip show tigorman-oradg-public-ip02...
Sat Apr 25 17:35:49 UTC 2020 - INFO: public IP 20.187.32.79 for tigorman-oradg-vm02...
Sat Apr 25 17:35:49 UTC 2020 - INFO: az network public-ip show tigorman-oradg-public-ip03...
Sat Apr 25 17:35:51 UTC 2020 - INFO: public IP 52.151.38.116 for tigorman-oradg-vm03...
Sat Apr 25 17:35:51 UTC 2020 - INFO: partition /dev/sdc on tigorman-oradg-vm01...
Sat Apr 25 17:35:52 UTC 2020 - INFO: mkdir /u02 on tigorman-oradg-vm01...
Sat Apr 25 17:35:53 UTC 2020 - INFO: chown /u02 on tigorman-oradg-vm01...
Sat Apr 25 17:35:54 UTC 2020 - INFO: mkfs.ext4 /dev/sdc1 on tigorman-oradg-vm01...
Sat Apr 25 17:35:57 UTC 2020 - INFO: mount /u02 on tigorman-oradg-vm01...
Sat Apr 25 17:35:57 UTC 2020 - INFO: mkdir /u02/oradata /u02/orarecv on tigorman-oradg-vm01...
Sat Apr 25 17:35:58 UTC 2020 - INFO: chown /u02/oradata /u02/orarecv on tigorman-oradg-vm01...
Sat Apr 25 17:35:59 UTC 2020 - INFO: copy oraInst.loc file on tigorman-oradg-vm01
Sat Apr 25 17:36:00 UTC 2020 - INFO: partition /dev/sdc on tigorman-oradg-vm02...
Sat Apr 25 17:36:02 UTC 2020 - INFO: mkdir /u02 on tigorman-oradg-vm02...
Sat Apr 25 17:36:02 UTC 2020 - INFO: chown /u02 on tigorman-oradg-vm02...
Sat Apr 25 17:36:04 UTC 2020 - INFO: mkfs.ext4 /dev/sdc1 on tigorman-oradg-vm02...
Sat Apr 25 17:36:07 UTC 2020 - INFO: mount /u02 on tigorman-oradg-vm02...
Sat Apr 25 17:36:07 UTC 2020 - INFO: mkdir /u02/oradata /u02/orarecv on tigorman-oradg-vm02...
Sat Apr 25 17:36:08 UTC 2020 - INFO: chown /u02/oradata /u02/orarecv on tigorman-oradg-vm02...
Sat Apr 25 17:36:08 UTC 2020 - INFO: copy oraInst.loc file on tigorman-oradg-vm02
Sat Apr 25 17:36:10 UTC 2020 - INFO: sudo su - oracle dbca -createDatabase oradg01 on tigorman-oradg-vm01...
Copying database files
3% complete
5% complete
21% complete
33% complete
Creating and starting Oracle instance
35% complete
40% complete
44% complete
49% complete
50% complete
53% complete
55% complete
Completing Database Creation
56% complete
57% complete
58% complete
62% complete
65% complete
66% complete
Executing Post Configuration Actions
100% complete
Look at the log file "/u01/app/oracle/cfgtoollogs/dbca/oradg01/oradg01.log" for further details.
Sat Apr 25 17:47:56 UTC 2020 - INFO: configure TNSNAMES on tigorman-oradg-vm01...
Sat Apr 25 17:48:01 UTC 2020 - INFO: configure TNSNAMES on tigorman-oradg-vm02...
Sat Apr 25 17:48:05 UTC 2020 - INFO: configure TNSNAMES.ORA on tigorman-oradg-vm03...
Sat Apr 25 17:48:07 UTC 2020 - INFO: create services and startDgServices trigger...
Sat Apr 25 17:48:08 UTC 2020 - INFO: set FORCE LOGGING...
Sat Apr 25 17:48:08 UTC 2020 - INFO: set LOG_ARCHIVE_DEST_1...
Sat Apr 25 17:48:09 UTC 2020 - INFO: set SERVICE_NAMES on tigorman-oradg-vm01...
Sat Apr 25 17:48:10 UTC 2020 - INFO: adding static LISTENER service on tigorman-oradg-vm01...
Sat Apr 25 17:48:11 UTC 2020 - INFO: set STANDBY_FILE_MANAGEMENT...
Sat Apr 25 17:48:12 UTC 2020 - INFO: set LOG_ARCHIVE_CONFIG...
Sat Apr 25 17:48:12 UTC 2020 - INFO: set DB_FLASHBACK_RETENTION_TARGET...
Sat Apr 25 17:48:13 UTC 2020 - INFO: set DG_BROKER_CONFIG_FILE1...
Sat Apr 25 17:48:14 UTC 2020 - INFO: set DG_BROKER_CONFIG_FILE2...
Sat Apr 25 17:48:14 UTC 2020 - INFO: set DG_BROKER_START...
Sat Apr 25 17:48:17 UTC 2020 - INFO: create STANDBY LOGFILE GROUPS...
Sat Apr 25 17:48:51 UTC 2020 - INFO: SHUTDOWN then STARTUP MOUNT...
Sat Apr 25 17:49:24 UTC 2020 - INFO: set MAXIMUM AVAILABILITY on tigorman-oradg-vm01...
Sat Apr 25 17:49:25 UTC 2020 - INFO: enable FLASHBACK DATABASE on tigorman-oradg-vm01...
Sat Apr 25 17:49:34 UTC 2020 - INFO: copy password file from tigorman-oradg-vm01 to tigorman-oradg-vm02...
Sat Apr 25 17:49:41 UTC 2020 - INFO: STARTUP FORCE...
Sat Apr 25 17:50:02 UTC 2020 - INFO: sudo su - oracle dbca -createDuplicateDB oradg01 on tigorman-oradg-vm02...
Listener config step
33% complete
Auxiliary instance creation
66% complete
RMAN duplicate
100% complete
Look at the log file "/u01/app/oracle/cfgtoollogs/dbca/oradg01_stdby/oradg01.log" for further details.
Sat Apr 25 17:53:44 UTC 2020 - INFO: adding static LISTENER service on tigorman-oradg-vm02...
Sat Apr 25 17:53:46 UTC 2020 - INFO: set SERVICE_NAMES...
Sat Apr 25 17:53:47 UTC 2020 - INFO: set LOG_ARCHIVE_CONFIG on tigorman-oradg-vm02...
Sat Apr 25 17:53:47 UTC 2020 - INFO: set MAXIMUM AVAILABILITY on tigorman-oradg-vm02...
Sat Apr 25 17:53:48 UTC 2020 - INFO: enable FLASHBACK DATABASE on tigorman-oradg-vm02...
Sat Apr 25 17:53:57 UTC 2020 - INFO: verify TNSNAMES entries on tigorman-oradg-vm01...
Sat Apr 25 17:54:00 UTC 2020 - INFO: verify TNSNAMES entries on tigorman-oradg-vm02...
Sat Apr 25 17:54:03 UTC 2020 - INFO: verify TNSNAMES entries on tigorman-oradg-vm03...
Sat Apr 25 17:54:06 UTC 2020 - INFO: enable DataGuard and FSFO...
Sat Apr 25 17:54:57 UTC 2020 - INFO: generate observer script on tigorman-oradg-vm03...
Sat Apr 25 17:54:57 UTC 2020 - INFO: start observer script in background on tigorman-oradg-vm03...
Sat Apr 25 17:54:58 UTC 2020 - INFO: pause for 10 seconds...
Sat Apr 25 17:55:08 UTC 2020 - INFO: show configuration and fast_start failover on tigorman-oradg-vm03...
DGMGRL for Linux: Release 12.2.0.1.0 - Production on Sat Apr 25 17:55:08 2020

Copyright (c) 1982, 2017, Oracle and/or its affiliates.  All rights reserved.

Welcome to DGMGRL, type "help" for information.
Connected to "oradg01"
Connected as SYSDBA.
DGMGRL> 
Configuration - FSF

  Protection Mode: MaxAvailability
  Members:
  oradg01       - Primary database
    Warning: ORA-16819: fast-start failover observer not started

    oradg01_stdby - (*) Physical standby database 
      Warning: ORA-16819: fast-start failover observer not started

Fast-Start Failover: ENABLED

Configuration Status:
WARNING   (status updated 23 seconds ago)

DGMGRL> 
Fast-Start Failover: ENABLED

  Threshold:          30 seconds
  Target:             oradg01_stdby
  Observer:           tigorman-oradg-vm03
  Lag Limit:          30 seconds (not in use)
  Shutdown Primary:   TRUE
  Auto-reinstate:     TRUE
  Observer Reconnect: (none)
  Observer Override:  FALSE

Configurable Failover Conditions
  Health Conditions:
    Corrupted Controlfile          YES
    Corrupted Dictionary           YES
    Inaccessible Logfile            NO
    Stuck Archiver                  NO
    Datafile Write Errors          YES

  Oracle Error Conditions:
    (none)

DGMGRL> DGMGRL> Sat Apr 25 17:55:10 UTC 2020 - INFO: successful completion!

## Testing DataGuard switchover and failover

To test the actions of "switchover" and "failover", SSH into the the "oracle" account of the "observer" VM and run the DGMGRL utility after connecting as the SYS database account using the TNS string "${DB_NAME}_dgmgrl".

For example, if the "${ORACLE_SID}" value is "oradg01", then the DB_NAME of the primary database on the first VM will also be "oradg01", while the DB_NAME of the standby database on the second VM will be "oradg01_stdby".

Therefore, starting from the Azure cloud shell where the "cr_oradg.sh" script was executed, perform the following steps to test switchover...

1. SSH into the "observer" VM using SSH public-key authentication via the administrative OS account
   - if the admin OS account is "tigorman" and the public IP address is "10.20.30.40", use "ssh tigorman@10.20.30.40"
2. Then, change from the administrative OS account to the "oracle" OS account
   - use "sudo su - oracle"
3. Initialize the ORACLE_SID environment variable
   - use "export ORACLE_SID=<value>". For example, if the value of ORACLE_SID is "oradg01", then use "export ORACLE_SID=oradg01".
4. Login to the DataGuard Broker DGMGRL utility
   - use the command "dgmgrl sys/<password>@<tns-string-for-dgmgrl>"
   - where "<password>" is the password for the SYS database account set by the "cr_oradg.sh" script (default: "oracleA1")
   - where "<tns-string-for-dgmgrl>" is "<db-name>_dgmgrl"
      - where "db-name" is "<oracle-sid>" for the primary database and "<oracle-sid>_stdby" for the standby database
      - if "ORACLE_SID" is "oradg01", use "oradg01_dgmgrl" for the primary and "oradg01_stdby_dgmgrl" for the standby
   - using the defaults cited above, "dgmgrl sys/oracleA1@oradg01_dgmgrl" will connect the DataGuard broker to the primary
5. Once connected to the DataGuard Broker DGMGRL utilty, show the DataGuard configuration status
   - at the "DGMGRL>" prompt, run "show configuration"
6. Once connected to broker utility, also show the Fast-Start Failover configuration status
   - at the "DGMGRL>" prompt, run "show fast_start failover"
7. If both "show configuration" and "show fast_start failover" display no warnings or errors...
   - switchover the PRIMARY role from "oradg01" on the first VM to "oradg01_stdby" on the second VM
   - when completed, "oradg01_stdby" will be PRIMARY and "oradg01" will be STANDBY
8. Switchover can be performed in either direction as desired
9. Failover can be triggered by performing SHUTDOWN ABORT on the database with the PRIMARY role
   - the failed former PRIMARY cannot become a STANDBY until it is manually mounted with STARTUP MOUNT
   - after the failed former PRIMARY has been manually mounted, it must be reinstated into the configuration in DGMGRL
      - use the command "reinstate database <db-name>" to complete reinstatement of the failed database as a standby
