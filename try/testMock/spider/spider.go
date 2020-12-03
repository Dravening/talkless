package spider

type Spider interface {
	GetBody() string
}

func CreateGoVersionSpider() Spider {

	return newSpiderStruct()
}

type spiderStruct struct {
	version string
}

func newSpiderStruct() spiderStruct {
	return spiderStruct{}
}

func (spiderStruct) GetBody() string {
	version := ""
	return version
}
