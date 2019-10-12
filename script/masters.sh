#!/bin/bash -v

#_______________________Install AWS CCM_____________________________________________________
git clone https://github.com/kubernetes/cloud-provider-aws.git

wget https://dl.google.com/go/go1.13.1.linux-amd64.tar.gz
sudo tar -xvf go1.13.1.linux-amd64.tar.gz
sudo mv go /usr/local
export GOROOT=/usr/local/go
export GOPATH=/home/ubuntu/cloud-provider-aws/cmd/aws-cloud-controller-manager/
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

cd /home/ubuntu/cloud-provider-aws/cmd/aws-cloud-controller-manager/
go install
cd bin/
sudo chmod +x aws-cloud-controller-manager
sudo mv aws-cloud-controller-manager /usr/local/bin/
cd /home/ubuntu/

#_______________________INSTALL_KUBE-*_____________________________________________________

sudo mkdir -p /etc/kubernetes/config
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.15.3/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl 
sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

sudo mkdir -p /var/lib/kubernetes/

sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
  service-account-key.pem service-account.pem \
  encryption-config.yaml /var/lib/kubernetes/
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

#_______________________API_____________________________________________________
echo "[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > kube-apiserver.service
sudo mv kube-apiserver.service /etc/systemd/system/kube-apiserver.service
#_______________________kubeCM_____________________________________________________
sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

echo "[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > kube-controller-manager.service

sudo mv kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service
#_______________________CCM_____________________________________________________
sudo mv cloud-controller-manager.kubeconfig /var/lib/kubernetes/
echo "[Unit]
Description=Kubernetes Cloud Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/aws-cloud-controller-manager \\
   --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
   --authentication-kubeconfig=/var/lib/kubernetes/cloud-controller-manager.kubeconfig \\
   --authorization-kubeconfig=/var/lib/kubernetes/cloud-controller-manager.kubeconfig \\
   --requestheader-client-ca-file=/var/lib/kubernetes/ca.pem \\
   --requestheader-allowed-names=aggregator \\
   --allocate-node-cidrs=false
   --configure-cloud-routes=false
   --leader-elect=true \\
   --use-service-account-credentials=true \\
   --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > cloud-controller-manager.service

sudo mv cloud-controller-manager.service /etc/systemd/system/cloud-controller-manager.service
#_______________________Scheduler_____________________________________________________
sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/
echo "apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true" > kube-scheduler.yaml
sudo mv kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml


echo "[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" > kube-scheduler.service
sudo mv kube-scheduler.service /etc/systemd/system/kube-scheduler.service

sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager cloud-controller-manager kube-scheduler 
sudo systemctl start kube-apiserver kube-controller-manager cloud-controller-manager kube-scheduler





