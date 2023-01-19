# 使用loop语句虚拟块设备

### 什么是loop设备

loop设备是类Unix系统中的一种伪设备，是一种使文件可以模拟为块设备(也称块特殊文件)来访问的技术。

在使用loop设备前，先要将其与需要模拟的文件进行链接，这种链接提供了一系列API使文件可以像块设备一样被用户使用，对这个loop设备的所有读写操作都将被重定向到文件所在的实际磁盘空间进行读写。

### 使用loop设备做什么

> 笔者在测试GlusterFS功能的时候，由于某些原因，没有额外的块设备（磁盘），故使用loop设备的方式当作块设备

一般情况下，使用loop设备的原因如下

##### 1.用于离线管理和编辑系统映像文件

对于.iso格式这样的镜像文件，我们在Linux系统中是无法直接打开读取其中的文件的，那么我们可以通过loop设备将文件映射为一个特殊的块设备，然后再将这个块设备挂载到系统的某个目录下，这样我们就可以通过通常的文件系统接口正常访问其中的文件了。

当然，这个操作的前提是文件要包含一个Linux可识别的文件系统，否则也无法正常访问，比如.iso文件一般包含 iso 9660 文件系统，这是一种CD上用的文件系统，linux是可以识别的。

##### 2.快捷安装操作系统

在loop设备上映射一个包含文件系统的空文件，然后就可以在这个虚拟块设备上安装操作系统，而无需对磁盘进行重新分区。

##### 3.提供数据的隔离

loop设备还提供了数据的永久隔离，例如，在更快更方便的硬盘上模拟可移动媒体或封装加密的文件系统时。

### loop设备使用实践

1.如下命令创建了一个1G大小的文件loopfile.img，其内容全为空字符

```
dd if=/dev/zero of=~/loopfile.img bs=1G count=1
```

> 其中/dev/zero是“零”设备，可以无限的提供空字符，常用来生成一个特定大小的文件。

如果需要虚拟超过2G的大文件，请增加count的数量

```
dd if=/dev/zero of=~/loopfile.img bs=2G count=30
```

2.将文件映射为loop设备

先查询现有情况，避免冲突

```
losetup -a # 查看所有在运行的loop设备，若无输出则说明系统中还没有文件映射被为loop设备
```

```
losetup -f # 可以查看loop文件
```

```
ls /dev | grep loop0
```

如无冲突，创建/dev/loop0设备

```
losetup /dev/loop0 ~/loopfile.img
```

3.挂载

> 此步骤笔者没有操作，因为使用heketi管理glusterfs不需要手动挂载磁盘

```
mount /dev/loop0 /mnt/loop_test_dir/
```

取消挂载

```
umount /dev/loop0
```

卸载loop设备

```
losetup -d /dev/loop0
```

### 测试性能

> 笔者使用loop设备作为GlusterFS的块设备，性能很差

创建一个1G的volume，大概花费20s左右

```
[root@test-master ~]# heketi-cli volume create --size=1 --clusters=bfd030873b8758526672131c910ac60d
Name: vol_e04e6bb1cd0e140f4d33c64a162d8a37
Size: 1
Volume Id: e04e6bb1cd0e140f4d33c64a162d8a37
Cluster Id: bfd030873b8758526672131c910ac60d
Mount: 10.206.73.137:vol_e04e6bb1cd0e140f4d33c64a162d8a37
Mount Options: backup-volfile-servers=10.206.73.138,10.206.73.143
Block: false
Free Size: 0
Reserved Size: 0
Block Hosting Restriction: (none)
Block Volumes: []
Durability Type: replicate
Distribute Count: 1
Replica Count: 3
```

删除这个volume：`e04e6bb1cd0e140f4d33c64a162d8a37`花费大概4min

```
[root@test-master ~]# heketi-cli volume delete e04e6bb1cd0e140f4d33c64a162d8a37
Volume e04e6bb1cd0e140f4d33c64a162d8a37 deleted
```

使用k8s创建一个1G的pvc（即动态创建一个pv），基本花费33s      

```
[root@test-master draven]# kubectl get pvc -A
NAMESPACE    NAME            STATUS   VOLUME                   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
XXXXX        glusterfs-test1 Pending                                                     glusterfs      32s
```

```
[root@test-master draven]# kubectl get pvc -A
NAMESPACE    NAME            STATUS   VOLUME                   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
XXXXX        glusterfs-test1 Bound                                                       glusterfs      34s
```

使用k8s删除一个1G的pvc（即动态删除一个pv），基本花费4min

```
[root@test-master draven]# date
Fri Jan 13 18:17:49 CST 2023

[root@test-master draven]# kubectl delete -n iotplat-tsdb pvc glusterfs-test1
persistentvolumeclaim "glusterfs-test1" deleted

[root@test-master draven]# kubectl get pv | grep Released
pvc-f0b6397a-8c03-4cd5-8afa-4b0c510d47bd   1Gi RWX  Delete    Released XXXXX/glusterfs-test1 glusterfs  49m

[root@test-master draven]# kubectl get pv | grep Released

[root@test-master draven]# date
Fri Jan 13 18:21:21 CST 2023
```

正常的pvc创建速度如下，基本就是2s

```
[root@cos-1 ~]# kubectl get pvc -A
NAMESPACE NAME               STATUS   VOLUME                  CAPACITY   ACCESS MODES   STORAGECLASS   AGE
default   glusterfs-pvc-test Pending                                                    glusterfs      1s

[root@cos-1 ~]# kubectl get pvc -A
NAMESPACE NAME               STATUS   VOLUME                  CAPACITY   ACCESS MODES   STORAGECLASS   AGE
default   glusterfs-pvc-test Bound    pvc-faf994.....         1Gi        RWX            glusterfs      3s
```

正常的pvc删除速度如下，基本1s内

```
[root@cos-1 ~]# date
Fri Jan 13 18:30:33 CST 2023

[root@cos-1 ~]# kubectl delete -f gluster-pvc-test.yaml
persistentvolumeclaim "glusterfs-pvc-test" deleted

[root@cos-1 ~]# kubectl get pv | grep released

[root@cos-1 ~]# date
Fri Jan 13 18:30:35 CST 2023
```

### 总结

loop设备虽然可以作为GlusterFS的存储设备使用，但性能极差，几乎无法使用