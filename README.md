# Employee App

A web application for managing employee records. The backend is a Python Flask API that stores employee data in RDS PostgreSQL and profile photos in S3. The frontend is a simple HTML/JS UI served by Nginx. The app runs on EKS with secrets pulled from AWS Secrets Manager via External Secrets Operator, and is exposed through an ALB Ingress.

## Deployment Steps

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply -var-file=env/dev/terraform.tfvars
```

### 2. Get Terraform Outputs

```bash
terraform output s3_access_role_arn
terraform output app_bucket_name
terraform output secrets_manager_secret_arn
```

Or use AWS CLI:

```bash
# serviceAccount.roleArn
aws iam get-role --role-name landmark-cluster-dev-app-sa --query "Role.Arn" --output text --profile terraform

# s3.bucket
aws s3api list-buckets --query "Buckets[?starts_with(Name,'landmark-app-bucket')].Name" --output text --profile terraform

# externalSecrets.secretName
aws secretsmanager list-secrets --region us-east-1 --query "SecretList[?starts_with(Name,'landmark-cluster')].Name" --output text --profile terraform
```

Copy the values and update `helm/values.yaml`:
- `s3_access_role_arn` → `serviceAccount.roleArn`
- `app_bucket_name` → `s3.bucket`
- `secrets_manager_secret_arn` → verify `externalSecrets.secretName` matches

### 3. Build and Push Docker Images

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 075120018043.dkr.ecr.us-east-1.amazonaws.com

cd employee-app/backend
docker build -t 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-backend:latest .
docker push 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-backend:latest

cd ../frontend
docker build -t 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-frontend:latest .
docker push 075120018043.dkr.ecr.us-east-1.amazonaws.com/employee-frontend:latest
```

### 4. Connect to EKS

```bash
aws eks update-kubeconfig --name landmark-cluster-dev --region us-east-1 --profile terraform
```

### 5. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait
```

### 6. Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=landmark-cluster-dev \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw lb_controller_role_arn)
```

### 7. Deploy the App

```bash
helm install employee-app helm/ --namespace employee-app --create-namespace
```

### 8. Verify

```bash
kubectl get pods -n employee-app
kubectl get ingress -n employee-app
```

The ALB URL from the ingress ADDRESS column is your app URL.

## CI/CD

The GitHub Actions pipeline (`.github/workflows/deploy.yml`) automatically:
1. Runs tests
2. Builds and pushes images to ECR (tagged as `be-dev-YYYYMMDD-HHMMSS`)
3. Updates `helm/values.yaml` with the new tag
4. Deploys to EKS via `helm upgrade`

Triggered on push to `main` or manually via `workflow_dispatch`.

## Run Tests

```bash
cd employee-app/backend
pip install -r requirements.txt
pytest
```

## Logs

### Container logs

```bash
kubectl logs -n employee-app -l app=backend
```

### CloudWatch

Logs stream to `/landmark/employee-app` log group in CloudWatch.

```bash
aws logs tail /landmark/employee-app --follow --profile terraform
```

## Connect to the Database

### From a pod in the cluster

```bash
# Spin up a postgres client pod
kubectl run pg-client --rm -it --image=postgres:15 --namespace=employee-app -- bash

# Connect to RDS
psql -h <RDS_ENDPOINT> -U landmark_admin -d employees
```

### Get the RDS endpoint

```bash
aws rds describe-db-instances --db-instance-identifier landmark-db-dev --query "DBInstances[0].Endpoint.Address" --output text --profile terraform
```

### Get DATABASE_URL from the secret

```bash
kubectl get secret db-credentials -n employee-app -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

### Useful psql commands

```sql
SELECT * FROM employees;
SELECT department, COUNT(*) FROM employees GROUP BY department;
SELECT * FROM employees ORDER BY id DESC LIMIT 5;
```

## S3 Photos

```bash
aws s3 ls s3://landmark-app-bucket-dev/photos/ --profile terraform
```

## Destroy

```bash
helm uninstall employee-app -n employee-app
cd terraform && terraform destroy -var-file=env/dev/terraform.tfvars
```
