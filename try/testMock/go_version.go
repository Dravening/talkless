package testMock

import "talkless/try/testMock/spider"

func GetGoVersion(s spider.Spider) string {
	body := s.GetBody()
	return body
}
