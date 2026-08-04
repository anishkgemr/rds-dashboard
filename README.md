# RDS Dashboard

## Introduction

The RDS Dashboard provides comprehensive visibility into Amazon RDS operational health, configuration posture, and cost optimization opportunities. This dashboard combines CID Data Collection inventory data with AWS Cost and Usage Report (CUR) data to deliver actionable insights for managing your RDS fleet across multiple accounts and regions.

The dashboard covers key operational areas including:

* **Engine Version Analysis** — Current vs. latest major/minor versions, upgrade readiness
* **End of Support Tracking** — RDS engines approaching or past end-of-support dates
* **Security & Resiliency** — Encryption status, certificate validity, Multi-AZ, backup enablement
* **Backup & Snapshot Analysis** — Daily backup status for both DB instances and Aurora clusters
* **Maintenance Windows** — Pending maintenance actions and scheduling
* **Cost Optimization** — RDS spend breakdown, extended support costs, and Aurora IO Optimized recommendations
* **Tag Compliance** — Resource tagging coverage and consistency

The dashboard is organized into 5 tabs:

1. **Inventory** — Fleet overview with instance counts, engine distribution, instance class breakdown, Graviton adoption, and dynamic group-by
2. **Version & Maintenance** — Major/minor version compliance, end-of-support status, pending maintenance actions
3. **Security & Resiliency** — Encryption, certificates, Multi-AZ, public accessibility, storage autoscaling
4. **Backup & Snapshot** — Daily backup coverage, snapshot age tracking, retention analysis
5. **Cost & Usage** — RDS spend by account/region/engine, extended support costs, Aurora IO Optimized savings recommendations

## Demo Dashboard

### Tab 1 — Inventory

![Inventory](images/RDS-Inventory-Screenshot.png)

### Tab 2 — Version & Maintenance

![Version & Maintenance](images/RDS-Version-Maintenance.png)

### Tab 3 — Security & Resiliency

![Security & Resiliency](images/RDS-Security-Resiliency.png)

### Tab 4 — Backup & Snapshot

![Backup & Snapshot](images/RDS-Backup-Snapshot.png)

### Tab 5 — Cost & Usage

![Cost & Usage](images/RDS-Cost-Usage.png)

![Aurora IO Optimized](images/RDS-Aurora-IO-Opt.png)

## Prerequisites

1. Deploy the [CID Data Collection Stack](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/data-collection.html) with the following modules enabled:
   - **Inventory module** (`IncludeInventoryCollectorModule: yes`) — collects RDS instances, clusters, and snapshots
   - **Reference module** (`IncludeReferenceModule: yes`) — provides engine version and end-of-support data
   - **RDS module** (`IncludeRDSModule: yes`) — collects pending maintenance actions
   - **Organization module** (`IncludeOrgDataModule: yes`) — provides account names

   Version 3.0.8 or higher required.

2. Deploy the [CID Foundational Dashboards](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/deployment-in-global-regions.html) stack. This will enable your CUR, Amazon Athena and QuickSight resources required for this and other dashboards.

> **Note:** The Cost tab requires CUR data (`resource_view`, `summary_view`). If CUR is not available, Tabs 1-4 still work — Tab 5 will be empty.

## Deployment

> ⚠️ **Important:** Before proceeding, ensure you have completed the [CID Data Collection Stack](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/data-collection.html) and [CID Foundational Dashboards](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/deployment-in-global-regions.html) deployment. These are required prerequisites.

### Data Collection Setup

The RDS module collects pending maintenance actions across your accounts. Until this module is merged into the official CID framework, deploy it separately:

```bash
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Deploy data collection module
aws cloudformation create-stack \
  --stack-name rds-data-collection \
  --template-body file://module-rds.yaml \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameters \
    ParameterKey=GlueRoleARN,ParameterValue=arn:aws:iam::${ACCOUNT_ID}:role/CID-DC-Glue-Crawler \
    ParameterKey=DestinationBucket,ParameterValue=cid-data-${ACCOUNT_ID} \
    ParameterKey=DestinationBucketARN,ParameterValue=arn:aws:s3:::cid-data-${ACCOUNT_ID} \
    ParameterKey=DatabaseName,ParameterValue=optimization_data \
    ParameterKey=MultiAccountRoleName,ParameterValue=CID-DC-Optimization-Data-Multi-Account-Role \
    ParameterKey=StepFunctionExecutionRoleARN,ParameterValue=arn:aws:iam::${ACCOUNT_ID}:role/CID-DC-StepFunctionExecutionRole \
    ParameterKey=SchedulerExecutionRoleARN,ParameterValue=arn:aws:iam::${ACCOUNT_ID}:role/CID-DC-SchedulerExecutionRole \
  --region ${REGION}
```

> **Note:** Once the RDS module is merged into the CID Data Collection framework, this separate deployment will no longer be needed. Simply enable `IncludeRDSModule: yes` in the CID Data Collection stack instead.

### Dashboard Deployment

#### CloudFormation

> **Prerequisite**: To install this dashboard using CloudFormation, you need to install the CID Foundational Dashboards CFN with version v4.0.0 or above as described [here](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/deployment-in-global-regions.html).

