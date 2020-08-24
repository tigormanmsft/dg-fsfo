#!/bin/bash
#================================================================================
# Name:	cr_oradg.sh
# Type:	bash script
# Date:	20-April 2020
# From:	Americas Customer Engineering team (CET) - Microsoft
#
# Copyright and license:
#
#	Licensed under the Apache License, Version 2.0 (the "License"); you may
#	not use this file except in compliance with the License.
#
#	You may obtain a copy of the License at
#
#		http://www.apache.org/licenses/LICENSE-2.0
#
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" basis,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
#	See the License for the specific language governing permissions and
#	limitations under the License.
#
#	Copyright (c) 2020 by Microsoft.  All rights reserved.
#
# Ownership and responsibility:
#
#	This script is offered without warranty by Microsoft Customer Engineering.
#	Anyone using this script accepts full responsibility for use, effect,
#	and maintenance.  Please do not contact Microsoft support unless there
#	is a problem with a supported Azure component used in this script,
#	such as an "az" command.
#
# Description:
#
#	Script to automate the creation of an Oracle DataGuard FSFO environment
#	within Microsoft Azure, using the Azure CLI.
#
# Command-line Parameters:
#
#	cr_oradg.sh -G val -H val -I val -N -M -O val -P val -S val -c val -d val -i val -p val -r val -s val -u val -v -w val
#
#	where:
#
#	-G resource=group-name	name of the Azure resource group (default: ${_azureOwner}-${_azureProject}-rg)
#	-H ORACLE_HOME		full path of the ORACLE_HOME software (default: /u01/app/oracle/product/12.2.0/dbhome_1)
#	-I obsvr-instance-type	name of the Azure VM instance type for DataGuard observer node (default: Standard_DS1_v2)
#	-N			skip steps to create vnet/subnet, public-IP, NSG, rules, and PPG (default: false)
#	-M			skip steps to create VMs and storage (default: false)
#	-O owner-tag		name of the owner to use in Azure tags (default: `whoami`)
#	-P project-tag		name of the project to use in Azure tags (default: "oradg")
#	-S subscription		name of the Azure subscription (no default)
#	-V vip-IPaddr		IP address for the virtual IP (VIP) (default: 10.0.0.10)
#	-d domain-name		IP domain name (default: internal.cloudapp.net)
#	-i instance-type	name of the Azure VM instance type for database nodes (default: Standard_DS11-1_v2)
#	-p Oracle-port		port number of the Oracle TNS Listener (default: 1521)
#	-r region		name of Azure region (default: westus2)
#	-s ORACLE_SID		Oracle System ID (SID) value (default: oradb01)
#	-u urn			URN from Azure marketplace (default: Oracle:Oracle-Database-Ee:12.2.0.1:12.2.20180725)
#	-v                      set verbose output is true (default: false)
#	-w SYS/SYSTEM pwd	initial password for Oracle database SYS and SYSTEM accounts (default: oracleA1)
#
# Expected command-line output:
#
# Usage notes:
#
#	1) Azure subscription must be specified with "-S" switch, always
#
#	2) Azure owner, default is output of "whoami" command in shell, can be
#	   specified using "-O" switch on command-line
#
#	3) Azure project, default is "oradg", can be specified using "-P"
#	   switch on command-line
#
#	4) Azure resource group, specify with "-G" switch or with a
#	   combination of "-O" (project owner tag) and "-P" (project name)
#	   values (default: "(project owner tag)-(project name)-rg").
#
#	   For example, if the project owner tag is "abc" and the project
#	   name is "beetlejuice", then by default the resource group is
#	   expected to be named "abc-beetlejuice-rg", unless changes have
#	   been specified using the "-G", "-O", or "-P" switches
#
#	5) Use the "-v" (verbose) switch to verify that program variables
#	   have the expected values
#
#	6) For users who are expected to use prebuilt storage accounts
#	   and networking (i.e. vnet, subnet, network security groups, etc),
#	   consider using the "-N" switch to accept these as prerequisites 
#
#	Please be aware that Azure owner (i.e. "-O") and Azure project (i.e. "-P")
#	are used to generate names for the Azure resource group, storage
#	account, virtual network, subnet, network security group and rules,
#	VM, and storage disks.  Use the "-v" switch to verify expected naming.
#
#	The "-N" and "-M" switches were mainly used for debugging, and might well
#	be removed in more mature versions of the script.  They intended to skip
#	over some steps if something failed later on.
#
# Modifications:
#	TGorman	20apr20	v0.1 written
#	TGorman	04may20	v0.3 lots of little cleanup changes...
#	TGorman	08jun20	v0.4 added _vmDataDiskCaching and fixed "_rgName" handling
#	TGorman	08jun20	v0.5 added _oraHome as parameter, set ORACLE_HOME,
#			     PATH, and TNS_ADMIN explicitly during all "su - oracle"
#			     sessions
#	TGorman	08jun20	v0.6 turn off Linux firewall on VMs
#	TGorman	24aug20	v0.7 added "N" and "M" command-line switches for
#			     debugging, made firewall disable a warning...
#================================================================================
#
#--------------------------------------------------------------------------------
# Set global environment variables for the entire script...
#--------------------------------------------------------------------------------
_progVersion="v0.7"
_outputMode="terse"
_azureOwner="`whoami`"
_azureProject="oradg"
_azureRegion="westus2"
_azureSubscription=""
_skipVnetNicNsg="false"
_skipMachines="false"
_workDir="`pwd`"
_logFile="${_workDir}/${_azureOwner}-${_azureProject}.log"
_saName="${_azureOwner}${_azureProject}sa"
_rgName="${_azureOwner}-${_azureProject}-rg"
_newRgName="~"
_vnetName="${_azureOwner}-${_azureProject}-vnet"
_subnetName="${_azureOwner}-${_azureProject}-subnet"
_nsgName="${_azureOwner}-${_azureProject}-nsg"
_nicName1="${_azureOwner}-${_azureProject}-nic01"
_nicName2="${_azureOwner}-${_azureProject}-nic02"
_nicName3="${_azureOwner}-${_azureProject}-nic03"
_pubIpName1="${_azureOwner}-${_azureProject}-public-ip01"
_pubIpName2="${_azureOwner}-${_azureProject}-public-ip02"
_pubIpName3="${_azureOwner}-${_azureProject}-public-ip03"
_vmZone1="1"
_vmZone2="2"
_vmZone3="3"
_vmNbr1="vm0${_vmZone1}"
_vmNbr2="vm0${_vmZone2}"
_vmNbr3="vm0${_vmZone3}"
_vmName1="${_azureOwner}-${_azureProject}-${_vmNbr1}"
_vmName2="${_azureOwner}-${_azureProject}-${_vmNbr2}"
_vmName3="${_azureOwner}-${_azureProject}-${_vmNbr3}"
_vmUrn="Oracle:Oracle-Database-Ee:12.2.0.1:12.2.20180725"
_vmDomain="internal.cloudapp.net"
_vmOsDiskSize="32"
_vmDataDiskSize="64"
_vmDataDiskCaching="ReadOnly"
_vmDbInstanceType="Standard_DS11-1_v2"
_vmObsvrInstanceType="Standard_DS1_v2"
_oraSid="oradg01"
_oraHome="/u01/app/oracle/product/12.2.0/dbhome_1"
_oraInvDir="/u01/app/oraInventory"
_oraOsAcct="oracle"
_oraOsGroup="oinstall"
_oraCharSet="WE8ISO8859P15"
_scsiDev="/dev/sdc"
_scsiPartition="${_scsiDev}1"
_oraMntDir="/u02"
_oraDataDir="${_oraMntDir}/oradata"
_oraFRADir="${_oraMntDir}/orarecv"
_oraSysPwd=oracleA1
_oraRedoSizeMB=500
_oraLsnrPort=1521
#
#--------------------------------------------------------------------------------
# Accept command-line parameter values to override default values (above)..
#--------------------------------------------------------------------------------
typeset -i _parseErrs=0
while getopts ":G:H:I:MNO:P:S:c:d:i:p:r:s:u:vw:" OPTNAME
do
	case "${OPTNAME}" in
		G)	_newRgName="${OPTARG}"		;;
		H)	_oraHome="${OPTARG}"		;;
		I)	_vmObsvrInstanceType="${OPTARG}" ;;
		M)	_skipMachines="true"		;;
		N)	_skipVnetNicNsg="true"		;;
		O)	_azureOwner="${OPTARG}"		;;
		P)	_azureProject="${OPTARG}"	;;
		S)	_azureSubscription="${OPTARG}"	;;
		c)	_vmDataDiskCaching="${OPTARG}"	;;
		d)	_vmDomain="${OPTARG}"		;;
		i)	_vmDbInstanceType="${OPTARG}"	;;
		p)	_oraLsnrPort="${OPTARG}"	;;
		r)	_azureRegion="${OPTARG}"	;;
		s)	_oraSid="${OPTARG}"		;;
		u)	_vmUrn="${OPTARG}"		;;
		v)	_outputMode="verbose"		;;
		w)	_oraSysPwd="${OPTARG}"		;;
		:)	echo "`date` - FAIL: expected \"${OPTARG}\" value not found"
			typeset -i _parseErrs=${_parseErrs}+1
			;;
		\?)	echo "`date` - FAIL: unknown command-line option \"${OPTARG}\""
			typeset -i _parseErrs=${_parseErrs}+1
			;;
	esac	
