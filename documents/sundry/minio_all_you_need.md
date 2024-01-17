# minio运维小全

## 一、安装

### 单节点多硬盘部署

1.获取并安装rpm

`wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio-20240113075303.0.0-1.x86_64.rpm -O minio.rpm`

`rpm -ivh minio.rpm`

2.修改配置

`vim /etc/default/minio`

```
# MINIO_ROOT_USER and MINIO_ROOT_PASSWORD sets the root account for the MinIO server.
# This user has unrestricted permissions to perform S3 and administrative API operations on any resource in the deployment.
# Omit to use the default values 'minioadmin:minioadmin'.
# MinIO recommends setting non-default values as a best practice, regardless of environment

MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="xxxx"

# MINIO_VOLUMES sets the storage volume or path to use for the MinIO server.

MINIO_VOLUMES="/data{1...4}/minio"

# MINIO_SERVER_URL sets the hostname of the local machine for use with the MinIO Server
# MinIO assumes your network control plane can correctly resolve this hostname to the local machine

# Uncomment the following line and replace the value with the correct hostname for the local machine and port for the MinIO server (9000 by default).

MINIO_SERVER_URL="http://localhost:9000"

MINIO_OPTS="--address 0.0.0.0:9000"
```

3.查看systemd注册内容（一般无需修改）

`vim /usr/lib/systemd/system/minio.service`

4.启动minio服务

`systemctl start minio.service`

`systemctl enable minio.service`


## 二、参考文献

[minio中文文档](https://www.minio.org.cn/docs/minio/linux/operations/install-deploy-manage/deploy-minio-single-node-multi-drive.html)