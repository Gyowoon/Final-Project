# Shop EKS Skeleton

This repository provides a minimal template for deploying a simple shopping mall web service on AWS EKS. The focus is on infrastructure and DevOps tooling (Terraform, Jenkins, Argo CD, Prometheus/Grafana), rather than implementing full business logic. All components are containerised and ready to be pushed to Amazon ECR and deployed via Kubernetes manifests.

## Architecture Overview

* **VPC / Subnets:** Two private subnets for the EKS worker nodes and RDS/Redis, and two public subnets for the load balancer and NAT gateway.
* **EKS Cluster:** Managed node group in private subnets. Ingress traffic is routed through an AWS Application Load Balancer (via the AWS Load Balancer Controller).
* **RDS MySQL:** Stores persistent data such as user accounts and product information.
* **ElastiCache Redis:** Holds transient session data (e.g. shopping cart contents).
* **S3 Bucket:** Stores product images and other static assets.
* **Frontend:** Static HTML/CSS/JS served via Nginx. These files are based on a simple prototype and can be replaced with your own design.
* **Backend:** Minimal Flask API implementing user registration/login, product listing and point retrieval. Database models and REST endpoints are defined in `backend/app.py`.
* **CI/CD:** A Jenkins pipeline builds Docker images for the backend and frontend and pushes them to ECR. Argo CD monitors the `k8s` folder in your Git repository and deploys resources automatically.

## Getting Started

### 1. Infrastructure Provisioning

1. Install [Terraform](https://www.terraform.io/) and configure AWS credentials (e.g. via `aws configure`).
2. Generate a secure database password and export it as an environment variable:

   ```bash
   export TF_VAR_db_password="YourStrongPasswordHere"
   ```

3. Initialise and apply the Terraform configuration:

   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

   This step creates the VPC, EKS cluster, RDS instance, Redis cluster and S3 bucket. After completion, Terraform will output the RDS and Redis endpoints.

### 2. Build and Push Docker Images

1. Authenticate to your ECR registry:

   ```bash
   aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
   ```

2. Build and push the backend image:

   ```bash
   cd backend
   docker build -t <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/shop-backend:latest .
   docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/shop-backend:latest
   ```

3. Build and push the frontend image:

   ```bash
   cd ../frontend
   docker build -t <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/shop-frontend:latest .
   docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/shop-frontend:latest
   ```

You can automate these steps with the provided Jenkinsfile.

### 3. Prepare Kubernetes Secrets

Create a Kubernetes secret containing your database URI, Redis URL and JWT secret. You can use the example manifest as a template. Make sure to replace the placeholders with the actual endpoints and credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: shop-secrets
  namespace: shop
type: Opaque
stringData:
  DB_URI: "mysql+pymysql://shopuser:<DB_PASSWORD>@<RDS_ENDPOINT>:3306/shopdb"
  JWT_SECRET_KEY: "super-secret-key"
  REDIS_URL: "redis://<REDIS_ENDPOINT>:6379/0"
```

Apply it with `kubectl apply -f secret.yaml`.

### 4. Deploy to EKS

1. Ensure the AWS Load Balancer Controller, Metrics Server, Argo CD, Prometheus and Grafana are installed on your EKS cluster (see the main guide for installation commands).
2. Apply the manifests in the `k8s` directory:

   ```bash
   kubectl apply -k k8s/
   ```

3. (Optional) Create an Argo CD Application to monitor the `k8s` folder. The example application is located at `argo/shop-app.yaml`. Replace the `repoURL` with your Git repository URL.

### 5. Access the Application

Once the Ingress has been created by the AWS Load Balancer Controller, a DNS name will be assigned to your Application Load Balancer. Point your domain (e.g. `shop.example.com`) at this DNS name via Route 53. You can then access the frontend in your browser at `http://shop.example.com` and the API at `http://shop.example.com/api`.

### Notes

- This skeleton provides only the basic functionality required for a DevOps-focused demonstration. You can extend the Flask backend with authentication, order processing, payment gateways, etc.
- The frontend consists of static HTML files from a prototype; integrate them with the API by replacing local storage logic with actual `fetch()` calls to `/api`. Alternatively, you can rebuild the frontend with React or another framework.
- Make sure to protect secrets and credentials. Do not commit sensitive values to version control.