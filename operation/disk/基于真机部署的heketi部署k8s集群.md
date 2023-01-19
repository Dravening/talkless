# 基于真机部署的Heketi部署k8s集群

在上一节我们已经真机部署了Heketi和GlusterFs，本节以此为默认StorageClass部署k8s集群。

> 如未部署heketi，请参考《真机部署GlusterFs并使用Heketi管理.md》

| 主机名 | IP 地址       | 操作系统                    | 设备            |
| :----- | :------------ | :-------------------------- | :-------------- |
| cos-1  | 192.168.0.89  | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 100 GB |
| cos-2  | 192.168.0.210 | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 100 GB |
| cos-3  | 192.168.0.247 | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 100 GB |

### 前置安装

1.安装依赖，三台机器都要安装

```
[root@cos-1 ~]# yum update -y
```

```
[root@cos-1 ~]# yum install openssl openssl-devel -y
```

```
[root@cos-1 ~]# yum install socat epel-release conntrack-tools -y
```

2.下载对应版本的kubekey

> 注意：一定要是这个v1.1.1版本，其它版本的kubekey不一定适用

```
[root@cos-1 ~]# curl -sfL https://get-kk.kubesphere.io | VERSION=v1.1.1 sh -
```

如果无法下载,可以手动下载

### 开始安装k8s

1.创建glusterfs配置文件

```
[root@cos-1 ~]# cat >> /root/glusterfs-sc.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: heketi-secret
  namespace: kube-system
type: kubernetes.io/glusterfs
data:
  key: "MTIzNDU2"    #请替换为您自己的密钥。Base64 编码。
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
    storageclass.kubesphere.io/supported-access-modes: '["ReadWriteOnce","ReadOnlyMany","ReadWriteMany"]'
  name: glusterfs
parameters:
  clusterid: "65e9887f72856eee2edb604374426c83"    #请替换为您自己的 GlusterFS 集群 ID。
  gidMax: "50000"
  gidMin: "40000"
  restauthenabled: "true"
  resturl: "http://192.168.0.89:8080"    #Gluster REST 服务/Heketi 服务 URL 可按需供应 gluster 存储卷。请替换为您自己的 URL。
  restuser: admin
  secretName: heketi-secret
  secretNamespace: kube-system
  volumetype: "replicate:3"    #请替换为您自己的存储卷类型。
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
EOF
```

2.创建 config-sample.yaml

```
[root@cosmo-1 ~]# ./kk create config --with-kubernetes v1.20.4 --with-kubesphere v3.1.1
```

```
[root@cos-1 draven]# cat config-sample.yaml
apiVersion: kubekey.kubesphere.io/v1alpha1
kind: Cluster
metadata:
  name: sample
spec:
  hosts:
  - {name: cos-1, address: 192.168.0.89, internalAddress: 192.168.0.89, user: root, password: Cosmo@2022}
  - {name: cos-2, address: 192.168.0.210, internalAddress: 192.168.0.210, user: root, password: Cosmo@2022}
  - {name: cos-3, address: 192.168.0.247, internalAddress: 192.168.0.247, user: root, password: Cosmo@2022}
  roleGroups:
    etcd:
    - cos-1
    master:
    - cos-1
    worker:
    - cos-1
    - cos-2
    - cos-3
  controlPlaneEndpoint:
    domain: lb.kubesphere.local
    address: ""
    port: 6443
  kubernetes:
    version: v1.20.4
    imageRepo: kubesphere
    clusterName: cluster.local
  network:
    plugin: calico
    kubePodsCIDR: 10.233.64.0/18
    kubeServiceCIDR: 10.233.0.0/18
  registry:
    registryMirrors: []
    insecureRegistries: []
  addons:
  - name: glusterfs
    namespace: kube-system
    sources:
      yaml:
        path:
        - /root/glusterfs-sc.yaml

---
```

3.执行安装命令

```
[root@cosmo-1 ~]# export KKZONE=cn
```

```
[root@cosmo-1 ~]# ./kk create cluster -f config-sample.yaml
```

### 卸载k8s

1.使用kk工具卸载k8s

```
[root@cos-1 draven]# ./kk delete cluster

Are you sure to delete this cluster? [yes/no]: yes
INFO[09:15:55 CST] Resetting kubernetes cluster ...
[cos-1 192.168.0.89] MSG:
[reset] Reading configuration from the cluster...
[reset] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
W0111 09:15:55.721172    4050 utils.go:69] The recommended value for "clusterDNS" in "KubeletConfiguration" is: [10.233.0.10]; the provided value is: [169.254.25.10]
[preflight] Running pre-flight checks
[reset] Removing info for node "cos-1" from the ConfigMap "kubeadm-config" in the "kube-system" Namespace
W0111 09:15:55.855149    4050 removeetcdmember.go:79] [reset] No kubeadm config, using etcd pod spec to get data directory
[reset] No etcd config found. Assuming external etcd
[reset] Please, manually reset etcd to prevent further issues
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
[reset] Deleting contents of config directories: [/etc/kubernetes/manifests /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]
[reset] Deleting contents of stateful directories: [/var/lib/kubelet /var/lib/dockershim /var/run/kubernetes /var/lib/cni]

The reset process does not clean CNI configuration. To do so, you must remove /etc/cni/net.d

The reset process does not reset or clean up iptables rules or IPVS tables.
If you wish to reset iptables, you must do so manually by using the "iptables" command.

If your cluster was setup to utilize IPVS, run ipvsadm --clear (or similar)
to reset your system's IPVS tables.

The reset process does not clean your kubeconfig files and you must remove them manually.
Please, check the contents of the $HOME/.kube/config file.
[cos-1 192.168.0.89] MSG:
sudo -E /bin/sh -c "iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat && ip link del kube-ipvs0 && ip link del nodelocaldns"
INFO[09:16:02 CST] Successful.
```

检查一下

```
[root@cos-1 draven]# kubectl get pvc
The connection to the server lb.kubesphere.local:6443 was refused - did you specify the right host or port?
```

2.如果要大删特删，可以执行后续语句

```
yum -y remove kubelet kubeadm kubectl
```

```
sudo rm -rvf $HOME/.kube
sudo rm -rvf ~/.kube/
sudo rm -rvf /etc/kubernetes/
sudo rm -rvf /etc/systemd/system/kubelet.service.d
sudo rm -rvf /etc/systemd/system/kubelet.service
sudo rm -rvf /usr/bin/kube*
sudo rm -rvf /etc/cni
sudo rm -rvf /opt/cni
sudo rm -rvf /var/lib/etcd
sudo rm -rvf /var/lib/kube*
sudo rm -rvf /var/etcd
sudo rm -rvf /etc/systemd/system/kubelet.service
sudo rm -rvf /etc/systemd/system/kube*
sudo rm -rvf /etc/ssl/etcd/
```

