# apisix进阶使用-可观测性

### 概述

前文主要讲解了apisix的常用功能，以nginx-podinfo应用为例，实现其灰度发布和蓝绿发布功能

### 配置request-id

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

加入request-id之后，应用的内部就可以在request和response的header中获取到每次访问的X-Request-Id。

> 已测试data-space项目，业务容器中可以获取到X-Request-Id，这样可以在log中打出此唯一uuid，用来快速定位报错日志的链路

### 启用prometheus

配置文件默认没有启动apisix指标，我们修改values.yaml启用它

```
  prometheus:
    # ref: https://apisix.apache.org/docs/apisix/plugins/prometheus/
    enabled: true
    # -- path of the metrics endpoint
    path: /apisix/prometheus/metrics
    # -- prefix of the metrics
    metricPrefix: apisix_
    # -- container port where the metrics are exposed
    containerPort: 9091
```

此时集群中的prometheus并没有scrape收录这个监控指标，需要增加serviceMonitor（不推荐手动修改promethues target配置）

```
metrics:
  serviceMonitor:
    # -- Enable or disable Apache APISIX serviceMonitor
    enabled: true
    # -- namespace where the serviceMonitor is deployed, by default, it is the same as the namespace of the apisix
    namespace: ""
    # -- name of the serviceMonitor, by default, it is the same as the apisix fullname
    name: ""
    # -- interval at which metrics should be scraped
    interval: 15s
    # -- @param serviceMonitor.labels ServiceMonitor extra labels
    labels: {}
    # -- @param serviceMonitor.annotations ServiceMonitor annotations
    annotations: {}
```

执行helm更新

```
helm upgrade apisix apisix -n ingress-apisix
```

执行后可以发现新增了一个pod和svc

```
[root@k8s-master apisix]# kubectl get pods -n ingress-apisix
NAME                                        READY   STATUS    RESTARTS   AGE
apisix-6b4d5b76fb-l26xr                     1/1     Running   0          20m
apisix-dashboard-577b859b87-n8cvs           1/1     Running   4          4d5h
apisix-etcd-0                               1/1     Running   1          4d
apisix-etcd-1                               1/1     Running   1          4d
apisix-etcd-2                               1/1     Running   1          4d
apisix-ingress-controller-c8c55bf84-hdj9j   1/1     Running   0          4d5h
[root@k8s-master apisix]# kubectl get svc  -n ingress-apisix
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
apisix-admin                ClusterIP   10.96.103.52    <none>        9180/TCP            4d5h
apisix-dashboard            ClusterIP   10.96.203.30    <none>        80/TCP              4d5h
apisix-etcd                 ClusterIP   10.96.199.28    <none>        2379/TCP,2380/TCP   4d5h
apisix-etcd-headless        ClusterIP   None            <none>        2379/TCP,2380/TCP   4d5h
apisix-gateway              NodePort    10.96.206.230   <none>        80:30080/TCP        4d5h
apisix-ingress-controller   ClusterIP   10.96.235.189   <none>        80/TCP              4d5h
apisix-prometheus-metrics   ClusterIP   10.96.10.10     <none>        9091/TCP            21m
```

访问指标如下

