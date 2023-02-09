#!/bin/bash

# 警告提示符[ERROR]
export err="[\033[31mERROR\033[0m]"
export warn="[\033[33mWARN\033[0m]"
export normal="[\033[32mNORMAL\033[0m]"

# 每个节点的IP
export k8s_master_ip="10.206.73.143"
export k8s_node01_ip="10.206.73.136"
export k8s_node02_ip="10.206.73.137"
export k8s_node03_ip="10.206.73.138"

# 物理网络ip地址段
export ip_segment="10.206.73.0\/26"

# k8s自定义域名
export domain="cosmo"

# 物理机网卡名
export eth="eth0"

# 三台服务器密码统一为cosmo
export passwd="cosmo"

export master="k8s-master"
export node01="k8s-node01"
export node02="k8s-node02"
export node03="k8s-node03"

export k8s_other="k8s-node01 k8s-node02 k8s-node03"
export k8s_all="k8s-master k8s-node01 k8s-node02 k8s-node03"
export Master='k8s-master'
export Work='k8s-node01 k8s-node02 k8s-node03'
k8s_all_ip=("10.206.73.143" "10.206.73.136" "10.206.73.137" "10.206.73.138")

function ping_test() {
        a=()
        for ip in $k8s_all
                do
                        if ! ping -c 2 "$ip" >/dev/null;
                        then
                            echo -e "$err" cant connect with "${a[*]}"
                            a+=( "$ip" )
                        fi
                done
        echo "${a[*]}"
}

function get_os() {
    os=$(grep "^ID=" /etc/os-release 2>/dev/null | awk -F= '{print $2}')

    if [ "$os" = "\"centos\"" ]; then
        yum update ; yum install -y sshpass
    fi
    if [ "$os" = "ubuntu" ]; then
        apt update ; apt install -y sshpass
    fi

    echo 本机系统"$os"
}

function set_local() {

os=$(grep "^ID=" /etc/os-release 2>/dev/null | awk -F= '{print $2}')
if [ "$os" = "\"centos\"" ]; then
   yum update -y; yum install -y sshpass
fi
if [ "$os" = "ubuntu" ]; then
   apt update -y; apt install -y sshpass
fi

echo 本机系统"$os"

echo "本机写入hosts配置文件..."

cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$k8s_master_ip k8s-master
$k8s_node01_ip k8s-node01
$k8s_node02_ip k8s-node02
$k8s_node03_ip k8s-node03
EOF

#echo "本机配置ssh免密..."
#
#rm -f /root/.ssh/id_rsa
#ssh-keygen -f /root/.ssh/id_rsa -P ''
#export SSHPASS=$passwd
#for HOST in $k8s_all;do
#     sshpass -e ssh-copy-id -o StrictHostKeyChecking=no "$HOST"
#done
}

