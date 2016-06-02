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
bash-4.3# cat run.sh
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

#ENVIRONMENT VARIABLES

# @info:	Overall script return code.
declare RETCODE=0

# @info:	File containing the mapping of regions to config rules.
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
removeSGEntry()
{
  local REGION=$1
  local SG_ID=$2
  local PORT=$3
  local CLI_PROFILE=$4
  local STATUS=0

  aws ec2 \
     revoke-security-group-ingress \
     --group-id ${SG_ID} \
     --protocol tcp \
     --port ${PORT} \
     --cidr '0.0.0.0/0' \
     --region ${REGION} \
     --profile ${CLI_PROFILE}
  STATUS=$?

  if [ ${STATUS} == 0 ]; then
    echo "Successfully removed rule from security group ${SG_ID} for port ${PORT}"
  else
    echo "*** ERROR: Unable to remove rule from security group ${SG_ID} for port ${PORT}"
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

if [ $RETCODE == 0 ]; then
  while read -r line; do

    # @info:	Array representing a single line from the regions map file.
    declare -A REGIONS="$line"

    REGION=${REGIONS[region]}
    CFG_RULE=${REGIONS[cfg-rule]}
    PORT=${REGIONS[port]}

    echo "Checking aws config for region ${REGION} (rule ${CFG_RULE} port ${PORT})"

    # Find out if we are compliant or not in 'this' region
    COMPLIANCE_STATUS=$(aws configservice \
                        describe-compliance-by-config-rule \
                        --config-rule-name ${CFG_RULE} \
                        --profile ${AWS_CLI_PROFILE} \
                        --region ${REGION} \
                        --query 'ComplianceByConfigRules[0].Compliance.ComplianceType' \
                        --output text)

    #echo "Config compliance status for ${cfg-rule} is ${compliance_status}"

    if [ "${COMPLIANCE_STATUS}" == "COMPLIANT" ]; then
      echo "Rule ${CFG_RULE} is compliant"
    elif [ -z "${COMPLIANCE_STATUS}" ]; then
      echo "*** ERROR: Unable to determine compliance status for ${CFG_RULE}"
    else
      echo "Rule ${CFG_RULE} is NOT compliant"
      # find the SGs not compliant
      getNonCompliantSGs ${REGION} ${CFG_RULE} ${AWS_CLI_PROFILE} ${PORT}

      # For each SG, remove the 0.0.0.0 rule for the specified port
      for SG in ${NON_COMPLIANT_SGS}
      do
        echo "SG $SG"
        removeSGEntry ${REGION} ${SG} ${PORT} ${AWS_CLI_PROFILE}
      done
    fi
  done < ${REGION_MAP_FILE}
fi

exit $RETCODE