```
[root@k8s-master apisix]# curl  http://10.96.10.10:9091/apisix/prometheus/metrics
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 444
apisix_etcd_modify_indexes{key="max_modify_index"} 446
apisix_etcd_modify_indexes{key="prev_index"} 459
apisix_etcd_modify_indexes{key="protos"} 0
apisix_etcd_modify_indexes{key="routes"} 446
apisix_etcd_modify_indexes{key="services"} 0
apisix_etcd_modify_indexes{key="ssls"} 0
apisix_etcd_modify_indexes{key="stream_routes"} 0
apisix_etcd_modify_indexes{key="upstreams"} 445
apisix_etcd_modify_indexes{key="x_etcd_index"} 461
# HELP apisix_etcd_reachable Config server etcd reachable from APISIX, 0 is unreachable
# TYPE apisix_etcd_reachable gauge
apisix_etcd_reachable 1
# HELP apisix_http_requests_total The total number of client requests since APISIX started
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 2632
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 2803
apisix_nginx_http_current_connections{state="active"} 100
apisix_nginx_http_current_connections{state="handled"} 2803
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 0
apisix_nginx_http_current_connections{state="writing"} 100
# HELP apisix_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE apisix_nginx_metric_errors_total counter
apisix_nginx_metric_errors_total 0
# HELP apisix_node_info Info of APISIX node
# TYPE apisix_node_info gauge
apisix_node_info{hostname="apisix-6b4d5b76fb-l26xr"} 1
# HELP apisix_shared_dict_capacity_bytes The capacity of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_capacity_bytes gauge
apisix_shared_dict_capacity_bytes{name="access-tokens"} 1048576
apisix_shared_dict_capacity_bytes{name="balancer-ewma"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-last-touched-at"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-locks"} 10485760
apisix_shared_dict_capacity_bytes{name="cas_sessions"} 10485760
apisix_shared_dict_capacity_bytes{name="discovery"} 1048576
apisix_shared_dict_capacity_bytes{name="etcd-cluster-health-check"} 10485760
apisix_shared_dict_capacity_bytes{name="ext-plugin"} 1048576
apisix_shared_dict_capacity_bytes{name="internal-status"} 10485760
apisix_shared_dict_capacity_bytes{name="introspection"} 10485760
apisix_shared_dict_capacity_bytes{name="jwks"} 1048576
apisix_shared_dict_capacity_bytes{name="kubernetes"} 1048576
apisix_shared_dict_capacity_bytes{name="lrucache-lock"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-api-breaker"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-conn"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-count"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-count-redis-cluster-slot-lock"} 1048576
apisix_shared_dict_capacity_bytes{name="plugin-limit-count-reset-header"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-req"} 10485760
apisix_shared_dict_capacity_bytes{name="prometheus-metrics"} 10485760
apisix_shared_dict_capacity_bytes{name="upstream-healthcheck"} 10485760
apisix_shared_dict_capacity_bytes{name="worker-events"} 10485760
# HELP apisix_shared_dict_free_space_bytes The free space of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_free_space_bytes gauge
apisix_shared_dict_free_space_bytes{name="access-tokens"} 1032192
apisix_shared_dict_free_space_bytes{name="balancer-ewma"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-last-touched-at"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-locks"} 10412032
apisix_shared_dict_free_space_bytes{name="cas_sessions"} 10412032
apisix_shared_dict_free_space_bytes{name="discovery"} 1032192
apisix_shared_dict_free_space_bytes{name="etcd-cluster-health-check"} 10412032
apisix_shared_dict_free_space_bytes{name="ext-plugin"} 1032192
apisix_shared_dict_free_space_bytes{name="internal-status"} 10407936
apisix_shared_dict_free_space_bytes{name="introspection"} 10412032
apisix_shared_dict_free_space_bytes{name="jwks"} 1032192
apisix_shared_dict_free_space_bytes{name="kubernetes"} 1007616
apisix_shared_dict_free_space_bytes{name="lrucache-lock"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-api-breaker"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-conn"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-count"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-count-redis-cluster-slot-lock"} 1036288
apisix_shared_dict_free_space_bytes{name="plugin-limit-count-reset-header"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-req"} 10412032
apisix_shared_dict_free_space_bytes{name="prometheus-metrics"} 10399744
apisix_shared_dict_free_space_bytes{name="upstream-healthcheck"} 10412032
apisix_shared_dict_free_space_bytes{name="worker-events"} 10407936
```

观察上面的`curl  http://10.96.10.10:9091/apisix/prometheus/metrics`命令返回的数据，发现缺失了很多数据，原因是apisix没有开启prometheus插件，可以在dashboard中开启prometheus插件。

