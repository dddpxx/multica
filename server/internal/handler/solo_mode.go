package handler

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/multica-ai/multica/server/internal/solomode"
)

func (h *Handler) soloAgentID() (pgtype.UUID, bool, error) {
	policy, err := solomode.Parse(h.cfg.SoloAgentID)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	return policy.AgentID, policy.Enabled, nil
}

func (h *Handler) validateSoloAssigneePair(assigneeType pgtype.Text, assigneeID pgtype.UUID) (int, string) {
	policy, err := solomode.Parse(h.cfg.SoloAgentID)
	if err != nil {
		return http.StatusInternalServerError, "solo mode is misconfigured"
	}
	if !policy.Enabled {
		return 0, ""
	}
	if !assigneeType.Valid || !policy.AllowsAssignee(assigneeType.String, assigneeID) {
		return http.StatusConflict, "solo mode locks issues to the configured agent"
	}
	return 0, ""
}

func (h *Handler) soloMentionAllowed(targetType, targetID string) (bool, error) {
	policy, err := solomode.Parse(h.cfg.SoloAgentID)
	if err != nil {
		return false, err
	}
	return policy.AllowsMention(targetType, targetID), nil
}
