package core

import (
	"encoding/json"
	"testing"
)

func TestSourceStatusesMatchesSingleAndDeduplicates(t *testing.T) {
	engine := &nativeEngine{
		catalogs: map[string][]nativeDrama{
			sourceHongguo: {{ID: "hongguo:fixture", Source: sourceHongguo}},
		},
		catalogStates: map[string]nativeCatalogState{
			sourceHongguo: {Page: 4, HasMore: true},
		},
		sourceRecords: map[string]nativeSourceRecord{
			sourceHongguo: {Running: true, Stage: "查找新剧", Completed: 2, Total: 5},
		},
	}
	items, err := engine.sourceStatuses([]string{sourceHongguo, sourceHongguo})
	if err != nil || len(items) != 1 {
		t.Fatalf("batch did not deduplicate: items=%+v err=%v", items, err)
	}
	batch, err := json.Marshal(items[0])
	if err != nil {
		t.Fatal(err)
	}
	single, err := json.Marshal(engine.sourceStatus(sourceHongguo))
	if err != nil {
		t.Fatal(err)
	}
	if string(batch) != string(single) {
		t.Fatalf("batch differs from single: %s != %s", batch, single)
	}
}

func TestSourceStatusesRejectsInvalidAndOversizedRequests(t *testing.T) {
	engine := &nativeEngine{}
	for _, sources := range [][]string{
		{sourceHongguo, "not-a-source"},
		make([]string, 129),
	} {
		items, err := engine.sourceStatuses(sources)
		if err == nil || items != nil {
			t.Fatalf("invalid batch was accepted: %+v %v", items, err)
		}
	}
	items, err := engine.sourceStatuses(nil)
	if err != nil || items == nil || len(items) != 0 {
		t.Fatalf("empty batch must return an empty array: %+v %v", items, err)
	}
}

func TestSourceStatusesRespectsCompiledEdition(t *testing.T) {
	engine := &nativeEngine{}
	items, err := engine.sourceStatuses([]string{sourceHongguo, sourceHuangguoVideo})
	if buildAllSources != "true" {
		if err == nil || items != nil {
			t.Fatalf("green edition exposed restricted source: %+v %v", items, err)
		}
		return
	}
	if err != nil || len(items) != 2 || items[0].Source != sourceHongguo || items[1].Source != sourceHuangguoVideo {
		t.Fatalf("full edition batch lost requested order or source: %+v %v", items, err)
	}
}
