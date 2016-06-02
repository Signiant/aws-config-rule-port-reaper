# aws-ssh-config-rule-reaper
Removes wide open ports from AWS security groups based on AWS config rules.

# Purpose
Find security groups that allow SSH or RDP (or your favourite port) access from 0.0.0.0/0 and remove the ingress rules from the security group.

# Prerequisites

* AWS config rules created in each region you want to enforce security group port rules for
* Each config rule MUST only validate a single port in a security group
* The [AWS CLI configuration](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) must be present.  The AWS CLI does NOT need to be installed but it's credential file must be present on the docker host with at least one named profile.

# Configuration

The app is driven by a small configuration file that can be mounted into the docker container using a bind mount.  An example file looks like:

```BASH
( [region]=us-east-1 [cfg-rule]=restricted-ssh 22 )
( [region]=us-west-2 [cfg-rule]=restricted-ssh 22  )
( [region]=eu-west-1 [cfg-rule]=restricted-ssh 22  )
( [region]=us-east-1 [cfg-rule]=restricted-rdp 3389 )
( [region]=us-west-2 [cfg-rule]=restricted-rdp 3389 )
( [region]=eu-west-1 [cfg-rule]=restricted-rdp 3389 )
```
In this example, each region is checked for 2 config rules (restricted-ssh and restricted-rdp) which in turn check for wide open ports 22 and 3389

# Usage

By default, the tool runs in dry run mode and will NOT to deletes.  To run the tool in dry run mode use:

```bash
docker run -e "AWS_CLI_PROFILE=dev" \
           -v ~/.aws/credentials:/root/.aws/credentials:ro \
           -v /my/data-dir/config.cfg:/src/config.cfg:ro \
           signiant/aws-config-rule-port-reaper
```

To enable deletes from security groups, set the variable REAPER_DO_DELETE to any value:

```bash
docker run -e "AWS_CLI_PROFILE=dev" \
           -e "REAPER_DO_DELETE=true" \
           -v ~/.aws/credentials:/root/.aws/credentials:ro \
           -v /my/data-dir/config.cfg:/src/config.cfg:ro \
           signiant/aws-config-rule-port-reaper
```