1. Log in to your **Data Collection** Account.
2. Click the Launch Stack button below to open the **pre-populated stack template** in your CloudFormation.

   [![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home#/stacks/create/review?templateURL=https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn/cid-plugin.yml&stackName=RDS-Dashboard&param_DashboardId=rds-dashboard&param_RequiresDataCollection=yes&param_ResourcesUrl=https://raw.githubusercontent.com/anishkgemr/rds-dashboard/main/dashboards/rds-dashboard.yaml)

3. You can change **Stack name** for your template if you wish.
4. Leave **Parameters** values as-is.
5. Review the configuration and click **Create stack**.
6. You will see the stack will start in **CREATE\_IN\_PROGRESS**. Once complete, the stack will show **CREATE\_COMPLETE**.
7. You can check the stack output for dashboard URLs.

> **Troubleshooting:** If you see error "No export named cid-CidExecArn found" during stack deployment, make sure you have completed prerequisite steps.

#### Command Line

Alternative method to install dashboards is the [cid-cmd](https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-framework/blob/main/CID-CMD.md#command-line-tool-cid-cmd) tool.

1. Log in to your **Data Collection** Account.
2. Open up a command-line interface with permissions to run API requests in your AWS account. We recommend to use [CloudShell](https://console.aws.amazon.com/cloudshell).
3. In your command-line interface run the following command to download and install the CID CLI tool:

   ```bash
   pip3 install --upgrade cid-cmd
   ```

4. In your command-line interface run the following command to deploy the dashboard:

   ```bash
   cid-cmd deploy --dashboard-id rds-dashboard \
     --resources https://raw.githubusercontent.com/anishkgemr/rds-dashboard/main/dashboards/rds-dashboard.yaml
   ```

   Please follow the instructions from the deployment wizard. More info about command line options are in the [Readme](https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-framework/blob/main/CID-CMD.md#command-line-tool-cid-cmd) or `cid-cmd --help`.

### Post-Deployment: Update CID Inventory Schedules

The CID Inventory module collects RDS data every 14 days by default. This dashboard benefits from daily data. Update the schedules:

```bash
REGION="us-east-1"

for SCHED in CID-DC-inventory-RdsDbInstances-RefreshSchedule \
             CID-DC-inventory-RdsDbClusters-RefreshSchedule \
             CID-DC-inventory-RdsDbSnapshots-RefreshSchedule; do

  TARGET=$(aws scheduler get-schedule --name ${SCHED} --region ${REGION} --query 'Target' --output json)

  aws scheduler update-schedule \
    --name ${SCHED} \
    --schedule-expression "rate(1 day)" \
    --flexible-time-window '{"Mode":"FLEXIBLE","MaximumWindowInMinutes":30}' \
    --target "${TARGET}" \
    --region ${REGION} \
  && echo "Updated: ${SCHED}" || echo "Failed: ${SCHED}"
done
```

> **Note:** If the CID Data Collection stack is redeployed later, these schedules may reset to 14 days. Re-run the commands above if that happens.

### Trigger Initial Data Collection

The dashboard will be empty until data is collected. Trigger the Step Functions:

```bash
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Trigger inventory collection
for SM in CID-DC-inventory-RdsDbInstances-StateMachine \
          CID-DC-inventory-RdsDbClusters-StateMachine \
          CID-DC-inventory-RdsDbSnapshots-StateMachine \
          CID-DC-rds-maintenance-StateMachine; do
  aws stepfunctions start-execution \
    --state-machine-arn arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${SM} \
    --region ${REGION} \
  && echo "Started: ${SM}" || echo "Failed: ${SM}"
done
```

Wait ~5 minutes for all executions to complete, then refresh the QuickSight SPICE datasets in the QuickSight console or wait for the next scheduled refresh.

## Update

Please note that currently dashboards can be initially deployed via CloudFormation but they cannot be updated through CloudFormation Stack updates. When new version of the dashboard template is released, you can update your dashboard by running the following command in your command-line interface:

```bash
cid-cmd update --dashboard-id rds-dashboard \
  --resources https://raw.githubusercontent.com/anishkgemr/rds-dashboard/main/dashboards/rds-dashboard.yaml
```

## Dashboard Customization

1. Create your own visuals from this dashboard. Follow the CID [guide](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/create-analysis.html) to get started.
2. To integrate CID with AWS Organizations for enhanced visibility across multiple accounts and organizational units follow the [documentation to add taxonomy details](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/add-org-taxonomy.html).

## Performance & Scale Testing

Tested with **110 RDS instances** across 3 AWS accounts and 5 regions (us-east-1, us-west-2, eu-west-1, ap-southeast-1, ca-central-1) with mixed engines: MySQL, PostgreSQL, MariaDB, SQL Server, Aurora MySQL, Aurora PostgreSQL (provisioned + Serverless v2).

### Measured Performance (110 instances)

| Component | Duration |
|-----------|----------|
| Maintenance Lambda | 17–19s |
| Crawlers | 44–87s |
| SPICE Refresh (per dataset) | 45–68s |
| **Total pipeline (end-to-end)** | **< 3 minutes** |

### Projected Scale

| Scenario | Instances | Accounts × Regions | Estimated Pipeline Time |
|----------|-----------|-------------------|------------------------|
| Small org | 110 | 3 × 5 | < 3 min |
| Mid-size enterprise | 1,000 | 50 × 10 | ~5–7 min |
| Large enterprise | 5,000 | 200 × 15 | ~12–15 min |

All components remain well within AWS service limits (Lambda 900s timeout, SPICE 250M row cap). The Maintenance Lambda is the primary scaling factor as it makes one API call per account×region combination.

## Authors & Contributors

* Anish Kumar Gopal — Initial development

## Feedback & Support

Follow [Feedback & Support](https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/feedback.html) guide.

> **Note:** These dashboards and their content: (a) are for informational purposes only, (b) represent current AWS product offerings and practices, which are subject to change without notice, and (c) does not create any commitments or assurances from AWS and its affiliates, suppliers or licensors. AWS content, products or services are provided "as is" without warranties, representations, or conditions of any kind, whether express or implied. The responsibilities and liabilities of AWS to its customers are controlled by AWS agreements, and this document is not part of, nor does it modify, any agreement between AWS and its customers.