function init_os() {

for HOST in $k8s_all;do
{

#echo "配置主机 $HOST yum源"

#ssh root@"$HOST" "sed -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://mirror.centos.org/\$contentdir|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos|g' -i.bak /etc/yum.repos.d/CentOS-*.repo"

echo -e "$normal""安装$HOST 基础环境"

ssh root@"$HOST" "yum update -y ; yum -y install wget jq psmisc vim net-tools nfs-utils telnet yum-utils device-mapper-persistent-data lvm2 git network-scripts tar curl chrony -y"
ssh root@"$HOST" "yum install epel* -y"
ssh root@"$HOST" "sed -e 's!^metalink=!#metalink=!g' -e 's!^#baseurl=!baseurl=!g' -e 's!//download\.fedoraproject\.org/pub!//mirrors.tuna.tsinghua.edu.cn!g' -e 's!//download\.example/pub!//mirrors.tuna.tsinghua.edu.cn!g' -e 's!http://mirrors!https://mirrors!g' -i /etc/yum.repos.d/epel*.repo"

wait
}   >> ./log/"$HOST".txt &
done
wait


for HOST in $k8s_all;do
{

echo -e "$normal""配置 $HOST 主机名"

# shellcheck disable=SC2029
ssh root@"$HOST" "hostnamectl set-hostname  $HOST"

echo -e "$normal""在主机 $HOST 配置hosts配置..."

ssh root@"$HOST" "cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

$k8s_master_ip k8s-master
$k8s_node01_ip k8s-node01
$k8s_node02_ip k8s-node02
$k8s_node03_ip k8s-node03
EOF"

echo -e "$normal""关闭$HOST 防火墙"

ssh root@"$HOST" "systemctl disable --now firewalld"

echo -e "$normal""关闭$HOST selinux"

ssh root@"$HOST" "setenforce 0"
ssh root@"$HOST" "sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config"

echo -e "$normal""关闭$HOST swap分区"
ssh root@"$HOST" "sed -ri 's/.*swap.*/#&/' /etc/fstab"
ssh root@"$HOST" "swapoff -a && sysctl -w vm.swappiness=0"

echo -e "$normal""在$HOST 修改fastab"
ssh root@"$HOST" "cat /etc/fstab"

echo -e "$normal""关闭$HOST NetworkManager"
ssh root@"$HOST" "systemctl disable --now NetworkManager"

echo -e "$normal""开启$HOST network"
ssh root@"$HOST" "systemctl start network && systemctl enable network"


echo -e "$normal""修改$HOST limits"
ssh root@"$HOST" "cat >> /etc/security/limits.conf <<EOF
* soft nofile 655360
* hard nofile 131072
* soft nproc 655350
* hard nproc 655350
* seft memlock unlimited
* hard memlock unlimitedd
EOF
ulimit -SHn 65535
"

echo -e "$normal""升级$HOST 内核"

os_version=$(ssh root@"$HOST" "cat /etc/os-release 2>/dev/null | grep VERSION_ID= | awk -F= '{print \$2}'")

if [ "$os_version" = "\"7\"" ]; then
      ssh root@"$HOST" "yum install https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm -y ; sed -i \"s@mirrorlist@#mirrorlist@g\" /etc/yum.repos.d/elrepo.repo ; sed -i \"s@elrepo.org/linux@mirrors.tuna.tsinghua.edu.cn/elrepo@g\" /etc/yum.repos.d/elrepo.repo ; yum  --disablerepo=\"*\"  --enablerepo=\"elrepo-kernel\"  list  available -y ; yum  --enablerepo=elrepo-kernel  install  kernel-ml -y ; grubby --set-default \$(ls /boot/vmlinuz-* | grep elrepo) ; grubby --default-kernel"
fi
if [ "$os_version" = "\"8\"" ]; then
      ssh root@"$HOST" "yum install https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm -y ; sed -i \"s@mirrorlist@#mirrorlist@g\" /etc/yum.repos.d/elrepo.repo ; sed -i \"s@elrepo.org/linux@mirrors.tuna.tsinghua.edu.cn/elrepo@g\" /etc/yum.repos.d/elrepo.repo ; yum  --disablerepo=\"*\"  --enablerepo=\"elrepo-kernel\"  list  available -y ; yum  --enablerepo=elrepo-kernel  install  kernel-ml -y ; grubby --default-kernel"
fi

echo -e "$normal""安装$HOST ipvs模块"

ssh root@"$HOST" "yum install ipvsadm ipset sysstat conntrack libseccomp -y"
ssh root@"$HOST" "cat >> /etc/modules-load.d/ipvs.conf <<EOF
cat
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF
systemctl restart systemd-modules-load.service"

ssh root@"$HOST" "lsmod | grep -e ip_vs -e nf_conntrack"

echo -e "$normal""配置$HOST 内核参数"

ssh root@"$HOST" "cat > /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF"

ssh root@"$HOST" "sysctl --system"

}  >> ./log/"$HOST".txt &
done
wait

for HOST in $k8s_other;do
    echo -e "$normal""重启$HOST"
    ssh root@"$HOST"  "reboot"
done

while true; do
    sleep 10
    ping_res=$(ping_test)
    if [ -z "$ping_res" ]
    then
            echo -e "$normal""服务器重启完成"
            break
    else
            echo -e "$normal""未启动服务器：$ping_res ，等待20秒..."
    fi
    sleep 20
done
}

