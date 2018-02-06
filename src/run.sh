#!/usr/local/bin/bash

# The MIT License (MIT)
# Copyright © 2016 ZZROT LLC <docker@zzrot.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

#EXTERNAL ENVIRONMENT VARIABLES
# AWS_CLI_PROFILE
# REAPER_DO_DELETE

#ENVIRONMENT VARIABLES

# @info:        Overall script return code.
declare RETCODE=0

# @info:        File containing the mapping of regions to config rules.
declare REGION_MAP_FILE=regions.cfg

# @info: A single region from the regions map file
declare REGION

# @info: A single config rule from the regions map file
declare CFG_RULE

# @info: A single port from the regions map file
declare PORT

# @info: Whether a config rule is compliant or non-compliant
declare COMPLIANCE_STATUS

# @info: List of security groups that are not compliant with the config rule
declare NON_COMPLIANT_SGS

# FUNCTIONS

# @info:  Remove an open rule from a security group for the given port
# @args:	AWS region, security group ID, port, aws cli profile name

removeSGRuleinRange()
{
  local FROM=$1
  local TO=$2
  local TEST_PORT=$3
  local PROTOCOL=$4

  if [[ $FROM -le $TEST_PORT ]] && [[ $TO -ge $TEST_PORT ]]; then
    #delete rule as in range
    aws ec2 \
      revoke-security-group-ingress \
      ${DRY_RUN_FLAG} \
      --group-id ${SG_ID} \
      --protocol ${PROTOCOL} \
      --port ${FROM}-${TO} \
      --cidr '0.0.0.0/0' \
      --region ${REGION} \
      --profile ${CLI_PROFILE}
    STATUS=$?
    if [ ${STATUS} == 0 ]; then
      echo "Successfully removed rule in ${PROTOCOL} port range ${FROM}-${TO} from security group ${SG_ID} for port ${PORT}"
    else
      echo "*** ERROR: Rule in ${PROTOCOL} range ${FROM}-${TO} but unable to remove from security group ${SG_ID} for port ${PORT}"
    fi
  else
    echo "*** ERROR: Unable to remove rule from security group ${SG_ID} for port ${PORT}"
  fi
}


removeSGEntry()
{
  local REGION=$1
  local SG_ID=$2
  local PORT=$3
  local CLI_PROFILE=$4
  local PROTOCOL=$5
  local STATUS=0
  local DRY_RUN_FLAG='--dry-run' # Default to dry run mode

  # Should we enable dry run mode or not
  if [ -z "$REAPER_DO_DELETE" ]; then
    DRY_RUN_FLAG='--dry-run' # Default to dry run mode
  else
    DRY_RUN_FLAG='--no-dry-run'
  fi
  aws ec2 \
     revoke-security-group-ingress \
     ${DRY_RUN_FLAG} \
     --group-id ${SG_ID} \
     --protocol ${PROTOCOL} \
     --port ${PORT} \
     --cidr '0.0.0.0/0' \
     --region ${REGION} \
     --profile ${CLI_PROFILE}
  STATUS=$?

  if [ ${STATUS} == 0 ]; then
    echo "Successfully removed rule from security group ${SG_ID} for port ${PORT}"
  else
    #Check to see if in range of rule instead of single port
    #get ports and protocols
    readarray -t FROM_PORTS < <(aws ec2 describe-security-groups --profile ${CLI_PROFILE} --region ${REGION} --filters Name=ip-permission.cidr,Values='0.0.0.0/0' --group-ids ${SG_ID} --query 'SecurityGroups[*].IpPermissions[*].{FromPort:FromPort}' | grep "FromPort" | awk '{ print $2 }')
    readarray -t TO_PORTS < <(aws ec2 describe-security-groups --profile ${CLI_PROFILE} --region ${REGION} --filter Name=ip-permission.cidr,Values='0.0.0.0/0' --group-ids ${SG_ID} --query 'SecurityGroups[*].IpPermissions[*].{ToPort:ToPort}' | grep "ToPort" | awk '{ print $2 }')
    readarray -t PROTOCOLS < <(aws ec2 describe-security-groups --profile ${CLI_PROFILE} --region ${REGION} --filter Name=ip-permission.cidr,Values='0.0.0.0/0' --group-ids ${SG_ID} --query 'SecurityGroups[*].IpPermissions[*].{IpProtocol:IpProtocol}' | grep "IpProtocol" | awk '{ print $2 }')
    declare -i x=0
    #Loop through and check for range
    for FROM_PORT in "${FROM_PORTS[@]}"
    do
      #remove quotes from protocols
      TEST_PROTOCOL="${PROTOCOLS[x]%\"}"
      TEST_PROTOCOL="${PROTOCOL#\"}"
      removeSGRuleinRange ${FROM_PORT} ${TO_PORTS[x]} ${PORT} ${TEST_PROTOCOL}
      x=$((x+1))
    done
  fi
}

