# 安装KubeEdge并纳管边缘节点

### 前言

本教程为从零安装教程，仅需要读者有两台云主机（CentOS 7）。

### 背景

此处引用KubeEdge官网（https://kubeedge.io/）对kubeedge的定义。

> KubeEdge是一个开源系统，将原生的容器化应用程序编排功能扩展到边缘节点

要弄清这句话的涵义，我们要先明确边缘节点的特点：

- 低延迟处理。车联网场景如果要进行数据共享和指令下发需要极低延迟的通信保障和计算处理速度。
- 本地处理数据。有些数据较敏感不能什么都传到云端（如用户照片、密码）
- 离线自治。很多边端设备不一定有可靠的连接保持和云端的通信。如农业、地理科学的传感器。

简单点来说，就是***边缘节点跟云端不在同一个内网，但又希望受到云端的管控***。

基于这种需求，产生了多个产品（如 KubeEdge、OpenYurt 、SuperEdge等）。

本文介绍KubeEdge的安装使用。

### 环境准备

目前我们有两台云主机如下

| 主机名 | 系统       | 功能                                                 | 备注                                               |
| ------ | ---------- | ---------------------------------------------------- | -------------------------------------------------- |
| draven | CentOS 7.9 | 中控节点：部署k8s、kubesphere、KubeEdge（CloudCore） | 内网ip：172.23.105.205<br />公网ip：47.100.220.146 |
| node1  | CentOS 7.9 | 边缘节点：部署KubeEdge（EdgeCore）                   | 内网ip：172.16.11.150  可以访问公网                |

> 注意：中控节点使用2c4g的主机是不够用的，需要手动协调资源分配；推荐至少4c8g的主机

##### 升级主机内核【中控节点】

详细操作请参考《升级系统内核.md》，具体操作过程略

升级前

```
[root@draven ~]# uname -r
3.10.0-1160.el7.x86_64
```

升级后

```
[root@draven ~]# uname -r
6.1.6-1.el7.elrepo.x86_64
```

##### 部署kubesphere【中控节点】

1.下载kubekey

```
curl -sfL https://get-kk.kubesphere.io | VERSION=v3.0.2 sh -
```

> 如果无法下载，请
>
> 手动下载
>
> `wget https://github.com/kubesphere/kubekey/releases/download/v3.0.2/kubekey-v3.0.2-linux-amd64.tar.gz`
>
> 手动解压
>
> `[root@draven ~]# tar zxvf kubekey-v3.0.2-linux-amd64.tar.gz`

2.安装依赖组件

```
[root@draven ~]# yum update
```

```
[root@draven ~]# yum install -y openssl openssl-devel socat epel-release conntrack-tools
```

3.安装k8s及kubesphere

```
export KKZONE=cn
```

缺省安装

```
[root@draven ~]# ./kk create cluster --with-kubernetes v1.22.12 --with-kubesphere v3.3.1
```

配置文件安装

```
[root@draven ~]# ./kk create config --with-kubernetes v1.22.12 --with-kubesphere v3.3.1
```

```
[root@draven ~]# vim config-sample.yaml
```

```
[root@draven ~]# ./kk create cluster -f config-sample.yaml
```

### 正式安装KubeEdge

目前我们有两台机器，draven作为主节点已经部署了kubesphere，node1作为边缘节点目前是原生centos7

##### 开启KubeEdge（CloudCore）功能【中控节点】

如果您对k8s操作比较熟悉，可以命令行修改crd文件ks-installer中`edgeruntime`和`kubeedge`的值为`true`，并添加`advertiseAddress`地址

> 请参考：https://kubesphere.io/zh/docs/v3.3/pluggable-components/kubeedge/
>
> 此处要注意，配置中的advertiseAddress地址必须填写一个可以被公网访问的地址；如果你的中控节点不能被公网访问到，那此处要配置跳板机的ip

