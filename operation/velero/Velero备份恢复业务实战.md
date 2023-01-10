# Velero备份恢复业务实战

### 安装

本章分为”前置安装“、”开始测试”、“卸载velero”、“总结”四部分。

#### 前置安装（client安装）

1.第一步先下载zip包，获得velero执行文件（client）。

```shell
wget https://github.com/vmware-tanzu/velero/releases/download/v1.10.0/velero-v1.10.0-linux-amd64.tar.gz
```

2.解压velero

```shell
tar zxvf velero-v1.10.0-linux-amd64.tar.gz 
```

```shell
cp velero /usr/local/bin/
```

3.安装minio,记得初始化bucket   velero（这一步可以直接去kubesphere装一个）

```shell
helm repo add minio https://helm.min.io/
```

```shell
helm install --set accessKey=YOURACCRESSKEY,secretKey=YOURSECRETKEY,mode=standalone,service.type=NodePort,persistence.size=500Gi,resources.requests.memory=4Gi,defaultBuckets="velero" -name minio minio/minio
```

4.写凭证，注意修改minio的密码

```shell
cat > ./velero-v1.10.0-linux-amd64/credentials-velero << EOF
[default]
aws_access_key_id = YOURACCRESSKEY
aws_secret_access_key = YOURSECRETKEY
EOF
```

5.准备一个velero-test环境

![mysql-studio-status1](http://rmm81kt1m.bkt.clouddn.com/mysql-studio-status1.png)

### 开始测试

6.启动velero(重复执行仅会刷新velero deployment)

```shell
./velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.2.1 \
    --bucket velero \
    --namespace velero  \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --use-restic \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://10.206.68.5:30421 \
    #--use-node-agent
    #这个操作是针对fsb的，不能用--default-volumes-to-fs-backup \
```

7.使用备份命令，创建一个名为velero-backup-pv的备份

```shell
velero backup create velero-backup-pv --include-namespaces velero-test --default-volumes-to-restic
```

使用`velero backup describe velero-backup-pv`检查一下备份情况

![image-20221223111814924](http://rmm81kt1m.bkt.clouddn.com/image-20221223111814924.png)

检查一下minio情况

![image-20221229154823813](http://rmm81kt1m.bkt.clouddn.com/image-20221229154823813.png)

8.删除velero-test

```shell
kubectl delete namespaces velero-test
```

![image-20221223113715784](http://rmm81kt1m.bkt.clouddn.com/image-20221223113715784.png)

9.恢复velero-test

```shell
./velero restore create --from-backup velero-backup-pv
```

![](http://rmm81kt1m.bkt.clouddn.com/image-20221223121457211.png)

![image-20221223121928740](http://rmm81kt1m.bkt.clouddn.com/image-20221223121928740.png)

![image-20221229160747295](http://rmm81kt1m.bkt.clouddn.com/image-20221229160747295.png)

![image-20221229140459634](http://rmm81kt1m.bkt.clouddn.com/image-20221229140459634.png)

#### 卸载velero

1.卸载

```
velero backup describe velero-backup-pv --details
velero restore delete  velero-backup-pv
```

```shell
kubectl delete clusterrolebinding/velero
kubectl delete crds -l component=velero
kubectl delete namespace/velero
```

### 总结

使用1.6.2版本的velero可以正常使用备份恢复功能。

1.使用velero恢复后，pod ID和docker ID是否有变化？

答：pod ID无变化，docker ID有变化（容器级别是重新创建的）

![image-20221229182115133](http://rmm81kt1m.bkt.clouddn.com/image-20221229182115133.png)

2.如果尝试恢复一个现在已经存在的资源，会发生什么？

答：执行命令会成功，但不会有实际动作（所以如果要回退节点的话，需要删除当前资源）

![image-20221229182535082](http://rmm81kt1m.bkt.clouddn.com/image-20221229182535082.png)

3.如果尝试恢复的资源中，有一部分已经存在，会发生什么？

答：会恢复不存在的部分，已存在的部分不会有实际动作。

