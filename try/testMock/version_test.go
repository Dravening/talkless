package testMock

import (
	"github.com/golang/mock/gomock"
	"talkless/try/testMock/spider"
	"testing"
)

func TestGetGoVersion1(t *testing.T) {
	v := GetGoVersion(spider.CreateGoVersionSpider())
	if v != "go1.8.3" {
		t.Errorf("Get wrong version %s", v)
	}
}

func TestGetGoVersion2(t *testing.T) {
	mockCtl := gomock.NewController(t)
	defer mockCtl.Finish()
	mockSpider := spider.NewMockSpider(mockCtl)
	mockSpider.EXPECT().GetBody().Return("go1.8.3")
	goVer := GetGoVersion(mockSpider)

	if goVer != "go1.8.3" {
		t.Errorf("Get wrong version %s", goVer)
	}
}
