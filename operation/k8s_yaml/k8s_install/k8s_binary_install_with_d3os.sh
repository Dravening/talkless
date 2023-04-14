#!/bin/bash

# 服务器密码统一为cosmo
passwd="cosmo"
# 默认内网网卡
nic="eth0"

# IP 注意k8s_master_ips的第一个ip一定要是脚本当前运行所在机器的ip
k8s_master_ips=("10.206.73.143")
k8s_master_names=("k8s-master")

k8s_node_ips=("10.206.73.136" "10.206.73.137" "10.206.73.138")
k8s_node_names=("k8s-node01" "k8s-node02" "k8s-node03")

# =====================================================================================================================
# 自动计算总共资源
k8s_all_ips=("${k8s_master_ips[@]}" "${k8s_node_ips[@]}")
k8s_all_names=("${k8s_master_names[@]}" "${k8s_node_names[@]}")
node_num_count=${#k8s_all_names[@]}
k8s_other_names=("${k8s_all_names[@]}")
unset 'k8s_other_names[0]'
k8s_master_ip="${k8s_master_ips[0]}"
current_node_name="${k8s_master_names[0]}"

# 警告提示符[ERROR]
err="[\033[31mERROR\033[0m]"
warn="[\033[33mWARN\033[0m]"
wait="[\033[33mWAITING\033[0m]"
normal="[\033[32mNORMAL\033[0m]"
star="\033[32m(^_^)\033[0m"

function ping_test() {
  a=()
  for ip in "${k8s_all_names[@]}"; do
    if ! ping -c 2 "$ip" >/dev/null; then
      echo -e "$err" cant connect with "${a[*]}"
      a+=("$ip")
    fi
  done
  echo "${a[*]}"
}

function spin() {
  local i=0
  local sp='/-\|'
  local n=${#sp}
  printf ' '
  sleep 0.1
  while true; do
    printf '\b%s' "${sp:i++%n:1}"
    sleep 0.1
  done
}

function get_os() {
  os=$(grep "^ID=" /etc/os-release 2>/dev/null | awk -F= '{print $2}')
  if [ "$os" = "\"centos\"" ]; then
    yum update
    yum install -y sshpass
  fi
  if [ "$os" = "ubuntu" ]; then
    apt update
    apt install -y sshpass
  fi
  echo 本机系统"$os"
}

function set_local() {
  clear
  os=$(grep "^ID=" /etc/os-release 2>/dev/null | awk -F= '{print $2}')
  if [ "$os" = "\"centos\"" ]; then
    yum update -y
    yum install -y sshpass
  fi
  if [ "$os" = "ubuntu" ]; then
    apt update -y
    apt install -y sshpass
  fi
  echo 本机系统"$os"

  echo "本机写入hosts配置文件"
  for(( i=0; i<"$node_num_count"; i++ )); do
    name="${k8s_all_names[i]}"
    ip="${k8s_all_ips[i]}"
    if ! grep "$name" /etc/hosts >/dev/null; then
      echo "$name $ip" >> /etc/hosts
    else
      sed -i "/$name/d" /etc/hosts
      echo "$name $ip" >> /etc/hosts
    fi
  done

  echo "本机配置ssh免密..."
  if [ -e /root/.ssh/id_rsa ]; then
    read -rp "/root/.ssh/id_rsa已存在,是否覆盖[y/n]" ssh_flag
    case $ssh_flag in
    y)
      rm -f /root/.ssh/id_rsa
      ssh-keygen -f /root/.ssh/id_rsa -P ''
      # sshpass 会使用全局变量SSHPASS作为密码
      export SSHPASS="$passwd"
      for HOST in ${k8s_all_names[@]}; do
        sshpass -e ssh-copy-id -o StrictHostKeyChecking=no "$HOST"
      done
      ;;
    *)
      ;;
    esac
  fi
}