```
[root@draven ~]# kubectl edit clusterconfigurations.installer.kubesphere.io  ks-installer  -n kubesphere-system
clusterconfiguration.installer.kubesphere.io/ks-installer edited
```

修改后需要重启`ks-installer`

```
[root@draven ~]# kubectl delete pod ks-installer-6484f6c4cf-fclw2 -n kubesphere-system
pod "ks-installer-6484f6c4cf-fclw2" deleted
```

成功启动后我们应有pod如下（你应该还会有monitor相关的容器）

```
[root@draven ~]# kubectl get pods -A
NAMESPACE           NAME                                          READY   STATUS      RESTARTS        AGE
kube-system         calico-kube-controllers-69cfcfdf6c-h56ld      1/1     Running     0               15h
kube-system         calico-node-b8rbm                             1/1     Running     0               15h
kube-system         coredns-5495dd7c88-76ms7                      1/1     Running     0               15h
kube-system         coredns-5495dd7c88-fpx5r                      1/1     Running     0               15h
kube-system         kube-apiserver-draven                         1/1     Running     0               15h
kube-system         kube-controller-manager-draven                1/1     Running     0               15h
kube-system         kube-proxy-849x4                              1/1     Running     0               15h
kube-system         kube-scheduler-draven                         1/1     Running     0               15h
kube-system         nodelocaldns-wfr4w                            1/1     Running     0               15h
kube-system         openebs-localpv-provisioner-6f8b56f75-hctvz   1/1     Running     0               15h
kube-system         snapshot-controller-0                         1/1     Running     0               24m
kubeedge            cloud-iptables-manager-v9ld8                  1/1     Running     0               26m
kubeedge            cloudcore-76f574c847-7jxtz                    1/1     Running     0               26m
kubeedge            edgeservice-5d899b567c-dm82z                  1/1     Running     0               26m
kubesphere-controls-system  default-http-backend-56d9d4fdf7-pjp8b 1/1     Running     0               15h
kubesphere-controls-system  kubectl-admin-7685cdd85b-nzqdp        1/1     Running     0               15h
kubesphere-controls-system  kubectl-yangyuzhe-7449989b99-zwtsk    1/1     Running     0               15h
kubesphere-system   ks-apiserver-57cff8b458-lxg8g                 1/1     Running     0               8m46s
kubesphere-system   ks-console-74f656f664-gdvgt                   1/1     Running     0               73m
kubesphere-system   ks-controller-manager-55844b48fb-gp24p        1/1     Running     0               11m
kubesphere-system   ks-installer-6484f6c4cf-vtdlm                 1/1     Running     0               6m26s
kubesphere-system   minio-6bcfb85c5b-bt8wx                        1/1     Running     0               30m
kubesphere-system   openpitrix-import-job-bh7d6                   0/1     Completed   0               27m
```

##### 获取边缘节点配置命令【中控节点】

在web页面中添加边缘节点，访问http://47.100.220.146:30880/clusters/default/edgenodes

点击`验证`按钮，获取`边缘节点配置命令`

```
arch=$(uname -m); if [[ $arch != x86_64 ]]; then arch='arm64'; fi;  curl -LO https://kubeedge.pek3b.qingstor.com/bin/v1.9.2/$arch/keadm-v1.9.2-linux-$arch.tar.gz  && tar xvf keadm-v1.9.2-linux-$arch.tar.gz && chmod +x keadm && ./keadm join --kubeedge-version=1.9.2 --region=zh --cloudcore-ipport=47.100.220.146:10000 --quicport 10001 --certport 10002 --tunnelport 10004 --edgenode-name node1-150 --edgenode-ip 172.16.11.150 --token XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX --with-edge-taint
```

至此，`中控节点`的配置已经完成了，接下来配置`边缘节点`

##### 开启KubeEdge（EdgeCore）功能【边缘节点】

1.首先配置机器

编辑 `/etc/nsswitch.conf`。