done
shift $((OPTIND-1))
#
#--------------------------------------------------------------------------------
# If any errors occurred while processing the command-line parameters, then display
# a usage message and exit with failure status...
#--------------------------------------------------------------------------------
if (( ${_parseErrs} > 0 )); then
	echo "Usage: $0 -G val -H val -I val -N -M -O val -P val -S val -c val -d val -i val -p val -r val -s val -u val -v -w val"
	echo "where:"
	echo "	-G resource=group-name	name of the Azure resource group (default: ${_azureOwner}-${_azureProject}-rg)"
	echo "	-H ORACLE_HOME		full pathname of Oracle software (default: /u01/app/oracle/product/12.2.0/dbhome_1)"
	echo "	-I obsvr-instance-type	name of the Azure VM instance type for DataGuard observer node (default: Standard_DS1_v2)"
	echo "	-N			skip steps to create vnet/subnet, public-IP, NSG, and network rules"
	echo "	-M			skip steps to create VMs and storage"
	echo "	-O owner-tag		name of the owner to use in Azure tags (default: \$USERNAME)"
	echo "	-P project-tag		name of the project to use in Azure tags (default: oradg)"
	echo "	-S subscription		name of the Azure subscription (no default)"
	echo "	-c ReadOnly | None	Azure managed disk caching: None (off) or ReadOnly (default)"
	echo "	-d domain-name		IP domain name (default: internal.cloudapp.net)"
	echo "	-i db-instance-type	name of the Azure VM instance type for database nodes (default: Standard_DS11-1_v2)"
	echo "	-p Oracle-port		port number of the Oracle TNS Listener (default: 1521)"
	echo "	-r region		name of Azure region (default: westus2)"
	echo "	-s ORACLE_SID		Oracle System ID (SID) value (default: oradb01)"
	echo "	-u urn			URN from Azure marketplace (default: Oracle:Oracle-Database-Ee:12.2.0.1:12.2.20180725)"
	echo "	-v			set verbose output is true (default: false)"
	echo "	-w SYS/SYSTEM pwd	initial password for Oracle database SYS and SYSTEM accounts (default: oracleA1)"
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Reset some of the script variables in case "owner" or "project" was changed
# from the default value...
#--------------------------------------------------------------------------------
_logFile="${_workDir}/${_azureOwner}-${_azureProject}.log"
if [[ "${_newRgName}" = "~" ]]
then
	_rgName="${_azureOwner}-${_azureProject}-rg"
else
	_rgName="${_newRgName}"
