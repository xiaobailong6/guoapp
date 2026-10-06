package core

import (
	"encoding/json"
	"os"
	"testing"
)

type providerContractCase struct {
	source   string
	name     string
	category string
	query    string
}

// maccmsContractCases 由站源目录自动推导，新增站源若漏接任何一环都会在这里失败。
func maccmsContractCases(t *testing.T) []providerContractCase {
	t.Helper()
	queries := map[string]string{
		sourceMiguo: "剧", sourceShuangguo: "生活", sourceYanguo: "学生",
		sourceTaoguo: "学生", sourceYouguo: "巨乳", sourceLiuguo: "换脸",
		sourceMeiguo: "制服", sourceHuaguo: "都市", sourceWuguo: "都市",
		sourceChengguo: "巨乳", sourceXiaoguo: "巨乳",
		sourceYingguo: "中文字幕", sourceLuguo: "中文字幕",
		sourceLiguo: "国产", sourceJuguo: "中文字幕", sourceZaoguo: "中文字幕",
		sourceNingguo: "国产自拍", sourceMangguo: "视频二区",
	}
	var cases []providerContractCase
	for _, spec := range duanjuProviderCatalog {
		if spec.Kind != "maccms" {
			continue
		}
		static, found := duanjuStaticCategories[spec.ID]
		if !found || len(static) == 0 {
			t.Fatalf("%s declares maccms but has no static categories", spec.ID)
		}
		query, found := queries[spec.ID]
		if !found {
			t.Fatalf("%s is missing a contract query; every maccms source must be covered", spec.ID)
		}
		cases = append(cases, providerContractCase{
			source: spec.ID, name: spec.Name, category: static[0].ID, query: query,
		})
	}
	if len(cases) == 0 {
		t.Fatal("no maccms sources were discovered")
	}
	return cases
}

func TestMaccmsSourcesAreFullyWired(t *testing.T) {
	for _, item := range maccmsContractCases(t) {
		if !isDuanjuProviderSource(item.source) {
			t.Fatalf("%s must be a registered source", item.source)
		}
		if !duanjuSupportsSearch(item.source) {
			t.Fatalf("%s must look searchable in the app", item.source)
		}
		// 只列出首页、没有翻页入口的站源：米果的分类页后续页返回同一批条目，
		// 樱果与露果则在模板里根本没有分页控件。
		switch item.source {
		case sourceMiguo, sourceYingguo, sourceLuguo, sourceLiguo, sourceJuguo,
			sourceZaoguo, sourceNingguo, sourceMangguo:
		default:
			if !duanjuSupportsPaging(item.source) {
				t.Fatalf("%s must look pageable in the app", item.source)
			}
		}
		if !validDuanjuCategory(item.source, item.category) {
			t.Fatalf("%s must accept category %s", item.source, item.category)
		}
	}
}

// TestNativeRequestServesEveryMaccmsSource 走 Dart 实际调用的顶层入口，
// 覆盖 分类 -> 目录 -> 搜索 -> 详情 四条真实链路。
func TestNativeRequestServesEveryMaccmsSource(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	previous := buildAllSources
	buildAllSources = "true"
	defer func() { buildAllSources = previous }()

	directory := t.TempDir()
	if response := NativeRequest(`{"action":"initialize","directory":"` + directory + `"}`); !containsText(response, `"ok":true`) {
		t.Fatal("engine did not start", response)
	}
	defer NativeRequest(`{"action":"release"}`)

	for _, item := range maccmsContractCases(t) {
		// 1. 分类列表必须包含首个静态分类。
		raw, _ := json.Marshal(map[string]any{"action": "categories", "source": item.source})
		response := NativeRequest(string(raw))
		if !containsText(response, `"ok":true`) {
			t.Fatalf("%s categories failed: %s", item.name, response)
		}
		_ = response
		if !containsText(response, `"id":"`+item.category+`"`) {
			t.Fatalf("%s categories missing %s", item.name, item.category)
		}

		// 2. 目录页必须返回条目。
		raw, _ = json.Marshal(map[string]any{
			"action": "catalog", "source": item.source, "category": item.category, "page": 1,
		})
		response = NativeRequest(string(raw))
		if !containsText(response, `"ok":true`) {
			// 上游封锁（浏览器验证、限流）属于外部条件，不掩盖接线错误。
			if containsText(response, `"source_blocked"`) {
				t.Logf("%s skipped: upstream blocked the catalog request", item.name)
				continue
			}
			t.Fatalf("%s catalog failed: %s", item.name, response)
		}
		var catalog struct {
			Data struct {
				Items []nativeDrama `json:"items"`
			} `json:"data"`
		}
		if err := json.Unmarshal([]byte(response), &catalog); err != nil {
			t.Fatalf("%s catalog response is not readable: %v", item.name, err)
		}
		if len(catalog.Data.Items) == 0 {
			t.Fatalf("%s catalog returned no items", item.name)
		}
		for _, drama := range catalog.Data.Items {
			if drama.ID == "" || drama.Title == "" || drama.Source != item.source {
				t.Fatalf("%s catalog item is incomplete: %+v", item.name, drama)
			}
			// 站点拼装的 SEO/状态文案不能出现在剧名里。
			for _, noise := range []string{"详情介绍", "剧情介绍", "在线播放", "立即播放", "猜你喜欢", "相关推荐"} {
				if containsText(drama.Title, noise) {
					t.Fatalf("%s title was not cleaned: %q", item.name, drama.Title)
				}
			}
		}

		// 3. 站内搜索必须返回条目。
		raw, _ = json.Marshal(map[string]any{
			"action": "catalog", "source": item.source, "query": item.query, "page": 1,
		})
		response = NativeRequest(string(raw))
		if !containsText(response, `"ok":true`) {
			t.Fatalf("%s search failed: %s", item.name, response)
		}
		if err := json.Unmarshal([]byte(response), &catalog); err != nil {
			t.Fatalf("%s search response is not readable: %v", item.name, err)
		}
		if len(catalog.Data.Items) == 0 {
			t.Fatalf("%s search returned no items for %q", item.name, item.query)
		}

		// 4. 详情必须返回可播放章节。
		target := catalog.Data.Items[0]
		raw, _ = json.Marshal(map[string]any{"action": "detail", "drama": target})
		response = NativeRequest(string(raw))
		if !containsText(response, `"ok":true`) {
			t.Fatalf("%s detail failed: %s", item.name, response)
		}
		var detail struct {
			Data struct {
				Chapters []Chapter `json:"chapters"`
			} `json:"data"`
		}
		if err := json.Unmarshal([]byte(response), &detail); err != nil {
			t.Fatalf("%s detail response is not readable: %v", item.name, err)
		}
		if len(detail.Data.Chapters) == 0 {
			t.Fatalf("%s detail returned no chapters", item.name)
		}
		playable := 0
		for _, chapter := range detail.Data.Chapters {
			if chapter.VideoURL != "" || chapter.PageURL != "" {
				playable++
			}
		}
		if playable == 0 {
			t.Fatalf("%s chapters carry no playable address", item.name)
		}
		t.Logf("%s ok: category=%s catalog=%d search=%q:%d detail=%q chapters=%d",
			item.name, item.category, len(catalog.Data.Items), item.query,
			len(catalog.Data.Items), target.Title, len(detail.Data.Chapters))
	}
}