```
[root@node1 ~]# vim /etc/nsswitch.conf
```

在该文件中添加以下内容。

```
hosts:          dns files mdns4_minimal [NOTFOUND=return]
```

保存文件并运行以下命令启用 IP 转发：

```
[root@node1 ~]# echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
```

验证修改：

```
[root@node1 ~]# sysctl -p | grep ip_forward
net.ipv4.ip_forward = 1
```

2.使用`边缘节点配置命令`

这里分两种情况

- `中控节点`可以被公网访问

  这种情况请修改`边缘节点配置命令`中的端口，将10000-10004改为30000-30004，直接连接`中控节点`开放的NodePort，修改后如下

  ```
  [root@node1 ~]# arch=$(uname -m); if [[ $arch != x86_64 ]]; then arch='arm64'; fi;  curl -LO https://kubeedge.pek3b.qingstor.com/bin/v1.9.2/$arch/keadm-v1.9.2-linux-$arch.tar.gz  && tar xvf keadm-v1.9.2-linux-$arch.tar.gz && chmod +x keadm && ./keadm join --kubeedge-version=1.9.2 --region=zh --cloudcore-ipport=47.100.220.146:30000 --quicport 30001 --certport 30002 --tunnelport 30004 --edgenode-name node1-150 --edgenode-ip 172.16.11.150 --token XXXXXXXXXXXXXXXXXXXXXXXXXX --with-edge-taint
  ```

- `中控节点`不可被公网访问

  这种情况，不需要修改`边缘节点配置命令`，但需要用户自行配置`跳板机`到`中控节点`的端口转发，可以配置`跳板机ip:10000-10004`跳转`中控节点ip:30000-30004`，命令参考如下

  ```
  iptables -t nat -A PREROUTING --dst 跳板机ip -p tcp --dport 10000 -j DNAT --to-destination 中控节点ip:30000
  ```

  ```
  iptables -t nat -A POSTROUTING --dst 中控节点ip -p tcp --dport 30000 -j SNAT --to-source 跳板机ip
  ```

3.等待`边缘节点配置命令`执行成功

```
[root@node1 ~]# systemctl status edgecore
● edgecore.service
     Loaded: loaded (/etc/systemd/system/edgecore.service; enabled; vendor preset: enabled)
     Active: active (running) since Wed 2023-01-18 11:39:39 CST; 1h 35min ago
   Main PID: 44387 (edgecore)
      Tasks: 89 (limit: 9830)
     Memory: 63.4M
        CPU: 3min 32.009s
     CGroup: /system.slice/edgecore.service
             └─44387 /usr/local/bin/edgecore
```

如果不成功可以查看日志

```
[root@node1 ~]# journalctl -xefu edgecore
```

### 使用KubeEdge边缘节点

##### 处理DaemonSet强容忍度问题【中控节点】

检查此时集群状态

```
[root@draven ~]# kubectl get nodes
NAME        STATUS   ROLES                         AGE    VERSION
draven      Ready    control-plane,master,worker   18h    v1.22.12
node1-150   Ready    agent,edge                    102m   v1.21.4-kubeedge-v1.9.2
```