fi
_saName="${_azureOwner}${_azureProject}sa"
_vnetName="${_azureOwner}-${_azureProject}-vnet"
_subnetName="${_azureOwner}-${_azureProject}-subnet"
_nsgName="${_azureOwner}-${_azureProject}-nsg"
_nicName1="${_azureOwner}-${_azureProject}-nic01"
_nicName2="${_azureOwner}-${_azureProject}-nic02"
_nicName3="${_azureOwner}-${_azureProject}-nic03"
_pubIpName1="${_azureOwner}-${_azureProject}-public-ip01"
_pubIpName2="${_azureOwner}-${_azureProject}-public-ip02"
_pubIpName3="${_azureOwner}-${_azureProject}-public-ip03"
_vmName1="${_azureOwner}-${_azureProject}-${_vmNbr1}"
_vmName2="${_azureOwner}-${_azureProject}-${_vmNbr2}"
_vmName3="${_azureOwner}-${_azureProject}-${_vmNbr3}"
#
#--------------------------------------------------------------------------------
# Display variable values when output is set to "verbose"...
#--------------------------------------------------------------------------------
if [[ "${_outputMode}" = "verbose" ]]; then
	echo "`date` - DBUG: parameter _rgName is \"${_rgName}\""
	echo "`date` - DBUG: parameter _progVersion is \"${_progVersion}\""
	echo "`date` - DBUG: parameter _azureOwner is \"${_azureOwner}\""
	echo "`date` - DBUG: parameter _azureProject is \"${_azureProject}\""
	echo "`date` - DBUG: parameter _azureSubscription is \"${_azureSubscription}\""
	echo "`date` - DBUG: parameter _vmDataDiskCaching is \"${_vmDataDiskCaching}\""
	echo "`date` - DBUG: parameter _vmDomain is \"${_vmDomain}\""
	echo "`date` - DBUG: parameter _vmDbInstanceType is \"${_vmDbInstanceType}\""
	echo "`date` - DBUG: parameter _oraHome is \"${_oraHome}\""
	echo "`date` - DBUG: parameter _vmObsvrInstanceType is \"${_vmObsvrInstanceType}\""
	echo "`date` - DBUG: parameter _oraLsnrPort is \"${_oraLsnrPort}\""
	echo "`date` - DBUG: parameter _azureRegion is \"${_azureRegion}\""
	echo "`date` - DBUG: parameter _oraSid is \"${_oraSid}\""
	echo "`date` - DBUG: parameter _vmUrn is \"${_vmUrn}\""
	echo "`date` - DBUG: variable _workDir is \"${_workDir}\""
	echo "`date` - DBUG: variable _logFile is \"${_logFile}\""
	echo "`date` - DBUG: variable _saName is \"${_saName}\""
	echo "`date` - DBUG: variable _vnetName is \"${_vnetName}\""
	echo "`date` - DBUG: variable _subnetName is \"${_subnetName}\""
	echo "`date` - DBUG: variable _nsgName is \"${_nsgName}\""
	echo "`date` - DBUG: variable _nicName1 is \"${_nicName1}\""
	echo "`date` - DBUG: variable _pubIpName1 is \"${_pubIpName1}\""
	echo "`date` - DBUG: variable _vmName1 is \"${_vmName1}\""
	echo "`date` - DBUG: variable _nicName2 is \"${_nicName2}\""
	echo "`date` - DBUG: variable _pubIpName2 is \"${_pubIpName2}\""
	echo "`date` - DBUG: variable _vmName2 is \"${_vmName2}\""
	echo "`date` - DBUG: variable _nicName3 is \"${_nicName3}\""
	echo "`date` - DBUG: variable _pubIpName3 is \"${_pubIpName3}\""
	echo "`date` - DBUG: variable _vmName3 is \"${_vmName3}\""
	echo "`date` - DBUG: variable _vmOsDiskSize is \"${_vmOsDiskSize}\""
	echo "`date` - DBUG: variable _oraInvDir is \"${_oraInvDir}\""
	echo "`date` - DBUG: variable _oraOsAcct is \"${_oraOsAcct}\""
	echo "`date` - DBUG: variable _oraOsGroup is \"${_oraOsGroup}\""
	echo "`date` - DBUG: variable _oraCharSet is \"${_oraCharSet}\""
	echo "`date` - DBUG: variable _scsiDev is \"${_scsiDev}\""
	echo "`date` - DBUG: variable _scsiPartition is \"${_scsiPartition}\""
	echo "`date` - DBUG: variable _oraMntDir is \"${_oraMntDir}\""
	echo "`date` - DBUG: variable _oraDataDir is \"${_oraDataDir}\""
	echo "`date` - DBUG: variable _oraFRADir is \"${_oraFRADir}\""
	echo "`date` - DBUG: variable _oraRedoSizeMB is \"${_oraRedoSizeMB}\""
fi
#
#--------------------------------------------------------------------------------
# Remove any existing logfile...
#--------------------------------------------------------------------------------
rm -f ${_logFile}
echo "`date` - INFO: \"$0 $*\" ${_progVersion}, starting..." >> ${_logFile}
#
#--------------------------------------------------------------------------------
# Verify that the resource group exists...
#--------------------------------------------------------------------------------
echo "`date` - INFO: az group exists -n ${_rgName}..." | tee -a ${_logFile}
if [[ "`az group exists -n ${_rgName}`" != "true" ]]; then
	echo "`date` - FAIL: resource group \"${_rgName}\" does not exist" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Set the default Azure subscription...
#--------------------------------------------------------------------------------
echo "`date` - INFO: az account set..." | tee -a ${_logFile}
az account set -s "${_azureSubscription}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: az account set" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Set the default Azure resource group and region/location...
#--------------------------------------------------------------------------------
echo "`date` - INFO: az configure --defaults group location..." | tee -a ${_logFile}
az configure --defaults group=${_rgName} location=${_azureRegion} >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: az configure --defaults group location" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# If the user elected to skip the creation of vnet, the NIC, the NSG, and the
# rules...
#--------------------------------------------------------------------------------
if [[ "${_skipVnetNicNsg}" = "false" ]]
then
	#
	#------------------------------------------------------------------------
	# Create an Azure storage account for this project...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az storage account create ${_saName}..." | tee -a ${_logFile}
	az storage account create \
		--name ${_saName} \
		--sku Standard_LRS \
		--access-tier Hot \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az storage account create ${_saName}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure virtual network for this project...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network vnet create ${_vnetName}..." | tee -a ${_logFile}
	az network vnet create \
		--name ${_vnetName} \
		--address-prefixes 10.0.0.0/16 \
		--subnet-name ${_subnetName} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--subnet-prefixes 10.0.0.0/24 \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network vnet create ${_vnetName}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure network security group for this project...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network nsg create ${_nsgName}..." | tee -a ${_logFile}
	az network nsg create \
		--name ${_nsgName} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network nsg create ${_nsgName}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create a custom Azure network security group rule to permit SSH access...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network nsg rule create default-all-ssh..." | tee -a ${_logFile}
	az network nsg rule create \
		--name default-all-ssh \
		--nsg-name ${_nsgName} \
		--priority 1000 \
		--direction Inbound \
		--protocol TCP \
		--source-address-prefixes \* \
		--source-port-ranges \* \
		--destination-address-prefixes \* \
		--destination-port-ranges 22 \
		--access Allow \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network nsg rule create default-all-ssh" | tee -a ${_logFile}
		exit 1
	fi
	#
