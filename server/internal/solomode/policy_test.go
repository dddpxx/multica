package solomode

import (
	"testing"

	"github.com/multica-ai/multica/server/internal/util"
)

func TestPolicy(t *testing.T) {
	const soloID = "11111111-1111-1111-1111-111111111111"
	target, err := util.ParseUUID(soloID)
	if err != nil {
		t.Fatal(err)
	}
	other, err := util.ParseUUID("22222222-2222-2222-2222-222222222222")
	if err != nil {
		t.Fatal(err)
	}

	disabled, err := Parse("  ")
	if err != nil || disabled.Enabled {
		t.Fatalf("Parse(empty) = (%+v, %v), want disabled policy", disabled, err)
	}

	policy, err := Parse("  " + soloID + "  ")
	if err != nil || !policy.Enabled || policy.AgentID != target {
		t.Fatalf("Parse(valid) = (%+v, %v), want enabled target %v", policy, err, target)
	}
	if !policy.AllowsAssignee("agent", target) {
		t.Fatal("configured agent must remain assignable")
	}
	if policy.AllowsAssignee("agent", other) || policy.AllowsAssignee("member", target) {
		t.Fatal("solo mode must reject other agents and non-agent assignees")
	}
	if !policy.AllowsMention("agent", soloID) {
		t.Fatal("configured agent mention must remain runnable")
	}
	if policy.AllowsMention("agent", "22222222-2222-2222-2222-222222222222") || policy.AllowsMention("squad", soloID) {
		t.Fatal("solo mode must block other-agent and squad mentions")
	}
}

func TestParseRejectsInvalidAgentID(t *testing.T) {
	if _, err := Parse("not-a-uuid"); err == nil {
		t.Fatal("Parse(invalid) succeeded, want error")
	}
}
