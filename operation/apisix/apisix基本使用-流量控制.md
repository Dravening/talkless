# apisix流量控制

### 概述

Apache APISIX 是一个动态、实时、高性能的云原生 API 网关。[官方文档](https://apisix.apache.org/zh/docs/apisix/getting-started/README/)

我们用apisix能做什么？灰度发布、蓝绿发布、api网关泳道、[API 货币化](https://www.apiseven.com/blog/api-monetization-with-chatgpt)

总的来说，k8s原有的ingress并不能支持细粒度的api控制；基于这个原因，产生了多种开源的api网关方案，我们选择了其中的apisix。[为什么 Apache APISIX 是最好的 API 网关？](https://www.apiseven.com/blog/why-is-apache-apisix-the-best-api-gateway)

本文主要讲解如何使用apisix搭建灰度发布流程。

### 部署apisix

helm部署

```
helm repo add apisix https://charts.apiseven.com
helm repo update
helm install apisix apisix/apisix   --set gateway.type=NodePort   --set ingress-controller.enabled=true   --namespace ingress-apisix   --set ingress-controller.config.apisix.serviceNamespace=ingress-apisix --set dashboard.enabled=true
```

> 注意：此安装方案没有支持服务发现功能。如需要使用服务发现，请自行修改helm-chart

以下是部署后的资源状态，请按需开启svc的nodeport

```
[root@k8s-master apisix]# helm list -n ingress-apisix
NAME    NAMESPACE       REVISION  UPDATED                                 STATUS   CHART         APP VERSION
apisix  ingress-apisix  4         2023-06-30 16:38:48.110243411 +0800 CST deployed apisix-2.0.0  3.3.0 
```

```
[root@k8s-master apisix]# kubectl get svc -n ingress-apisix
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
apisix-admin                ClusterIP   10.96.103.52    <none>        9180/TCP            3d2h
apisix-dashboard            NodePort    10.96.203.30    <none>        80:32080/TCP        3d2h
apisix-etcd                 ClusterIP   10.96.199.28    <none>        2379/TCP,2380/TCP   3d2h
apisix-etcd-headless        ClusterIP   None            <none>        2379/TCP,2380/TCP   3d2h
apisix-gateway              NodePort    10.96.206.230   <none>        80:30080/TCP        3d2h
apisix-ingress-controller   ClusterIP   10.96.235.189   <none>        80/TCP              3d2h
```

验证部署状态
浏览器访问apisix-dashboard的nodeport端口（10.206.73.143:32080），出现页面则部署成功

### 部署测试应用

本次测试应用使用nginx，部署两个deployment，分别代表dev分支和master分支。

```
[root@k8s-master apisix]# cat nginx-podinfo-dev.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx-podinfo-dev
  name: nginx-podinfo-dev
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-podinfo-dev
  template:
    metadata:
      name: nginx-podinfo-dev
      labels:
        app: nginx-podinfo-dev
    spec:
      containers:
        - name: nginx
          image: nginx:1.8
          ports:
            - name: web
              containerPort: 80
              protocol: TCP
          volumeMounts:
            - name: workdir
              mountPath: /usr/share/nginx/html
      initContainers:
        - name: install
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          image: busybox
          command:
            - sh
            - -c
            - echo "POD_NAME:${POD_NAME} POD_IP:${POD_IP} branch:dev" > /work-dir/index.html
          volumeMounts:
            - name: workdir
              mountPath: "/work-dir"
      volumes:
        - name: workdir
          emptyDir: {}

---
kind: Service
apiVersion: v1
metadata:
  name: nginx-podinfo-dev
  namespace: default
spec:
  ports:
    - name: web
      protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: nginx-podinfo-dev
  type: ClusterIP
```

```
[root@k8s-master apisix]# cat nginx-podinfo-master.yaml 
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx-podinfo-master
  name: nginx-podinfo-master
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-podinfo-master
  template:
    metadata:
      name: nginx-podinfo-master
      labels:
        app: nginx-podinfo-master
    spec:
      containers:
        - name: nginx
          image: nginx:1.8
          ports:
            - name: web
              containerPort: 80
              protocol: TCP
          volumeMounts:
            - name: workdir
              mountPath: /usr/share/nginx/html
      initContainers:
        - name: install
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          image: busybox
          command:
            - sh
            - -c
            - echo "POD_NAME:${POD_NAME} POD_IP:${POD_IP} branch:master" > /work-dir/index.html
          volumeMounts:
            - name: workdir
              mountPath: "/work-dir"
      volumes:
        - name: workdir
          emptyDir: {}

---
kind: Service
apiVersion: v1
metadata:
  name: nginx-podinfo-master
  namespace: default
spec:
  ports:
    - name: web
      protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: nginx-podinfo-master
  type: ClusterIP
```

### 配置灰度发布

灰度发布需要使用[traffic-split](https://apisix.apache.org/zh/docs/apisix/plugins/traffic-split/)插件，无需安装，配置即可启用。

配置upstream

```
{
  "nodes": [{
      "host": "nginx-podinfo-master.default",
      "port": 80,
      "weight": 1
  }],
  "timeout": {
    "connect": 6,
    "send": 6,
    "read": 6
  },
  "type": "roundrobin",
  "scheme": "http",
  "pass_host": "pass",
  "name": "nginx-master",
  "keepalive_pool": {
    "idle_timeout": 60,
    "requests": 1000,
    "size": 320
  }
}
```

```
{
  "nodes": [{
    "host": "nginx-podinfo-dev.default",
    "port": 80,
    "weight": 1
  }],
  "timeout": {
    "connect": 6,
    "send": 6,
    "read": 6
  },
  "type": "roundrobin",
  "scheme": "http",
  "pass_host": "pass",
  "name": "nginx-dev",
  "keepalive_pool": {
    "idle_timeout": 60,
    "requests": 1000,
    "size": 320
  }
}
```

配置好upstream后，会生成upstream_id，如`467784917854454963`

接下来配置路由，在其中加入刚刚生成的upstream_id

```
{
  "uri": "/*",
  "name": "nginx-branch-service",
  "desc": "podinfo灰度发布",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "host": "nginx.cosmoplat-73.com",
  "plugins": {
    "traffic-split": {
      "_meta": {
        "disable": false
      },
      "rules": [
        {
          "weighted_upstreams": [
            {
              "upstream_id": "467785843201803443",
              "weight": 1
            },
            {
              "upstream_id": "467784917854454963",
              "weight": 1
            }
          ]
        }
      ]
    }
  },
  "upstream_id": "467784917854454963",
  "labels": {
    "API_VERSION": "v1"
  },
  "status": 1
}
```

路由配置好之后，配置本机的host

```
10.206.73.143  nginx.cosmoplat-73.com
```

访问浏览器进行验收

```
[root@k8s-master apisix]# curl http://nginx.cosmoplat-73.com
POD_NAME:nginx-podinfo-master-bd4964d4b-dsff2 POD_IP:10.244.235.226 branch:master
[root@k8s-master apisix]# curl http://nginx.cosmoplat-73.com
POD_NAME:nginx-podinfo-dev-7467b4d899-jtq66 POD_IP:10.244.235.233 branch:dev
```

### 配置蓝绿发布（api泳道）

##### 概念

<img data-original-src="//upload-images.jianshu.io/upload_images/21233906-efc4b857f69d96c9.png" data-original-width="1344" data-original-height="582" data-original-format="image/png" data-original-filesize="106394">

```undefined
泳道价值
价值：
1.硬件成本：比如部署3套测试环境，我们就能提供一套稳定的测试环境+2套分支测试环境，支持一个服务的2个需求同时测试。这意味着需要有3套完整的测试环境。在泳道环境下，只有和被测需求相关的调用链上的服务才需要在泳道中额外部署，大部分服务不需要额外部署。而且需求测试完成后，泳道可以被回收。因而增加的成本较部署完整的测试环境要少的多。
2.运营成本：多套环境中运行的服务和依赖的数据是需要维护的。特别是数据，多套环境中的数据维护成本是巨大的。

优势：
1.并行测试。（因此可以根据测试需要，部署不同分支的服务分组，多个泳道并行，多个服务/多个版本可同时提测）
2.提供稳定的骨干链路。（保证整个测试流程始终能正常运行）
3.错误隔离。（泳道内的服务发生异常，不会影响其他泳道）
```

> 总结：对于微服务场景，在基本不增加成本的前提下，满足并行测试的需求；

```
泳道搭建关键点
1.流量路由机制
2.环境管理【需要有一个面板，看到整个系统中存在哪几个泳道，哪个泳道下有哪几个服务】
3.资源回收【要设置合理的回收机制，否则忘记释放资源将导致极大的浪费，某团是每次申请给一个固定时间，到期自动删除，可以按需续期】
4.底层存储是否需要隔离，比如mysql，redis等，一般场景下是不需要隔离的
```

> 总结：apisix可以处理流量路由机制，环境管理待调研（dashboard），资源回收方案待确定

##### 开始配置蓝绿发布

```
{
  "uri": "/*",
  "name": "nginx-podinfo-bluegreen",
  "desc": "podinfo蓝绿发布",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "host": "nginx.cosmoplat-73.com",
  "plugins": {
    "traffic-split": {
      "_meta": {
        "disable": false
      },
      "rules": [
        {
          "match": [
            {
              "vars": [
                [
                  "http_release",
                  "==",
                  "dev"
                ]
              ]
            }
          ],
          "weighted_upstreams": [
            {
              "upstream_id": "467785843201803443"
            }
          ]
        }
      ]
    }
  },
  "upstream_id": "467784917854454963",
  "labels": {
    "API_VERSION": "v1"
  },
  "status": 1
}
```

```
[root@k8s-master apisix]# curl -H "release:dev" http://nginx.cosmoplat-73.com
POD_NAME:nginx-podinfo-dev-7467b4d899-qctxb POD_IP:10.244.235.234 branch:dev
```

```
[root@k8s-master apisix]# curl http://nginx.cosmoplat-73.com
POD_NAME:nginx-podinfo-master-bd4964d4b-xwwrn POD_IP:10.244.235.225 branch:master
```

### 配置监控

##### 配置request-id

以蓝绿发布路由为例，在其基础上增加request-id

```
{
  "uri": "/*",
  "name": "nginx-podinfo-bluegreen",
  "desc": "podinfo蓝绿发布",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "host": "nginx.cosmoplat-73.com",
  "plugins": {
    "request-id": {
      "_meta": {
        "disable": false
      }
    },
    "traffic-split": {
      "_meta": {
        "disable": false
      },
      "rules": [
        {
          "match": [
            {
              "vars": [
                [
                  "http_release",
                  "==",
                  "dev"
                ]
              ]
            }
          ],
          "weighted_upstreams": [
            {
              "upstream_id": "467785843201803443"
            }
          ]
        }
      ]
    }
  },
  "upstream_id": "467784917854454963",
  "labels": {
    "API_VERSION": "v1"
  },
  "status": 1
}
```