fi
#
#--------------------------------------------------------------------------------
# If the user elected to skip the creation of virtual machines and data storage...
#--------------------------------------------------------------------------------
if [[ "${_skipMachines}" = "false" ]]
then
	#
	#------------------------------------------------------------------------
	# Create an Azure public IP address object for use with the first VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network public-ip create ${_pubIpName1}..." | tee -a ${_logFile}
	az network public-ip create \
		--name ${_pubIpName1} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--allocation-method Static \
		--sku Basic \
		--version IPv4 \
		--zone ${_vmZone1} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network public-ip create ${_pubIpName1}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure network interface (NIC) object for use with the first VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network nic create ${_nicName1}..." | tee -a ${_logFile}
	az network nic create \
		--name ${_nicName1} \
		--vnet-name ${_vnetName} \
		--subnet ${_subnetName} \
		--network-security-group ${_nsgName} \
		--public-ip-address ${_pubIpName1} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network nic create ${_nicName1}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create the first Azure virtual machine (VM), intended to be used as the
	# primary Oracle database server/host...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az vm create ${_vmName1}..." | tee -a ${_logFile}
	az vm create \
		--name ${_vmName1} \
		--image ${_vmUrn}:latest \
		--admin-username ${_azureOwner} \
		--size ${_vmDbInstanceType} \
		--zone ${_vmZone1} \
		--nics ${_nicName1} \
		--os-disk-name ${_vmName1}-osdisk \
		--os-disk-size-gb ${_vmOsDiskSize} \
		--os-disk-caching ReadWrite \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--generate-ssh-keys \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az vm create ${_vmName1}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create and attach a data disk to the VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az vm disk attach..." | tee -a ${_logFile}
	az vm disk attach \
		--new \
		--name ${_vmName1}-datadisk01 \
		--vm-name ${_vmName1} \
		--caching ${_vmDataDiskCaching} \
		--size-gb ${_vmDataDiskSize} \
		--sku Premium_LRS \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az vm disk attach ${_vmName1}-datadisk01" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure public IP address object for use with the second VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network public-ip create ${_pubIpName2}..." | tee -a ${_logFile}
	az network public-ip create \
		--name ${_pubIpName2} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--allocation-method Static \
		--sku Basic \
		--version IPv4 \
		--zone ${_vmZone2} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network public-ip create ${_pubIpName2}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure network interface (NIC) object for use with the second VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network nic create ${_nicName2}..." | tee -a ${_logFile}
	az network nic create \
		--name ${_nicName2} \
		--vnet-name ${_vnetName} \
		--subnet ${_subnetName} \
		--network-security-group ${_nsgName} \
		--public-ip-address ${_pubIpName2} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network nic create ${_nicName2}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create the second Azure virtual machine (VM), intended to be used as
	# the standby Oracle database server/host...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az vm create ${_vmName2}..." | tee -a ${_logFile}
	az vm create \
		--name ${_vmName2} \
		--image ${_vmUrn}:latest \
		--admin-username ${_azureOwner} \
		--size ${_vmDbInstanceType} \
		--zone ${_vmZone2} \
		--nics ${_nicName2} \
		--os-disk-name ${_vmName2}-osdisk \
		--os-disk-size-gb ${_vmOsDiskSize} \
		--os-disk-caching ReadWrite \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--generate-ssh-keys \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az vm create ${_vmName2}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create and attach a data disk to the VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az vm disk attach..." | tee -a ${_logFile}
	az vm disk attach \
		--new \
		--name ${_vmName2}-datadisk01 \
		--vm-name ${_vmName2} \
		--caching ${_vmDataDiskCaching} \
		--size-gb ${_vmDataDiskSize} \
		--sku Premium_LRS \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az vm disk attach ${_vmName2}-datadisk01" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure public IP address object for use with the third VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network public-ip create ${_pubIpName3}..." | tee -a ${_logFile}
	az network public-ip create \
		--name ${_pubIpName3} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--allocation-method Static \
		--sku Basic \
		--version IPv4 \
		--zone ${_vmZone3} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network public-ip create ${_pubIpName3}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create an Azure network interface (NIC) object for use with the third VM...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az network nic create ${_nicName3}..." | tee -a ${_logFile}
	az network nic create \
		--name ${_nicName3} \
		--vnet-name ${_vnetName} \
		--subnet ${_subnetName} \
		--network-security-group ${_nsgName} \
		--public-ip-address ${_pubIpName3} \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az network nic create ${_nicName3}" | tee -a ${_logFile}
		exit 1
	fi
	#
	#------------------------------------------------------------------------
	# Create the third Azure virtual machine (VM), intended to be used as the
	# Oracle DataGuard FSFO observer node...
	#------------------------------------------------------------------------
	echo "`date` - INFO: az vm create ${_vmName3}..." | tee -a ${_logFile}
	az vm create \
		--name ${_vmName3} \
		--image ${_vmUrn}:latest \
		--admin-username ${_azureOwner} \
		--size ${_vmObsvrInstanceType} \
		--zone ${_vmZone3} \
		--nics ${_nicName3} \
		--os-disk-name ${_vmName3}-osdisk \
		--os-disk-size-gb ${_vmOsDiskSize} \
		--os-disk-caching ReadWrite \
		--tags owner=${_azureOwner} project=${_azureProject} \
		--generate-ssh-keys \
		--verbose >> ${_logFile} 2>&1
	if (( $? != 0 )); then
		echo "`date` - FAIL: az vm create ${_vmName3}" | tee -a ${_logFile}
		exit 1
	fi
	#
fi
#
#--------------------------------------------------------------------------------
# Obtain the public IP addresses for future use within the script...
#--------------------------------------------------------------------------------
echo "`date` - INFO: az network public-ip show ${_pubIpName1}..." | tee -a ${_logFile}
_ipAddr1=`az network public-ip show --name ${_pubIpName1} | \
	 jq '. | {ipaddr: .ipAddress}' | \
	 grep ipaddr | \
	 awk '{print $2}' | \
	 sed 's/"//g'`
if (( $? != 0 )); then
	echo "`date` - FAIL: az network public-ip show ${_pubIpName1}" | tee -a ${_logFile}
	exit 1
fi
echo "`date` - INFO: public IP ${_ipAddr1} for ${_vmName1}..." | tee -a ${_logFile}
#
echo "`date` - INFO: az network public-ip show ${_pubIpName2}..." | tee -a ${_logFile}
_ipAddr2=`az network public-ip show --name ${_pubIpName2} | \
	 jq '. | {ipaddr: .ipAddress}' | \
	 grep ipaddr | \
	 awk '{print $2}' | \
	 sed 's/"//g'`
if (( $? != 0 )); then
	echo "`date` - FAIL: az network public-ip show ${_pubIpName2}" | tee -a ${_logFile}
	exit 1
fi
echo "`date` - INFO: public IP ${_ipAddr2} for ${_vmName2}..." | tee -a ${_logFile}
#
echo "`date` - INFO: az network public-ip show ${_pubIpName3}..." | tee -a ${_logFile}
_ipAddr3=`az network public-ip show --name ${_pubIpName3} | \
	 jq '. | {ipaddr: .ipAddress}' | \
	 grep ipaddr | \
	 awk '{print $2}' | \
	 sed 's/"//g'`
if (( $? != 0 )); then
	echo "`date` - FAIL: az network public-ip show ${_pubIpName3}" | tee -a ${_logFile}
	exit 1
