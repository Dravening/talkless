# 一. 安装（可略过）
1. 从github下载最新release包：本次使用最新版[4.1.0](https://github.com/wg/wrk/archive/4.1.0.zip)
wrk是开源的, 代码在 github 上：https://github.com/wg/wrk
2. 解压源码包: tar -xzvf 4.1.0.tar.gz
3. 执行编译命令：make
4. make之后不报错，成功后会在项目路径下生成可执行文件wrk，就可以在项目路径下用wrk进行HTTP压测了
5. 为了方便可以在任何路径直接使用wrk，把这个wrk可执行文件拷贝到某个已在path中的路径，比如/usr/local/bin即可
6. 最后验证一下：执行wrk -v。返回wrk版本号，说明已经安装成功

``` 
[root@VM-33-16-centos temp]# wrk -v
wrk  [epoll] Copyright (C) 2012 Will Glozer
```



# 二. 基本使用
## 1. 先看参数说明
``` 
[root@VM-33-16-centos temp]# wrk --help
Usage: wrk <options> <url>
  Options:
    -c, --connections <N>  Connections to keep open
    -d, --duration    <T>  Duration of test
    -t, --threads     <N>  Number of threads to use

    -s, --script      <S>  Load Lua script file
    -H, --header      <H>  Add header to request
        --latency          Print latency statistics
        --timeout     <T>  Socket/request timeout
    -v, --version          Print version details

  Numeric arguments may include a SI unit (1k, 1M, 1G)
  Time arguments may include a time unit (2s, 2m, 2h)
```
**翻译一下**

``` 
使用方法: wrk <选项> <被测HTTP服务的URL>                            
  Options:                                            
    -c, --connections <N>  跟服务器建立并保持的TCP连接数量  
    -d, --duration    <T>  压测时间           
    -t, --threads     <N>  使用多少个线程进行压测   
                                                      
    -s, --script      <S>  指定Lua脚本路径       
    -H, --header      <H>  为每一个HTTP请求添加HTTP头      
        --latency          在压测结束后，打印延迟统计信息   
        --timeout     <T>  超时时间     
    -v, --version          打印正在使用的wrk的详细版本信息
                                                      
  <N>代表数字参数，支持国际单位 (1k, 1M, 1G)
  <T>代表时间参数，支持时间单位 (2s, 2m, 2h)
```
**重要参数解释**

``` 
-c（连接数）：
连接数（connection）可以理解为并发数，一般在测试过程中，这个值需要使用者不断向上调试，直至QPS达到一个临界点，便可认为此时的并发数为系统所能承受的最大并发量。
-t（线程数）：
一般是CPU核数，最大不要超过CPUx2核数，否则会带来额外的上下文切换，将线程数设置为CPU核数主要是为了WRK能最大化利用CPU，使结果更准确
```



## 2. 结合一次简单压测及结果分析，理解参数和测试结果
``` 
wrk -t8 -c200 -d30s --latency  http://www.bing.com
```
这条命令表示，利用 wrk 对 www.bing.com 发起压力测试，线程数为 8，模拟 200 个并发请求，持续 30 秒。并要求在压测结果中输出响应延迟信息。
**分析一下结果**

``` 

Running 30s test @ http://www.bing.com （压测时间30s）

  8 threads and 200 connections （共8个测试线程，200个连接）

  Thread Stats   Avg      Stdev     Max   +/- Stdev
              （平均值） （标准差）（最大值）（正负一个标准差所占比例）
    Latency    46.67ms  215.38ms   1.67s    95.59%
    （延迟）
    Req/Sec     7.91k     1.15k   10.26k    70.77%
    （处理中的请求数）

  Latency Distribution （延迟分布）
     50%    2.93ms
     75%    3.78ms
     90%    4.73ms
     99%    1.35s （99分位的延迟：%99的请求在1.35s以内）
  1790465 requests in 30.01s, 684.08MB read （30.01秒内共处理完成了1790465个请求，读取了684.08MB数据）
Requests/sec:  59658.29 （平均每秒处理完成59658.29个请求）
Transfer/sec:     22.79MB （平均每秒读取数据22.79MB）
```

**结果说明：一般我们最关心的几个结果指标**
1. Latency: 可以理解为响应时间分布（需要在命令中添加 --latency）。
- 顺序分别是： 平均值，标准偏差，最大值，正负标准差；其中，平均值，最大值，有一定参考意义，**平均响应时间`Avg`是最重要的参考指标之一。
- 标准差`Stdev` 不太好理解 表示样本数据的离散程度。
	- 例如两组数据 {0,5,9,14} 和 {5,6,8,9}，平均值都是 7，但第二个具有较小的标准差，说明更加稳定。所以，如果标准偏差越小，一定层面能反应待测的接口是比较稳定的。如果多次测试结果中的 Stdev 差距较大，说明有可能系统性能波动很大。

2. Requests/Sec: 每秒的处理请求数，可以理解为qps。顺序分别是： 平均值，标准差，最大值，正负标准差；
- **`QPS`是最重要的参考指标之一**
- QPS即单位时间内处理的请求数, QPS=完成的请求数/总消耗时间。反应服务器的处理能力，性能。QPS越高，代表服务处理效率就越高

3. 连接超时数目timeout。
默认的timeout是1s，可以自己设置超时时间（需要在命令中添加 --timeout）

```
[root@VM-33-16-centos shengjieliu]# wrk  -t8 -c10 -d30s -s search_related_inst_asso.lua http://paas.ee10.bktencent.com:80/api/c/compapi/v2/cc/search_related_inst_asso/
Running 30s test @ http://paas.ee10.bktencent.com:80/api/c/compapi/v2/cc/search_related_inst_asso/
  8 threads and 10 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     0.00us    0.00us   0.00us    -nan%
    Req/Sec     0.00      0.00     0.00    100.00%
  40 requests in 30.04s, 6.57MB read
  Socket errors: connect 0, read 0, write 0, timeout 40
Requests/sec:      1.33
Transfer/sec:    223.84KB
```
从结果看，30s内发送了40个request，40个request全部超时（即响应时间大于1秒），超时的接口不会做数据统计。因此Latency看到的指标都是0

# 三. 进阶使用
1. wrk支持用户使用--script指定Lua脚本，来定制压测过程，满足个性化需求
在lua脚本里你可以修改 method, header, body, 可以对 response 做自定义的分析
2. 如果想构造不同的get请求，请求带随机参数，则lua脚本如下：
``` 
request = function()
num = math.random(1000,9999)
   path = "/test.html?t=" .. num
   return wrk.format("GET", path)
end
```

3. 如果想构造不同的POST请求，而且每次的请求参数都不一样，用来模拟用户使用的实际场景。如CMDB的create_object接口，每次创建都需要不同的模型id和模型name。
参考脚本如下

``` 
wrk.method = "POST"
wrk.body   = "foo=bar&baz=quux"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"

math.randomseed(os.time())
 
function getRandom(n) 
    local t = {
        "0","1","2","3","4","5","6","7","8","9",
        "a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
        "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
    }    
    local s = ""
    for i =1, n do
        s = s .. t[math.random(#t)]        
    end;
    return s
end;

request = function()
    local headers = { }
    headers['Content-Type'] = "application/json"
    bk_obj_name_0="性能测试模型" .. getRandom(8)
    bk_obj_id_0="perftest_object2" .. getRandom(8)
    body = {
        bk_app_code="bk_user_manage",
        bk_app_secret="5d16f5e0-e7a6-43cf-a1f6-b63459f8dcf5",
        bk_username="admin",
        creator="admin",
        bk_classification_id="perftest4",
        bk_obj_name=bk_obj_name_0,
        bk_supplier_account="0",
        bk_obj_icon="icon-cc-business",
        bk_obj_id=bk_obj_id_0
    }
    local cjson = require("cjson")
    body_str = cjson.encode(body)
--    print(body_str)
    return wrk.format('POST', nil, headers, body_str)
end

success_number = 0
fail_number = 0
function response(status,headers,body)
        local cjson = require("cjson")
        body_table = cjson.decode(body)
        code = body_table.code
        if code ~= 0 then --将服务器返回状态码不是200的请求结果打印出来
                fail_number = fail_number + 1
                print("fail_number" .. fail_number)
                print(body)
        --      wrk.thread:stop()
        else
            success_number = success_number + 1
            print("success_number" .. success_number)
            print(body)
        end
end

```

执行命令

``` 
wrk -t2 -c4 -d1s -s create_object.lua http://paas.ee10.bktencent.com:80/api/c/compapi/v2/cc/create_object
```