```
[root@draven ~]# kubectl describe node node1-150
Name:               node1-150
Roles:              agent,edge
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=node1-150
                    kubernetes.io/os=linux
                    node-role.kubernetes.io/agent=
                    node-role.kubernetes.io/edge=
Annotations:        node.alpha.kubernetes.io/ttl: 0
CreationTimestamp:  Wed, 18 Jan 2023 11:39:41 +0800
Taints:             node-role.kubernetes.io/edge:NoSchedule
Unschedulable:      false
Lease:              Failed to get lease: leases.coordination.k8s.io "node1-150" not found
Conditions:
  Type    Status  LastHeartbeatTime                 LastTransitionTime                Reason      Message
  ----    ------  -----------------                 ------------------                ------      -------
  Ready   True    Wed, 18 Jan 2023 13:24:01 +0800   Wed, 18 Jan 2023 11:39:41 +0800   EdgeReady   edge is posting ready status
Addresses:
  InternalIP:  172.16.11.150
  Hostname:    node1-150
Capacity:
  cpu:                80
  ephemeral-storage:  464890076Ki
  memory:             257577Mi
  pods:               110
Allocatable:
  cpu:                80
  ephemeral-storage:  463841500Ki
  memory:             257477Mi
  pods:               110
System Info:
  Machine ID:
  System UUID:
  Boot ID:
  Kernel Version:             5.15.0-56-generic
  OS Image:                   Ubuntu 22.04.1 LTS
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  docker://20.10.22
  Kubelet Version:            v1.21.4-kubeedge-v1.9.2
  Kube-Proxy Version:
PodCIDR:                      10.233.65.0/24
PodCIDRs:                     10.233.65.0/24
Non-terminated Pods:          (3 in total)
  Namespace          Name                  CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------          ----                  ------------  ----------  ---------------  -------------  ---
  kube-system        calico-node-z9t9t     250m (0%)     0 (0%)      0 (0%)           0 (0%)         104m
  kube-system        kube-proxy-thbgp      0 (0%)        0 (0%)      0 (0%)           0 (0%)         104m
  kube-system        nodelocaldns-x8rbp    100m (0%)     0 (0%)      70Mi (0%)        170Mi (0%)     104m
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                350m (0%)  0 (0%)
  memory             70Mi (0%)  170Mi (0%)
  ephemeral-storage  0 (0%)     0 (0%)
Events:              <none>
```

可以看到由于calico-node，kube-proxy，nodelocaldns三个daemonset配置了强容忍度，所以它们的pod出现在了边缘节点上；
我们可以手动 Patch Pod 配置节点亲和性，以防止非边缘节点调度至工作节点

```
#!/bin/bash
NoShedulePatchJson='{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"node-role.kubernetes.io/edge","operator":"DoesNotExist"}]}]}}}}}}}'
ns="kube-system"
DaemonSets=("nodelocaldns" "kube-proxy" "calico-node")
length=${#DaemonSets[@]}
for((i=0;i<length;i++));  
do
        ds=${DaemonSets[$i]}
        echo "Patching resources:DaemonSet/${ds}" in ns:"$ns",
        kubectl -n $ns patch DaemonSet/${ds} --type merge --patch "$NoShedulePatchJson"
        sleep 1
done
```

```
[root@draven ~]# vi edge-node.sh
[root@draven ~]# ./edge-node.sh
Patching resources:DaemonSet/nodelocaldns in ns:kube-system,
daemonset.apps/nodelocaldns patched
Patching resources:DaemonSet/kube-proxy in ns:kube-system,
daemonset.apps/kube-proxy patched
Patching resources:DaemonSet/calico-node in ns:kube-system,
daemonset.apps/calico-node patched
```

##### 使用边缘节点部署Nginx容器【中控节点】

```
[root@draven ~]# cat >> ./nginx.yaml << EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: nginx
  namespace: test               #替换为自己的namespace
  labels:
    app: nginx
  annotations:
    deployment.kubernetes.io/revision: '1'
    kubesphere.io/creator: admin         #替换为自己的creator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: nginx
      annotations:
        kubesphere.io/creator: admin     #替换为自己的creator
    spec:
      containers:
        - name: container-triywi
          image: nginx
          ports:
            - name: tcp-80
              containerPort: 80
              protocol: TCP
          resources:
            limits:
              cpu: 100m
              memory: 50Mi
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/hostname: raspberrypi         #替换为自己的边缘节点的node名
      serviceAccountName: default
      serviceAccount: default
      securityContext: {}
      schedulerName: default-scheduler
      tolerations:                            #注意这里，容忍了edge节点
        - key: node-role.kubernetes.io/edge
          operator: Exists
          effect: NoSchedule
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
  
---
kind: Service
apiVersion: v1
metadata:
  name: nginx
  namespace: test                 #替换为自己的namespace
  labels:
    app: nginx-svc
  annotations:
    kubesphere.io/creator: admin          #替换为自己的creator
spec:
  ports:
    - name: http-80
      protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 31180
  selector:
    app: nginx
  type: NodePort
EOF
```

