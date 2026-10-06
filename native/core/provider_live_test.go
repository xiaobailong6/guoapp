package core

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestLiveProviderCatalogRankingDetailAndPlaybackSmoke(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	for _, scenario := range []struct {
		source string
		board  string
	}{
		{source: sourceHuangju, board: "huangju-hot"},
		{source: sourceYeguo, board: "yeguo-recommend"},
		{source: sourceDSD, board: "dsd-catalog"},
	} {
		t.Run(scenario.source, func(t *testing.T) {
			dramas, more, err := fetchLiveCatalogPage(ctx, engine.downloader, scenario.source)
			if err != nil || len(dramas) == 0 {
				t.Fatalf("catalog failed: count=%d more=%t err=%v", len(dramas), more, err)
			}
			board, found := findRankingBoard(scenario.board)
			if !found {
				t.Fatal("ranking board missing")
			}
			ranking, err := engine.downloader.loadRankingPage(ctx, board, 1, true)
			if err != nil || len(ranking.Items) == 0 {
				t.Fatalf("ranking failed: count=%d err=%v", len(ranking.Items), err)
			}
			var lastErr error
			for index, drama := range dramas {
				if index >= 8 {
					break
				}
				raw, chapters, err := fetchLiveDetail(ctx, engine.downloader, scenario.source, drama.SourceID)
				if err != nil {
					lastErr = err
					continue
				}
				if raw.ID != drama.ID || len(chapters) == 0 {
					lastErr = err
					continue
				}
				for chapterIndex, chapter := range chapters {
					if chapterIndex >= 4 {
						break
					}
					media, err := engine.downloader.resolveProviderMedia(ctx, Task{DramaID: raw.ID, DramaTitle: raw.DisplayTitle(), Chapter: chapter, Index: chapterIndex + 1})
					if err != nil {
						lastErr = err
						continue
					}
					choice := nativePlaybackChoices(media, 0)
					if len(choice.media) == 0 {
						lastErr = err
						continue
					}
					plan, err := engine.nativeOpenPlayback(ctx, choice)
					if err != nil {
						lastErr = err
						continue
					}
					engine.nativeReleasePlayback(plan.Session)
					if !strings.HasPrefix(plan.URL, "http://127.0.0.1:") || plan.RouteCount < 1 {
						t.Fatalf("playback plan did not use local stream route: %+v", plan)
					}
					t.Logf("%s live smoke ok: catalog=%d ranking=%d detail=%s chapters=%d routes=%d quality=%d", scenario.source, len(dramas), len(ranking.Items), raw.ID, len(chapters), plan.RouteCount, plan.Quality)
					return
				}
			}
			t.Fatalf("could not resolve a playable %s episode; last error: %v", scenario.source, lastErr)
		})
	}
}

func fetchLiveCatalogPage(ctx context.Context, d *Downloader, source string) ([]Drama, bool, error) {
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuCatalogPage(ctx, 1, "", "")
	case sourceYeguo:
		return d.fetchYeguoCatalogPage(ctx, 1, "", "")
	case sourceDSD:
		return d.fetchDSDCatalogPage(ctx, 1, "", "")
	default:
		return nil, false, errNativeBuildSource
	}
}

func TestLiveChaoguoCatalogSearchRankingAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchChaoguoCatalogPage(ctx, 1, "class:mainstream")
	if err != nil || len(first) == 0 {
		t.Fatalf("chaoguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	second, _, err := d.fetchChaoguoCatalogPage(ctx, 2, "class:mainstream")
	if err != nil || len(second) == 0 {
		t.Fatalf("chaoguo second page failed: count=%d err=%v", len(second), err)
	}
	seen := map[string]bool{}
	for _, drama := range append(append([]Drama{}, first...), second...) {
		if drama.ID == "" || drama.Source != sourceChaoguo || drama.Title == "" {
			t.Fatalf("chaoguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("chaoguo paging repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}

	results, _, err := d.searchChaoguoPage(ctx, "长生", 1)
	if err != nil || len(results) == 0 {
		t.Fatalf("chaoguo search failed: count=%d err=%v", len(results), err)
	}

	for _, id := range []string{"chaoguo-hot", "chaoguo-urban"} {
		board, found := findRankingBoard(id)
		if !found {
			t.Fatalf("chaoguo board %s is missing", id)
		}
		page, err := d.loadRankingPage(ctx, board, 1, true)
		if err != nil || len(page.Items) == 0 {
			t.Fatalf("chaoguo ranking %s failed: count=%d err=%v", id, len(page.Items), err)
		}
		for _, item := range page.Items {
			if item.Drama.ID == "" || item.Drama.Source != sourceChaoguo || item.Drama.Cover != nil {
				t.Fatalf("chaoguo ranking %s item is wrong: %+v", id, item.Drama)
			}
		}
	}

	drama, chapters, err := d.fetchChaoguoDetail(ctx, first[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("chaoguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || drama.EpisodeCount != json.Number(strconv.Itoa(len(chapters))) {
		t.Fatalf("chaoguo detail metadata is wrong: %+v", drama)
	}
	for _, chapter := range chapters {
		if !duanjuLooksLikeMedia(chapter.VideoURL) || chapter.Referer == "" {
			t.Fatalf("chaoguo chapter is not directly playable: %+v", chapter)
		}
	}
	t.Logf("chaoguo live ok: catalog=%d+%d search=%d hot=%d detail=%s chapters=%d",
		len(first), len(second), len(results), 50, drama.ID, len(chapters))
}

func fetchLiveDetail(ctx context.Context, d *Downloader, source, sourceID string) (Drama, []Chapter, error) {
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuDetail(ctx, sourceID)
	case sourceYeguo:
		return d.fetchYeguoDetail(ctx, sourceID)
	case sourceDSD:
		return d.fetchDSDDetail(ctx, sourceID)
	default:
		return Drama{}, nil, errNativeBuildSource
	}
}

func TestLiveMiguoCatalogSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	items, more, err := d.fetchMaccmsCatalogPage(ctx, sourceMiguo, 1, "36")
	if err != nil || len(items) == 0 {
		t.Fatalf("miguo catalog failed: count=%d more=%t err=%v", len(items), more, err)
	}
	if more {
		t.Fatalf("miguo catalog reports more pages, but the site returns one page")
	}
	seen := map[string]bool{}
	for _, drama := range items {
		if drama.ID == "" || drama.Source != sourceMiguo || drama.Title == "" {
			t.Fatalf("miguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("miguo catalog repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}
	// 站点分页返回同一批条目，第二页应与第一页一致而不是追加。
	again, _, err := d.fetchMaccmsCatalogPage(ctx, sourceMiguo, 2, "36")
	if err != nil {
		t.Fatalf("miguo second page failed: %v", err)
	}
	if len(again) != len(items) {
		t.Fatalf("miguo paging should repeat the same page: first=%d second=%d", len(items), len(again))
	}

	netflix, _, err := d.fetchMaccmsCatalogPage(ctx, sourceMiguo, 1, "netflix")
	if err != nil || len(netflix) == 0 {
		t.Fatalf("miguo netflix label failed: count=%d err=%v", len(netflix), err)
	}

	results, err := d.searchMaccms(ctx, sourceMiguo, "我")
	if err != nil || len(results) == 0 {
		t.Fatalf("miguo search failed: count=%d err=%v", len(results), err)
	}
	for _, drama := range results {
		if drama.Source != sourceMiguo || drama.Title == "" {
			t.Fatalf("miguo search item is incomplete: %+v", drama)
		}
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceMiguo, items[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("miguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || drama.Source != sourceMiguo {
		t.Fatalf("miguo detail is incomplete: %+v", drama)
	}
	playable := 0
	for _, chapter := range chapters {
		if strings.TrimSpace(chapter.VideoURL) != "" {
			playable++
		}
	}
	if playable == 0 {
		t.Fatalf("miguo detail has no playable chapter among %d", len(chapters))
	}
	media, err := d.resolveDuanjuMedia(ctx, Task{
		DramaID: nativeNormalize(items[0]).ID, Chapter: chapters[0],
	})
	if err != nil {
		t.Fatalf("miguo 解析播放地址失败: %v", err)
	}
	size := liveSegmentBytes(t, media.URL, miguoBaseURL+"/")
	if size < 1024 {
		t.Fatalf("miguo 首分片只有 %d 字节，地址可用但取不到画面: %s", size, media.URL)
	}
	t.Logf("miguo catalog=%d search=%d detail=%s chapters=%d playable=%d 首分片=%d字节",
		len(items), len(results), drama.Title, len(chapters), playable, size)
}

func TestLiveShuangguoCatalogSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceShuangguo, 1, "all")
	if err != nil || len(first) == 0 {
		t.Fatalf("shuangguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatalf("shuangguo should report more pages")
	}
	second, _, err := d.fetchMaccmsCatalogPage(ctx, sourceShuangguo, 2, "all")
	if err != nil || len(second) == 0 {
		t.Fatalf("shuangguo second page failed: count=%d err=%v", len(second), err)
	}
	seen := map[string]bool{}
	for _, drama := range append(append([]Drama{}, first...), second...) {
		if drama.ID == "" || drama.Source != sourceShuangguo || drama.Title == "" {
			t.Fatalf("shuangguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("shuangguo paging repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}

	trait, _, err := d.fetchMaccmsCatalogPage(ctx, sourceShuangguo, 1, "现代都市")
	if err != nil || len(trait) == 0 {
		t.Fatalf("shuangguo trait catalog failed: count=%d err=%v", len(trait), err)
	}
	// 题材分类是「全部」的子集，重合正常；关键是它确实被题材过滤过，
	// 不能与「全部」首页返回同一批条目。
	same := 0
	for _, drama := range trait {
		if seen[drama.ID] {
			same++
		}
	}
	if same == len(trait) && len(trait) == len(first) {
		t.Fatalf("shuangguo trait category returned the same page as the all category")
	}

	results, err := d.searchMaccms(ctx, sourceShuangguo, "狂")
	if err != nil || len(results) == 0 {
		t.Fatalf("shuangguo search failed: count=%d err=%v", len(results), err)
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceShuangguo, first[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("shuangguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || drama.Source != sourceShuangguo {
		t.Fatalf("shuangguo detail is incomplete: %+v", drama)
	}
	playable := 0
	for _, chapter := range chapters {
		if strings.TrimSpace(chapter.VideoURL) != "" {
			playable++
		}
	}
	if playable == 0 {
		t.Fatalf("shuangguo detail has no playable chapter among %d", len(chapters))
	}
	media, err := d.resolveDuanjuMedia(ctx, Task{
		DramaID: nativeNormalize(first[0]).ID, Chapter: chapters[0],
	})
	if err != nil {
		t.Fatalf("shuangguo 解析播放地址失败: %v", err)
	}
	size := liveSegmentBytes(t, media.URL, shuangguoBaseURL+"/")
	if size < 1024 {
		t.Fatalf("shuangguo 首分片只有 %d 字节，地址可用但取不到画面: %s", size, media.URL)
	}
	t.Logf("shuangguo catalog=%d+%d trait=%d search=%d detail=%s chapters=%d playable=%d 首分片=%d字节",
		len(first), len(second), len(trait), len(results), drama.Title, len(chapters), playable, size)
}

func TestLiveYanguoCatalogSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceYanguo, 1, "44")
	if err != nil || len(first) == 0 {
		t.Fatalf("yanguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatalf("yanguo should report more pages")
	}
	second, _, err := d.fetchMaccmsCatalogPage(ctx, sourceYanguo, 2, "44")
	if err != nil || len(second) == 0 {
		t.Fatalf("yanguo second page failed: count=%d err=%v", len(second), err)
	}
	seen := map[string]bool{}
	for _, drama := range append(append([]Drama{}, first...), second...) {
		if drama.ID == "" || drama.Source != sourceYanguo || drama.Title == "" {
			t.Fatalf("yanguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("yanguo paging repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}

	results, err := d.searchMaccms(ctx, sourceYanguo, "日本")
	if err != nil || len(results) == 0 {
		t.Fatalf("yanguo search failed: count=%d err=%v", len(results), err)
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceYanguo, first[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("yanguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || drama.Source != sourceYanguo {
		t.Fatalf("yanguo detail is incomplete: %+v", drama)
	}
	// 播放页里混有播放器自带的示例片地址，取到的必须是正片。
	for _, chapter := range chapters {
		if strings.Contains(chapter.VideoURL, "sample/test1.mp4") {
			t.Fatalf("yanguo picked the player sample clip instead of the feature: %q", chapter.VideoURL)
		}
	}
	t.Logf("yanguo catalog=%d+%d search=%d detail=%s chapters=%d first=%s",
		len(first), len(second), len(results), drama.Title, len(chapters), chapters[0].VideoURL)
}

func TestLiveTaoguoResolvesWrapperPlayerPage(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceTaoguo, 1, "1")
	if err != nil || len(first) == 0 {
		t.Fatalf("taoguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatalf("taoguo should report more pages")
	}
	seen := map[string]bool{}
	for _, drama := range first {
		if drama.ID == "" || drama.Source != sourceTaoguo || drama.Title == "" {
			t.Fatalf("taoguo catalog item is incomplete: %+v", drama)
		}
		if seen[drama.ID] {
			t.Fatalf("taoguo catalog repeated %s", drama.ID)
		}
		seen[drama.ID] = true
	}

	results, err := d.searchMaccms(ctx, sourceTaoguo, "学生")
	if err != nil || len(results) == 0 {
		t.Fatalf("taoguo search failed: count=%d err=%v", len(results), err)
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceTaoguo, first[0].SourceID)
	if err != nil || len(chapters) == 0 {
		t.Fatalf("taoguo detail failed: chapters=%d err=%v", len(chapters), err)
	}
	if drama.Title == "" || !strings.Contains(chapters[0].VideoURL, "lujj31.buzz") {
		t.Fatalf("taoguo detail is incomplete: %+v %q", drama, chapters[0].VideoURL)
	}

	// 该站播放数据指向 hsckyun 的 share 包装页，必须再取一层才能得到清单。
	media, err := d.resolveDuanjuWebPage(ctx, sourceTaoguo, chapters[0].PageURL, taoguoBaseURL+"/")
	if err != nil {
		t.Fatalf("taoguo play resolution failed: %v", err)
	}
	if !strings.HasSuffix(strings.ToLower(strings.Split(media.URL, "?")[0]), ".m3u8") {
		t.Fatalf("taoguo should resolve the wrapper page to a playlist, got %q", media.URL)
	}
	t.Logf("taoguo catalog=%d search=%d detail=%s chapters=%d resolved=%s",
		len(first), len(results), drama.Title, len(chapters), media.URL)
}

func TestLiveYouguoCatalogSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceYouguo, 1, "22")
	if err != nil || len(first) == 0 {
		t.Fatalf("youguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatal("youguo should report more pages")
	}
	second, _, err := d.fetchMaccmsCatalogPage(ctx, sourceYouguo, 2, "22")
	if err != nil || len(second) == 0 {
		t.Fatalf("youguo page 2 failed: count=%d err=%v", len(second), err)
	}
	pageOne := map[string]bool{}
	for _, drama := range first {
		pageOne[drama.ID] = true
	}
	overlap := 0
	for _, drama := range second {
		if pageOne[drama.ID] {
			overlap++
		}
	}
	if overlap == len(second) {
		t.Fatalf("youguo page 2 repeated page 1 entirely (%d items)", overlap)
	}
	// 编号必须取自 /play/id/{id}/sid/{sid}/nid/{nid}/，不能取成线路或分集序号。
	for _, drama := range first {
		if drama.SourceID == "1" || drama.Title == "" {
			t.Fatalf("youguo catalog id extraction is wrong: %+v", drama)
		}
	}

	results, err := d.searchMaccms(ctx, sourceYouguo, "巨乳")
	if err != nil || len(results) == 0 {
		t.Fatalf("youguo search failed: count=%d err=%v", len(results), err)
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceYouguo, first[0].SourceID)
	if err != nil {
		t.Fatalf("youguo detail failed: %v", err)
	}
	// 该站播放页里的其它链接是相关推荐，只能算作单集。
	if len(chapters) != 1 {
		t.Fatalf("youguo should expose exactly one part, got %d", len(chapters))
	}
	if drama.Title == "" {
		t.Fatal("youguo detail title is empty")
	}
	for _, chapter := range chapters {
		if !strings.Contains(chapter.PageURL, first[0].SourceID) {
			t.Fatalf("youguo chapter points at another drama: %q for %s", chapter.PageURL, first[0].SourceID)
		}
	}
	media, err := d.resolveDuanjuWebPage(ctx, sourceYouguo, chapters[0].PageURL, youguoBaseURL+"/")
	if err != nil {
		t.Fatalf("youguo play resolution failed: %v", err)
	}
	if !duanjuLooksLikeMedia(media.URL) {
		t.Fatalf("youguo should resolve to a media address, got %q", media.URL)
	}
	t.Logf("youguo catalog=%d/%d search=%d detail=%s chapters=%d media=%s",
		len(first), len(second), len(results), drama.Title, len(chapters), media.URL)
}

func TestLiveLiuguoCatalogSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceLiuguo, 1, "10")
	if err != nil || len(first) == 0 {
		t.Fatalf("liuguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatal("liuguo should report more pages")
	}
	second, _, err := d.fetchMaccmsCatalogPage(ctx, sourceLiuguo, 2, "10")
	if err != nil || len(second) == 0 {
		t.Fatalf("liuguo page 2 failed: count=%d err=%v", len(second), err)
	}
	pageOne := map[string]bool{}
	for _, drama := range first {
		pageOne[drama.ID] = true
	}
	overlap := 0
	for _, drama := range second {
		if pageOne[drama.ID] {
			overlap++
		}
	}
	if overlap == len(second) {
		t.Fatalf("liuguo page 2 repeated page 1 entirely (%d items)", overlap)
	}
	for _, drama := range first {
		if drama.SourceID == "1" || drama.Title == "" {
			t.Fatalf("liuguo catalog id extraction is wrong: %+v", drama)
		}
	}

	results, err := d.searchMaccms(ctx, sourceLiuguo, "换脸")
	if err != nil || len(results) == 0 {
		t.Fatalf("liuguo search failed: count=%d err=%v", len(results), err)
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceLiuguo, first[0].SourceID)
	if err != nil {
		t.Fatalf("liuguo detail failed: %v", err)
	}
	if len(chapters) != 1 {
		t.Fatalf("liuguo should expose exactly one part, got %d", len(chapters))
	}
	if drama.Title == "" || maccmsIsSectionHeading(drama.Title) {
		t.Fatalf("liuguo detail should report a real title, got %q", drama.Title)
	}
	media, err := d.resolveDuanjuWebPage(ctx, sourceLiuguo, chapters[0].PageURL, liuguoBaseURL+"/")
	if err != nil {
		t.Fatalf("liuguo play resolution failed: %v", err)
	}
	if !duanjuLooksLikeMedia(media.URL) {
		t.Fatalf("liuguo should resolve to a media address, got %q", media.URL)
	}
	t.Logf("liuguo catalog=%d/%d search=%d detail=%s chapters=%d media=%s",
		len(first), len(second), len(results), drama.Title, len(chapters), media.URL)
}

func TestLiveMeiguoCatalogSuggestSearchAndDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := engine.downloader

	first, more, err := d.fetchMaccmsCatalogPage(ctx, sourceMeiguo, 1, "1")
	if err != nil || len(first) == 0 {
		t.Fatalf("meiguo catalog failed: count=%d more=%t err=%v", len(first), more, err)
	}
	if !more {
		t.Fatal("meiguo should report more pages")
	}
	second, _, err := d.fetchMaccmsCatalogPage(ctx, sourceMeiguo, 2, "1")
	if err != nil || len(second) == 0 {
		t.Fatalf("meiguo page 2 failed: count=%d err=%v", len(second), err)
	}
	pageOne := map[string]bool{}
	for _, drama := range first {
		pageOne[drama.ID] = true
	}
	overlap := 0
	for _, drama := range second {
		if pageOne[drama.ID] {
			overlap++
		}
	}
	if overlap == len(second) {
		t.Fatalf("meiguo page 2 repeated page 1 entirely (%d items)", overlap)
	}

	// 该站 HTML 搜索页返回 500，搜索必须走 suggest JSON 接口。
	results, err := d.searchMaccms(ctx, sourceMeiguo, "制服")
	if err != nil || len(results) == 0 {
		t.Fatalf("meiguo suggest search failed: count=%d err=%v", len(results), err)
	}
	hits := 0
	for _, item := range results {
		if item.SourceID == "" || item.Title == "" {
			t.Fatalf("meiguo suggest item is incomplete: %+v", item)
		}
		if strings.Contains(item.Title, "制服") {
			hits++
		}
	}
	if hits == 0 {
		t.Fatal("meiguo suggest search returned nothing matching the query")
	}

	drama, chapters, err := d.fetchMaccmsDetail(ctx, sourceMeiguo, first[0].SourceID)
	if err != nil {
		t.Fatalf("meiguo detail failed: %v", err)
	}
	if len(chapters) != 1 {
		t.Fatalf("meiguo should expose exactly one part, got %d", len(chapters))
	}
	if drama.Title == "" || strings.Contains(drama.Title, "详情介绍") {
		t.Fatalf("meiguo detail title should drop the seo marker, got %q", drama.Title)
	}
	media, err := d.resolveDuanjuWebPage(ctx, sourceMeiguo, chapters[0].PageURL, meiguoBaseURL+"/")
	if err != nil {
		t.Fatalf("meiguo play resolution failed: %v", err)
	}
	if !duanjuLooksLikeMedia(media.URL) {
		t.Fatalf("meiguo should resolve to a media address, got %q", media.URL)
	}
	t.Logf("meiguo catalog=%d/%d suggestSearch=%d hits=%d detail=%s chapters=%d media=%s",
		len(first), len(second), len(results), hits, drama.Title, len(chapters), media.URL)
}

func TestLiveXiaoguoAndChengguoDetail(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()
	d := engine.downloader

	for _, item := range []struct{ source, id string }{
		{sourceXiaoguo, "302677"},
		{sourceChengguo, "22723"},
		{sourceMiguo, "238123"},
		{sourceYanguo, "546309"},
		{sourceHuaguo, "1"},
		{sourceWuguo, "1"},
	} {
		drama, chapters, err := d.fetchMaccmsDetail(ctx, item.source, item.id)
		if err != nil {
			t.Fatalf("%s detail failed: %v", item.source, err)
		}
		t.Logf("%s title=%q chapters=%d", item.source, drama.Title, len(chapters))
		for index, chapter := range chapters {
			if index < 4 {
				t.Logf("    [%d] title=%q page=%s", index, chapter.Title, chapter.PageURL)
			}
		}
	}
}

// liveProxy 在 macOS 上没有原生系统代理探测，实测需要代理的站源时显式传入。
func liveProxy(engine *nativeEngine) error {
	address := strings.TrimSpace(os.Getenv("LIVE_PROXY"))
	if address == "" {
		return nil
	}
	return engine.updateSystemProxy(nativeSystemProxy{HTTP: address, HTTPS: address})
}

func TestLiveYingguoAndLuguoPlayback(t *testing.T) {
	if os.Getenv("CHECK_LIVE_PROVIDERS") != "true" {
		t.Skip("set CHECK_LIVE_PROVIDERS=true to touch live provider text APIs")
	}
	previous := buildAllSources
	buildAllSources = "true"
	t.Cleanup(func() { buildAllSources = previous })
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	if err := liveProxy(engine); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	for _, scenario := range []struct {
		source   string
		category string
	}{
		{source: sourceYingguo, category: "21"},
		{source: sourceLuguo, category: "26"},
		{source: sourceLiguo, category: "20"},
		{source: sourceJuguo, category: "66"},
		{source: sourceZaoguo, category: "29"},
		{source: sourceNingguo, category: "1"},
		{source: sourceMangguo, category: "20"},
	} {
		t.Run(scenario.source, func(t *testing.T) {
			items, _, err := engine.downloader.fetchDuanjuCatalogPage(ctx, scenario.source, 1, scenario.category)
			if err != nil || len(items) == 0 {
				t.Fatalf("catalog failed: count=%d err=%v", len(items), err)
			}
			t.Logf("目录 %d 条，首条标题=%q id=%s", len(items), items[0].Title, items[0].SourceID)
			if strings.TrimSpace(items[0].Title) == "" {
				t.Fatal("首条标题为空")
			}
			_, chapters, err := engine.downloader.fetchDuanjuDetail(ctx, scenario.source, items[0].SourceID)
			if err != nil || len(chapters) == 0 {
				t.Fatalf("detail failed: chapters=%d err=%v", len(chapters), err)
			}
			t.Logf("分集 %d 条", len(chapters))
			media, err := engine.downloader.resolveDuanjuMedia(ctx, Task{
				DramaID: nativeNormalize(items[0]).ID, Chapter: chapters[0],
			})
			if err != nil {
				t.Fatalf("resolve failed: %v", err)
			}
			if !isProviderHTTPMediaURL(media.URL) {
				t.Fatalf("无效播放地址: %q", media.URL)
			}
			// 这些站源的 CDN 会校验 Referer，传站源 id 当 Referer 会一律拒流，
			// 必须用站源自身的站点地址。
			size := liveSegmentBytes(t, media.URL, engine.downloader.duanjuBaseURL(scenario.source)+"/")
			if size < 1024 {
				t.Fatalf("首分片只有 %d 字节，地址可用但取不到画面: %s", size, media.URL)
			}
			t.Logf("播放地址 %s 首分片=%d字节", media.URL, size)
		})
	}
}

// liveSegmentBytes 取回首个可下载分片的字节数，作为「真的能出画面」的证据。
// 只断言章节地址非空是不够的：源站返回死链、空壳清单或占位地址时，
// 地址照样非空，但用户打开就是黑屏。
func liveSegmentBytes(t *testing.T, playlistURL, referer string) int {
	t.Helper()
	return liveSegmentBytesDepth(t, playlistURL, referer, 0)
}

func liveSegmentBytesDepth(t *testing.T, playlistURL, referer string, depth int) int {
	t.Helper()
	if depth > 3 {
		return 0
	}
	text := livePlaylistText(t, playlistURL, referer)
	if text == "" {
		return 0
	}
	// 主清单与媒体清单按 HLS 语义区分：带 EXT-X-STREAM-INF 的每一行都是
	// 变体清单，其余清单的每一行都是分片。分片不一定以 .ts 结尾——实测有
	// 站源把分片写成 seg_00000.jpg，按扩展名过滤会把可用站源误判成死链。
	master := strings.Contains(text, "#EXT-X-STREAM-INF")
	tried := 0
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if tried >= 8 {
			break
		}
		tried++
		address := line
		if !strings.HasPrefix(address, "http") {
			// 相对地址必须按 URL 规则解析：主清单普遍写的是 /path/x.m3u8
			// 这类根相对地址，用「当前目录 + 路径」拼接会拼出重复目录。
			address = ""
			if base, err := url.Parse(playlistURL); err == nil {
				if reference, err := url.Parse(line); err == nil {
					address = base.ResolveReference(reference).String()
				}
			}
			if address == "" {
				continue
			}
		}
		if master {
			if size := liveSegmentBytesDepth(t, address, referer, depth+1); size > 0 {
				return size
			}
			continue
		}
		if size := len(livePlaylistTextRaw(t, address, referer)); size > 0 {
			return size
		}
	}
	return 0
}

func livePlaylistText(t *testing.T, address, referer string) string {
	t.Helper()
	body := livePlaylistTextRaw(t, address, referer)
	text := string(body)
	if !strings.Contains(text, "#EXTM3U") {
		return ""
	}
	return text
}

func livePlaylistTextRaw(t *testing.T, address, referer string) []byte {
	t.Helper()
	request, err := http.NewRequest(http.MethodGet, address, nil)
	if err != nil {
		return nil
	}
	request.Header.Set("User-Agent", duanjuUserAgent)
	if referer != "" {
		request.Header.Set("Referer", referer)
	}
	// 实测这批媒体 CDN 会偶发超时与 5xx，重试两次再判定失败，
	// 避免把网络抖动写成「站源不可用」。
	for attempt := 0; attempt < 3; attempt++ {
		response, err := liveSegmentClient.Do(request)
		if err != nil {
			continue
		}
		if response.StatusCode != http.StatusOK {
			_, _ = io.Copy(io.Discard, response.Body)
			_ = response.Body.Close()
			continue
		}
		body, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
		_ = response.Body.Close()
		if err != nil {
			continue
		}
		return body
	}
	return nil
}

// 仅用于实测取流证据。部分站源的媒体 CDN 在本机直连被阻断、只有挂代理可达，
// 与 App 里的表现一致：设备直连能通的不用代理，通不了的按 LIVE_PROXY 走。
var liveSegmentClient = newLiveSegmentClient()

func newLiveSegmentClient() *http.Client {
	client := &http.Client{Timeout: 45 * time.Second}
	address := strings.TrimSpace(os.Getenv("LIVE_PROXY"))
	if address == "" {
		return client
	}
	parsed, err := url.Parse(address)
	if err != nil {
		return client
	}
	client.Transport = &http.Transport{Proxy: http.ProxyURL(parsed)}
	return client
}