function init_containerd() {

for HOST in $k8s_all;do
  {
    echo -e "$normal""配置主机$HOST Containerd"
    ssh root@"$HOST" 'cat >/etc/containerd/config.toml<<EOF
root = "/var/lib/containerd"
state = "/run/containerd"
oom_score = -999

[grpc]
  address = "/run/containerd/containerd.sock"
  uid = 0
  gid = 0
  max_recv_message_size = 16777216
  max_send_message_size = 16777216

[debug]
  address = ""
  uid = 0
  gid = 0
  level = ""

[metrics]
  address = ""
  grpc_histogram = false

[cgroup]
  path = ""

[plugins]
  [plugins.cgroups]
    no_prometheus = false
  [plugins.cri]
    stream_server_address = "127.0.0.1"
    stream_server_port = "0"
    enable_selinux = false
    sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.6"
    stats_collect_period = 10
    systemd_cgroup = true
    enable_tls_streaming = false
    max_container_log_line_size = 16384
    [plugins.cri.containerd]
      snapshotter = "overlayfs"
      no_pivot = false
      [plugins.cri.containerd.default_runtime]
        runtime_type = "io.containerd.runtime.v1.linux"
        runtime_engine = ""
        runtime_root = ""
      [plugins.cri.containerd.untrusted_workload_runtime]
        runtime_type = ""
        runtime_engine = ""
        runtime_root = ""
    [plugins.cri.cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
      conf_template = "/etc/cni/net.d/10-default.conf"
    [plugins.cri.registry]
      [plugins.cri.registry.mirrors]
        [plugins.cri.registry.mirrors."docker.io"]
          endpoint = [
            "https://docker.mirrors.ustc.edu.cn",
            "http://hub-mirror.c.163.com"
          ]
        [plugins.cri.registry.mirrors."gcr.io"]
          endpoint = [
            "https://gcr.mirrors.ustc.edu.cn"
          ]
        [plugins.cri.registry.mirrors."k8s.gcr.io"]
          endpoint = [
            "https://gcr.mirrors.ustc.edu.cn/google-containers/"
          ]
        [plugins.cri.registry.mirrors."quay.io"]
          endpoint = [
            "https://quay.mirrors.ustc.edu.cn"
          ]
        [plugins.cri.registry.mirrors."harbor.kubemsb.com"]
          endpoint = [
            "http://harbor.kubemsb.com"
          ]
    [plugins.cri.x509_key_pair_streaming]
      tls_cert_file = ""
      tls_key_file = ""
  [plugins.diff-service]
    default = ["walking"]
  [plugins.linux]
    shim = "containerd-shim"
    runtime = "runc"
    runtime_root = ""
    no_shim = false
    shim_debug = false
  [plugins.opt]
    path = "/opt/containerd"
  [plugins.restart]
    interval = "10s"
  [plugins.scheduler]
    pause_threshold = 0.02
    deletion_threshold = 0
    mutation_threshold = 100
    schedule_delay = "0s"
    startup_delay = "100ms"
EOF'

    echo -e "$normal""启动主机$HOST Containerd"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl start containerd"
    ssh root@"$HOST" "systemctl enable containerd"
  } >> ./log/"$HOST".txt &
done
wait

}

function init_local(){

echo -e "$normal""配置证书工具cfssl"
\cp ./package/cfssl_linux-amd64 /usr/local/bin/cfssl
\cp ./package/cfssljson_linux-amd64 /usr/local/bin/cfssljson
\cp ./package/cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
chmod +x /usr/local/bin/cfssl*

echo -e "$normal""解压package程序包"
tar -xf ./package/kubernetes-server-linux-amd64.tar.gz  --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}
tar -xf ./package/etcd-v3.5.2-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-v3.5.2-linux-amd64/etcd{,ctl}
tar -xf ./package/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -C /
\cp ./package/runc.amd64 /usr/local/sbin/runc
chmod +x /usr/local/sbin/runc

echo -e "$normal""将所需组件发送到各k8s节点"
#for NODE in $Master; do echo "$NODE"; scp /usr/local/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy} "$NODE":/usr/local/bin/; scp /usr/local/bin/etcd* $NODE:/usr/local/bin/; done
for NODE in $Work; do
  scp /usr/local/bin/kubelet "$NODE":/usr/local/bin/;
  scp /usr/local/bin/kube-proxy "$NODE":/usr/local/bin/;
  scp ./package/cri-containerd-cni-1.6.1-linux-amd64.tar.gz "$NODE":~;
  sleep 1
done
wait

for NODE in $Work; do
  ssh root@"$NODE" "tar -xf ~/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -C /";
  scp /usr/local/sbin/runc "$NODE":/usr/local/sbin/runc
  ssh root@"$NODE" "chmod +x /usr/local/sbin/runc"
done

echo -e "$normal""创建ca证书"
cat > ca-csr.json << EOF
{
  "CN": "kubernetes",
  "key": {
      "algo": "rsa",
      "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "kubemsb",
      "OU": "CN"
    }
  ],
  "ca": {
          "expiry": "87600h"
  }
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
#cfssl print-defaults config > ca-config.json
cat > ca-config.json << EOF
{
  "signing": {
      "default": {
          "expiry": "87600h"
        },
      "profiles": {
          "kubernetes": {
              "usages": [
                  "signing",
                  "key encipherment",
                  "server auth",
                  "client auth"
              ],
              "expiry": "87600h"
          }
      }
  }
}
EOF
\cp ca* /etc/kubernetes/pki/
wait

}

