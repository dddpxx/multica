package service

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/multica-ai/multica/server/internal/util"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
)

func TestApplySoloAgent(t *testing.T) {
	const soloID = "11111111-1111-1111-1111-111111111111"
	target, err := util.ParseUUID(soloID)
	if err != nil {
		t.Fatal(err)
	}
	other, err := util.ParseUUID("22222222-2222-2222-2222-222222222222")
	if err != nil {
		t.Fatal(err)
	}
	original := db.Autopilot{AssigneeType: "squad", AssigneeID: other}

	disabled, err := (&AutopilotService{}).applySoloAgent(original)
	if err != nil || disabled.AssigneeType != original.AssigneeType || disabled.AssigneeID != original.AssigneeID {
		t.Fatalf("disabled solo mode changed autopilot: (%+v, %v)", disabled, err)
	}

	got, err := (&AutopilotService{SoloAgentID: soloID}).applySoloAgent(original)
	if err != nil || got.AssigneeType != "agent" || got.AssigneeID != target {
		t.Fatalf("applySoloAgent() = (%q, %v, %v), want agent %v", got.AssigneeType, got.AssigneeID, err, target)
	}

	if _, err := (&AutopilotService{SoloAgentID: "invalid"}).applySoloAgent(original); err == nil {
		t.Fatal("invalid solo agent configuration succeeded")
	}
}

func TestSoloAgentConfigurationGuardsAutopilotDispatchEntries(t *testing.T) {
	svc := &AutopilotService{SoloAgentID: "invalid"}
	ap := db.Autopilot{ExecutionMode: "create_issue"}
	run := &db.AutopilotRun{}

	assertConfigError := func(name string, call func() error) {
		t.Run(name, func(t *testing.T) {
			defer func() {
				if recovered := recover(); recovered != nil {
					t.Fatalf("panicked before validating solo configuration: %v", recovered)
				}
			}()
			if err := call(); err == nil {
				t.Fatal("invalid solo configuration reached dispatch")
			}
		})
	}

	assertConfigError("regular dispatch", func() error {
		_, _, err := svc.dispatchAutopilot(context.Background(), ap, pgtype.UUID{}, "test", nil, pgtype.Timestamptz{}, pgtype.UUID{}, pgtype.UUID{}, "test")
		return err
	})
	assertConfigError("webhook admission", func() error {
		_, err := svc.AdmitAutopilotWebhookDelivery(context.Background(), ap, pgtype.UUID{}, nil, pgtype.UUID{Valid: true})
		return err
	})
	assertConfigError("webhook worker", func() error {
		_, _, err := svc.dispatchAutopilotRun(context.Background(), ap, pgtype.UUID{}, "webhook", run, pgtype.UUID{})
		return err
	})
	assertConfigError("webhook repair", func() error {
		return svc.ensureWebhookCreateIssueTask(context.Background(), ap, *run)
	})
}