function init_os() {
  for HOST in ${k8s_all_names[@]}; do
    {
      #echo "配置主机 $HOST yum源"
      #ssh root@"$HOST" "sed -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://mirror.centos.org/\$contentdir|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos|g' -i.bak /etc/yum.repos.d/CentOS-*.repo"

      echo -e "$normal""安装$HOST 基础环境"
      ssh root@"$HOST" "yum update -y; yum -y install wget jq psmisc vim net-tools nfs-utils telnet yum-utils device-mapper-persistent-data lvm2 git network-scripts tar curl chrony -y"
      ssh root@"$HOST" "yum install epel* -y"
      # ssh root@"$HOST" "sed -e 's!^metalink=!#metalink=!g' -e 's!^#baseurl=!baseurl=!g' -e 's!//download\.fedoraproject\.org/pub!//mirrors.tuna.tsinghua.edu.cn!g' -e 's!//download\.example/pub!//mirrors.tuna.tsinghua.edu.cn!g' -e 's!http://mirrors!https://mirrors!g' -i /etc/yum.repos.d/epel*.repo"

      wait
    } >>./log/"$HOST".txt &
  done
  wait

  for HOST in ${k8s_other_names[@]}; do
    {
      echo -e "$normal""配置 $HOST 主机名"
      # shellcheck disable=SC2029
      ssh root@"$HOST" "hostnamectl set-hostname $HOST"

      echo -e "$normal""在主机 $HOST 配置hosts配置..."
      for(( i=0; i<"$node_num_count"; i++ )); do
        name=${k8s_all_names[i]}
        ip=${k8s_all_ips[i]}
        # shellcheck disable=SC2029
        ssh root@"$HOST" "if ! grep $name /etc/hosts >/dev/null; then
  echo $name $ip >> /etc/hosts
else
  sed -i /$name/d /etc/hosts
  echo $name $ip >> /etc/hosts
fi"
      done

      echo -e "$normal""关闭$HOST 防火墙"
      ssh root@"$HOST" "systemctl disable --now firewalld"

      echo -e "$normal""关闭$HOST selinux"
      ssh root@"$HOST" "setenforce 0"
      ssh root@"$HOST" "sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config"

      echo -e "$normal""关闭$HOST swap分区"
      ssh root@"$HOST" "sed -ri 's/.*swap.*/#&/' /etc/fstab"
      ssh root@"$HOST" "swapoff -a && sysctl -w vm.swappiness=0"

      echo -e "$normal""关闭$HOST NetworkManager"
      ssh root@"$HOST" "systemctl disable --now NetworkManager"

      echo -e "$normal""开启$HOST network"
      ssh root@"$HOST" "systemctl start network && systemctl enable network"

      echo -e "$normal""修改$HOST limits"
      ssh root@"$HOST" "cat >> /etc/security/limits.conf <<EOF
* soft nofile 655360
* hard nofile 131072
* soft nproc 65535
* hard nproc 655350
* seft memlock unlimited
* hard memlock unlimited
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
    } >>./log/"$HOST".txt &
  done
  wait

  for HOST in ${k8s_other_names[@]}; do
    echo -e "$normal""重启$HOST"
    ssh root@"$HOST" "reboot"
  done

  while true; do
    sleep 10
    ping_res=$(ping_test)
    if [ -z "$ping_res" ]; then
      echo -e "$normal""服务器重启完成"
      break
    else
      echo -e "$normal""未启动服务器：$ping_res ，等待20秒..."
    fi
    sleep 20
  done

  read -rp "主节点即将重启[y/n]" restart_flag
  case $restart_flag in
  y)
    reboot
    ;;
  *)
    echo -e "$normal""主节点未重启"
    ;;
  esac
}

function init_containerd() {
  for HOST in ${k8s_all_names[@]}; do
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
    } >>./log/"$HOST".txt &
  done
  wait
}

function init_local() {
  echo -e "$normal""配置证书工具cfssl"
  \cp ./package/cfssl_linux-amd64 /usr/local/bin/cfssl
  \cp ./package/cfssljson_linux-amd64 /usr/local/bin/cfssljson
  \cp ./package/cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
  chmod +x /usr/local/bin/cfssl*

  echo -e "$normal""解压package程序包"
  tar -xf ./package/kubernetes-server-linux-amd64.tar.gz --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}
  tar -xf ./package/etcd-v3.5.2-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-v3.5.2-linux-amd64/etcd{,ctl}
  tar -xf ./package/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -C /
  \cp ./package/runc.amd64 /usr/local/sbin/runc
  chmod +x /usr/local/sbin/runc

  echo -e "$normal""将所需组件发送到各k8s节点"
  #for NODE in "${k8s_all_names[@]}"; do echo "$NODE"; scp /usr/local/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy} "$NODE":/usr/local/bin/; scp /usr/local/bin/etcd* $NODE:/usr/local/bin/; done
  for NODE in ${k8s_node_names[@]}; do
    scp /usr/local/bin/kubelet "$NODE":/usr/local/bin/
    scp /usr/local/bin/kube-proxy "$NODE":/usr/local/bin/
    scp ./package/cri-containerd-cni-1.6.1-linux-amd64.tar.gz "$NODE":~
    sleep 1
  done
  wait

  for NODE in ${k8s_node_names[@]}; do
    ssh root@"$NODE" "tar -xf ~/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -C /"
    scp /usr/local/sbin/runc "$NODE":/usr/local/sbin/runc
    ssh root@"$NODE" "chmod +x /usr/local/sbin/runc"
  done

  echo -e "$normal""创建ca证书"
  cat >ca-csr.json <<EOF
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
  cat >ca-config.json <<EOF
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