```
再次访问metrics，发现多了很多
[root@k8s-master apisix]# curl http://10.244.235.217:9091/apisix/prometheus/metrics
# HELP apisix_bandwidth Total bandwidth in bytes consumed per service in APISIX
# TYPE apisix_bandwidth counter
apisix_bandwidth{type="egress",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 393399
apisix_bandwidth{type="ingress",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 182962
# HELP apisix_etcd_modify_indexes Etcd modify index for APISIX keys
# TYPE apisix_etcd_modify_indexes gauge
apisix_etcd_modify_indexes{key="consumers"} 0
apisix_etcd_modify_indexes{key="global_rules"} 529
apisix_etcd_modify_indexes{key="max_modify_index"} 529
apisix_etcd_modify_indexes{key="prev_index"} 529
apisix_etcd_modify_indexes{key="protos"} 0
apisix_etcd_modify_indexes{key="routes"} 524
apisix_etcd_modify_indexes{key="services"} 0
apisix_etcd_modify_indexes{key="ssls"} 0
apisix_etcd_modify_indexes{key="stream_routes"} 0
apisix_etcd_modify_indexes{key="upstreams"} 526
apisix_etcd_modify_indexes{key="x_etcd_index"} 529
# HELP apisix_etcd_reachable Config server etcd reachable from APISIX, 0 is unreachable
# TYPE apisix_etcd_reachable gauge
apisix_etcd_reachable 1
# HELP apisix_http_latency HTTP request latency in milliseconds per service in APISIX
# TYPE apisix_http_latency histogram
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1"} 95
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2"} 124
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5"} 128
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10"} 130
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="20"} 133
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="50"} 139
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="100"} 143
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="200"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="500"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="30000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="60000"} 146
apisix_http_latency_bucket{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="+Inf"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1"} 1
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2"} 9
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5"} 94
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10"} 122
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="20"} 125
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="50"} 137
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="100"} 143
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="200"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="500"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="30000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="60000"} 146
apisix_http_latency_bucket{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="+Inf"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1"} 9
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2"} 43
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5"} 117
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10"} 139
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="20"} 141
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="50"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="100"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="200"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="500"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="1000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="2000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="5000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="10000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="30000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="60000"} 146
apisix_http_latency_bucket{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28",le="+Inf"} 146
apisix_http_latency_count{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 146
apisix_http_latency_count{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 146
apisix_http_latency_count{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 146
apisix_http_latency_sum{type="apisix",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 1080.0014324188
apisix_http_latency_sum{type="request",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 1725.9991168976
apisix_http_latency_sum{type="upstream",route="468109361646929070",service="",consumer="",node="10.96.216.28"} 664
# HELP apisix_http_requests_total The total number of client requests since APISIX started
# TYPE apisix_http_requests_total gauge
apisix_http_requests_total 37788
# HELP apisix_http_status HTTP status codes per service in APISIX
# TYPE apisix_http_status counter
apisix_http_status{code="200",route="468109361646929070",matched_uri="/*",matched_host="grafana.cosmoplat-73.com",service="",consumer="",node="10.96.216.28"} 128
apisix_http_status{code="400",route="468109361646929070",matched_uri="/*",matched_host="grafana.cosmoplat-73.com",service="",consumer="",node="10.96.216.28"} 17
apisix_http_status{code="499",route="468109361646929070",matched_uri="/*",matched_host="grafana.cosmoplat-73.com",service="",consumer="",node="10.96.216.28"} 1
# HELP apisix_nginx_http_current_connections Number of HTTP connections
# TYPE apisix_nginx_http_current_connections gauge
apisix_nginx_http_current_connections{state="accepted"} 37818
apisix_nginx_http_current_connections{state="active"} 101
apisix_nginx_http_current_connections{state="handled"} 37818
apisix_nginx_http_current_connections{state="reading"} 0
apisix_nginx_http_current_connections{state="waiting"} 1
apisix_nginx_http_current_connections{state="writing"} 100
# HELP apisix_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE apisix_nginx_metric_errors_total counter
apisix_nginx_metric_errors_total 0
# HELP apisix_node_info Info of APISIX node
# TYPE apisix_node_info gauge
apisix_node_info{hostname="apisix-6b4d5b76fb-l26xr"} 1
# HELP apisix_shared_dict_capacity_bytes The capacity of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_capacity_bytes gauge
apisix_shared_dict_capacity_bytes{name="access-tokens"} 1048576
apisix_shared_dict_capacity_bytes{name="balancer-ewma"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-last-touched-at"} 10485760
apisix_shared_dict_capacity_bytes{name="balancer-ewma-locks"} 10485760
apisix_shared_dict_capacity_bytes{name="cas_sessions"} 10485760
apisix_shared_dict_capacity_bytes{name="discovery"} 1048576
apisix_shared_dict_capacity_bytes{name="etcd-cluster-health-check"} 10485760
apisix_shared_dict_capacity_bytes{name="ext-plugin"} 1048576
apisix_shared_dict_capacity_bytes{name="internal-status"} 10485760
apisix_shared_dict_capacity_bytes{name="introspection"} 10485760
apisix_shared_dict_capacity_bytes{name="jwks"} 1048576
apisix_shared_dict_capacity_bytes{name="kubernetes"} 1048576
apisix_shared_dict_capacity_bytes{name="lrucache-lock"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-api-breaker"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-conn"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-count"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-count-redis-cluster-slot-lock"} 1048576
apisix_shared_dict_capacity_bytes{name="plugin-limit-count-reset-header"} 10485760
apisix_shared_dict_capacity_bytes{name="plugin-limit-req"} 10485760
apisix_shared_dict_capacity_bytes{name="prometheus-metrics"} 10485760
apisix_shared_dict_capacity_bytes{name="upstream-healthcheck"} 10485760
apisix_shared_dict_capacity_bytes{name="worker-events"} 10485760
# HELP apisix_shared_dict_free_space_bytes The free space of each nginx shared DICT since APISIX start
# TYPE apisix_shared_dict_free_space_bytes gauge
apisix_shared_dict_free_space_bytes{name="access-tokens"} 1032192
apisix_shared_dict_free_space_bytes{name="balancer-ewma"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-last-touched-at"} 10412032
apisix_shared_dict_free_space_bytes{name="balancer-ewma-locks"} 10412032
apisix_shared_dict_free_space_bytes{name="cas_sessions"} 10412032
apisix_shared_dict_free_space_bytes{name="discovery"} 1032192
apisix_shared_dict_free_space_bytes{name="etcd-cluster-health-check"} 10412032
apisix_shared_dict_free_space_bytes{name="ext-plugin"} 1032192
apisix_shared_dict_free_space_bytes{name="internal-status"} 10407936
apisix_shared_dict_free_space_bytes{name="introspection"} 10412032
apisix_shared_dict_free_space_bytes{name="jwks"} 1032192
apisix_shared_dict_free_space_bytes{name="kubernetes"} 1007616
apisix_shared_dict_free_space_bytes{name="lrucache-lock"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-api-breaker"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-conn"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-count"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-count-redis-cluster-slot-lock"} 1036288
apisix_shared_dict_free_space_bytes{name="plugin-limit-count-reset-header"} 10412032
apisix_shared_dict_free_space_bytes{name="plugin-limit-req"} 10412032
apisix_shared_dict_free_space_bytes{name="prometheus-metrics"} 10358784
apisix_shared_dict_free_space_bytes{name="upstream-healthcheck"} 10412032
apisix_shared_dict_free_space_bytes{name="worker-events"} 10407936
```

### 启用grafana

要先安装grafana，一般prometheus-stack会自带一个grafana，如果没有，按如下流程手动安装

```
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana
```

开启grafana的nodeport

1.grafana配置datasource（指prometheus的地址）

2.grafana配置dashboard的模板

访问grafana并配置grafana的dashboard，访问https://grafana.com/grafana/dashboards/11719-apache-apisix/下载dashboard模板-->11719

> import dashboard方法：登录grafana-->dashboards-->new-->import-->load 11719-->确认即可

3.保存此dashboard，方便以后访问