fi
echo "`date` - INFO: public IP ${_ipAddr3} for ${_vmName3}..." | tee -a ${_logFile}
#
#--------------------------------------------------------------------------------
# Remove any previous entries of the IP address from the "known hosts" config
# file...
#--------------------------------------------------------------------------------
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R ${_ipAddr1} >> ${_logFile} 2>&1
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R ${_ipAddr2} >> ${_logFile} 2>&1
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R ${_ipAddr3} >> ${_logFile} 2>&1
#
#--------------------------------------------------------------------------------
# SSH into all three VM's to stop the Linux firewall daemon, if it is running...
#--------------------------------------------------------------------------------
echo "`date` - INFO: systemctl stop firewalld on ${_vmName1}..." | tee -a ${_logFile}
ssh -o StrictHostKeyChecking=no ${_azureOwner}@${_ipAddr1} "sudo systemctl stop firewalld" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - WARN: sudo systemctl stop firewalld on ${_vmName1}" | tee -a ${_logFile}
fi
echo "`date` - INFO: systemctl stop firewalld on ${_vmName2}..." | tee -a ${_logFile}
ssh -o StrictHostKeyChecking=no ${_azureOwner}@${_ipAddr2} "sudo systemctl stop firewalld" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - WARN: sudo systemctl stop firewalld on ${_vmName2}" | tee -a ${_logFile}
fi
echo "`date` - INFO: systemctl stop firewalld on ${_vmName3}..." | tee -a ${_logFile}
ssh -o StrictHostKeyChecking=no ${_azureOwner}@${_ipAddr3} "sudo systemctl stop firewalld" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - WARN: sudo systemctl stop firewalld on ${_vmName3}" | tee -a ${_logFile}
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to create a GPT label on the SCSI device...
#--------------------------------------------------------------------------------
echo "`date` - INFO: parted ${_scsiDev} mklabel gpt on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo parted ${_scsiDev} mklabel gpt" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo parted ${_scsiDev} mklabel gpt on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to create a single primary partitition consuming the entire
# SCSI device...
#--------------------------------------------------------------------------------
echo "`date` - INFO: parted -a opt ${_scsiDev} mkpart primary on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo parted -a opt ${_scsiDev} mkpart primary ext4 0% 100%" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo parted mkpart -a opt ${_scsiDev} primary ext4 0% 100% on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to create a directory mount-point for the soon-to-be-created
# filesystem in which Oracle database files will reside...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkdir ${_oraMntDir} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo mkdir ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkdir ${_oraMntDir} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to set the OS account:group ownership of the directory
# mount-point...
#--------------------------------------------------------------------------------
echo "`date` - INFO: chown ${_oraMntDir} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo chown ${_oraOsAcct}:${_oraOsGroup} ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraMntDir} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to create the Linux EXT4 filesystem on the partitioned
# data disk...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkfs.ext4 ${_scsiPartition} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo mkfs.ext4 ${_scsiPartition}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkfs.ext4 ${_scsiPartition} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to mount the newly-created filesystem on the newly-created
# directory mount-point...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mount ${_oraMntDir} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo mount ${_scsiPartition} ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mount ${_oraMntDir} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to create sub-directories for the Oracle database files
# and for the Oracle Flash Recovery Area (FRA) files...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkdir ${_oraDataDir} ${_oraFRADir} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo mkdir -p ${_oraDataDir} ${_oraFRADir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkdir -p ${_oraDataDir} ${_oraFRADir} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to set the OS account:group ownership of the sub-directories
# within the newly-created filesystem...
#--------------------------------------------------------------------------------
echo "`date` - INFO: chown ${_oraDataDir} ${_oraFRADir} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo chown ${_oraOsAcct}:${_oraOsGroup} ${_oraDataDir} ${_oraFRADir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraDataDir} ${_oraFRADir} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to copy the file "oraInst.loc" from the current Oracle
# Inventory default location into the "/etc" system directory, where it can be
# easily found by any Oracle programs accessing the host.  Set the ownership and
# permissions appropriately for the copied file...
#--------------------------------------------------------------------------------
echo "`date` - INFO: copy oraInst.loc file on ${_vmName1}" | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo cp ${_oraInvDir}/oraInst.loc /etc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo cp ${_azureOwner}@${_ipAddr1}:${_oraInvDir}/oraInst.loc /etc on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo chown ${_oraOsAcct}:${_oraOsGroup} /etc/oraInst.loc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraOsAcct}:${_oraOsGroup} /etc/oraInst.loc on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo chmod 644 /etc/oraInst.loc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chmod 644 /etc/oraInst.loc on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to create a GPT label on the SCSI device...
#--------------------------------------------------------------------------------
echo "`date` - INFO: parted ${_scsiDev} mklabel gpt on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo parted ${_scsiDev} mklabel gpt" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo parted ${_scsiDev} mklabel gpt on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to create a single primary partitition consuming the entire
# SCSI device...
#--------------------------------------------------------------------------------
echo "`date` - INFO: parted -a opt ${_scsiDev} mkpart primary on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo parted -a opt ${_scsiDev} mkpart primary ext4 0% 100%" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo parted mkpart -a opt ${_scsiDev} primary ext4 0% 100% on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to create a directory mount-point for the soon-to-be-
# created filesystem in which Oracle database files will reside...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkdir ${_oraMntDir} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo mkdir ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkdir ${_oraMntDir} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to set the OS account:group ownership of the directory
# mount-point...
#--------------------------------------------------------------------------------
echo "`date` - INFO: chown ${_oraMntDir} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo chown ${_oraOsAcct}:${_oraOsGroup} ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraMntDir} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to create the Linux EXT4 filesystem on the partitioned
# data disk...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkfs.ext4 ${_scsiPartition} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo mkfs.ext4 ${_scsiPartition}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkfs.ext4 ${_scsiPartition} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to mount the newly-created filesystem on the newly-created
# directory mount-point...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mount ${_oraMntDir} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo mount ${_scsiPartition} ${_oraMntDir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mount ${_oraMntDir} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to create sub-directories for the Oracle database files
# and for the Oracle Flash Recovery Area (FRA) files...
#--------------------------------------------------------------------------------
echo "`date` - INFO: mkdir ${_oraDataDir} ${_oraFRADir} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo mkdir -p ${_oraDataDir} ${_oraFRADir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo mkdir -p ${_oraDataDir} ${_oraFRADir} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to set the OS account:group ownership of the sub-
# directories within the newly-created filesystem...
#--------------------------------------------------------------------------------
echo "`date` - INFO: chown ${_oraDataDir} ${_oraFRADir} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo chown ${_oraOsAcct}:${_oraOsGroup} ${_oraDataDir} ${_oraFRADir}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraDataDir} ${_oraFRADir} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to copy the file "oraInst.loc" from the current Oracle
# Inventory default location into the "/etc" system directory, where it can be
# easily found by any Oracle programs accessing the host.  Set the ownership and
# permissions appropriately for the copied file...
#--------------------------------------------------------------------------------
echo "`date` - INFO: copy oraInst.loc file on ${_vmName2}" | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo cp ${_oraInvDir}/oraInst.loc /etc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo cp ${_azureOwner}@${_ipAddr2}:${_oraInvDir}/oraInst.loc /etc on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo chown ${_oraOsAcct}:${_oraOsGroup} /etc/oraInst.loc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chown ${_oraOsAcct}:${_oraOsGroup} /etc/oraInst.loc on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo chmod 644 /etc/oraInst.loc" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo chmod 644 /etc/oraInst.loc on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to run the Oracle Database Creation Assistant (DBCA)
# program to create a new primary Oracle database...
#--------------------------------------------------------------------------------
echo "`date` - INFO: sudo su - ${_oraOsAcct} dbca -createDatabase ${_oraSid} on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"\
	export ORACLE_HOME=${_oraHome}; \
	export PATH=${_oraHome}/bin:\${PATH}; \
	export TNS_ADMIN=${_oraHome}/network/admin; \
	dbca -silent -createDatabase \
		-gdbName ${_oraSid} \
		-templateName ${_oraHome}/assistants/dbca/templates/General_Purpose.dbc \
		-sid ${_oraSid} \
		-sysPassword ${_oraSysPwd} \
		-systemPassword ${_oraSysPwd} \
		-characterSet ${_oraCharSet} \
		-createListener LISTENER:${_oraLsnrPort} \
		-storageType FS \
		-datafileDestination ${_oraDataDir} \
		-enableArchive TRUE \
		-memoryMgmtType AUTO_SGA \
		-memoryPercentage 70 \
		-recoveryAreaDestination ${_oraFRADir} \
		-recoveryAreaSize 40960 \
		-redoLogFileSize ${_oraRedoSizeMB}\"" | tee -a ${_logFile}
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo su - ${_oraOsAcct} dbca -createDatabase ${_oraSid} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Create TNS names entries for both TNS services in the "tnsnames.ora"
# configuration file on the first VM...
#--------------------------------------------------------------------------------
echo "`date` - INFO: configure TNSNAMES on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}=(DESCRIPTION=(FAILOVER=ON)(LOAD_BALANCE=OFF)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort}))(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=PRIMARY)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid} in tnsnames.ora on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_${_vmNbr1}=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_${_vmNbr1})(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_${_vmNbr1} in tnsnames.ora on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_${_vmNbr2}=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_${_vmNbr2})(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_${_vmNbr2} in tnsnames.ora on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_dgmgrl in tnsnames.ora on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_stdby_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_stdby_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_stdby_dgmgrl in tnsnames.ora on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Create TNS names entries for both TNS services in the "tnsnames.ora"
# configuration file on the second VM...
#--------------------------------------------------------------------------------
echo "`date` - INFO: configure TNSNAMES on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}=(DESCRIPTION=(FAILOVER=ON)(LOAD_BALANCE=OFF)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort}))(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=PRIMARY)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid} in tnsnames.ora on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_${_vmNbr1}=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_${_vmNbr1})(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_azureProject}_${_vmNbr1} in tnsnames.ora on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_${_vmNbr2}=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_${_vmNbr2})(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_azureProject}_${_vmNbr2} in tnsnames.ora on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_dgmgrl in tnsnames.ora on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_stdby_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_stdby_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_stdby_dgmgrl in tnsnames.ora on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Configure a "tnsnames.ora" configuration file on the 3rd "observer" VM for use
# by the Oracle DataGuard DGMGRL utility...
#--------------------------------------------------------------------------------
echo "`date` - INFO: configure TNSNAMES on ${_vmName3}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}=(DESCRIPTION=(FAILOVER=ON)(LOAD_BALANCE=OFF)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort}))(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=PRIMARY)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid} in tnsnames.ora on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName1}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_dgmgrl in tnsnames.ora on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"echo \\\"${_oraSid}_stdby_dgmgrl=(DESCRIPTION=(SDU=32767)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=${_vmName2}.${_vmDomain})(PORT=${_oraLsnrPort})))(CONNECT_DATA=(SERVICE_NAME=${_oraSid}_stdby_dgmgrl)(SERVER=DEDICATED)))\\\" >> ${_oraHome}/network/admin/tnsnames.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set ${_oraSid}_stdby_dgmgrl in tnsnames.ora on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Create an AFTER STARTUP database trigger to startup a dynamic service named
# PRIMARY if the database is a PRIMARY, otherwise start a dynamic service named
# STANDBY if the database is not a PRIMARY (i.e. PHYSICAL STANDBY).  Then,
# create the dynamic services themselves...
#--------------------------------------------------------------------------------
echo "`date` - INFO: create services and startDgServices trigger..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
exec dbms_service.create_service('PRIMARY','PRIMARY')
exec dbms_service.create_service('STANDBY','STANDBY')
create or replace trigger startDgServices after startup on database
declare db_role varchar(30);
begin	select database_role into db_role from V\\\\\\\$DATABASE;
	if db_role = 'PRIMARY' then dbms_service.start_service('PRIMARY'); dbms_service.stop_service('STANDBY');
	else dbms_service.start_service('STANDBY'); dbms_service.stop_service('PRIMARY');
	end if;
