package models

import "time"

type PlayerScore struct {
    PlayerID   string    `json:"player_id"`
    Score      int64     `json:"score"`
    LastUpdate time.Time `json:"last_update"`
}

type ScoreUpdateRequest struct {
    PlayerID   string `json:"player_id" binding:"required"`
    ScoreDelta int64  `json:"score_delta" binding:"required"`
}

type LeaderboardEntry struct {
    PlayerID string `json:"player_id"`
    Score    int64  `json:"score"`
    Rank     int    `json:"rank"`
}

type RankResponse struct {
    PlayerID string              `json:"player_id"`
    Rank     int                 `json:"rank"`
    Score    int64               `json:"score"`
    Above    []LeaderboardEntry  `json:"above"`
    Below    []LeaderboardEntry  `json:"below"`
}