# @info:  Get the list of security groups that are not compliant with the config rule
# @args:	AWS region, config rule name, aws cli profile name
getNonCompliantSGs()
{
  local REGION=$1
  local CFG_RULE=$2
  local CLI_PROFILE=$3

  NON_COMPLIANT_SGS=""

  echo "Obtaining non-compliant SGs for ${CFG_RULE}"

  NON_COMPLIANT_SGS=$(aws configservice \
                      get-compliance-details-by-config-rule \
                      --config-rule-name ${CFG_RULE} \
                      --compliance-types NON_COMPLIANT \
                      --limit 100 \
                      --region ${REGION} \
                      --profile ${CLI_PROFILE} \
                      --query 'EvaluationResults[*].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId' \
                      --output text)
}

###########################
########################### MAINLINE
###########################
if [ -z "$AWS_CLI_PROFILE" ]; then
  echo "ERROR: No AWS CLI profile specified in the enviroment (AWS_CLI_PROFILE)"
  RETCODE=1
fi

if [ -z "$REAPER_DO_DELETE" ]; then
  echo "*** Running in Dry-run mode.  To enable deletes, set the environment variable REAPER_DO_DELETE"
fi

echo "Checking config rule compliance using AWS CLI profile ${AWS_CLI_PROFILE}"

if [ $RETCODE == 0 ]; then
  while read -r line; do

    # @info:	Array representing a single line from the regions map file.
    declare -A REGIONS="$line"

    REGION=${REGIONS[region]}
    CFG_RULE=${REGIONS[cfg-rule]}
    PORT=${REGIONS[port]}
    PROTOCOL=${REGIONS[protocol]}

    echo "Checking aws config for region ${REGION} rule ${CFG_RULE} port ${PORT} protocol ${PROTOCOL}"

    # Find out if we are compliant or not in 'this' region
    COMPLIANCE_STATUS=$(aws configservice \
                        describe-compliance-by-config-rule \
                        --config-rule-name ${CFG_RULE} \
                        --profile ${AWS_CLI_PROFILE} \
                        --region ${REGION} \
                        --query 'ComplianceByConfigRules[0].Compliance.ComplianceType' \
                        --output text)

    if [ "${COMPLIANCE_STATUS}" == "COMPLIANT" ]; then
      echo "Rule ${CFG_RULE} is compliant"
    elif [ -z "${COMPLIANCE_STATUS}" ]; then
      echo "*** ERROR: Unable to determine compliance status for ${CFG_RULE}"
    else
      # find the SGs not compliant
      getNonCompliantSGs ${REGION} ${CFG_RULE} ${AWS_CLI_PROFILE} ${PORT}

      # For each SG, remove the 0.0.0.0 rule for the specified port
      for SG in ${NON_COMPLIANT_SGS}
      do
        echo "Rule ${CFG_RULE} is NOT compliant in ${AWS_CLI_PROFILE} ${REGION}: SG $SG"
        removeSGEntry ${REGION} ${SG} ${PORT} ${AWS_CLI_PROFILE} ${PROTOCOL}
      done
    fi
  done < ${REGION_MAP_FILE}
fi

exit $RETCODE
