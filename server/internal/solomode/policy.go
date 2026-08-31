package solomode

import (
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/multica-ai/multica/server/internal/util"
)

type Policy struct {
	AgentID pgtype.UUID
	Enabled bool
}

func Parse(raw string) (Policy, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return Policy{}, nil
	}
	id, err := util.ParseUUID(raw)
	if err != nil {
		return Policy{}, fmt.Errorf("invalid MULTICA_SOLO_AGENT_ID: %w", err)
	}
	return Policy{AgentID: id, Enabled: true}, nil
}

func (p Policy) AllowsAssignee(assigneeType string, assigneeID pgtype.UUID) bool {
	return !p.Enabled || assigneeType == "agent" && assigneeID.Valid && assigneeID == p.AgentID
}

func (p Policy) AllowsMention(targetType, targetID string) bool {
	if !p.Enabled {
		return true
	}
	if targetType != "agent" {
		return false
	}
	id, err := util.ParseUUID(targetID)
	return err == nil && id == p.AgentID
}
