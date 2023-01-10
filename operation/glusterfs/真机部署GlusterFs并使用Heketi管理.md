# 真机部署GlusterFs并使用Heketi管理

[GlusterFS](https://kubernetes.io/zh/docs/concepts/storage/volumes/#glusterfs) 是开源的分布式文件系统，您能使用 GlusterFS 将 `glusterfs` 存储卷挂载到 Pod。如果 `glusterfs` 存储卷中预先填充了数据，则可以在 Kubernetes 集群中的 Pod 之间共享这些数据。

本教程演示了如何在三台服务器机器上配置 GlusterFS 以及如何安装 [Heketi](https://github.com/heketi/heketi) 来管理 GlusterFS 集群。

> 注意：GlusterFS至少要三个节点才能正常使用，切记不要骗自己

| 主机名 | IP 地址       | 操作系统                    | 设备           |
| :----- | :------------ | :-------------------------- | :------------- |
| cos-1  | 192.168.0.89  | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 20 GB |
| cos-2  | 192.168.0.210 | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 20 GB |
| cos-3  | 192.168.0.247 | CentOS 7.9，2 核，4 GB 内存 | /dev/vdb 20 GB |

#### 前置安装

1.确定hostname是符合预期的

```
[root@cos-1 ~]# hostnamectl set-hostname cos-1
```

```
[root@cos-2 ~]# hostnamectl set-hostname cos-2
```

```
[root@cos-3 ~]# hostnamectl set-hostname cos-3
```

2.填写各节点的host解析（所有节点）

```
[root@cos-1 ~]# cat /etc/hosts
::1     localhost       localhost.localdomain   localhost6      localhost6.localdomain6
127.0.0.1       localhost       localhost.localdomain   localhost4      localhost4.localdomain4
192.168.0.89 cos-1
192.168.0.210 cos-2
192.168.0.247 cos-3
```

3.确定ntp时间同步正常（略）

### 部署GlusterFs

4.安装glusterfs（所有节点）

```
[root@cos-1 ~]# yum update -y
```

```
[root@cos-1 ~]# yum install centos-release-gluster -y
```

```
[root@cos-1 ~]# yum install glusterfs-server -y
```

确定安装结果

```
[root@cos-1 ~]# glusterfs -V
glusterfs 9.6
Repository revision: git://git.gluster.org/glusterfs.git
Copyright (c) 2006-2016 Red Hat, Inc. <https://www.gluster.org/>
GlusterFS comes with ABSOLUTELY NO WARRANTY.
It is licensed to you under your choice of the GNU Lesser
General Public License, version 3 or any later version (LGPLv3
or later), or the GNU General Public License, version 2 (GPLv2),
in all cases as published by the Free Software Foundation.
```

5.加载必要的内核模块（所有节点）

```
[root@cos-1 ~]# modprobe dm_snapshot
```

```
[root@cos-1 ~]# modprobe dm_mirror
```

```
[root@cos-1 ~]# modprobe dm_thin_pool
```

查看结果

```
[root@cos-1 ~]# lsmod | grep dm_snapshot
dm_snapshot            43699  0
dm_bufio               28014  2 dm_persistent_data,dm_snapshot
dm_mod                124501  5 dm_log,dm_mirror,dm_bufio,dm_thin_pool,dm_snapshot
```

```
[root@cos-1 ~]# lsmod | grep dm_mirror
dm_mirror              22326  0
dm_region_hash         20813  1 dm_mirror
dm_log                 18411  2 dm_region_hash,dm_mirror
dm_mod                124501  5 dm_log,dm_mirror,dm_bufio,dm_thin_pool,dm_snapshot
```

```
[root@cos-1 ~]# lsmod | grep dm_thin_pool
dm_thin_pool           70389  0
dm_persistent_data     75275  1 dm_thin_pool
dm_bio_prison          18209  1 dm_thin_pool
dm_mod                124501  5 dm_log,dm_mirror,dm_bufio,dm_thin_pool,dm_snapshot
```

6.启动glusterfs（所有节点）

```
[root@cos-1 ~]# systemctl start glusterd.service
```

```
[root@cos-1 ~]# systemctl status glusterd.service
```

```
[root@cos-1 ~]# systemctl enable glusterd.service
```

7.加入节点

```
[root@cos-1 ~]# gluster peer probe cos-2
peer probe: success
```

```
[root@cos-1 ~]# gluster peer probe cos-3
peer probe: success
```

检查执行结果

```
[root@cos-1 ~]# gluster peer status
Number of Peers: 2

Hostname: cos-2
Uuid: 23f72798-69c5-4620-981e-4e70aed67427
State: Peer in Cluster (Connected)

Hostname: cos-3
Uuid: 647b7863-5e65-4b47-8936-72457b789f53
State: Peer in Cluster (Connected)
```

### 部署Heketi

8.下载并安装heketi

本次部署，笔者使用了目前最新版heketi:10.4.0

```
[root@cos-1 ~]# wget https://github.com/heketi/heketi/releases/download/v10.4.0/heketi-v10.4.0-release-10.linux.amd64.tar.gz
```

```
[root@cos-1 ~]# tar -xf heketi-v7.0.0.linux.amd64.tar.gz
[root@cos-1 ~]# cd heketi
[root@cos-1 heketi]# cp heketi /usr/bin
[root@cos-1 heketi]# cp heketi-cli /usr/bin
[root@cos-1 heketi]# mkdir -p /var/lib/heketi
[root@cos-1 heketi]# mkdir -p /etc/heketi
```

9.创建 Heketi 服务文件

```
[root@cos-1 heketi]# cat >> /lib/systemd/system/heketi.service << EOF
[Unit]
Description=Heketi Server
[Service]
Type=simple
WorkingDirectory=/var/lib/heketi
ExecStart=/usr/bin/heketi --config=/etc/heketi/heketi.json
Restart=on-failure
StandardOutput=syslog
StandardError=syslog
[Install]
WantedBy=multi-user.target
EOF
```

10.创建 Heketi 的配置文件heketi.json

```
[root@cos-1 heketi]# cat >> /etc/heketi/heketi.json << EOF
{
  "_port_comment": "Heketi Server Port Number",
  "port": "8080",

  "_use_auth": "Enable JWT authorization. Please enable for deployment",
  "use_auth": false,

  "_jwt": "Private keys for access",
  "jwt": {
    "_admin": "Admin has access to all APIs",
    "admin": {
      "key": "123456"
    },
    "_user": "User only has access to /volumes endpoint",
    "user": {
      "key": "123456"
    }
  },

  "_glusterfs_comment": "GlusterFS Configuration",
  "glusterfs": {
    "_executor_comment": [
      "Execute plugin. Possible choices: mock, ssh",
      "mock: This setting is used for testing and development.",
      "      It will not send commands to any node.",
      "ssh:  This setting will notify Heketi to ssh to the nodes.",
      "      It will need the values in sshexec to be configured.",
      "kubernetes: Communicate with GlusterFS containers over",
      "            Kubernetes exec api."
    ],

    "executor": "ssh",
    "_sshexec_comment": "SSH username and private key file information",
    "sshexec": {
      "keyfile": "/root/.ssh/id_rsa",
      "user": "root"
    },

    "_kubeexec_comment": "Kubernetes configuration",
    "kubeexec": {
      "host" :"https://kubernetes.host:8443",
      "cert" : "/path/to/crt.file",
      "insecure": false,
      "user": "kubernetes username",
      "password": "password for kubernetes user",
      "namespace": "Kubernetes namespace",
      "fstab": "Optional: Specify fstab file on node.  Default is /etc/fstab"
    },

    "_db_comment": "Database file name",
    "db": "/var/lib/heketi/heketi.db",
    "brick_max_size_gb" : 1024,
    "brick_min_size_gb" : 1,
    "max_bricks_per_volume" : 33,

    "_loglevel_comment": [
      "Set log level. Choices are:",
      "  none, critical, error, warning, info, debug",
      "Default is warning"
    ],
    "loglevel" : "debug"
  }
}
EOF
```

11.启动heketi

```
[root@cos-1 heketi]# systemctl start heketi
[root@cos-1 heketi]# systemctl status heketi
[root@cos-1 heketi]# systemctl enable heketi
```

12.为 Heketi 创建拓扑配置文件，该文件包含添加到 Heketi 的集群、节点和磁盘的信息。

```
[root@cos-1 heketi]# cat >> /etc/heketi/topology.json << EOF
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                  "cos-1"
              ],
              "storage": [
                  "192.168.0.89"
              ]
            },
            "zone": 1
          },
          "devices": [
              "/dev/vdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                  "cos-2"
              ],
              "storage": [
                  "192.168.0.210"
              ]
            },
            "zone": 1
          },
          "devices": [
              "/dev/vdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                  "cos-3"
              ],
              "storage": [
                  "192.168.0.247"
              ]
            },
            "zone": 1
          },
          "devices": [
              "/dev/vdb"
          ]
        }
      ]
    }
  ]
}
EOF
```

13.加载 Heketi JSON 文件，创建glusterfs集群

```
[root@cosmo-1 heketi]# export HEKETI_CLI_SERVER=http://192.168.0.89:8080
```

```
[root@cosmo-1 heketi]# export HEKETI_CLI_USER=admin
```

```
[root@cosmo-1 heketi]# export HEKETI_CLI_KEY=123456
```

```
[root@cosmo-1 heketi]# heketi-cli topology load --json=/etc/heketi/topology.json --user admin --secret 123456
Creating cluster ... ID: 2cc5c45ded7672c490b7014e8c683f8c
        Allowing file volumes on cluster.
        Allowing block volumes on cluster.
        Creating node 192.168.0.215 ... ID: 24b8ca6752ae02b3b1add687c682d268
                Adding device /dev/vdb ... OK
        Creating node 192.168.0.50 ... ID: 4193119f0e297cbdda985079ab8a6c4d
                Adding device /dev/vdb ... OK
```

检查集群创建结果

```
[root@cos-1 heketi]# heketi-cli topology info --user admin --secret 123456
```

```
[root@cos-1 heketi]# heketi-cli cluster list
Clusters:
Id:65e9887f72856eee2edb604374426c83 [file][block]
```

### 验证部署结果

14.手动测试集群情况

> 笔者遇到过，集群状态正常但其实并不可用的情况（报错no space）；
>
> 所以务必手动测试集群情况

手动创建一个大小为1G的volume

```
[root@cos-1 heketi]# heketi-cli volume create --size=1 --clusters=65e9887f72856eee2edb604374426c83
Name: vol_4ea09df42037a9c61355a7df7e38c82b
Size: 1
Volume Id: 4ea09df42037a9c61355a7df7e38c82b
Cluster Id: 65e9887f72856eee2edb604374426c83
Mount: 192.168.0.247:vol_4ea09df42037a9c61355a7df7e38c82b
Mount Options: backup-volfile-servers=192.168.0.89,192.168.0.210
Block: false
Free Size: 0
Reserved Size: 0
Block Hosting Restriction: (none)
Block Volumes: []
Durability Type: replicate
Distribute Count: 1
Replica Count: 3
```

```
[root@cos-1 heketi]# lsblk
NAME                                                                              MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
vda                                                                               253:0    0  40G  0 disk
└─vda1                                                                            253:1    0  40G  0 part /
vdb                                                                               253:16   0  20G  0 disk
├─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b_tmeta   252:0    0   8M  0 lvm
│ └─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b-tpool 252:2    0   1G  0 lvm
│   ├─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b     252:3    0   1G  1 lvm
│   └─vg_74c481bd897a8ddf3a3f56da41d1c19a-brick_6ee2ffe13261c1296dc99a3876532a7b  252:4    0   1G  0 lvm  /var/lib/heketi/mounts/vg_74c481bd897a8ddf3a3f56da41d1c19a/brick_6
└─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b_tdata   252:1    0   1G  0 lvm
  └─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b-tpool 252:2    0   1G  0 lvm
    ├─vg_74c481bd897a8ddf3a3f56da41d1c19a-tp_6ee2ffe13261c1296dc99a3876532a7b     252:3    0   1G  1 lvm
    └─vg_74c481bd897a8ddf3a3f56da41d1c19a-brick_6ee2ffe13261c1296dc99a3876532a7b  252:4    0   1G  0 lvm  /var/lib/heketi/mounts/vg_74c481bd897a8ddf3a3f56da41d1c19a/brick_6
```

```
[root@cos-1 heketi]# gluster volume info
Volume Name: vol_4ea09df42037a9c61355a7df7e38c82b
Type: Replicate
Volume ID: f2272cd8-3c2c-4a6e-a0d7-b0dc34ea594a
Status: Started
Snapshot Count: 0
Number of Bricks: 1 x 3 = 3
Transport-type: tcp
Bricks:
Brick1: 192.168.0.210:/var/lib/heketi/mounts/vg_8edd4df2fa839919336b59833587226a/brick_8d2ddd84e063df86e566de3a24484134/brick
Brick2: 192.168.0.89:/var/lib/heketi/mounts/vg_74c481bd897a8ddf3a3f56da41d1c19a/brick_6ee2ffe13261c1296dc99a3876532a7b/brick
Brick3: 192.168.0.247:/var/lib/heketi/mounts/vg_0d097bc84a9deb1f5d42f779fcc04ead/brick_6776ffecaf71ae1d6285c1fa9302b5b5/brick
Options Reconfigured:
user.heketi.id: 4ea09df42037a9c61355a7df7e38c82b
cluster.granular-entry-heal: on
storage.fips-mode-rchecksum: on
transport.address-family: inet
nfs.disable: on
performance.client-io-threads: off
```

```
[root@cos-1 heketi]# gluster volume status
Status of volume: vol_4ea09df42037a9c61355a7df7e38c82b
Gluster process                             TCP Port  RDMA Port  Online  Pid
------------------------------------------------------------------------------
Brick 192.168.0.210:/var/lib/heketi/mounts/
vg_8edd4df2fa839919336b59833587226a/brick_8
d2ddd84e063df86e566de3a24484134/brick       49152     0          Y       2667
Brick 192.168.0.89:/var/lib/heketi/mounts/v
g_74c481bd897a8ddf3a3f56da41d1c19a/brick_6e
e2ffe13261c1296dc99a3876532a7b/brick        49152     0          Y       2986
Brick 192.168.0.247:/var/lib/heketi/mounts/
vg_0d097bc84a9deb1f5d42f779fcc04ead/brick_6
776ffecaf71ae1d6285c1fa9302b5b5/brick       49152     0          Y       2697
Self-heal Daemon on localhost               N/A       N/A        Y       3003
Self-heal Daemon on cos-3                   N/A       N/A        Y       2714
Self-heal Daemon on cos-2                   N/A       N/A        Y       2684

Task Status of Volume vol_4ea09df42037a9c61355a7df7e38c82b
------------------------------------------------------------------------------
There are no active volume tasks
```

遍历volume

```
[root@cos-1 heketi]# heketi-cli volume list
Id:4ea09df42037a9c61355a7df7e38c82b    Cluster:65e9887f72856eee2edb604374426c83    Name:vol_4ea09df42037a9c61355a7df7e38c82b
```

停止volume vol_4ea09df42037a9c61355a7df7e38c82b

```
[root@cos-1 heketi]# gluster volume stop vol_4ea09df42037a9c61355a7df7e38c82b
Stopping volume will make its data inaccessible. Do you want to continue? (y/n) y
volume stop: vol_4ea09df42037a9c61355a7df7e38c82b: success
```

查询volume状态

```
[root@cos-1 heketi]# gluster volume status
Volume vol_4ea09df42037a9c61355a7df7e38c82b is not started
```

启动volume vol_4ea09df42037a9c61355a7df7e38c82b

```
[root@cos-1 heketi]# gluster volume start vol_4ea09df42037a9c61355a7df7e38c82b
volume start: vol_4ea09df42037a9c61355a7df7e38c82b: success
```

删除volume 4ea09df42037a9c61355a7df7e38c82b

```
[root@cos-1 heketi]# heketi-cli volume delete 4ea09df42037a9c61355a7df7e38c82b
Volume 4ea09df42037a9c61355a7df7e38c82b deleted
```

