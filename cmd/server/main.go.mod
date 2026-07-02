package main

import (
    "context"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "leaderboard/internal/api"
    "leaderboard/internal/cache"
    "leaderboard/internal/config"
    "leaderboard/internal/repository"
    "leaderboard/internal/service"

    "github.com/gin-gonic/gin"
)

func main() {
    // Загружаем конфигурацию
    cfg, err := config.Load()
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }

    // Установка режима
    if os.Getenv("GIN_MODE") == "release" {
        gin.SetMode(gin.ReleaseMode)
    }

    // Инициализируем репозиторий PostgreSQL
    repo, err := repository.NewPostgresRepository(cfg.GetDBConnString())
    if err != nil {
        log.Fatalf("Failed to connect to PostgreSQL: %v", err)
    }
    defer repo.Close()

    // Инициализируем кэш Redis
    cacheClient, err := cache.NewRedisCache(
        cfg.GetRedisAddr(),
        cfg.RedisPassword,
        cfg.RedisDB,
    )
    if err != nil {
        log.Fatalf("Failed to connect to Redis: %v", err)
    }
    defer cacheClient.Close()

    // Инициализируем сервис
    svc := service.NewLeaderboardService(repo, cacheClient, cfg.NeighborCount)

    // Инициализируем HTTP хендлеры
    handler := api.NewHandler(svc)
    router := api.SetupRouter(handler)

    // healthcheck endpoint
    router.GET("/health", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "healthy"})
    })

    // Запускаем сервер
    srv := &http.Server{
        Addr:         ":" + cfg.ServerPort,
        Handler:      router,
        ReadTimeout:  15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    // Запускаем сервер в горутине
    go func() {
        log.Printf("Server starting on port %s", cfg.ServerPort)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("Failed to start server: %v", err)
        }
    }()

    // Ожидаем сигнал для graceful shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    log.Println("Shutting down server...")

    // Graceful shutdown
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }

    log.Println("Server exited properly")
}