package api

import (
    "github.com/gin-gonic/gin"
)

func SetupRouter(handler *Handler) *gin.Engine {
    router := gin.Default()

    // Добавляем middleware для логирования и CORS при необходимости
    router.Use(gin.Recovery())

    api := router.Group("/api/v1")
    {
        api.POST("/score", handler.UpdateScore)
        api.GET("/leaderboard/top", handler.GetTopPlayers)
        api.GET("/leaderboard/rank/:player_id", handler.GetPlayerRank)
    }

    return router
}