END;
/
show errors
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: create services and startDgServices trigger on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to set the database into FORCE LOGGING mode, verifying
# that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set FORCE LOGGING..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE FORCE LOGGING;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: ALTER DATABASE FORCE LOGGING on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to set the database initialization parameter
# LOG_ARCHIVE_DEST_1 to use the Fast Recovery Area (FRA) as the archivelog
# destination, compatible with a configuration with DataGuard...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set LOG_ARCHIVE_DEST_1..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=${_oraSid}' SCOPE=SPFILE;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set LOG_ARCHIVE_DEST_1 on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to set the database initialization parameter
# SERVICE_NAMES to contain three values: "${ORACLE_SID}" and "${ORACLE_SID}_dgmgrl".
#
# The first value is the standard service name based on DB_NAME, which the second
# value intended solely for the use of the DataGuard Broker utility DGMGRL as a
# static service.
#--------------------------------------------------------------------------------
echo "`date` - INFO: set SERVICE_NAMES on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET SERVICE_NAMES='${_oraSid}','${_oraSid}_dgmgrl' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set SERVICE_NAMES on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and add a static LISTENER service for DGMGRL so that the
# DataGuard observer can automatically connect even when the database instance is
# down (and all dynamic services are absent), and then restart the LISTENER
# process...
#--------------------------------------------------------------------------------
echo "`date` - INFO: adding static LISTENER service on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"echo \\\"SID_LIST_LISTENER=(SID_LIST=(SID_DESC=(GLOBAL_DBNAME=${_oraSid}_dgmgrl)(ORACLE_HOME=${_oraHome})(SID_NAME=${_oraSid})))\\\" >> ${_oraHome}/network/admin/listener.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: adding static LISTENER service on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
lsnrctl reload LISTENER\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: lsnrctl reload LISTENER on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# STANDBY_FILE_MANAGEMENT to AUTO, verifying that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set STANDBY_FILE_MANAGEMENT..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT=AUTO SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set STANDBY_FILE_MANAGEMENT=AUTO on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# LOG_ARCHIVE_CONFIG to point to the database unique name when it resides in the
# standby host/server or second VM, then verify that the change has been made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set LOG_ARCHIVE_CONFIG..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=${_oraSid}_stdby' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set LOG_ARCHIVE_CONFIG=DG_CONFIG=${_oraSid}_stdby on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# down to FLASHBACK_RETENTION_TARGET to 60, verifying that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set DB_FLASHBACK_RETENTION_TARGET..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET=60 SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set DB_FLASHBACK_RETENTION_TARGET=60 on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# DG_BROKER_CONFIG_FILE1, verifying that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set DG_BROKER_CONFIG_FILE1..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET DG_BROKER_CONFIG_FILE1='${_oraDataDir}/dgbcf01.dat' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set DG_BROKER_CONFIG_FILE1 on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# DG_BROKER_CONFIG_FILE2, verifying that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set DG_BROKER_CONFIG_FILE2..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET DG_BROKER_CONFIG_FILE2='${_oraFRADir}/dgbcf02.dat' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set DG_BROKER_CONFIG_FILE2 on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database initialization parameter
# DG_BROKER_START, verifying that the change was made...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set DG_BROKER_START..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET DG_BROKER_START=TRUE SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set DG_BROKER_START on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and create four standby logfile groups on the database,
# and verify that they have been created...
#--------------------------------------------------------------------------------
echo "`date` - INFO: create STANDBY LOGFILE GROUPS..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
if [ ! -d ${_oraFRADir}/${_oraSid} ]
then
	mkdir ${_oraFRADir}/${_oraSid}