function init_etcd(){
echo -e "$normal""生成etcd证书"
cat > etcd-csr.json << EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "$k8s_master_ip"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
    "C": "CN",
    "ST": "Beijing",
    "L": "Beijing",
    "O": "kubemsb",
    "OU": "CN"
  }]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson  -bare etcd
\cp ca*.pem /etc/etcd/ssl
mv -f etcd*.pem /etc/etcd/ssl

#echo "分发etcd证书"
#for NODE in $Master; do
#    for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
#    scp /etc/etcd/ssl/${FILE} "$NODE":/etc/etcd/ssl/${FILE}
#    done
#done

echo -e "$normal""配置主机$HOST etcd"
cat >  /etc/etcd/etcd.conf << EOF
#[Member]
ETCD_NAME='etcd1'
ETCD_DATA_DIR='/var/lib/etcd/default.etcd'
ETCD_LISTEN_PEER_URLS='https://$k8s_master_ip:2380'
ETCD_LISTEN_CLIENT_URLS='https://$k8s_master_ip:2379,http://127.0.0.1:2379'

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS='https://$k8s_master_ip:2380'
ETCD_ADVERTISE_CLIENT_URLS='https://$k8s_master_ip:2379'
ETCD_INITIAL_CLUSTER='etcd1=https://$k8s_master_ip:2380'
ETCD_INITIAL_CLUSTER_TOKEN='etcd-cluster'
ETCD_INITIAL_CLUSTER_STATE='new'
EOF


echo "配置主机$master etcd service文件"
cat > /etc/systemd/system/etcd.service << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/etcd/etcd.conf
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/local/bin/etcd \
  --cert-file=/etc/etcd/ssl/etcd.pem \
  --key-file=/etc/etcd/ssl/etcd-key.pem \
  --trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \
  --peer-trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "测试$master etcd"
