package wiring_test

import (
	"testing"

	"github.com/multica-ai/multica/server/internal/analytics"
	"github.com/multica-ai/multica/server/internal/handler"
)

func TestNewWiresSoloAgentIntoCreateServices(t *testing.T) {
	const want = "11111111-1111-1111-1111-111111111111"
	h := handler.New(nil, nil, nil, nil, nil, nil, nil, analytics.NoopClient{}, handler.Config{SoloAgentID: want})
	if h.IssueService.SoloAgentID != want || h.AutopilotService.SoloAgentID != want {
		t.Fatalf("solo agent wiring = (%q, %q), want %q", h.IssueService.SoloAgentID, h.AutopilotService.SoloAgentID, want)
	}
}