```
[root@draven ~]# kubectl apply -f nginx.yaml
deployment.apps/nginx created
```

```
[root@draven ~]# kubectl get pods -n yangyuzhe-project -o wide
NAME                   READY  STATUS   RESTARTS  AGE   IP         NODE       NOMINATED NODE  READINESS GATES
nginx-84486dfb88-tlqjn 1/1    Running  0         56s   172.17.0.3 node1-150  <none>          <none>
```

```
[root@draven ~]# kubectl get svc -n yangyuzhe-project -o wide
NAME    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE   SELECTOR
nginx   NodePort   10.233.37.248   <none>        80:31045/TCP   12m   app=nginx
```

成功使用`边缘节点`部署Nginx容器

尝试访问nginx的外网端口，发现无法ping通

```
[root@draven ~]# curl http://47.100.220.146:31180
curl: (7) Failed to connect to 47.100.220.146 port 31180 after 3091 ms: No route to host
```

### 云边服务互访

在边缘计算机的场景下，网络拓扑结构更加复杂。不同区域的边缘节点往往不能互联，而应用之间又需要业务流量互通。EdgeMesh 即可满足边缘节点之间流量互通的要求。按照官方 Github 介绍，EdgeMesh 作为 KubeEdge 集群的数据平面组件，为应用程序提供简单的服务发现和流量代理功能，从而屏蔽了边缘场景中的复杂网络结构。

因此 EdgeMesh 主要实现两个终极目标：

- 用户可以在不同的网络中访问边到边、边到云、云到边的应用
- 部署 EdgeMesh 相当于部署了 CoreDNS+Kube-Proxy+CNI

##### 开启KubeEdge的Kube-API Endpoint功能

1.启用cloudcore的dynamicController

```
[root@draven ~]# kubectl edit cm cloudcore  -n kubeedge
modules:
  ...
  dynamicController: 
    enable: true
```

2.启用edgecore的metaserver

