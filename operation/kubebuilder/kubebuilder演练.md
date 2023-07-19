# kubebuilder演练

本文参考https://zhuanlan.zhihu.com/p/386645764

### 一、前言

​		随着对k8s的使用逐步加深，企业期望可以将一些个性化的镜像及其部署流程在k8s上实现。k8s已经抽象出了CRD（custom resource definition）的概念；为实现此需求，我们需要实现并注册CRD对象，实现一个控制器，这部分工作在框架出现前，需要手动使用go-client进行编写，很复杂。

​		目前k8s已经基于这种“云原生”研发的需求，开发出了kubebuilder和operator-sdk两种框架（脚手架），简化了crd编程和operator开发的复杂度，让我们只关心控制器具体的业务逻辑就可。



### 二、步骤

1.下载kubebuilder

```
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH) && chmod +x kubebuilder && mv kubebuilder /usr/local/bin/
```

2.初始化一个项目

```
kubebuilder init --domain my.domain --repo my.domain/tutorial
```

3.创建api

```
kubebuilder create api --group batch --version v1 --kind Draven
```

4.初始化 WebhookConfiguration、ClusterRole 和 CustomResourceDefinition

```
make manifests
```

5.生成部署yaml

```
make docker-build docker-push IMG=registry.cn-hangzhou.aliyuncs.com/draven_yyz/kubebuilder-test:v1.0
```

```
cd config/manager && ./bin/kustomize edit set image controller=registry.cn-hangzhou.aliyuncs.com/draven_yyz/kubebuilder-test:v1.0
```

```
./bin/kustomize build config/default > demo.yaml
```

6.部署controller

```
kubectl apply -f demo.yaml
```

7.部署测试pod

```
kubectl apply -f test.yaml
```