fi
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE ADD STANDBY LOGFILE GROUP 11 '${_oraFRADir}/${_oraSid}/stby-t01-g11-m1.log' SIZE ${_oraRedoSizeMB}M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 12 '${_oraFRADir}/${_oraSid}/stby-t01-g12-m1.log' SIZE ${_oraRedoSizeMB}M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 13 '${_oraFRADir}/${_oraSid}/stby-t01-g13-m1.log' SIZE ${_oraRedoSizeMB}M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 14 '${_oraFRADir}/${_oraSid}/stby-t01-g14-m1.log' SIZE ${_oraRedoSizeMB}M;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: add STANDBY LOGFILE GROUPs on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and shutdown the database then start it into MOUNT mode
# to perform two important operations: putting the database into FLASHBACK
# -enabled mode and into MAXIMUM AVAILABILITY mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: SHUTDOWN then STARTUP MOUNT..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
SHUTDOWN IMMEDIATE
whenever oserror exit failure
whenever sqlerror exit failure
STARTUP MOUNT
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: SHUTDOWN IMMEDIATE and STARTUP MOUNT on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database into MAXIMUM AVAILABILITY mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set MAXIMUM AVAILABILITY on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set MAXIMUM AVAILABILITY on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM and set the database into FLASHBACK mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: enable FLASHBACK DATABASE on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE FLASHBACK ON;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: enable FLASHBACK DATABASE on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM, copy the Oracle password file from the first VM to the
# local cloud shell, then copy the Oracle password file to the second VM, making
# sure to clean up all of the extraneous copies along the way...
#--------------------------------------------------------------------------------
echo "`date` - INFO: copy password file from ${_vmName1} to ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"rm -f /tmp/orapw${_oraSid}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: clean up temporary password files on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "rm -f /tmp/orapw${_oraSid}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: clean up temporary password files on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"cp ${_oraHome}/dbs/orapw${_oraSid} /tmp\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: copy password file to /tmp on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"chmod 777 /tmp/orapw${_oraSid}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: open up permissions on temp password file on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
scp ${_azureOwner}@${_ipAddr1}:/tmp/orapw${_oraSid} /tmp >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: copy password file from ${_vmName1} to local shell" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"rm -f /tmp/orapw${_oraSid}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: clean up temp password file on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
scp /tmp/orapw${_oraSid} ${_azureOwner}@${_ipAddr2}:/tmp >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: copy password file from local shell to ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
rm -f /tmp/orapw${_oraSid}
if (( $? != 0 )); then
	echo "`date` - FAIL: clean up local copy of password file" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "chmod 777 /tmp/orapw${_oraSid}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: open up permissions on temp password file on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"cp /tmp/orapw${_oraSid} ${_oraHome}/dbs\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: copy password file from /tmp on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"chmod 640 ${_oraHome}/dbs/orapw${_oraSid}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: lock down permissions on password file on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "rm -f /tmp/orapw${_oraSid}" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: clean up temp password file on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to restart the Oracle database instance to shut it down
# and then re-open it after being in MOUNT mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: STARTUP FORCE..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
STARTUP FORCE
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: STARTUP FORCE on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second (standby) VM to use the Oracle Database Creation Assistant
# (DBCA) utility to duplicate the primary database from the first VM to the
# second VM as a standby database...
#--------------------------------------------------------------------------------
echo "`date` - INFO: sudo su - ${_oraOsAcct} dbca -createDuplicateDB ${_oraSid} on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"\
	export ORACLE_HOME=${_oraHome}; \
	export PATH=${_oraHome}/bin:\${PATH}; \
	export TNS_ADMIN=${_oraHome}/network/admin; \
	dbca -silent -createDuplicateDB \
		-gdbName ${_oraSid} \
		-sysPassword ${_oraSysPwd} \
		-sid ${_oraSid} \
		-createAsStandby \
		-dbUniqueName ${_oraSid}_stdby \
		-primaryDBConnectionString ${_vmName1}.${_vmDomain}:${_oraLsnrPort}/${_oraSid}\"" | tee -a ${_logFile}
if (( $? != 0 )); then
	echo "`date` - FAIL: sudo su - ${_oraOsAcct} dbca -createDuplicateDB ${_oraSid} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM and add a static LISTENER service for DGMGRL so that the