```
[root@node1 ~]# cat /etc/kubeedge/config/edgecore.yaml
apiVersion: edgecore.config.kubeedge.io/v1alpha1
database:
  aliasName: default
  dataSource: /var/lib/kubeedge/edgecore.db
  driverName: sqlite3
kind: EdgeCore
modules:
  dbTest:
    enable: false
  deviceTwin:
    enable: true
  edgeHub:
    enable: true
    heartbeat: 15
    httpServer: https://47.100.220.146:30002
    projectID: e632aba927ea4ac2b575ec1603d56f10
    quic:
      enable: false
      handshakeTimeout: 30
      readDeadline: 15
      server: 47.100.220.146:30001
      writeDeadline: 15
    rotateCertificates: true
    tlsCaFile: /etc/kubeedge/ca/rootCA.crt
    tlsCertFile: /etc/kubeedge/certs/server.crt
    tlsPrivateKeyFile: /etc/kubeedge/certs/server.key
    token: xxxxxxxxxxxxxxxxxxx.xxxxxxxxxxxxxx.xxxxxxxxxxxxxxxxxx.xxxxxxxxxxxxxxxxxxxxx
    websocket:
      enable: true
      handshakeTimeout: 30
      readDeadline: 15
      server: 47.100.220.146:30000
      writeDeadline: 15
  edgeStream:
    enable: false
    handshakeTimeout: 30
    readDeadline: 15
    server: 47.100.220.146:10004
    tlsTunnelCAFile: /etc/kubeedge/ca/rootCA.crt
    tlsTunnelCertFile: /etc/kubeedge/certs/server.crt
    tlsTunnelPrivateKeyFile: /etc/kubeedge/certs/server.key
    writeDeadline: 15
  edged:
    cgroupDriver: cgroupfs
    cgroupRoot: ""
    cgroupsPerQOS: true
    clusterDNS: "169.254.96.16"            # -----------------------修改这里为169.254.96.16,一般情况不用改这个ip
    clusterDomain: "cluster.local"         # -----------------------修改这里为cluster.local
    cniBinDir: /opt/cni/bin
    cniCacheDirs: /var/lib/cni/cache
    cniConfDir: /etc/cni/net.d
    concurrentConsumers: 5
    devicePluginEnabled: false
    dockerAddress: unix:///var/run/docker.sock
    edgedMemoryCapacity: 7852396000
    enable: true
    enableMetrics: true
    gpuPluginEnabled: false
    hostnameOverride: node1
    imageGCHighThreshold: 80
    imageGCLowThreshold: 40
    imagePullProgressDeadline: 60
    maximumDeadContainersPerPod: 1
    networkPluginMTU: 1500
    nodeIP: 172.16.11.150
    nodeStatusUpdateFrequency: 10
    podSandboxImage: kubeedge/pause:3.1
    registerNode: true
    registerNodeNamespace: default
    remoteImageEndpoint: unix:///var/run/dockershim.sock
    remoteRuntimeEndpoint: unix:///var/run/dockershim.sock
    runtimeRequestTimeout: 2
    runtimeType: docker
    taints:
    - effect: NoSchedule
      key: node-role.kubernetes.io/edge
    volumeStatsAggPeriod: 60000000000
  eventBus:
    enable: true
    eventBusTLS:
      enable: false
      tlsMqttCAFile: /etc/kubeedge/ca/rootCA.crt
      tlsMqttCertFile: /etc/kubeedge/certs/server.crt
      tlsMqttPrivateKeyFile: /etc/kubeedge/certs/server.key
    mqttMode: 2
    mqttQOS: 0
    mqttRetain: false
    mqttServerExternal: tcp://127.0.0.1:1883
    mqttServerInternal: tcp://127.0.0.1:1884
    mqttSessionQueueSize: 100
  metaManager:
    contextSendGroup: hub
    contextSendModule: websocket
    enable: true
    metaServer:
      enable: true                          # -------------------------修改这里为true
      server: 127.0.0.1:10550
    podStatusSyncInterval: 60
    remoteQueryTimeout: 60
  serviceBus:
    enable: false
    port: 9060
    server: 127.0.0.1
    timeout: 60
```

3.记得重启cloudCore和edgeCore服务

```
[root@draven ~]# kubectl delete pod cloudcore-XXXXXX-XXXXX -n kubeedge
```

```
[root@node1 ~]# systemctl restart edgecore
```

4.测试能够请求Kube-API

```
[root@node1 ~]# curl 127.0.0.1:10550/api/v1/services
{"apiVersion":"v1","items":[{"apiVersion":"v1","kind":"Service","metadata":{"creationTimestamp":"2023-01-19T02:50:38Z","labels":{"component":"apiserver","provider":"kubernetes"},"managedFields":[{"apiVersion":"v1","fieldsType":"FieldsV1","fieldsV1":{"f:metadata":{"f:labels":{".":{},"f:component":{},"f:provider":{}}},"f:spec":{"f:clusterIP":{},"f:internalTrafficPolicy":{},"f:ipFamilyPolicy":{}
...
...
...
```

##### 安装edgeMesh

> 注意：当前版本kubesphere自带的edgemesh版本与环境变量不匹配，不要使用应用商店里面的edgemesh包

> 注意：此处边缘节点如果有多网卡很可能埋坑，优先配序号小的

下方命令中psk的值可以使用`openssl rand -base64 32`获取

```
[root@draven ~]# openssl rand -base64 32
a6C3os/ucfBVQGfuKTi8xrQzIcBCjPpDwwfTIkEoScg=
```