mkdir -p /etc/kubernetes/pki/etcd;
ln -s /etc/etcd/ssl/* /etc/kubernetes/pki/etcd/;
systemctl daemon-reload;
systemctl enable etcd;
systemctl start etcd
}

function init_k8s_master() {
# ----kube-apiserver----
echo -e "$normal""配置主机$master api-server证书及token文件"
cat > kube-apiserver-csr.json << EOF
{
"CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "$k8s_master_ip",
    "$k8s_node01_ip",
    "$k8s_node02_ip",
    "$k8s_node03_ip",
    "10.96.0.1",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "kubemsb",
      "OU": "CN"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare /etc/kubernetes/pki/kube-apiserver
cat > /etc/kubernetes/token.csv << EOF
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

echo -e "$normal""配置主机$master api-server配置文件"
cat > /etc/kubernetes/kube-apiserver.conf << EOF
KUBE_APISERVER_OPTS=--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --anonymous-auth=false \
  --bind-address=$k8s_master_ip \
  --secure-port=6443 \
  --advertise-address=$k8s_master_ip \
  --insecure-port=0 \
  --authorization-mode=Node,RBAC \
  --runtime-config=api/all=true \
  --enable-bootstrap-token-auth \
  --requestheader-allowed-names=aggregator \
  --requestheader-group-headers=X-Remote-Group \
  --requestheader-username-headers=X-Remote-User \
  --requestheader-extra-headers-prefix=X-Remote-Extra- \
  --requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \
  --service-cluster-ip-range=10.96.0.0/16 \
  --token-auth-file=/etc/kubernetes/token.csv \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.pem  \
  --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver-key.pem \
  --client-ca-file=/etc/kubernetes/pki/ca.pem \
  --kubelet-client-certificate=/etc/kubernetes/pki/kube-apiserver.pem \
  --kubelet-client-key=/etc/kubernetes/pki/kube-apiserver-key.pem \
  --service-account-key-file=/etc/kubernetes/pki/ca-key.pem \
  --service-account-signing-key-file=/etc/kubernetes/pki/ca-key.pem  \
  --service-account-issuer=api \
  --etcd-cafile=/etc/etcd/ssl/ca.pem \
  --etcd-certfile=/etc/etcd/ssl/etcd.pem \
  --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \
  --etcd-servers=https://$k8s_master_ip:2379 \
  --enable-swagger-ui=true \
  --allow-privileged=true \
  --apiserver-count=3 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/kube-apiserver-audit.log \
  --event-ttl=1h \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=4
EOF

cat > /usr/lib/systemd/system/kube-apiserver.service << "EOF"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
Wants=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/kube-apiserver.conf
ExecStart=/usr/local/bin/kube-apiserver $KUBE_APISERVER_OPTS
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo -e "$normal""配置主机$master api-server开机自启"
systemctl daemon-reload && systemctl enable --now kube-apiserver

# ----kubectl----
echo -e "$normal""配置kubectl并进行角色绑定"
cat > admin-csr.json << "EOF"
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:masters",
      "OU": "system"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare /etc/kubernetes/pki/admin

# ----kubeconfig----
kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$k8s_master_ip:6443 --kubeconfig=kube.config
kubectl config set-credentials kubernetes-admin --client-certificate=/etc/kubernetes/pki/admin.pem --client-key=/etc/kubernetes/pki/admin-key.pem --embed-certs=true --kubeconfig=kube.config
kubectl config set-context kubernetes --cluster=kubernetes --user=kubernetes-admin --kubeconfig=kube.config
kubectl config use-context kubernetes --kubeconfig=kube.config

\cp kube.config ~/.kube/config
sleep 1
kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes --kubeconfig=/root/.kube/config
export KUBECONFIG=$HOME/.kube/config

# ----kube-controller-manager----
echo -e "$normal""配置主机$master kube-controller-manager配置文件"
cat > kube-controller-manager-csr.json << EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
      "algo": "rsa",
      "size": 2048
  },
  "hosts": [
    "127.0.0.1",
    "$k8s_master_ip"
  ],
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:kube-controller-manager",
      "OU": "system"
    }
  ]
}
EOF

cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare /etc/kubernetes/pki/kube-controller-manager
kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$k8s_master_ip:6443 --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
kubectl config set-credentials system:kube-controller-manager --client-certificate=/etc/kubernetes/pki/kube-controller-manager.pem --client-key=/etc/kubernetes/pki/kube-controller-manager-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
kubectl config set-context system:kube-controller-manager --cluster=kubernetes --user=system:kube-controller-manager --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
kubectl config use-context system:kube-controller-manager --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig

cat > /etc/kubernetes/kube-controller-manager.conf << "EOF"
KUBE_CONTROLLER_MANAGER_OPTS="--port=10252 \
  --secure-port=10257 \
  --bind-address=127.0.0.1 \
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
  --service-cluster-ip-range=10.96.0.0/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
  --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
  --allocate-node-cidrs=true \
  --cluster-cidr=10.244.0.0/16 \
  --experimental-cluster-signing-duration=87600h \
  --root-ca-file=/etc/kubernetes/pki/ca.pem \
  --service-account-private-key-file=/etc/kubernetes/pki/ca-key.pem \
  --leader-elect=true \
  --feature-gates=RotateKubeletServerCertificate=true \
  --controllers=*,bootstrapsigner,tokencleaner \
  --horizontal-pod-autoscaler-use-rest-clients=true \
  --horizontal-pod-autoscaler-sync-period=10s \
  --tls-cert-file=/etc/kubernetes/pki/kube-controller-manager.pem \
  --tls-private-key-file=/etc/kubernetes/pki/kube-controller-manager-key.pem \
  --use-service-account-credentials=true \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2"
EOF

cat > /usr/lib/systemd/system/kube-controller-manager.service << "EOF"
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-controller-manager.conf
ExecStart=/usr/local/bin/kube-controller-manager $KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
echo -e "$normal""配置主机$master kube-controller-manager开机自启"
systemctl daemon-reload && systemctl enable --now kube-controller-manager

# kube-scheduler
echo -e "$normal""配置主机$master kube-scheduler配置文件"
cat > kube-scheduler-csr.json << EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
      "127.0.0.1",
      "$k8s_master_ip"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "Beijing",
        "L": "Beijing",
        "O": "system:kube-scheduler",
        "OU": "system"
      }
    ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare /etc/kubernetes/pki/kube-scheduler
kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$k8s_master_ip:6443 --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
kubectl config set-credentials system:kube-scheduler --client-certificate=/etc/kubernetes/pki/kube-scheduler.pem --client-key=/etc/kubernetes/pki/kube-scheduler-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
kubectl config set-context system:kube-scheduler --cluster=kubernetes --user=system:kube-scheduler --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
kubectl config use-context system:kube-scheduler --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig

cat > /etc/kubernetes/kube-scheduler.conf << "EOF"
KUBE_SCHEDULER_OPTS="--address=127.0.0.1 \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--alsologtostderr=true \
--logtostderr=false \
--log-dir=/var/log/kubernetes \
--v=2"
EOF

cat > /usr/lib/systemd/system/kube-scheduler.service << "EOF"
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-scheduler.conf
ExecStart=/usr/local/bin/kube-scheduler $KUBE_SCHEDULER_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
echo -e "$normal""配置主机$master kube-scheduler开机自启"
systemctl daemon-reload
systemctl enable --now kube-scheduler
}

function init_k8s_other() {
#kubelet
echo -e "$normal""配置主机$master kubelet配置文件"
BOOTSTRAP_TOKEN=$(awk -F "," '{print $1}' /etc/kubernetes/token.csv)
kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$k8s_master_ip:6443 --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
kubectl config set-credentials kubelet-bootstrap --token="$BOOTSTRAP_TOKEN" --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig

kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=kubelet-bootstrap
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig

for HOST in "${k8s_all_ip[@]}";do
ssh root@"$HOST" "cat > /etc/kubernetes/kubelet.json << EOF
{
  \"kind\": \"KubeletConfiguration\",
  \"apiVersion\": \"kubelet.config.k8s.io/v1beta1\",
  \"authentication\": {
    \"x509\": {
      \"clientCAFile\": \"/etc/kubernetes/pki/ca.pem\"
    },
    \"webhook\": {
      \"enabled\": true,
      \"cacheTTL\": \"2m0s\"
    },
    \"anonymous\": {
      \"enabled\": false
    }
  },
  \"authorization\": {
    \"mode\": \"Webhook\",
    \"webhook\": {
      \"cacheAuthorizedTTL\": \"5m0s\",
      \"cacheUnauthorizedTTL\": \"30s\"
    }
  },
  \"address\": \"$HOST\",
  \"port\": 10250,
  \"readOnlyPort\": 10255,
  \"cgroupDriver\": \"systemd\",
  \"hairpinMode\": \"promiscuous-bridge\",
  \"serializeImagePulls\": false,
  \"clusterDomain\": \"cluster.local.\",
  \"clusterDNS\": [\"10.96.0.2\"]
}
EOF"
done


cat > /etc/kubernetes/kubelet.json << EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "authentication": {
    "x509": {
      "clientCAFile": "/etc/kubernetes/pki/ca.pem"
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "anonymous": {
      "enabled": false
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "address": "$k8s_master_ip",
  "port": 10250,
  "readOnlyPort": 10255,
  "cgroupDriver": "systemd",
  "hairpinMode": "promiscuous-bridge",
  "serializeImagePulls": false,
  "clusterDomain": "cluster.local.",
  "clusterDNS": ["10.96.0.2"]
}
EOF

cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \
  --bootstrap-kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig \
  --cert-dir=/etc/kubernetes/pki \
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
  --config=/etc/kubernetes/kubelet.json \
  --cni-bin-dir=/opt/cni/bin \
  --cni-conf-dir=/etc/cni/net.d \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --network-plugin=cni \
  --rotate-certificates \
  --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.2 \
  --root-dir=/etc/cni/net.d \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable --now kubelet

for HOST in $k8s_other;do
    scp /etc/kubernetes/kubelet-bootstrap.kubeconfig "$HOST":/etc/kubernetes/;
    #scp /etc/kubernetes/kubelet.json "$HOST":/etc/kubernetes/;
    scp /etc/kubernetes/pki/ca.pem "$HOST":/etc/kubernetes/pki;
    scp /usr/lib/systemd/system/kubelet.service "$HOST":/usr/lib/systemd/system/;
    sleep 1
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now kubelet"
done

#kubeproxy
cat > kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "kubemsb",
      "OU": "CN"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare /etc/kubernetes/pki/kube-proxy
kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$k8s_master_ip:6443 --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy --client-certificate=/etc/kubernetes/pki/kube-proxy.pem --client-key=/etc/kubernetes/pki/kube-proxy-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig

for HOST in "${k8s_all_ip[@]}";do
ssh root@"$HOST" "cat > /etc/kubernetes/kube-proxy.yaml << EOF
\"apiVersion\": \"kubeproxy.config.k8s.io/v1alpha1\"
\"bindAddress\": \"$HOST\"
\"clientConnection\":
  \"kubeconfig\": \"/etc/kubernetes/kube-proxy.kubeconfig\"
\"clusterCIDR\": \"10.244.0.0/16\"
\"healthzBindAddress\": \"$HOST:10256\"
\"kind\": \"KubeProxyConfiguration\"
\"metricsBindAddress\": \"$HOST:10249\"
\"mode\": \"ipvs\"
EOF"
done

cat >  /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \
  --config=/etc/kubernetes/kube-proxy.yaml \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now kube-proxy

for HOST in $k8s_other;do
  #scp /etc/kubernetes/kube-proxy.yaml "$HOST":/etc/kubernetes/
  scp /etc/kubernetes/kube-proxy.kubeconfig "$HOST":/etc/kubernetes/
  scp /usr/lib/systemd/system/kube-proxy.service "$HOST":/usr/lib/systemd/system/

  sleep 1
  ssh root@"$HOST" "systemctl daemon-reload"
  ssh root@"$HOST" "systemctl enable --now kube-proxy"
done
}


function menu() {
    mkdir log
    mkdir package
    clear
    echo "#####################################################################"
    echo -e "#           kubernetes一键安装脚本"
    echo -e "# 作者: draven"
    echo -e "# 网址: https://www.draven.top"
    echo -e "# 版本: 目前仅支持v1.20.4"
    #echo -e "# 说明: 无"
    echo -e "# "
    echo -e "# 该脚本示例默认四台主机，其中一台为master，三台为worker"
    echo -e "# 将其中服务器配置好静态IP，修改如下变量中的IP即可"
    echo -e "# 同时查看服务器中的网卡名，并将其修改"
    echo -e "# "
    echo -e "# 执行脚本可使用bash -x 即可显示执行中详细信息"
    echo -e "# 该脚本已适配centos7和centos8"
    echo -e "# 请预先手动准备好如下安装包"
    echo -e "# wget https://dl.k8s.io/v1.20.4/kubernetes-server-linux-amd64.tar.gz -P ./package/"
    echo -e "# wget https://github.com/containerd/containerd/releases/download/v1.6.1/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -P ./package/"
    echo -e "# wget https://github.com/opencontainers/runc/releases/download/v1.1.0/runc.amd64 -P ./package/"
    echo -e "# wget https://github.com/etcd-io/etcd/releases/download/v3.5.2/etcd-v3.5.2-linux-amd64.tar.gz -P ./package/"
    echo -e "# wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -P ./package/"
    echo -e "# wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -P ./package/"
    echo -e "# wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -P ./package/"
    echo "####################################################################"
    echo " -------------"
    echo -e "  ${GREEN}1.${PLAIN}  v1.20.4"
    echo " -------------"
    echo -e "  ${GREEN}2.${PLAIN}  v1.22.17(暂不支持)"
    echo " -------------"
    echo -e "  ${GREEN}3.${PLAIN}  v1.23.16(暂不支持)"
    echo " -------------"
    echo -e "  ${GREEN}4.${PLAIN}  v1.24.10(暂不支持)"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo

    read -rp " 请选择操作[0-4]：" draven
    case $draven in
        0)
            exit 0
            ;;
        1)
            echo -e "$normal""准备安装k8s v1.20.4"
            ;;
        2)
            echo -e "$normal""暂不支持v1.22.17！"
            exit 1
            ;;
        3)
            echo -e "$normal""暂不支持v1.23.16！"
            exit 1
            ;;
        4)
            echo -e "$normal""暂不支持v1.24.10！"
            exit 1
            ;;
        *)
            echo -e "$normal""请选择正确的操作！"
            exit 1
            ;;
    esac
    exit_flag=0
    if [ ! -f "./package/kubernetes-server-linux-amd64.tar.gz" ]; then
        echo -e "$err""当前package目录下缺少 kubernetes-server-linux-amd64.tar.gz 文件"
        exit_flag=1
    fi
    if [ ! -f "./package/cri-containerd-cni-1.6.1-linux-amd64.tar.gz" ]; then
        echo -e "$err""当前package目录下缺少 cri-containerd-cni-1.6.1-linux-amd64.tar.gz 文件"
        exit_flag=1
    fi
    if [ ! -f "./package/runc.amd64" ]; then
        echo -e "$warn""当前package目录下缺少 runc.amd64 文件"
        # exit_flag不修改
    fi
    if [ ! -f "./package/etcd-v3.5.2-linux-amd64.tar.gz" ]; then
        echo -e "$err""当前package目录下缺少 etcd-v3.5.2-linux-amd64.tar.gz 文件"
        exit_flag=1
    fi
    if [ ! -f "./package/cfssl_linux-amd64" ]; then
        echo -e "$err""当前package目录下缺少 cfssl_linux-amd64 文件"
        exit_flag=1
    fi
    if [ ! -f "./package/cfssljson_linux-amd64" ]; then
        echo -e "$err""当前package目录下缺少 cfssljson_linux-amd64 文件"
        exit_flag=1
    fi
    if [ ! -f "./package/cfssl-certinfo_linux-amd64" ]; then
        echo -e "$err""当前package目录下缺少 cfssl-certinfo_linux-amd64 文件"
        exit_flag=1
    fi
    if [[ $exit_flag == 1 ]]; then
      exit 1
    else
      echo -e "$normal""package文件检测通过"
    fi
}

function make_dir() {
  for HOST in $k8s_all;do
  {
    echo -e "$normal""创建$HOST目录"
    ssh root@"$HOST" "mkdir -p /etc/cni/net.d"
    ssh root@"$HOST" "mkdir -p /etc/containerd"
    ssh root@"$HOST" "mkdir -p /opt/cni/bin /etc/cni/net.d"
    ssh root@"$HOST" "mkdir -p /etc/kubernetes/pki /etc/kubernetes/manifests/"
    ssh root@"$HOST" "mkdir -p /etc/kubernetes/manifests/"
    ssh root@"$HOST" "mkdir -p /etc/systemd/system/kubelet.service.d /var/lib/kubelet /var/lib/kube-proxy /var/log/kubernetes"
  } >> ./log/"$HOST".txt
  done

  for HOST in $master;do
  {
    echo -e "$normal""创建$HOST目录"
    ssh root@"$HOST" "mkdir -p /etc/etcd/ssl"
    ssh root@"$HOST" "mkdir -p /var/lib/etcd/default.etcd"
  } >> ./log/"$HOST".txt
  done
  mkdir ~/.kube
}


#----环境准备----
menu
echo -e "$normal"menu finished
#set_local
echo -e "$normal"set_local finished
#init_os
echo -e "$normal"init_os finished

#----安装依赖----
make_dir
echo -e "$normal"make_dir finished
init_local
echo -e "$normal"init_local finished
init_etcd
echo -e "$normal"init_etcd finished
init_containerd
echo -e "$normal"init_containerd finished

#----安装k8s----
init_k8s_master
echo -e "$normal"init_k8s_master finished
init_k8s_other
echo -e "$normal"init_k8s_other finished
#init_k8s_pod
#echo -e "$normal"init_k8s_pod finished