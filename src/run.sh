#!/usr/local/bin/bash

# This will run for a single AWS CLI profile which should be set in the environment
# using the env var AWS_CLI_PROFILE

RETCODE=0
REGION_MAP_FILE=regions.cfg

removeSGEntry()
{
  echo "Removing SG 0.0.0.0 entry"
}

getNonCompliantSGs()
{
  region=$1
  cfg_rule=$2
  cli_profile=$3

  echo "Obtaining non-compliant SGs for ${cfg_rule}"
}

if [ -z "$AWS_CLI_PROFILE" ]; then
  echo "ERROR: No AWS CLI profile specified in the enviroment"
  RETCODE=1
fi

if [ "$RETCODE" -eq 0 ]; then
  while read -r line; do
    declare -A regions="$line"

    region=${regions[region]}
    cfg_rule=${regions[cfg-rule]}

    echo "Checking aws config for region ${region} (rule ${cfg_rule})"

    # Find out if we are compliant or not in 'this' region
    compliance_status=$(aws configservice \
                        describe-compliance-by-config-rule \
                        --config-rule-name ${cfg_rule} \
                        --profile ${AWS_CLI_PROFILE} \
                        --region ${region} \
                        --query 'ComplianceByConfigRules[0].Compliance.ComplianceType' \
                        --output text)

    #echo "Config compliance status for ${cfg-rule} is ${compliance_status}"

    if [ "${compliance_status}" == "COMPLIANT" ]; then
      echo "Rule ${cfg_rule} is compliant"
    else
      echo "Rule ${cfg_rule} is NOT compliant"
      # find the SGs not compliant
      getNonCompliantSGs ${region} ${cfg_rule} ${AWS_CLI_PROFILE}
      # for each SG, remove the 0.0.0.0 rule
    fi

  done < ${REGION_MAP_FILE}

fi

exit $RETCODE