function init_etcd() {
  echo -e "$normal""生成etcd证书"
  cat >etcd-csr.json <<EOF
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
  cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
  \cp ca*.pem /etc/etcd/ssl
  mv -f etcd*.pem /etc/etcd/ssl

  #echo "分发etcd证书"
  #for NODE in "${k8s_all_names[@]}"; do
  #    for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
  #    scp /etc/etcd/ssl/${FILE} "$NODE":/etc/etcd/ssl/${FILE}
  #    done
  #done

  echo -e "$normal""配置主机$HOST etcd"
  cat >/etc/etcd/etcd.conf <<EOF
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

  echo "配置主机$current_node_name etcd service文件"
  cat >/etc/systemd/system/etcd.service <<EOF
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

  echo "测试$current_node_name etcd"
  mkdir -p /etc/kubernetes/pki/etcd
  ln -s /etc/etcd/ssl/* /etc/kubernetes/pki/etcd/
  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd

  cat >>~/.bashrc << EOF
export ETCDCTL_API=3
alias etcdctl='etcdctl --endpoints=https://[$k8s_master_ip]:2379 --cacert=/etc/kubernetes/pki/etcd/ca.pem --cert=/etc/kubernetes/pki/etcd/etcd.pem --key=/etc/kubernetes/pki/etcd/etcd-key.pem'
EOF

  # shellcheck source=/root/.bashrc
  source ~/.bashrc
}

function init_k8s_master() {
  # ----kube-apiserver----
  echo -e "$normal""配置主机$current_node_name api-server证书及token文件"
  cat >kube-apiserver-csr.json <<EOF
{
"CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
EOF
  for ip in "${k8s_all_ips[@]}"; do
    echo "    \"$ip\"," >> kube-apiserver-csr.json
  done

  echo '    "10.96.0.1",
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
}' >> kube-apiserver-csr.json

  cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=/etc/kubernetes/pki/ca-config.json -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare /etc/kubernetes/pki/kube-apiserver
  cat >/etc/kubernetes/token.csv <<EOF
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

  echo -e "$normal""配置主机$current_node_name api-server配置文件"
  cat >/etc/kubernetes/kube-apiserver.conf <<EOF
KUBE_APISERVER_OPTS=--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
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

  cat >/usr/lib/systemd/system/kube-apiserver.service <<"EOF"
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
  echo -e "$normal""配置主机$current_node_name api-server开机自启"
  systemctl daemon-reload && systemctl enable --now kube-apiserver

  # ----kubectl----
  echo -e "$normal""配置kubectl并进行角色绑定"
  cat >admin-csr.json <<"EOF"
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
  kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://"$k8s_master_ip":6443 --kubeconfig=kube.config
  kubectl config set-credentials kubernetes-admin --client-certificate=/etc/kubernetes/pki/admin.pem --client-key=/etc/kubernetes/pki/admin-key.pem --embed-certs=true --kubeconfig=kube.config
  kubectl config set-context kubernetes --cluster=kubernetes --user=kubernetes-admin --kubeconfig=kube.config
  kubectl config use-context kubernetes --kubeconfig=kube.config

  \cp kube.config ~/.kube/config
  sleep 1
  kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes --kubeconfig=/root/.kube/config
  export KUBECONFIG=$HOME/.kube/config

  # ----kube-controller-manager----
  echo -e "$normal""配置主机$current_node_name kube-controller-manager配置文件"
  cat >kube-controller-manager-csr.json <<EOF
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
  kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://"$k8s_master_ip":6443 --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
  kubectl config set-credentials system:kube-controller-manager --client-certificate=/etc/kubernetes/pki/kube-controller-manager.pem --client-key=/etc/kubernetes/pki/kube-controller-manager-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
  kubectl config set-context system:kube-controller-manager --cluster=kubernetes --user=system:kube-controller-manager --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig
  kubectl config use-context system:kube-controller-manager --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig

  cat >/etc/kubernetes/kube-controller-manager.conf <<"EOF"
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

  cat >/usr/lib/systemd/system/kube-controller-manager.service <<"EOF"
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
  echo -e "$normal""配置主机$current_node_name kube-controller-manager开机自启"
  systemctl daemon-reload && systemctl enable --now kube-controller-manager

  # kube-scheduler
  echo -e "$normal""配置主机$current_node_name kube-scheduler配置文件"
  cat >kube-scheduler-csr.json <<EOF
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
  kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://"$k8s_master_ip":6443 --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
  kubectl config set-credentials system:kube-scheduler --client-certificate=/etc/kubernetes/pki/kube-scheduler.pem --client-key=/etc/kubernetes/pki/kube-scheduler-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
  kubectl config set-context system:kube-scheduler --cluster=kubernetes --user=system:kube-scheduler --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig
  kubectl config use-context system:kube-scheduler --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig

  cat >/etc/kubernetes/kube-scheduler.conf <<"EOF"
KUBE_SCHEDULER_OPTS="--address=127.0.0.1 \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--alsologtostderr=true \
--logtostderr=false \
--log-dir=/var/log/kubernetes \
--v=2"
EOF

  cat >/usr/lib/systemd/system/kube-scheduler.service <<"EOF"
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
  echo -e "$normal""配置主机$current_node_name kube-scheduler开机自启"
  systemctl daemon-reload
  systemctl enable --now kube-scheduler
}

function init_k8s_other() {
  #kubelet
  echo -e "$normal""配置主机$current_node_name kubelet配置文件"
  BOOTSTRAP_TOKEN=$(awk -F "," '{print $1}' /etc/kubernetes/token.csv)
  kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://"$k8s_master_ip":6443 --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
  kubectl config set-credentials kubelet-bootstrap --token="$BOOTSTRAP_TOKEN" --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
  kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig
  kubectl config use-context default --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig

  kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=kubelet-bootstrap
  kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap --kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig

  for HOST in "${k8s_all_ips[@]}"; do
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

  cat >/etc/kubernetes/kubelet.json <<EOF
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

  cat >/usr/lib/systemd/system/kubelet.service <<EOF
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

  for HOST in ${k8s_other_names[@]}; do
    scp /etc/kubernetes/kubelet-bootstrap.kubeconfig "$HOST":/etc/kubernetes/
    #scp /etc/kubernetes/kubelet.json "$HOST":/etc/kubernetes/;
    scp /etc/kubernetes/pki/ca.pem "$HOST":/etc/kubernetes/pki
    scp /usr/lib/systemd/system/kubelet.service "$HOST":/usr/lib/systemd/system/
    sleep 1
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now kubelet"
  done

  #kubeproxy
  cat >kube-proxy-csr.json <<EOF
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
  kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://"$k8s_master_ip":6443 --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
  kubectl config set-credentials kube-proxy --client-certificate=/etc/kubernetes/pki/kube-proxy.pem --client-key=/etc/kubernetes/pki/kube-proxy-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
  kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig
  kubectl config use-context default --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig

  for HOST in "${k8s_all_ips[@]}"; do
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

  cat >/usr/lib/systemd/system/kube-proxy.service <<EOF
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

  for HOST in ${k8s_other_names[@]}; do
    #scp /etc/kubernetes/kube-proxy.yaml "$HOST":/etc/kubernetes/
    scp /etc/kubernetes/kube-proxy.kubeconfig "$HOST":/etc/kubernetes/
    scp /usr/lib/systemd/system/kube-proxy.service "$HOST":/usr/lib/systemd/system/

    sleep 1
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now kube-proxy"
  done
}

function init_k8s_pod() {
  echo -e "$normal""please wait ..."
  sleep 5
  count=0
  while true; do
    # 这里要查询k8s组件的启动状态
    if [ "$(kubectl get nodes | grep -Ec "Ready|Not Ready")" -eq "$node_num_count" ]; then
      echo -e "$normal""k8s节点初始化完毕"
      kubectl get nodes
      break
    else
      echo -e "$wait""等待k8s节点初始化完成..."
      kubectl get nodes
      sleep 5
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((5 * count + 5))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""启动calico容器"
  sed -i "s/interface=eth0/interface=$nic/g" ./package/calico.yaml
  kubectl apply -f ./package/calico.yaml

  echo -e "$normal""正在判断calico容器状态(可能需要等待2min-12min)"
  count=0
  sleep 30
  while true; do
    # 这里要查询不是Running状态的pod, 如"ContainerCreating","Init:0/3,"PodInitializing","0/1 Running"
    if kubectl get pods -n kube-system | grep -E 'ContainerCreating|Init:|PodInitializing|0/1' &>/dev/null; then
      echo -e "$wait""等待calico容器部署完成..."
      kubectl get pods -n kube-system -o wide | grep calico
      sleep 20
    else
      echo -e "$normal""calico服务已成功启动"
      kubectl get pods -A -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 30 ]; then
      echo -e "$warn""已等待$((20 * count + 30))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""启动coreDNS容器"
  cat >./package/coredns.yaml <<"EOF"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
  - apiGroups:
    - ""
    resources:
    - endpoints
    - services
    - pods
    - namespaces
    verbs:
    - list
    - watch
  - apiGroups:
    - discovery.k8s.io
    resources:
    - endpointslices
    verbs:
    - list
    - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        kubernetes cluster.local  in-addr.arpa ip6.arpa {
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
          max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  # replicas: not specified here:
  # 1. Default is 1.
  # 2. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        kubernetes.io/os: linux
      affinity:
         podAntiAffinity:
           preferredDuringSchedulingIgnoredDuringExecution:
           - weight: 100
             podAffinityTerm:
               labelSelector:
                 matchExpressions:
                   - key: k8s-app
                     operator: In
                     values: ["kube-dns"]
               topologyKey: kubernetes.io/hostname
      containers:
      - name: coredns
        image: coredns/coredns:1.8.4
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.2
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF

  kubectl apply -f ./package/coredns.yaml
  echo -e "$normal""正在判断coreDNS容器状态"
  echo -e "$normal""根据网络情况不同，可能需要等待2min-5min不等"
  count=0
  sleep 30
  while true; do
    # 这里要查询不是Running状态的pod, 如"ContainerCreating","Init:0/3,"PodInitializing","0/1 Running"
    if kubectl get pods -n kube-system | grep coredns | grep -E 'ContainerCreating|PodInitializing|0/1' &>/dev/null; then
      echo -e "$wait""等待coreDNS容器部署完成..."
      kubectl get pods -n kube-system -o wide | grep coredns
      sleep 20
    else
      echo -e "$normal""coredns服务已成功启动"
      kubectl get pods -A -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((20 * count + 30))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""准备部署默认存储类"
  tar -zxvf ./package/helm-v3.11.0-linux-amd64.tar.gz
  mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64
  if [ ! -f "./package/openebs-3.3.1.tgz" ]; then
    echo -e "$warn""未检测到./package/openebs-3.3.1.tgz文件，即将自动下载，请确定网络环境"
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm pull openebs/openebs --version "v3.3.1" -d ./package
  else
    echo -e "$normal""已检测到helm包./package/openebs-3.3.1.tgz"
  fi

  helm install openebs --namespace kube-system ./package/openebs-3.3.1.tgz >/dev/null
  sleep 30

  while true; do
    # 这里要查询不是Running状态的pod, 如"ContainerCreating","Init:0/3,"PodInitializing","0/1 Running"
    if kubectl get pods -n kube-system | grep openebs | grep -E 'ContainerCreating|0/1' &>/dev/null; then
      echo -e "$wait""等待openebs容器部署完成..."
      kubectl get pods -n kube-system -o wide | grep openebs
      sleep 20
    else
      echo -e "$normal""openebs服务已成功启动"
      kubectl get pods -n kube-system -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((20 * count + 30))s,时间过长,请考虑手动排错"
    fi
  done

  kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  if kubectl get sc | grep "openebs-hostpath (default)" &>/dev/null; then
    echo -e "$normal""默认存储类配置成功"
  else
    echo -e "$err""默认存储类配置失败"
    exit 1
  fi
}

function menu() {
  mkdir log
  mkdir package
  clear

  echo -e "请用户选择依赖包拉取方案..."
  sleep 1
  echo -e "1.""[\033[33m我的网络很好, 请脚本自动下载各依赖包\033[0m]"
  echo "     -->wget https://dl.k8s.io/v1.20.4/kubernetes-server-linux-amd64.tar.gz -P ./package/
     -->wget https://github.com/containerd/containerd/releases/download/v1.6.1/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -P ./package/
     -->wget https://github.com/opencontainers/runc/releases/download/v1.1.0/runc.amd64 -P ./package/
     -->wget https://github.com/etcd-io/etcd/releases/download/v3.5.2/etcd-v3.5.2-linux-amd64.tar.gz -P ./package/
     -->wget https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz -P ./package/
     -->wget https://docs.projectcalico.org/v3.18/manifests/calico.yaml -P ./package/
     -->wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -P ./package/
     -->wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -P ./package/
     -->wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -P ./package/"
  echo -e "2.""[\033[33m我已手动下载上述依赖包, 请继续脚本\033[0m]"
  echo "     -->安装etcd
     -->安装containerd
     -->安装kube-apiserver、kubectl、kube-controller-manager、kube-scheduler
     -->安装kubelet、kube-proxy
     -->安装calico、coredns"
  echo -e "0.""[\033[33m退出\033[0m]"
  echo "     -->退出脚本"
  read -rp " 请选择目标[1/2/0]：" cosmoplat
  case $cosmoplat in
  0)
    exit 0
    ;;
  1)
    clear
    echo -e "$normal""正在下载依赖包"
    wget https://dl.k8s.io/v1.20.4/kubernetes-server-linux-amd64.tar.gz -P ./package/
    wget https://github.com/containerd/containerd/releases/download/v1.6.1/cri-containerd-cni-1.6.1-linux-amd64.tar.gz -P ./package/
    wget https://github.com/opencontainers/runc/releases/download/v1.1.0/runc.amd64 -P ./package/
    wget https://github.com/etcd-io/etcd/releases/download/v3.5.2/etcd-v3.5.2-linux-amd64.tar.gz -P ./package/
    wget https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz -P ./package/
    wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -P ./package/
    wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -P ./package/
    wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -P ./package/
    ;;
  2)
    clear
    echo -e "$normal""执行依赖包检测"
    ;;
  *)
    echo -e "$err""未选择正确的操作,退出"
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
    echo -e "$err""当前package目录下缺少 runc.amd64 文件"
    exit_flag=1
  fi
  if [ ! -f "./package/etcd-v3.5.2-linux-amd64.tar.gz" ]; then
    echo -e "$err""当前package目录下缺少 etcd-v3.5.2-linux-amd64.tar.gz 文件"
    exit_flag=1
  fi
  if [ ! -f "./package/helm-v3.11.0-linux-amd64.tar.gz" ]; then
    echo -e "$err""当前package目录下缺少 helm-v3.11.0-linux-amd64.tar.gz 文件"
    exit_flag=1
  fi
  if [ ! -f "./package/openebs-3.3.1.tgz" ]; then
    echo -e "$warn""当前package目录下缺少 openebs-3.3.1.tgz 文件, 脚本可以自动下载"
    #exit_flag
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
  for HOST in ${k8s_all_names[@]}; do
    {
      echo -e "$normal""创建$HOST目录"
      ssh root@"$HOST" "mkdir -p /etc/cni/net.d"
      ssh root@"$HOST" "mkdir -p /etc/containerd"
      ssh root@"$HOST" "mkdir -p /opt/cni/bin /etc/cni/net.d"
      ssh root@"$HOST" "mkdir -p /etc/kubernetes/pki /etc/kubernetes/manifests/"
      ssh root@"$HOST" "mkdir -p /etc/kubernetes/manifests/"
      ssh root@"$HOST" "mkdir -p /etc/systemd/system/kubelet.service.d /var/lib/kubelet /var/lib/kube-proxy /var/log/kubernetes"
    } >>./log/"$HOST".txt
  done

  for HOST in ${k8s_master_names[@]}; do
    {
      echo -e "$normal""创建$HOST目录"
      ssh root@"$HOST" "mkdir -p /etc/etcd/ssl"
      ssh root@"$HOST" "mkdir -p /var/lib/etcd/default.etcd"
    } >>./log/"$HOST".txt
  done
  mkdir ~/.kube
}

function init_d3os() {
  echo -e "$normal""开始引导d3os平台(约需要5min)"
  kubectl apply -f ./package/d3os-platform-installer.yaml

  sleep 2
  while true; do
    if kubectl get pod -n d3os-system -l app=ks-install -o jsonpath="{.items[0].metadata.name}" | xargs -i kubectl logs -n d3os-system {}; then
      if kubectl apply -f ./package/d3os-cluster-configuration.yaml; then
        break
      fi
    fi
    sleep 1
  done

  sleep 1
  kubectl get pod -n d3os-system -l app=ks-install -o jsonpath="{.items[0].metadata.name}" | xargs -i kubectl logs -n d3os-system {} -f | sed '/^Task .* failed:\|d3os-platform installation completed/ Q'

  while true; do
    if kubectl get pod -n d3os-system -l app=ks-install -o jsonpath="{.items[0].metadata.name}" | xargs -i kubectl logs -n d3os-system {} | grep 'd3os-platform installation completed' &>/dev/null; then
      echo 'd3os-platform installation completed!'
      break
    else
      kubectl get pod -n d3os-system -l app=ks-install -o jsonpath="{.items[0].metadata.name}" | xargs -i kubectl delete -n d3os-system pod {};
      sleep 2
      kubectl get pod -n d3os-system -l app=ks-install -o jsonpath="{.items[0].metadata.name}" | xargs -i kubectl logs -n d3os-system {} -f | sed '/^Task .* failed:\|d3os-platform installation completed/ Q'
    fi
    sleep 2
  done
}

function uninstall_d3os() {
  echo -e "$normal""开始卸载d3os平台"
  chmod +x ./package/d3os-platform-delete.sh
  ./package/d3os-platform-delete.sh
  echo -e "$normal""d3os平台已完成卸载"
}

function uninstall_k8s() {
  echo -e "$normal""检测卸载k8s的必要文件"
  exit_flag=0
  if [ ! -f "/usr/local/bin/helm" ]; then
    echo -e "$err""/usr/local/bin/helm文件缺失"
    exit_flag=1
  fi
  if [ ! -f "./package/coredns.yaml" ]; then
    echo -e "$err""当前package目录下缺少 coredns.yaml 文件"
    exit_flag=1
  fi
  if [ ! -f "./package/calico.yaml" ]; then
    echo -e "$err""当前package目录下缺少 calico.yaml 文件"
    exit_flag=1
  fi
  if [[ $exit_flag == 1 ]]; then
    exit 1
  else
    echo -e "$normal""uninstall文件检测通过"
  fi

  echo -e "$normal""删除所有ns"
  kubectl get ns | grep -vE "kube-public|kube-system|default|kube-node-lease" | awk 'NR>1' | awk '{print $1}' | xargs -i kubectl delete ns {}
  sleep 10
  while true; do
    # 这里要查询删除ns情况
    if [ "$(kubectl get ns | grep -vE 'kube-public|kube-system|default|kube-node-lease' | awk 'NR>1' | wc -l)" -eq 0 ]; then
      echo -e "$normal""k8s ns 删除完毕"
      kubectl get ns
      break
    else
      echo -e "$wait""等待k8s删除ns..."
      kubectl get ns
      sleep 5
    fi
  done

  count=0
  while true; do
    # 这里要查询pv情况
    if [ "$(kubectl get pv -A | wc -l)" -eq 0 ]; then
      echo -e "$normal""k8s pv 删除完毕"
      kubectl get pv -A
      break
    else
      echo -e "$wait""等待k8s删除pv..."
      kubectl get pv -A
      sleep 5
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((5 * count + 5))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""开始卸载openebs"
  helm 'uninstall' openebs -n kube-system
  sleep 5
  while true; do
    if kubectl get all -A | grep openebs &>/dev/null; then
      echo -e "$wait""等待openebs容器卸载完成..."
      kubectl get all -n kube-system -o wide | grep openebs
      sleep 20
    else
      echo -e "$normal""openebs服务已成功卸载"
      kubectl get pods -n kube-system -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((20 * count + 5))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""开始卸载coredns"
  kubectl delete -f ./package/coredns.yaml
  sleep 5
  while true; do
    if kubectl get all -A | grep coredns &>/dev/null; then
      echo -e "$wait""等待coredns容器卸载完成..."
      kubectl get pods -n kube-system -o wide | grep coredns
      sleep 20
    else
      echo -e "$normal""coredns服务已成功卸载"
      kubectl get pods -n kube-system -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((20 * count + 5))s,时间过长,请考虑手动排错"
    fi
  done

  echo -e "$normal""开始卸载calico"
  kubectl delete -f ./package/calico.yaml
  sleep 5
  while true; do
    if kubectl get all -A | grep calico &>/dev/null; then
      echo -e "$wait""等待calico容器卸载完成..."
      kubectl get pods -n kube-system -o wide | grep calico
      sleep 20
    else
      echo -e "$normal""calico服务已成功卸载"
      kubectl get pods -n kube-system -o wide
      break
    fi
    ((count += 1))
    if [ "$count" -gt 10 ]; then
      echo -e "$warn""已等待$((20 * count + 5))s,时间过长,请考虑手动排错"
    fi
  done

  for HOST in ${k8s_all_names[@]}; do
    echo -e "$normal""停止$HOST kube-proxy"
    ssh root@"$HOST" "systemctl stop kube-proxy;systemctl disable kube-proxy"

    echo -e "$normal""停止$HOST kubelet"
    ssh root@"$HOST" "systemctl stop kubelet;systemctl disable kubelet"

    echo -e "$normal""停止$HOST containerd"
    ssh root@"$HOST" "systemctl stop containerd;systemctl disable containerd"
  done

  for HOST in ${k8s_master_names[@]}; do
    echo -e "$normal""停止$HOST kube-scheduler"
    ssh root@"$HOST" "systemctl stop kube-scheduler;systemctl disable kube-scheduler"

    echo -e "$normal""停止$HOST kube-controller-manager"
    ssh root@"$HOST" "systemctl stop kube-controller-manager;systemctl disable kube-controller-manager"

    echo -e "$normal""停止$HOST kube-apiserver"
    ssh root@"$HOST" "systemctl stop kube-apiserver;systemctl disable kube-apiserver"

    echo -e "$normal""停止$HOST etcd"
    ssh root@"$HOST" "systemctl stop etcd;systemctl disable etcd"
  done

  sleep 3

  for HOST in ${k8s_all_names[@]}; do
    echo -e "$normal""停止$HOST calico网卡"
    ssh root@"$HOST" "modprobe -r ipip"
    ssh root@"$HOST" "ip link delete kube-ipvs0"
    ssh root@"$HOST" "ip link delete cni0"
  done

  sleep 1

  for HOST in ${k8s_all_names[@]}; do
    ssh root@"$HOST" "rm -rf ~/.kube/"
    ssh root@"$HOST" "rm -rf /etc/kubernetes/"
    ssh root@"$HOST" "rm -rf /etc/systemd/system/kubelet.service.d"
    ssh root@"$HOST" "rm -rf /etc/systemd/system/kubelet.service"
    ssh root@"$HOST" "rm -rf /usr/bin/kube*"
    ssh root@"$HOST" "rm -rf /etc/cni"
    ssh root@"$HOST" "rm -rf /opt/cni"
    ssh root@"$HOST" "rm -rf /var/lib/etcd"
    ssh root@"$HOST" "rm -rf /var/lib/kube*"
    ssh root@"$HOST" "rm -rf /var/etcd"
    ssh root@"$HOST" "rm -rf /etc/systemd/system/kubelet.service"
    ssh root@"$HOST" "rm -rf /etc/systemd/system/kube*"
    ssh root@"$HOST" "rm -rf /etc/etcd/"
    echo -e "$normal""已清空$HOST k8s相关的目录"
  done

  echo -e "$normal""k8s卸载成功"
}

function uninstall() {
  clear

  echo -e "请用户选择卸载方案..."
  sleep 1
  echo -e "1.""[\033[33m仅卸载D3os\033[0m]"
  echo -e "     -->卸载D3os"
  echo -e "2.""[\033[33m不仅卸载D3os平台, 也卸载二进制k8s集群\033[0m]"
  echo "     -->卸载D3os
       -->卸载openebs
       -->卸载calico、coredns
       -->停止kubelet、kube-proxy
       -->停止kube-apiserver、kube-controller-manager、kube-scheduler、etcd、containerd
       -->删除k8s相关目录"
  echo -e "0.""[\033[33m退出\033[0m]"
  echo "     -->退出脚本"
  read -rp "请选择目标[1/2/0]:" cosmoplat
  case $cosmoplat in
  0)
    #----退出----
    exit 0
    ;;
  1)
    #----完全卸载D3os----
    uninstall_d3os
    echo -e "$normal"'uninstall_d3os finished'
    ;;
  2)
    #----完全卸载D3os并卸载二进制k8s集群----
    uninstall_d3os
    echo -e "$normal"'uninstall_d3os finished'
    uninstall_k8s
    echo -e "$normal"'uninstall_k8s finished'
    ;;
  *)
    echo -e "$err""未选择正确的操作,退出"
    exit 1
    ;;
  esac
}

clear
echo "#####################################################################"
echo -e "#           D3OS平台一键安装脚本"
echo -e "# 作者: cosmoplat"
echo -e "# 版本: 目前仅支持k8s v1.20.4"
echo -e "# "
echo -e "# 该脚本示例默认四台主机，其中一台为master，三台为worker"
echo -e "# 该脚本已适配centos7.9"
echo "#####################################################################"
echo -e "1.""[\033[33m优化系统内核\033[0m]"
echo -e "     -->配置host文件
     -->配置ssh免密登录
     -->配置系统内核参数
     -->升级系统内核(\033[31m会重启主机\033[0m)"
echo -e "2.""[\033[33m二进制安装k8s并引导D3os平台\033[0m]"
echo "     -->安装etcd
     -->安装containerd
     -->安装kube-apiserver、kubectl、kube-controller-manager、kube-scheduler
     -->安装kubelet、kube-proxy
     -->安装calico、coredns
     -->安装D3os平台"
echo -e "3.""[\033[33m卸载D3OS\033[0m]"
echo "     -->卸载D3OS工业操作系统
     -->卸载二进制k8s集群(可选)"
echo -e "0.""[\033[33m退出\033[0m]"
echo "     -->退出脚本"
read -rp "请选择目标[1/2/3/0]:" cosmoplat
case $cosmoplat in
0)
  #----退出----
  exit 0
  ;;
1)
  #----环境准备----
  set_local
  echo -e "$normal"set_local finished
  init_os
  echo -e "$normal"init_os finished
  echo -e "$star""脚本执行完毕""$star"
  ;;
2)
  #----目录----
  menu
  echo -e "$normal"menu finished

  #----安装依赖组件----
  make_dir
  echo -e "$normal"make_dir finished
  init_local
  echo -e "$normal"init_local finished
  init_etcd
  echo -e "$normal"init_etcd finished
  init_containerd
  echo -e "$normal"init_containerd finished

  #----安装k8s组件----
  init_k8s_master
  echo -e "$normal"init_k8s_master finished
  init_k8s_other
  echo -e "$normal"init_k8s_other finished

  #----安装k8s应用----
  init_k8s_pod
  echo -e "$normal"init_k8s_pod finished

  #----安装D3OS平台
  init_d3os
  echo -e "$normal"init_d3os finished
  echo -e "$star""脚本执行完毕""$star"
  ;;
3)
  #----卸载k8s----
  uninstall
  echo -e "$star""脚本执行完毕""$star"
  ;;
*)
  echo -e "$err""未选择正确的操作,退出"
  exit 1
  ;;
esac
