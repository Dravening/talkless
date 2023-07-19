# k8s-vgpu-scheduler功能测试

[k8s-vgpu-scheduler](https://github.com/4paradigm/k8s-vgpu-scheduler/tree/master)在保留4pd-k8s-device-plugin([4paradigm/k8s-device-plugin](https://github.com/4paradigm/k8s-device-plugin))插件功能的基础上，添加了调度模块，以实现多个GPU节点间的负载均衡。k8s vGPU scheduler在原有显卡分配方式的基础上，可以进一步根据显存和算力来切分显卡。在k8s集群中，基于这些切分后的vGPU进行调度，使不同的容器可以安全的共享同一张物理GPU，提高GPU的利用率。此外，插件还可以对显存做虚拟化处理（使用到的显存可以超过物理上的显存），运行一些超大显存需求的任务，或提高共享的任务数。

## 安装

### GPU节点准备

以下步骤要在所有GPU节点执行。这份README文档假定GPU节点已经安装NVIDIA驱动和`nvidia-docker`套件。

注意你需要安装的是`nvidia-docker2`而非`nvidia-container-toolkit`。因为新的`--gpus`选项kubernetes尚不支持。安装步骤举例：

```
# 加入套件仓库
$ distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
$ curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
$ curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

$ sudo apt-get update && sudo apt-get install -y nvidia-docker2
$ sudo systemctl restart docker
```

你需要在节点上将nvidia runtime做为你的docker runtime预设值。我们将编辑docker daemon的配置文件，此文件通常在`/etc/docker/daemon.json`路径：

```
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
```

> *如果 `runtimes` 字段没有出现, 前往的安装页面执行安装操作 [nvidia-docker](https://github.com/NVIDIA/nvidia-docker)*

最后，你需要将所有要使用到的GPU节点打上gpu=on标签，否则该节点不会被调度到

```
$ kubectl label nodes {nodeid} gpu=on
```



### Kubernetes开启vGPU支持

> 注意：此项目已经覆盖了nvidia的k8s插件，故无需安装[NVIDIA/k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin)

首先使用helm添加我们的vgpu repo

```
helm repo add vgpu-charts https://4paradigm.github.io/k8s-vgpu-scheduler
```

随后，使用下列指令获取集群服务端版本

```
kubectl version
```

在安装过程中须根据集群服务端版本（上一条指令的结果）指定调度器镜像版本，例如集群服务端版本为1.20.4，则可以使用如下指令进行安装

```
$ helm install vgpu vgpu-charts/vgpu --set scheduler.kubeScheduler.imageTag=v1.20.4 -n kube-system
```



### 配置修改

如果需要客制化配置，可以参考以下文档：

- `devicePlugin.deviceSplitCount:` 整数类型，预设值是10。GPU的分割数，每一张GPU都不能分配超过其配置数目的任务。若其配置为N的话，每个GPU上最多可以同时存在N个任务。
- `devicePlugin.deviceMemoryScaling:` 浮点数类型，预设值是1。NVIDIA装置显存使用比例，可以大于1（启用虚拟显存，实验功能）。对于有*M*显存大小的NVIDIA GPU，如果我们配置`devicePlugin.deviceMemoryScaling`参数为*S*，在部署了我们装置插件的Kubenetes集群中，这张GPU分出的vGPU将总共包含 `S * M` 显存。
- `devicePlugin.migStrategy:` 字符串类型，目前支持"none“与“mixed“两种工作方式，前者忽略MIG设备，后者使用专门的资源名称指定MIG设备，使用详情请参考mix_example.yaml，默认为"none"
- `devicePlugin.disablecorelimit:` 字符串类型，"true"为关闭算力限制，"false"为启动算力限制，默认为"false"
- `scheduler.defaultMem:` 整数类型，预设值为5000，表示不配置显存时使用的默认显存大小，单位为MB
- `scheduler.defaultCores:` 整数类型(0-100)，默认为0，表示默认为每个任务预留的百分比算力。若设置为0，则代表任务可能会被分配到任一满足显存需求的GPU中，若设置为100，代表该任务独享整张显卡
- `resourceName:` 字符串类型, 申请vgpu个数的资源名, 默认: "nvidia.com/gpu"
- `resourceMem:` 字符串类型, 申请vgpu显存大小资源名, 默认: "nvidia.com/gpumem"
- `resourceMemPercentage:` 字符串类型，申请vgpu显存比例资源名，默认: "nvidia.com/gpumem-percentage"
- `resourceCores:` 字符串类型, 申请vgpu算力资源名, 默认: "nvidia.com/cores"
- `resourcePriority:` 字符串类型，表示申请任务的任务优先级，默认: "nvidia.com/priority"



### 功能实测

创建如下pod，使用机器内的gpu资源

```shell
cat > vgpu-test.yaml <EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vgpu-test
  namespace: default
spec:
  replicas: 10
  selector:
    matchLabels:
      app: vgpu-test
      release: test
  template:
    metadata:
      labels:
        app: vgpu-test
        release: test
    spec:
      containers:
      - name: ubuntu-container
        image: ubuntu:18.04
        command: ["bash", "-c", "sleep 86400"]
        resources:
          limits:
            nvidia.com/gpu: 1
            nvidia.com/gpumem: 10000 # 每个vGPU申请10000m显存 （可选，整数类型）
            nvidia.com/gpucores: 10 # 每个vGPU的算力为10%实际显卡的算力 （可选，整数类型）
EOF
```

##### 环境说明

```
[root@cosmo-ai01 draven]# nvidia-smi
```

| 属性        | 值                                                           |
| ----------- | ------------------------------------------------------------ |
| ip          | 10.138.146.11                                                |
| os          | Linux  5.4.240-1.el7.elrepo.x86_64                           |
| 显卡驱动    | NVIDIA-SMI 515.86.01    Driver Version: 515.86.01    CUDA Version: 11.7 |
| 显卡1&显卡2 | 每张显存32768MiB                                             |

##### 官方功能测试用例如下

| 功能                                | 案例设定                                             | 测试                                         | 结果 |
| ----------------------------------- | ---------------------------------------------------- | -------------------------------------------- | ---- |
| 指定每张物理GPU切分的最大vGPU的数量 | 10（双核一共20）                                     | 可以同时运行“独占显卡”的进程数量超过GPU个数  | 通过 |
| 限制vGPU的显存                      | 不允许超量使用                                       | 6 Running / 4 Pending，意味着使用了60G显存   | 通过 |
| 允许通过指定显存申请GPU             | 同"限制vGPU的显存"                                   | 同"限制vGPU的显存"                           | 通过 |
| 允许通过指定vGPU使用比例申请GPU     | nvidia.com/gpumem: 5000<br />nvidia.com/gpucores: 30 | 6 Running / 4 Pending，意味着使用了180%的GPU | 通过 |
| 限制vGPU的计算单元                  | 未知                                                 | 未知                                         | 未知 |
| 执行优先级resourcePriority          | 增加nvidia.com/priority属性                          | 无法正确识别优先级                           | 无效 |

##### 检测k8s是否真的按需分配了相应显存资源

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vgpu-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vgpu-test
      release: test
  template:
    metadata:
      labels:
        app: vgpu-test
        release: test
    spec:
      containers:
      - name: ubuntu-container
        image: registry-edge.cosmoplat.com/ai-train/cuda117:0.1
        command: ["bash", "-c", "nvidia-smi;python3 /gpu_torch.py;sleep 86400"]
        resources:
          limits:
            nvidia.com/gpu: 1
            nvidia.com/gpumem: 3000 # 每个vGPU申请3000m显存 （可选，整数类型）
```

此镜像`registry-edge.cosmoplat.com/ai-train/cuda117:0.1`启动固定需要2000M显存，针对分配1000M和3000M对其进行测试

###### 分配1000M

```
修改yaml--->nvidia.com/gpumem: 1000 # 每个vGPU申请1000m显存 （可选，整数类型）
```

```
(base) [root@cosmo-ai01 draven]# kubectl logs vgpu-test-84d96dd8f6-x665s 
[4pdvGPU Warn(7:140408980604736:util.c:149)]: new_uuid=GPU-fcda056f-77c6-7fdf-f7c7-6453511eaaa1 1
[4pdvGPU Msg(7:140408980604736:libvgpu.c:871)]: Initializing.....
[4pdvGPU Msg(7:140408980604736:device.c:249)]: driver version=11070
Mon May 22 07:42:43 2023       
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 515.86.01    Driver Version: 515.86.01    CUDA Version: 11.7     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  Tesla V100-PCIE...  On   | 00000000:D8:00.0 Off |                    0 |
| N/A   37C    P0    26W / 250W |      0MiB /  1000MiB |      0%      Default |
|                               |                      |                  N/A |
+-------------------------------+----------------------+----------------------+
                                                                               
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
[4pdvGPU Msg(7:140408980604736:multiprocess_memory_limit.c:457)]: Calling exit handler 7
[4pdvGPU Msg(8:139937750087232:libvgpu.c:871)]: Initializing.....
[4pdvGPU Warn(8:139937750087232:util.c:149)]: new_uuid=GPU-fcda056f-77c6-7fdf-f7c7-6453511eaaa1 1
[4pdvGPU Msg(8:139937750087232:device.c:249)]: driver version=11070
[4pdvGPU Msg(8:139937750087232:utils.c:233)]: current processes num = 0 1
[4pdvGPU Warn(8:139937750087232:utils.c:243)]: hostPid=72798
[4pdvGPU Warn(8:139937750087232:utils.c:248)]: Primary Context Size==317718528
[4pdvGPU Msg(8:139937750087232:libvgpu.c:904)]: Initialized
[4pdvGPU Msg(8:139937750087232:device.c:249)]: driver version=11070
[4pdvGPU ERROR (pid:8 thread=139937750087232 allocator.c:53)]: Device 0 OOM 1559232512 / 1048576000
GPU is available with Tesla V100-PCIE-32GB
Traceback (most recent call last):
  File "/gpu_torch.py", line 11, in <module>
    x = torch.randn(100000, 3100).to(device)
RuntimeError: CUDA error: unrecognized error code
CUDA kernel errors might be asynchronously reported at some other API call, so the stacktrace below might be incorrect.
For debugging consider passing CUDA_LAUNCH_BLOCKING=1.
Compile with `TORCH_USE_CUDA_DSA` to enable device-side assertions.

[4pdvGPU Msg(8:139937750087232:multiprocess_memory_limit.c:457)]: Calling exit handler 8
```

<u>**请关注nvidia-smi命令的结果，显示0MiB /  1000MiB，且python进程报错Device 0 OOM 1559232512 / 1048576000**</u>

###### 分配3000M

```
(base) [root@cosmo-ai01 draven]# kubectl logs vgpu-test-698f587ff6-vckxd
[4pdvGPU Warn(7:140010871437120:util.c:149)]: new_uuid=GPU-709fac35-5f40-624b-90f7-b0a3db7a97a0 1
[4pdvGPU Msg(7:140010871437120:libvgpu.c:871)]: Initializing.....
[4pdvGPU Msg(7:140010871437120:device.c:249)]: driver version=11070
Mon May 22 07:33:42 2023       
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 515.86.01    Driver Version: 515.86.01    CUDA Version: 11.7     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  Tesla V100-PCIE...  On   | 00000000:AF:00.0 Off |                    0 |
| N/A   36C    P0    24W / 250W |      0MiB /  3000MiB |      0%      Default |
|                               |                      |                  N/A |
+-------------------------------+----------------------+----------------------+
                                                                               
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
[4pdvGPU Msg(7:140010871437120:multiprocess_memory_limit.c:457)]: Calling exit handler 7
[4pdvGPU Msg(8:140366668387904:libvgpu.c:871)]: Initializing.....
[4pdvGPU Warn(8:140366668387904:util.c:149)]: new_uuid=GPU-709fac35-5f40-624b-90f7-b0a3db7a97a0 1
[4pdvGPU Msg(8:140366668387904:device.c:249)]: driver version=11070
[4pdvGPU Msg(8:140366668387904:utils.c:233)]: current processes num = 0 1
[4pdvGPU Warn(8:140366668387904:utils.c:243)]: hostPid=55138
[4pdvGPU Warn(8:140366668387904:utils.c:248)]: Primary Context Size==317718528
[4pdvGPU Msg(8:140366668387904:libvgpu.c:904)]: Initialized
[4pdvGPU Msg(8:140366668387904:device.c:249)]: driver version=11070
```

<u>**请关注nvidia-smi命令的结果，显示0MiB /  3000MiB，且python进程正常运行**</u>

##### 检测是否允许超量分配显存资源

在官方文档中，可以找到`devicePlugin.deviceMemoryScaling`配置，其是用来设置“虚拟显存与真实显存之间关系”的，这是一个实验功能，我们对其进行测试。

调整helm包的配置

```
helm uninstall vgpu -n kube-system
```

```
helm install vgpu vgpu-charts/vgpu --set scheduler.kubeScheduler.imageTag=v1.20.4 --set devicePlugin.deviceMemoryScaling=3.0  -n kube-system
```

```
修改yaml--->nvidia.com/gpumem: 10000 # 每个vGPU申请10000m显存 （可选，整数类型）
```

```shell
(base) [root@cosmo-ai01 draven]# kubectl get pods | grep vgpu-test
vgpu-test-f964c78fb-2qdp2                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-7rzzv                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-8glsd                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-l94jx                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-m57w5                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-q5f8f                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-qvmbt                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-rsdl8                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-snbxl                       1/1     Running                    0          7m17s
vgpu-test-f964c78fb-wqlz8                       1/1     Running                    0          7m17s
```

分析实验结果：

本实验共有资源65536MiB显存，每个任务需要`nvidia.com/gpumem: 10000`显存，即如果启用虚拟显存，则最多只能运行6个任务（已测试过）。本次实验10个任务可以全部运行，说明虚拟显存启用成功。

进入任务容器中也可查看到，任务有10000MiB的显存环境，如下。

```
(base) [root@cosmo-ai01 draven]# kubectl exec -it vgpu-test-f964c78fb-2qdp2 /bin/bash
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
root@vgpu-test-f964c78fb-2qdp2:/# nvidia-smi
[4pdvGPU Warn(91:139761141241664:util.c:149)]: new_uuid=GPU-709fac35-5f40-624b-90f7-b0a3db7a97a0 1
[4pdvGPU Msg(91:139761141241664:libvgpu.c:871)]: Initializing.....
[4pdvGPU Msg(91:139761141241664:device.c:249)]: driver version=11070
Tue May 23 06:17:07 2023       
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 515.86.01    Driver Version: 515.86.01    CUDA Version: 11.7     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  Tesla V100-PCIE...  On   | 00000000:AF:00.0 Off |                    0 |
| N/A   35C    P0    24W / 250W |      0MiB / 10000MiB |      0%      Default |
|                               |                      |                  N/A |
+-------------------------------+----------------------+----------------------+
                                                                               
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```





```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vgpu-test
  namespace: default
spec:
  replicas: 5
  selector:
    matchLabels:
      app: vgpu-test
      release: test
  template:
    metadata:
      labels:
        app: vgpu-test
        release: test
    spec:
      containers:
      - name: ubuntu-container
        image: registry-edge.cosmoplat.com/ai-train/cuda117:0.2
        command: ["bash", "-c", "nvidia-smi;python3 /gpu_torch.py;sleep 86400"]
        resources:
          limits:
            nvidia.com/gpu: 1
            nvidia.com/gpumem: 16000 # 每个vGPU申请10000m显存 （可选，整数类型）
```

