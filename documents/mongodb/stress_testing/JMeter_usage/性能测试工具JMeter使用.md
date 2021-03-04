# 一. 安装（可略过）
1. 登录官网Jmeter下载，得到压缩包`jmeter-5.0.tgz`，下载地址：http://jmeter.apache.org/download_jmeter.cgi，如下图

   -----------------------

   ![download_address](.\img\download_address.png)

2. 下载https://mirrors.bfsu.edu.cn/apache//jmeter/binaries/apache-jmeter-5.4.1.zip

3. 将下载得到的压缩包解压即可，这里我解压到自己电脑的路径为`D:\apache-jmeter-5.4.1`

# 二. 基本使用
## 启动
双击`D:\apache-jmeter-5.4.1\bin\jemeter.bat`启动，显示图形界面

![menu](.\img\menu.png)

## 开始压测
现有一个蓝鲸cmdb的接口http://paas.bkdevee3.com/api/c/compapi/v2/cc/batch_update_inst/，我们使用JMeter对它进行压测。

### 1.新建一个线程组

![new_thread_group](.\img\new_thread_group.png)

### 2.设置线程组参数

![thread_group_param](.\img\thread_group_param.png)

### 3.添加要压测的http请求

![add_http_request](.\img\add_http_request.png)

### 4.填入请求参数

![enter_request_param](.\img\enter_request_param.png)

### 5.增加监听器，用于查看结果。本次使用聚合报告监听器。

![aggregate_report](.\img\aggregate_report.png)

### 6.开始测试

![start_test](.\img\start_test.png)

### 7.得到结果

![test_result](.\img\test_result.png)

### 8.备注

另外，对于阶梯式的逐步增压方案，JMeter也有支持。
请加载JMeter软件Templates目录下的step_thread_group.jmx模板。

