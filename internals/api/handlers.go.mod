package api

import (
    "net/http"
    "strconv"

    "leaderboard/internal/models"
    "leaderboard/internal/service"

    "github.com/gin-gonic/gin"
)

type Handler struct {
    service *service.LeaderboardService
}

func NewHandler(service *service.LeaderboardService) *Handler {
    return &Handler{service: service}
}

func (h *Handler) UpdateScore(c *gin.Context) {
    var req models.ScoreUpdateRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Доп проверка
    if req.ScoreDelta <= 0 {
        c.JSON(http.StatusBadRequest, gin.H{"error": "score_delta must be positive"})
        return
    }

    if err := h.service.UpdateScore(req.PlayerID, req.ScoreDelta); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{"status": "updated"})
}

func (h *Handler) GetTopPlayers(c *gin.Context) {
    // Ограничение лимита для производительности
    limit := 100
    if limitStr := c.Query("limit"); limitStr != "" {
        if l, err := strconv.Atoi(limitStr); err == nil {
            if l > 0 && l <= 200 { // Максимум 200
                limit = l
            } else if l > 200 {
                limit = 200
            }
        }
    }

    entries, err := h.service.GetTopPlayers(limit)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, entries)
}

func (h *Handler) GetPlayerRank(c *gin.Context) {
    playerID := c.Param("player_id")
    if playerID == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "player_id is required"})
        return
    }

    response, err := h.service.GetPlayerRank(playerID)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, response)
}

// Сброс сезона вручную
func (h *Handler) ResetSeason(c *gin.Context) {
    if err := h.service.ResetSeason(); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, gin.H{"status": "season reset successfully"})
}