```
helm install edgemesh --namespace kubeedge \
--set agent.psk=a6C3os/ucfBVQGfuKTi8xrQzIcBCjPpDwwfTIkEoScg= \
--set agent.relayNodes[0].nodeName=draven,agent.relayNodes[0].advertiseAddress="{47.100.220.146}" \
--set agent.relayNodes[1].nodeName=node1,agent.relayNodes[1].advertiseAddress="{172.16.11.150}" \
https://raw.githubusercontent.com/kubeedge/edgemesh/main/build/helm/edgemesh.tgz
```

记得配置edgemesh-agent的容忍度

```
[root@draven ~]# kubectl edit daemonset edgemesh-agent -n kubeedge
daemonset.apps/edgemesh-agent edited
```

```
      restartPolicy: Always
      schedulerName: default-scheduler
      tolerations:
        - key: node-role.kubernetes.io/edge
          operator: Exists
          effect: NoSchedule
```

查看部署结果，出现两个edgemesh-agent的pod

```
[root@draven ~]# kubectl get pods -n kubeedge
NAME                           READY   STATUS    RESTARTS   AGE
cloud-iptables-manager-nk8bf   1/1     Running   0          4h3m
cloudcore-8665485757-2tdr8     1/1     Running   0          89m
edgemesh-agent-6njfh           1/1     Running   0          76s
edgemesh-agent-d9shw           1/1     Running   0          27s
edgeservice-66577bb846-vl8fs   1/1     Running   0          121m
```

##### 测试外网功能

