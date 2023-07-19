# prometheus-operator配置外部exporter

本文参考https://www.cnblogs.com/cndarren/p/17137233.html

### 一、前言

prometheus-operator中需要纳管外部的exporter，配置与常用prometheus不一致，特此记录

### 二、方案说明

##### 原计划

1.查找prometheus的配置文件，发现其被加密为prometheus.yaml.gz，无法直接修改。
2.使用命令取出配置
kubectl get secret -n d3os-monitoring-system  prometheus-k8s -o json | jq -r '.data."prometheus.yaml.gz"' | base64 -d | gzip -d > prometheus-k8s.yaml
3.修改后，base64 prometheus-k8s.yaml > prometheus-k8s.yaml.txt
4.kubectl edit secrets -n d3os-monitoring-system  prometheus-k8s，粘贴上去保存

##### 新计划

上述方案并不可行，因为prometheus-operator会刷新prometheus的配置；应当使用使用ServiceMonitor监控外部服务；并创建PrometheusRule配置普罗的监控指标
1.创建endpoints和service

```
cat >mysql-service-endpoint.yaml<EOF
---
apiVersion: v1
kind: Endpoints
metadata:
  name: mysql-exporter
  namespace: d3os-monitoring-system
  labels:
    app: mysql-exporter
    app.kubernetes.io/name: mysql-exporter
subsets:
- addresses:
  - ip: 10.206.68.2
  ports:
  - name: metrics
    port: 9104

---
apiVersion: v1
kind: Service
metadata:
  name: mysql-exporter
  namespace: d3os-monitoring-system
  labels:
    app: mysql-exporter
    app.kubernetes.io/name: mysql-exporter
spec:
  clusterIP: None
  ports:
  - name: metrics
    port: 9014
    protocol: TCP
    targetPort: 9014
EOF
```

2.创建ServiceMonitor

```
cat >mysql-servicemonitor.yaml<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mysql-exporter
  namespace: d3os-monitoring-system
  labels:
    app: mysql-exporter
spec:
  selector:
    matchLabels:
      app: mysql-exporter
  namespaceSelector:
    matchNames:
      - d3os-monitoring-system
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
      scheme: http
EOF
```

3.访问http://10.206.68.1:30581/targets查看，发现d3os-monitoring-system/mysql-exporter/0 (1/1 up)存在

4.配置rules

```
cat >mysql-export-rules.yaml<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    prometheus: k8s
    role: alert-rules
  name: mysql-rules
  namespace: d3os-monitoring-system
spec:
  groups:
    - name: mysql-alert
      rules:
        - alert: MysqlDownAlert
          annotations:
            summary: mysql down
            description: If one more mysql goes down the cluster will be unavailable
          expr: |
            mysql_up == 0
          for: 1m
          labels:
            severity: critical
```

