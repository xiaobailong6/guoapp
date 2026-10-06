package core

import (
	"net/url"
	"regexp"
	"strings"
)

const (
	sourceYaguo     = "yaguo"
	sourceMaoguo    = "maoguo"
	sourceFanguo    = "fanguo"
	sourceGuanguo   = "guanguo"
	sourceHeguo     = "heguo"
	sourceXingguo   = "xingguo"
	sourceHuaguo    = "huaguo"
	sourceNiuguo    = "niuguo"
	sourceWuguo     = "wuguo"
	sourceChaoguo   = "chaoguo"
	sourceMiguo     = "miguo"
	sourceShuangguo = "shuangguo"
	sourceYanguo    = "yanguo"
	sourceTaoguo    = "taoguo"
	sourceYouguo    = "youguo"
	sourceLiuguo    = "liuguo"
	sourceMeiguo    = "meiguo"
	sourceChengguo  = "chengguo"
	sourceXiaoguo   = "xiaoguo"
	sourceYingguo   = "yingguo"
	sourceLuguo     = "luguo"
	sourceLiguo     = "liguo"
	sourceJuguo     = "juguo"
	sourceZaoguo    = "zaoguo"
	sourceNingguo   = "ningguo"
	sourceMangguo   = "mangguo"

	duanjuMaxBodyBytes = 8 * 1024 * 1024
	duanjuUserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

var (
	yaguoBaseURL     = "https://app.whjzjx.cn"
	yaguoLoginURL    = "https://u.shytkjgs.com/user/v1/account/login"
	maoguoBaseURL    = "https://api-store.qmplaylet.com"
	maoguoReadURL    = "https://api-read.qmplaylet.com"
	fanguoBaseURL    = "https://xifan-api-cn.youlishipin.com"
	guanguoBaseURL   = "https://api.drama.9ddm.com"
	heguoBaseURL     = "https://www.kuaikaw.cn"
	xingguoBaseURL   = "http://read.api.duodutek.com"
	huaguoBaseURL    = "https://www.zywest263.com"
	niuguoBaseURL    = "https://ccc.chaojichaojichanga.com:35620"
	niuguoParseURL   = "http://ccs.jshh.gzbaoxian.com"
	niuguoParseURL2  = "http://101.42.92.211:5560"
	wuguoBaseURL     = "https://www.duanju55.com"
	chaoguoBaseURL   = "https://www.shanekids.com"
	miguoBaseURL     = "https://dmxq40.com"
	shuangguoBaseURL = "https://www.duanju2.com"
	yanguoBaseURL    = "https://xqxq1.cc"
	taoguoBaseURL    = "https://lujj31.buzz"
	youguoBaseURL    = "https://youavhub.com"
	liuguoBaseURL    = "https://www.llsp.me"
	meiguoBaseURL    = "https://shiresm.lol"
	chengguoBaseURL  = "https://a.qingyiduz.xyz"
	xiaoguoBaseURL   = "https://yese.co"
	yingguoBaseURL   = "https://missav02.xyz"
	luguoBaseURL     = "https://luyitian.com"
	liguoBaseURL     = "https://ririlu.cc"
	juguoBaseURL     = "https://4tw3gy653a.bulunhufait.buzz"
	zaoguoBaseURL    = "https://www.yhsp5.yachts/cn/home/web"
	ningguoBaseURL   = "https://toptv15.cyou"
	mangguoBaseURL   = "https://zsrqab03.zsrenqi.xyz"
)

type duanjuSourceSpec struct {
	ID        string
	Name      string
	Base      string
	Kind      string
	Agent     string
	Referer   string
	Searcher  bool
	Paged     bool
	Browser   bool
	BrowseAll bool
	// Single 表示详情与播放同页，且页面里的播放链接是相关推荐而非分集。
	Single bool
	// Suggest 表示 HTML 搜索页不可用，改走框架自带的 suggest JSON 接口。
	Suggest bool
}

var duanjuProviderCatalog = []duanjuSourceSpec{
	{ID: sourceYaguo, Name: "芽果", Base: yaguoBaseURL, Kind: "api", Searcher: true, Paged: true, BrowseAll: true},
	{ID: sourceMaoguo, Name: "猫果", Base: maoguoBaseURL, Kind: "api", Searcher: true, Paged: true},
	{ID: sourceFanguo, Name: "饭果", Base: fanguoBaseURL, Kind: "api", Searcher: true, Paged: true},
	{ID: sourceGuanguo, Name: "观果", Base: guanguoBaseURL, Kind: "api", Agent: "okhttp/5.1.0", Searcher: true, Paged: true},
	{ID: sourceHeguo, Name: "河果", Base: heguoBaseURL, Kind: "next", Searcher: true, Paged: true},
	{ID: sourceXingguo, Name: "星果", Base: xingguoBaseURL, Kind: "api", Searcher: true, Paged: true},
	{ID: sourceHuaguo, Name: "花果", Base: huaguoBaseURL, Kind: "maccms", Searcher: true, Paged: true},
	{ID: sourceNiuguo, Name: "牛果", Base: niuguoBaseURL, Kind: "api", Searcher: true, Paged: true},
	{ID: sourceWuguo, Name: "伍果", Base: wuguoBaseURL, Kind: "maccms", Searcher: true, Paged: true},
	{ID: sourceChaoguo, Name: "超果", Base: chaoguoBaseURL, Kind: "web", Searcher: true, Paged: true},
	{ID: sourceMiguo, Name: "米果", Base: miguoBaseURL, Kind: "maccms", Searcher: true},
	{ID: sourceShuangguo, Name: "爽果", Base: shuangguoBaseURL, Kind: "maccms", Searcher: true, Paged: true},
	{ID: sourceYanguo, Name: "艳果", Base: yanguoBaseURL, Kind: "maccms", Searcher: true, Paged: true},
	{ID: sourceTaoguo, Name: "桃果", Base: taoguoBaseURL, Kind: "maccms", Searcher: true, Paged: true},
	{ID: sourceYouguo, Name: "柚果", Base: youguoBaseURL, Kind: "maccms", Searcher: true, Paged: true, Single: true},
	{ID: sourceLiuguo, Name: "榴果", Base: liuguoBaseURL, Kind: "maccms", Searcher: true, Paged: true, Single: true},
	{ID: sourceMeiguo, Name: "美果", Base: meiguoBaseURL, Kind: "maccms", Searcher: true, Paged: true, Single: true, Suggest: true},
	{ID: sourceChengguo, Name: "城果", Base: chengguoBaseURL, Kind: "maccms", Searcher: true, Paged: true, Single: true, Suggest: true},
	{ID: sourceXiaoguo, Name: "宵果", Base: xiaoguoBaseURL, Kind: "maccms", Searcher: true, Paged: true, Suggest: true},
	// 以下两站共用同一套 maccms 后端与模板族，列表页直接给出播放页，站内无分页。
	{ID: sourceYingguo, Name: "樱果", Base: yingguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceLuguo, Name: "露果", Base: luguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceLiguo, Name: "荔果", Base: liguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceJuguo, Name: "橘果", Base: juguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceZaoguo, Name: "枣果", Base: zaoguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceNingguo, Name: "柠果", Base: ningguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
	{ID: sourceMangguo, Name: "芒果", Base: mangguoBaseURL, Kind: "maccms", Searcher: true, Single: true},
}

var duanjuMarkupPattern = regexp.MustCompile(`<[^>]{1,80}>`)

func duanjuPlainText(raw string) string {
	text := strings.TrimSpace(raw)
	if !strings.Contains(text, "<") {
		return text
	}
	text = duanjuMarkupPattern.ReplaceAllString(text, "")
	text = strings.NewReplacer("&nbsp;", " ", "&amp;", "&", "&lt;", "<", "&gt;", ">", "&quot;", `"`, "&#39;", "'").Replace(text)
	return strings.Join(strings.Fields(text), " ")
}

const (
	heguoSearchPath       = "/seo/video/6007"
	heguoSearchPName      = "www.kuaikaw.cn"
	heguoSearchSourceType = 1
)

var duanjuSourceAliases = map[string]string{
	"yaguo": "yaguo", "xingya": sourceYaguo, "星芽": sourceYaguo, "app.whjzjx.cn": sourceYaguo,
	"maoguo": "maoguo", "qimao": sourceMaoguo, "七猫": sourceMaoguo, "api-store.qmplaylet.com": sourceMaoguo,
	"fanguo": "fanguo", "xifan": sourceFanguo, "西饭": sourceFanguo, "xifan-api-cn.youlishipin.com": sourceFanguo,
	"guanguo": "guanguo", "weiguan": sourceGuanguo, "围观": sourceGuanguo, "api.drama.9ddm.com": sourceGuanguo,
	"heguo": "heguo", "hema": sourceHeguo, "河马": sourceHeguo, "www.kuaikaw.cn": sourceHeguo, "kuaikaw.cn": sourceHeguo,
	"xingguo": "xingguo", "xingxing": sourceXingguo, "星星": sourceXingguo, "read.api.duodutek.com": sourceXingguo,
	"huaguo": "huaguo", "huasheng": sourceHuaguo, "花生": sourceHuaguo, "www.zywest263.com": sourceHuaguo,
	"niuguo": "niuguo", "niuniu": sourceNiuguo, "牛牛": sourceNiuguo,
	"wuguo": "wuguo", "wuwu": sourceWuguo, "五五": sourceWuguo, "www.duanju55.com": sourceWuguo,
	"chaoguo": "chaoguo", "chaoduanju": sourceChaoguo, "超短剧": sourceChaoguo, "超果": sourceChaoguo,
	"shanekids": sourceChaoguo, "www.shanekids.com": sourceChaoguo, "shanekids.com": sourceChaoguo,
	"miguo": "miguo", "dami": sourceMiguo, "大米": sourceMiguo, "大米星球": sourceMiguo,
	"dmxq40.com": sourceMiguo, "www.dmxq40.com": sourceMiguo,
	"shuangguo": "shuangguo", "duanju2": sourceShuangguo, "短剧网": sourceShuangguo,
	"短剧网站小生": sourceShuangguo, "duanju2.com": sourceShuangguo, "www.duanju2.com": sourceShuangguo,
	"yanguo": "yanguo", "艳果": sourceYanguo, "av星球": sourceYanguo, "AV星球": sourceYanguo,
	"xqxq1.cc": sourceYanguo, "www.xqxq1.cc": sourceYanguo,
	"taoguo": "taoguo", "桃果": sourceTaoguo, "撸鸡鸡": sourceTaoguo,
	"lujj31.buzz": sourceTaoguo, "www.lujj31.buzz": sourceTaoguo,
	"youguo": "youguo", "柚果": sourceYouguo, "youavhub": sourceYouguo,
	"youavhub.com": sourceYouguo, "www.youavhub.com": sourceYouguo,
	"liuguo": "liuguo", "榴果": sourceLiuguo, "榴莲视频": sourceLiuguo,
	"llsp.me": sourceLiuguo, "www.llsp.me": sourceLiuguo,
	"meiguo": "meiguo", "美果": sourceMeiguo, "唯美精品": sourceMeiguo,
	"shiresm.lol": sourceMeiguo, "www.shiresm.lol": sourceMeiguo,
	"chengguo": "chengguo", "城果": sourceChengguo, "不夜城": sourceChengguo,
	"qingyiduz.xyz": sourceChengguo, "a.qingyiduz.xyz": sourceChengguo,
	"xiaoguo": "xiaoguo", "宵果": sourceXiaoguo, "夜色": sourceXiaoguo,
	"yese.co": sourceXiaoguo, "www.yese.co": sourceXiaoguo,
	"yingguo": "yingguo", "樱果": sourceYingguo, "missav": sourceYingguo,
	"missav02.xyz": sourceYingguo, "www.missav02.xyz": sourceYingguo,
	"luguo": "luguo", "露果": sourceLuguo, "撸一天": sourceLuguo,
	"luyitian.com": sourceLuguo, "www.luyitian.com": sourceLuguo,
	"liguo": "liguo", "荔果": sourceLiguo, "日日撸": sourceLiguo,
	"ririlu.cc": sourceLiguo, "www.ririlu.cc": sourceLiguo,
	"juguo": "juguo", "橘果": sourceJuguo, "海角乱伦": sourceJuguo,
	"bulunhufait.buzz": sourceJuguo,
	"zaoguo":           "zaoguo", "枣果": sourceZaoguo, "银河视频": sourceZaoguo,
	"yhsp5.yachts": sourceZaoguo, "www.yhsp5.yachts": sourceZaoguo,
	"yhsp9.homes": sourceZaoguo, "www.yhsp9.homes": sourceZaoguo,
	"ningguo": "ningguo", "柠果": sourceNingguo, "愛豆AV": sourceNingguo,
	"toptv15.cyou": sourceNingguo, "www.toptv15.cyou": sourceNingguo,
	"mangguo": "mangguo", "芒果": sourceMangguo, "真实人妻": sourceMangguo,
	"zsrenqi.xyz": sourceMangguo,
}

var duanjuSourcesByName = func() map[string]duanjuSourceSpec {
	registry := map[string]duanjuSourceSpec{}
	for _, spec := range duanjuProviderCatalog {
		registry[spec.ID] = spec
	}
	return registry
}()

func isDuanjuProviderSource(source string) bool {
	_, found := duanjuSourcesByName[canonicalProviderSource(source)]
	return found
}

func duanjuSourceSpecFor(source string) (duanjuSourceSpec, bool) {
	spec, found := duanjuSourcesByName[canonicalProviderSource(source)]
	return spec, found
}

func duanjuSourceName(source string) string {
	if spec, found := duanjuSourceSpecFor(source); found {
		return spec.Name
	}
	return canonicalProviderSource(source)
}

func (d *Downloader) duanjuBaseURL(source string) string {
	spec, found := duanjuSourceSpecFor(source)
	if !found {
		return ""
	}
	base := strings.TrimRight(spec.Base, "/")
	if configured := strings.TrimRight(d.providerHosts[canonicalProviderSource(source)], "/"); configured != "" {
		// 站点重定向只更换域名，注册的路径前缀依然有效。直接采用学习到的
		// 主机名会把带目录前缀的站源地址打散（子路径被丢掉后落到站点的
		// 默认首页），所以同源时只替换主机部分。
		specURL, specErr := url.Parse(base)
		learnedURL, learnedErr := url.Parse(configured)
		if specErr == nil && learnedErr == nil && learnedURL.Host != "" && specURL.Path != "" {
			specURL.Scheme = learnedURL.Scheme
			specURL.Host = learnedURL.Host
			return strings.TrimRight(specURL.String(), "/")
		}
		return configured
	}
	return base
}

func duanjuSourceForHost(host string) string {
	host = strings.ToLower(strings.TrimSpace(host))
	switch {
	case host == "app.whjzjx.cn" || host == "u.shytkjgs.com":
		return sourceYaguo
	case host == "api-store.qmplaylet.com" || host == "api-read.qmplaylet.com":
		return sourceMaoguo
	case host == "xifan-api-cn.youlishipin.com":
		return sourceFanguo
	case host == "api.drama.9ddm.com":
		return sourceGuanguo
	case host == "www.kuaikaw.cn" || host == "kuaikaw.cn":
		return sourceHeguo
	case host == "read.api.duodutek.com":
		return sourceXingguo
	case host == "www.zywest263.com" || host == "zywest263.com":
		return sourceHuaguo
	case host == "ccc.chaojichaojichanga.com":
		return sourceNiuguo
	case host == "www.duanju55.com" || host == "duanju55.com":
		return sourceWuguo
	case host == "www.shanekids.com" || host == "shanekids.com":
		return sourceChaoguo
	case host == "dmxq40.com" || host == "www.dmxq40.com":
		return sourceMiguo
	case host == "www.duanju2.com" || host == "duanju2.com":
		return sourceShuangguo
	case host == "xqxq1.cc" || host == "www.xqxq1.cc":
		return sourceYanguo
	case host == "lujj31.buzz" || host == "www.lujj31.buzz":
		return sourceTaoguo
	case host == "youavhub.com" || host == "www.youavhub.com":
		return sourceYouguo
	case host == "llsp.me" || host == "www.llsp.me":
		return sourceLiuguo
	case host == "shiresm.lol" || host == "www.shiresm.lol":
		return sourceMeiguo
	case host == "qingyiduz.xyz" || host == "a.qingyiduz.xyz":
		return sourceChengguo
	case host == "yese.co" || host == "www.yese.co":
		return sourceXiaoguo
	case host == "missav02.xyz" || host == "www.missav02.xyz":
		return sourceYingguo
	case host == "luyitian.com" || host == "www.luyitian.com":
		return sourceLuguo
	case host == "ririlu.cc" || host == "www.ririlu.cc":
		return sourceLiguo
	case host == "bulunhufait.buzz" || host == "4tw3gy653a.bulunhufait.buzz":
		return sourceJuguo
	case host == "yhsp5.yachts" || host == "www.yhsp5.yachts":
		return sourceZaoguo
	case host == "yhsp9.homes" || host == "www.yhsp9.homes":
		return sourceZaoguo
	case host == "toptv15.cyou" || host == "www.toptv15.cyou":
		return sourceNingguo
	case host == "zsrenqi.xyz" || host == "zsrqab03.zsrenqi.xyz":
		return sourceMangguo
	default:
		return ""
	}
}

func validDuanjuCategory(source, category string) bool {
	if category == "" {
		return true
	}
	if len(category) > 128 || strings.ContainsAny(category, "|/\\\x00\r\n") {
		return false
	}
	switch canonicalProviderSource(source) {
	case sourceMaoguo:
		return validMaoguoCategory(category)
	case sourceXingguo:
		if category == xingguoWalkCategory {
			return true
		}
		return webProviderNumericID.MatchString(strings.SplitN(category, "-", 2)[0])
	case sourceHeguo, sourceYaguo, sourceNiuguo:
		return webProviderNumericID.MatchString(strings.SplitN(category, "-", 2)[0])
	case sourceFanguo, sourceGuanguo:
		return true
	case sourceChaoguo:
		return validChaoguoCategory(category)
	default:
		return true
	}
}

func validMaoguoCategory(category string) bool {
	body := strings.TrimPrefix(strings.TrimSpace(category), "-")
	if body == "" || len(body) > 18 {
		return false
	}
	for _, digit := range body {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

type duanjuCategory struct {
	ID   string
	Name string
}

var duanjuStaticCategories = map[string][]duanjuCategory{
	sourceYaguo: {
		{ID: "1", Name: "剧场"},
		{ID: "9", Name: "榜单"},
	},
	sourceMaoguo: {
		{ID: "0", Name: "推荐"},
	},
	sourceFanguo: {
		{ID: "都市", Name: "都市"},
		{ID: "甜宠", Name: "甜宠"},
		{ID: "逆袭", Name: "逆袭"},
		{ID: "战神", Name: "战神"},
		{ID: "古装", Name: "古装"},
		{ID: "穿越", Name: "穿越"},
		{ID: "萌宝", Name: "萌宝"},
		{ID: "总裁", Name: "总裁"},
		{ID: "重生", Name: "重生"},
		{ID: "复仇", Name: "复仇"},
		{ID: "豪门", Name: "豪门"},
		{ID: "虐恋", Name: "虐恋"},
		{ID: "年代", Name: "年代"},
		{ID: "神医", Name: "神医"},
		{ID: "玄幻", Name: "玄幻"},
		{ID: "言情", Name: "言情"},
		{ID: "家庭", Name: "家庭"},
		{ID: "婚姻", Name: "婚姻"},
		{ID: "异能", Name: "异能"},
		{ID: "赘婿", Name: "赘婿"},
		{ID: "王妃", Name: "王妃"},
		{ID: "修仙", Name: "修仙"},
		{ID: "武侠", Name: "武侠"},
		{ID: "宫廷", Name: "宫廷"},
		{ID: "江湖", Name: "江湖"},
		{ID: "职场", Name: "职场"},
		{ID: "青春", Name: "青春"},
		{ID: "灵异", Name: "灵异"},
		{ID: "兵王", Name: "兵王"},
		{ID: "龙王", Name: "龙王"},
		{ID: "弃女", Name: "弃女"},
		{ID: "真假千金", Name: "真假千金"},
		{ID: "追妻", Name: "追妻"},
		{ID: "闪婚", Name: "闪婚"},
		{ID: "离婚", Name: "离婚"},
		{ID: "短剧", Name: "短剧"},
	},
	sourceXingguo: {
		{ID: "1287", Name: "推荐一"},
		{ID: "1288", Name: "推荐二"},
		{ID: "1289", Name: "推荐三"},
		{ID: "1290", Name: "推荐四"},
		{ID: "1291", Name: "推荐五"},
	},
	sourceNiuguo: {
		{ID: "5", Name: "短剧"},
		{ID: "1", Name: "电影"},
		{ID: "2", Name: "电视剧"},
		{ID: "4", Name: "动漫"},
		{ID: "3", Name: "综艺"},
	},
	sourceHeguo: {
		{ID: "462", Name: "甜宠"},
		{ID: "1102", Name: "古装仙侠"},
		{ID: "1145", Name: "现代言情"},
		{ID: "1170", Name: "青春"},
		{ID: "585", Name: "豪门恩怨"},
		{ID: "417-464", Name: "逆袭"},
		{ID: "439-465", Name: "重生"},
		{ID: "1159", Name: "系统"},
		{ID: "1147", Name: "总裁"},
		{ID: "943", Name: "职场商战"},
	},
	sourceChengguo: {
		{ID: "1", Name: "日韩电影"},
		{ID: "2", Name: "欧美视频"},
		{ID: "3", Name: "国产高清"},
		{ID: "4", Name: "动漫精品"},
	},
	// 该站的分类参数被服务端忽略，任何分类都返回同一批内容，因此只保留站方自己声明的分类。
	sourceXiaoguo: {
		{ID: "1", Name: "亚洲情色"},
	},
	sourceYingguo: {
		{ID: "28", Name: "日本中字"},
		{ID: "20", Name: "国产精品"},
		{ID: "21", Name: "人妻"},
		{ID: "22", Name: "无码精品"},
		{ID: "23", Name: "欧美精品"},
		{ID: "24", Name: "动漫精品"},
		{ID: "25", Name: "综合三级"},
	},
	sourceLuguo: {
		{ID: "26", Name: "国产精品"},
		{ID: "27", Name: "国产剧情"},
		{ID: "29", Name: "国产自拍"},
		{ID: "31", Name: "人妻"},
		{ID: "35", Name: "国产主播"},
		{ID: "44", Name: "素人"},
		{ID: "51", Name: "日本中字"},
		{ID: "101", Name: "有码精品"},
		{ID: "102", Name: "无码精品"},
		{ID: "103", Name: "动漫精品"},
	},
	sourceLiguo: {
		{ID: "28", Name: "中文字幕"},
		{ID: "20", Name: "国产"},
		{ID: "21", Name: "日本有码"},
		{ID: "22", Name: "日本无码"},
		{ID: "23", Name: "欧美"},
		{ID: "24", Name: "动漫"},
	},
	sourceJuguo: {
		{ID: "66", Name: "中文字幕"},
		{ID: "19", Name: "日韩无码"},
		{ID: "9", Name: "日韩主播"},
		{ID: "143", Name: "强奸乱伦"},
		{ID: "636", Name: "家庭乱伦"},
		{ID: "38", Name: "大秀视频"},
		{ID: "357", Name: "制服诱惑"},
		{ID: "52", Name: "欧美"},
		{ID: "418", Name: "日本动漫"},
		{ID: "600", Name: "极品资源"},
		{ID: "424", Name: "麻豆视频"},
		{ID: "427", Name: "蜜桃传媒"},
	},
	sourceZaoguo: {
		{ID: "21", Name: "女神学生"},
		{ID: "22", Name: "美女直播"},
		{ID: "23", Name: "人妻系列"},
		{ID: "24", Name: "强奸乱伦"},
		{ID: "25", Name: "自拍偷拍"},
		{ID: "26", Name: "制服诱惑"},
		{ID: "27", Name: "巨乳系列"},
		{ID: "28", Name: "自慰系列"},
		{ID: "29", Name: "国产视频"},
		{ID: "30", Name: "无码视频"},
		{ID: "31", Name: "有码视频"},
		{ID: "32", Name: "中文字幕"},
		{ID: "33", Name: "日韩精品"},
		{ID: "34", Name: "欧美精品"},
		{ID: "35", Name: "动漫精品"},
		{ID: "36", Name: "三级伦理"},
	},
	sourceNingguo: {
		{ID: "1", Name: "国产自拍"},
		{ID: "2", Name: "国产传媒"},
		{ID: "3", Name: "探花系列"},
		{ID: "4", Name: "人妻熟女"},
		{ID: "5", Name: "日本无码"},
		{ID: "6", Name: "美乳巨乳"},
		{ID: "7", Name: "强制侵犯"},
		{ID: "8", Name: "制服诱惑"},
		{ID: "9", Name: "绝色佳人"},
		{ID: "10", Name: "家庭乱伦"},
		{ID: "11", Name: "绝顶潮吹"},
		{ID: "12", Name: "网红主播"},
	},
	sourceMangguo: {
		{ID: "20", Name: "视频二区"},
		{ID: "24", Name: "视频三区"},
		{ID: "32", Name: "视频四区"},
		{ID: "40", Name: "欧美系列"},
		{ID: "1", Name: "视频一区"},
		{ID: "2", Name: "视频二区"},
	},
	sourceMeiguo: {
		{ID: "4", Name: "精品推荐"},
		{ID: "1", Name: "国产乱伦"},
		{ID: "7", Name: "国产高清"},
		{ID: "2", Name: "制服诱惑"},
		{ID: "3", Name: "中文字幕"},
		{ID: "6", Name: "日韩专区"},
		{ID: "5", Name: "成人动漫"},
		{ID: "8", Name: "欧美极品"},
	},
	sourceLiuguo: {
		{ID: "3", Name: "国产精品"},
		{ID: "4", Name: "国产自拍"},
		{ID: "5", Name: "国产偷拍"},
		{ID: "6", Name: "探花视频"},
		{ID: "7", Name: "主播福利"},
		{ID: "8", Name: "丝袜恋足"},
		{ID: "9", Name: "网红爆料"},
		{ID: "10", Name: "明星换脸"},
		{ID: "11", Name: "母狗调教"},
		{ID: "12", Name: "国产乱伦"},
		{ID: "13", Name: "学生嫩妹"},
		{ID: "14", Name: "人妻少妇"},
		{ID: "15", Name: "港台美女"},
		{ID: "16", Name: "抖阴视频"},
		{ID: "17", Name: "麻豆传媒"},
		{ID: "18", Name: "日韩情色"},
		{ID: "20", Name: "日本无码"},
		{ID: "21", Name: "韩国无码"},
		{ID: "22", Name: "欧美无码"},
		{ID: "23", Name: "中文字幕"},
		{ID: "24", Name: "黄色动漫"},
		{ID: "25", Name: "三级伦理"},
		{ID: "26", Name: "香港三级"},
		{ID: "27", Name: "韩国三级"},
		{ID: "28", Name: "丝袜制服"},
		{ID: "29", Name: "童颜巨乳"},
		{ID: "30", Name: "熟女人妻"},
		{ID: "31", Name: "少女萝莉"},
		{ID: "32", Name: "强奸乱伦"},
		{ID: "33", Name: "变态调教"},
		{ID: "34", Name: "女优高清"},
		{ID: "35", Name: "淫乱群交"},
		{ID: "36", Name: "口交颜射"},
		{ID: "37", Name: "男同女同"},
		{ID: "38", Name: "淫语解说"},
		{ID: "39", Name: "第一视角"},
		{ID: "40", Name: "女优大全"},
	},
	sourceYouguo: {
		{ID: "1", Name: "全部"},
		{ID: "20", Name: "巨乳"},
		{ID: "21", Name: "熟女人妻"},
		{ID: "22", Name: "日本AV"},
		{ID: "23", Name: "中文字幕"},
		{ID: "24", Name: "少女蘿莉"},
		{ID: "25", Name: "抖陰短片"},
		{ID: "26", Name: "翹臀美尻"},
		{ID: "27", Name: "高潮潮吹"},
		{ID: "28", Name: "歐美無碼"},
		{ID: "29", Name: "亂倫、誘惑"},
		{ID: "30", Name: "國產素人自拍"},
		{ID: "32", Name: "同性戀"},
		{ID: "33", Name: "AV女優無碼"},
		{ID: "34", Name: "制服誘惑"},
		{ID: "37", Name: "麻豆"},
		{ID: "38", Name: "SM調教"},
		{ID: "39", Name: "激情口交"},
		{ID: "40", Name: "野外性愛"},
		{ID: "41", Name: "多P群交"},
		{ID: "43", Name: "18+成人激情電影"},
		{ID: "45", Name: "AI換臉"},
	},
	sourceTaoguo: {
		{ID: "1", Name: "国产精品"},
		{ID: "2", Name: "亚洲综合"},
		{ID: "4", Name: "工口动漫"},
		{ID: "6", Name: "cosplay"},
		{ID: "7", Name: "国产乱伦"},
		{ID: "8", Name: "91大神"},
		{ID: "9", Name: "主播网红"},
		{ID: "10", Name: "清纯学生"},
		{ID: "11", Name: "国产原创"},
		{ID: "12", Name: "怀旧AV"},
		{ID: "13", Name: "日本有码"},
		{ID: "14", Name: "日本无码"},
		{ID: "20", Name: "国产自拍"},
		{ID: "21", Name: "偷拍偷窥"},
		{ID: "23", Name: "抖阴短片"},
		{ID: "24", Name: "日韩主播"},
		{ID: "25", Name: "中文字幕"},
		{ID: "26", Name: "AI明星"},
		{ID: "27", Name: "强奸乱伦"},
		{ID: "28", Name: "女优明星"},
		{ID: "29", Name: "VR视角"},
		{ID: "30", Name: "SM调教"},
		{ID: "31", Name: "泰国风情"},
		{ID: "32", Name: "绝色佳人"},
		{ID: "33", Name: "泡泡浴"},
		{ID: "34", Name: "时间停止"},
		{ID: "35", Name: "漫改系列"},
		{ID: "36", Name: "绝顶潮吹"},
	},
	sourceYanguo: {
		{ID: "44", Name: "日本"},
		{ID: "46", Name: "国产"},
		{ID: "50", Name: "传媒"},
		{ID: "48", Name: "主播"},
		{ID: "47", Name: "探花"},
		{ID: "45", Name: "乱伦"},
		{ID: "51", Name: "偷拍"},
		{ID: "49", Name: "吃瓜"},
		{ID: "53", Name: "字幕"},
		{ID: "61", Name: "日韩精选"},
		{ID: "62", Name: "口交"},
		{ID: "63", Name: "多P"},
		{ID: "64", Name: "VR"},
		{ID: "65", Name: "素人"},
		{ID: "66", Name: "学生"},
		{ID: "67", Name: "迷奸"},
		{ID: "68", Name: "制服"},
		{ID: "70", Name: "反差"},
		{ID: "71", Name: "异域"},
		{ID: "72", Name: "AI短剧"},
	},
	sourceShuangguo: {
		{ID: "all", Name: "全部"},
		{ID: "反转爽文", Name: "反转爽文"},
		{ID: "古装仙侠", Name: "古装仙侠"},
		{ID: "女频恋爱", Name: "女频恋爱"},
		{ID: "年代穿越", Name: "年代穿越"},
		{ID: "现代言情", Name: "现代言情"},
		{ID: "现代都市", Name: "现代都市"},
		{ID: "短剧", Name: "短剧"},
	},
	sourceMiguo: {
		{ID: "36", Name: "短剧"},
		{ID: "netflix", Name: "Netflix"},
		{ID: "21", Name: "电视剧"},
		{ID: "20", Name: "电影"},
		{ID: "22", Name: "动漫"},
		{ID: "23", Name: "综艺"},
	},
	sourceHuaguo: {
		{ID: "27", Name: "短剧"},
	},
	sourceWuguo: {
		{ID: "都市", Name: "都市"},
		{ID: "逆袭", Name: "逆袭"},
		{ID: "穿越", Name: "穿越"},
		{ID: "女频", Name: "女频"},
		{ID: "男频", Name: "男频"},
		{ID: "现代都市", Name: "现代都市"},
		{ID: "小人物", Name: "小人物"},
		{ID: "AI漫", Name: "AI漫"},
	},
	sourceChaoguo: {
		{ID: "class:mainstream", Name: "主流剧情"},
		{ID: "class:adult", Name: "成人向"},
		{ID: "class:anime_ip", Name: "动漫风格"},
		{ID: "class:unknown", Name: "其他"},
		{ID: "tag:都市", Name: "都市"},
		{ID: "tag:高颜值", Name: "高颜值"},
		{ID: "tag:现代", Name: "现代"},
		{ID: "tag:剧情", Name: "剧情"},
		{ID: "tag:古风", Name: "古风"},
		{ID: "tag:校园", Name: "校园"},
		{ID: "tag:逆袭", Name: "逆袭"},
		{ID: "tag:职场", Name: "职场"},
		{ID: "tag:甜宠", Name: "甜宠"},
		{ID: "tag:穿越", Name: "穿越"},
		{ID: "tag:玄幻", Name: "玄幻"},
		{ID: "tag:重生", Name: "重生"},
	},
}

func duanjuQueryEscape(value string) string { return url.QueryEscape(strings.TrimSpace(value)) }

func duanjuAbsolute(base, reference string) string {
	reference = strings.TrimSpace(reference)
	if reference == "" {
		return ""
	}
	if strings.HasPrefix(reference, "//") {
		return "https:" + reference
	}
	address, err := url.Parse(reference)
	if err != nil {
		return ""
	}
	if address.IsAbs() {
		return address.String()
	}
	origin, err := url.Parse(strings.TrimRight(base, "/") + "/")
	if err != nil {
		return ""
	}
	return origin.ResolveReference(address).String()
}