# DataGuard observer can automatically connect even when the database instance is
# down (and all dynamic services are absent), and restart the listener process...
#--------------------------------------------------------------------------------
echo "`date` - INFO: adding static LISTENER service on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"sed -i 's|(SID_LIST =|(SID_LIST = (SID_DESC=(GLOBAL_DBNAME=${_oraSid}_stdby_dgmgrl)(ORACLE_HOME=${_oraHome})(SID_NAME=${_oraSid}))|' ${_oraHome}/network/admin/listener.ora\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: adding static LISTENER service on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
lsnrctl reload LISTENER\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: lsnrctl reload LISTENER on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to set the database initialization parameter
# SERVICE_NAMES to contain three values: "${ORACLE_SID}" and
# "${ORACLE_SID}_stdby_dgmgrl".
#
# The first value is the standard service name based on DB_NAME, which the second
# value intended solely for the use of the DataGuard Broker utility DGMGRL as a
# static service.
#--------------------------------------------------------------------------------
echo "`date` - INFO: set SERVICE_NAMES..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET SERVICE_NAMES='${_oraSid}_stdby','${_oraSid}_stdby_dgmgrl' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set SERVICE_NAMES on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM to set the database initialization parameter
# LOG_ARCHIVE_CONFIG to point back at the SERVICE_NAME for "$ORACLE_SID" back
# on the primary...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set LOG_ARCHIVE_CONFIG on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=${_oraSid}' SCOPE=BOTH;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set LOG_ARCHIVE_CONFIG on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM and set the database into MAXIMUM AVAILABILITY mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: set MAXIMUM AVAILABILITY on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: set MAXIMUM AVAILABILITY on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the second VM and set the database into FLASHBACK mode...
#--------------------------------------------------------------------------------
echo "`date` - INFO: enable FLASHBACK DATABASE on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
sqlplus -S / as sysdba << __EOF__
whenever oserror exit failure
whenever sqlerror exit failure
ALTER DATABASE FLASHBACK ON;
exit success
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: enable FLASHBACK DATABASE on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# On all three VMs, verify that all of the TNSNAMES entries work correctly...
#--------------------------------------------------------------------------------
echo "`date` - INFO: verify TNSNAMES entries on ${_vmName1}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_${_vmNbr1}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_${_vmNbr1} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_${_vmNbr2}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_${_vmNbr2} on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_dgmgrl on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_stdby_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_stdby_dgmgrl on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
echo "`date` - INFO: verify TNSNAMES entries on ${_vmName2}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_${_vmNbr1}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_${_vmNbr1} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_${_vmNbr2}\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_${_vmNbr2} on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_dgmgrl on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr2} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_stdby_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_stdby_dgmgrl on ${_vmName2}" | tee -a ${_logFile}
	exit 1
fi
echo "`date` - INFO: verify TNSNAMES entries on ${_vmName3}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_dgmgrl on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
tnsping ${_oraSid}_stdby_dgmgrl\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: tnsping ${_oraSid}_stdby_dgmgrl on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the first VM to use the DGMGRL utility on the primary database to
# configure and enable Oracle DataGuard and Fast-Start Failover (FSFO)...
#--------------------------------------------------------------------------------
echo "`date` - INFO: enable DataGuard and FSFO..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr1} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
dgmgrl sys/${_oraSysPwd}@${_oraSid}_dgmgrl << __EOF__
create configuration 'FSF' as primary database is ${_oraSid} connect identifier is ${_oraSid}_dgmgrl;
add database ${_oraSid}_stdby as connect identifier is ${_oraSid}_stdby_dgmgrl maintained as physical;
edit database ${_oraSid} set property LogXptMode='SYNC';
edit database ${_oraSid} set property NetTimeout=10;
edit database ${_oraSid}_stdby set property LogXptMode='SYNC';
edit database ${_oraSid}_stdby set property NetTimeout=10;
enable configuration;
host sleep 10
show configuration
enable fast_start failover;
host sleep 10
show configuration
__EOF__\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: enable DataGuard and FSFO on ${_vmName1}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the 3rd "observer" VM and start the observer process using DGMGRL...
#--------------------------------------------------------------------------------
echo "`date` - INFO: generate observer script on ${_vmName3}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"
echo \\\"#!/bin/bash\\\" > ./${_oraSid}_dgmgrl.sh
chmod 700 ./${_oraSid}_dgmgrl.sh
echo \\\"export ORACLE_SID=${_oraSid}\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"export ORACLE_HOME=${_oraHome}\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"export PATH=${_oraHome}/bin:\${PATH}\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"export TNS_ADMIN=${_oraHome}/network/admin\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"dgmgrl << __EOF__\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"connect sys/${_oraSysPwd}@${_oraSid}_dgmgrl\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"show configuration\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"show fast_start failover\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"start observer\\\" >> ./${_oraSid}_dgmgrl.sh
echo \\\"__EOF__\\\" >> ./${_oraSid}_dgmgrl.sh\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: generate observer script on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# SSH into the 3rd "observer" VM and start the observer process using DGMGRL...
#--------------------------------------------------------------------------------
echo "`date` - INFO: start observer script in background on ${_vmName3}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"nohup ./${_oraSid}_dgmgrl.sh > ./${_oraSid}_dgmgrl.out 2> ./${_oraSid}_dgmgrl.err &\"" >> ${_logFile} 2>&1
if (( $? != 0 )); then
	echo "`date` - FAIL: start observer script on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Pause for 10 seconds to let the observer process settle down...
#--------------------------------------------------------------------------------
echo "`date` - INFO: pause for 10 seconds..." | tee -a ${_logFile}
sleep 10
#
#--------------------------------------------------------------------------------
# SSH into the 3rd "observer" VM and display the status of the Data Guard
# configuration and the status of Fast-Start-Failover...
#--------------------------------------------------------------------------------
echo "`date` - INFO: show configuration and fast_start failover on ${_vmName3}..." | tee -a ${_logFile}
ssh ${_azureOwner}@${_ipAddr3} "sudo su - ${_oraOsAcct} -c \"
export ORACLE_SID=${_oraSid}
export ORACLE_HOME=${_oraHome}
export PATH=${_oraHome}/bin:\${PATH}
export TNS_ADMIN=${_oraHome}/network/admin
dgmgrl sys/${_oraSysPwd}@${_oraSid}_dgmgrl << __EOF__
show configuration
show fast_start failover
__EOF__\"" | tee -a ${_logFile}
if (( $? != 0 )); then
	echo "`date` - FAIL: show configuration and fast_start failover on ${_vmName3}" | tee -a ${_logFile}
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Completed successfully!  End of program...
#--------------------------------------------------------------------------------
echo "`date` - INFO: successful completion!" | tee -a ${_logFile}
exit 0
