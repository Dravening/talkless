在单元测试文件version_test.go中，实现了一个测试函数。
这个单元测试其实既测试了函数GetGoVersion也测试了spider.CreateGoVersionSpider返回的对象。
而有时候，我们可能仅仅想测试下GetGoVersion函数，或者我们的spider.CreateGoVersionSpider爬虫实现还没有写好，那该如何是好呢？

此时Mock工具就显的尤为重要了。

这里首先用gomock提供的mockgen工具生成要mock的接口的实现：
```
mockgen -destination spider/mock_spider.go -package spider talkless/try/testMock/spider Spider
```
然后关注go_version.go中的实现。

```
mockSpider.EXPECT().GetBody().Return("go1.8.3")
```
这句会mock一个值为“go1.8.3”的return.