```
[root@draven ~]# curl http://47.100.220.146:31180
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

### 边边服务互访

##### 环境准备

| 主机名      | 系统                     | 功能                                                 | 备注                                               |
| ----------- | ------------------------ | ---------------------------------------------------- | -------------------------------------------------- |
| draven      | CentOS 7.9               | 中控节点：部署k8s、kubesphere、KubeEdge（CloudCore） | 内网ip：172.23.105.205<br />公网ip：47.100.220.146 |
| node1       | CentOS 7.9               | 边缘节点：部署KubeEdge（EdgeCore）                   | 内网ip：172.16.11.150  可以访问公网                |
| raspberrypi | raspberrypi 5.15.76-v7l+ | 边缘节点：部署KubeEdge（EdgeCore）                   | 内网ip：172.16.12.208  可以访问公网                |

> 注意：当前kubesphere版本（3.3.1），默认的脚本仅支持arm64位，我们需要手动下载arm32位的kubeedge
>

raspberrypi节点需要安装docker

```
root@raspberrypi:~# curl -sSL https://get.docker.com | sh
```

可能会遇到cgroupfs对不上systemd的问题，修改docker配置

```
root@raspberrypi:~# cat /etc/docker/daemon.json
{
  "exec-opts":["native.cgroupdriver=cgroupfs"]
}
```

```
root@raspberrypi:~# systemctl daemon-reload
root@raspberrypi:~# systemctl restart docker
```

##### 安装KubeEdge（edgeCore）

手动下载arm32位keadm

```
root@raspberrypi:~# curl -LO https://kubeedge.pek3b.qingstor.com/bin/v1.9.2/arm/keadm-v1.9.2-linux-arm.tar.gz
```

执行安装

```
root@raspberrypi:~# tar xvf keadm-v1.9.2-linux-arm.tar.gz && chmod +x keadm && ./keadm join --kubeedge-version=1.9.2 --region=zh --cloudcore-ipport=47.100.220.146:30000 --quicport 30001 --certport 30002 --tunnelport 30004 --edgenode-name raspberrypi --edgenode-ip 172.16.12.208 --token xxxxxxxxxxxx.xxxxxxxxxxx.xxxxxxxxxxxxxxxx.xxxxxxxxxxx --with-edge-taint
```

##### 部署edgeMesh

直接修改主节点的edgemesh配置，加入新节点的配置即可

```
[root@draven ~]# kubectl edit cm edgemesh-agent-cfg  -n kubeedge
```

### 结论

节点状态

```
[root@draven ~]# kubectl get nodes
NAME          STATUS   ROLES                         AGE     VERSION
draven        Ready    control-plane,master,worker   7h33m   v1.22.12
node1         Ready    agent,edge                    5h8m    v1.21.4-kubeedge-v1.9.2
raspberrypi   Ready    agent,edge                    38m     v1.21.4-kubeedge-v1.9.2
```

kubeedge状态

```
[root@draven ~]# kubectl get pod -n kubeedge
NAME                           READY   STATUS    RESTARTS      AGE
cloud-iptables-manager-nk8bf   1/1     Running   0             6h56m
cloudcore-8665485757-2tdr8     1/1     Running   0             4h22m
edgemesh-agent-4l6gz           1/1     Running   0             134m
edgemesh-agent-9qbxk           1/1     Running   0             134m
edgemesh-agent-h5v92           1/1     Running   0             40m
edgeservice-66577bb846-vl8fs   1/1     Running   0             4h54m
```

nginx服务状态

```
[root@draven ~]# kubectl get pod -n demo-project -o wide
NAME                   READY  STATUS   RESTARTS AGE  IP         NODE        NOMINATED NODE   READINESS GATES
nginx-67b5bdb44-74skq  1/1    Running  0        52m  172.17.0.3 node1       <none>           <none>
nginx-raspberrypi-xxx  1/1    Running  0        10m  172.17.0.2 raspberrypi <none>           <none>
```

```
[root@draven ~]# kubectl get svc -n demo-project -o wide
NAME                TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE     SELECTOR
nginx               NodePort   10.233.7.95     <none>        80:31180/TCP   54m     app=nginx
nginx-raspberrypi   NodePort   10.233.62.229   <none>        80:31280/TCP   15m     app=nginx-raspberrypi
```

测试公网访问nginx

```
[root@draven ~]# curl http://47.100.220.146:31180
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
```

```
[root@draven ~]# curl http://47.100.220.146:31280
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
```

可得结论，边缘节点已经成功使用kubeedge开放公网服务

### 卸载KubeEdge

##### 卸载KubeEdge（EdgeCore）【边缘节点】

一定要先执行reset，否则会残留证书问题

```
[root@node1 ~]# ./keadm reset
```

```
[root@node1 ~]# ./keadm reset --force  #不行的时候再用
```

```
[root@node1 ~]# yum remove -y mosquitto
```

删除相关文件

```
[root@node1 ~]# rm -rf /etc/systemd/system/edgecore.service
[root@node1 ~]# rm -rf /usr/lib/systemd/system/edgecore.service
[root@node1 ~]# rm -rf /var/lib/kubeedge
[root@node1 ~]# rm -rf /var/lib/edged
[root@node1 ~]# rm -rf /etc/kubeedge
```

##### 卸载KubeEdge（CloudCore）【中控节点】

运行以下命令从集群中移除边缘节点：

```
[root@draven ~]# kubectl delete node <edgenode-name>
```

如需从集群中卸载 KubeEdge，运行以下命令：

```
[root@draven ~]# helm uninstall edgemesh -n kubeedge
[root@draven ~]# helm uninstall kubeedge -n kubeedge
[root@draven ~]# kubectl delete ns kubeedge
```

### 参考文献

部署参考：https://kubesphere.io/zh/docs/v3.3/pluggable-components/kubeedge/

部署参考：https://kubesphere.io/zh/docs/v3.3/installing-on-linux/cluster-operation/add-edge-nodes/

部署参考：https://www.cnblogs.com/kubesphere/p/17045662.html

排错参考：https://kubesphere.io/forum/d/4362-kubeedge

排错参考：https://zhuanlan.zhihu.com/p/585749690
