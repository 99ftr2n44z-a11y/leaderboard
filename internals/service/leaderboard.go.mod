package service

import (
    "fmt"
    "leaderboard/internal/cache"
    "leaderboard/internal/models"
    "leaderboard/internal/repository"
    "log"
    "sync"
    "time"
)

type LeaderboardService struct {
    repo          *repository.PostgresRepository
    cache         *cache.RedisCache
    mutex         sync.RWMutex
    neighborCount int
    cacheTTL      time.Duration
    refreshTTL    time.Duration 
}

func NewLeaderboardService(
    repo *repository.PostgresRepository,
    cache *cache.RedisCache,
    neighborCount int,
) *LeaderboardService {
    svc := &LeaderboardService{
        repo:          repo,
        cache:         cache,
        neighborCount: neighborCount,
        cacheTTL:      2 * time.Minute, 
        refreshTTL:    30 * time.Second, 
    }
    
    // Запускаем фоновое обновление кэша
    go svc.backgroundRefresh()
    
    return svc
}

func (s *LeaderboardService) UpdateScore(playerID string, delta int64) error {
    // Обновляем в БД
    if err := s.repo.UpdateScore(playerID, delta); err != nil {
        return err
    }

    // Атомарная инвалидация кэша с обработкой ошибок
    s.mutex.Lock()
    defer s.mutex.Unlock()

    // Инвалидируем кэш
    if err := s.cache.InvalidateTop(); err != nil {
        // Логируем, но не возвращаем ошибку клиенту
        log.Printf("Warning: failed to invalidate top cache: %v", err)
    }
    
    if err := s.cache.InvalidatePlayer(playerID); err != nil {
        log.Printf("Warning: failed to invalidate player cache: %v", err)
    }

    return nil
}

func (s *LeaderboardService) GetTopPlayers(limit int) ([]models.LeaderboardEntry, error) {
    s.mutex.RLock()
    defer s.mutex.RUnlock()

    // Пытаемся получить из кэша
    entries, err := s.cache.GetTopPlayers()
    if err == nil && entries != nil {
        // Проверяем, не пора ли обновить кэш
        if s.shouldRefreshTopCache() {
            go s.refreshTopCache(limit) // Фоновое обновление
        }
        return entries, nil
    }

    // Если в кэше нет, берем из БД
    entries, err = s.repo.GetTopPlayers(limit)
    if err != nil {
        return nil, err
    }

    // Сохраняем в кэш с обработкой ошибки
    if err := s.cache.SetTopPlayers(entries, s.cacheTTL); err != nil {
        log.Printf("Failed to set top cache: %v", err)
    }

    return entries, nil
}

// Фоновое обновление кэша
func (s *LeaderboardService) backgroundRefresh() {
    ticker := time.NewTicker(s.refreshTTL)
    defer ticker.Stop()
    
    for range ticker.C {
        s.mutex.Lock()
        if s.shouldRefreshTopCache() {
            s.refreshTopCache(100)
        }
        s.mutex.Unlock()
    }
}

func (s *LeaderboardService) shouldRefreshTopCache() bool {
    if !s.cache.TopPlayersExists() {
        return true
    }
    
    ttl, err := s.cache.GetTopPlayersTTL()
    if err != nil {
        return true
    }
    
    // Обновляем, если осталось меньше 30 секунд
    return ttl < s.refreshTTL
}

func (s *LeaderboardService) refreshTopCache(limit int) {
    entries, err := s.repo.GetTopPlayers(limit)
    if err != nil {
        log.Printf("Failed to refresh top cache: %v", err)
        return
    }
    
    if err := s.cache.SetTopPlayers(entries, s.cacheTTL); err != nil {
        log.Printf("Failed to set refreshed top cache: %v", err)
    }
}

func (s *LeaderboardService) GetPlayerRank(playerID string) (*models.RankResponse, error) {
    s.mutex.RLock()
    defer s.mutex.RUnlock()

    // Пытаемся получить ранг из кэша
    rank, score, err := s.cache.GetPlayerRank(playerID)
    if err == nil && rank > 0 {
        // Пытаемся получить окружение из кэша
        around, _ := s.cache.GetPlayersAround(playerID)
        if around != nil {
            return s.buildRankResponse(playerID, rank, score, around), nil
        }
    }

    // Если в кэше нет, берем из БД
    rank, score, err = s.repo.GetPlayerRank(playerID)
    if err != nil {
        return nil, err
    }
    if rank == 0 {
        return nil, fmt.Errorf("player not found")
    }

    // Получаем окружение
    around, err := s.repo.GetPlayersAround(playerID, s.neighborCount)
    if err != nil {
        return nil, err
    }

    // Сохраняем в кэш с обработкой ошибок
    if err := s.cache.SetPlayerRank(playerID, rank, score, s.cacheTTL); err != nil {
        log.Printf("Failed to cache player rank: %v", err)
    }
    
    if err := s.cache.SetPlayersAround(playerID, around, s.cacheTTL); err != nil {
        log.Printf("Failed to cache players around: %v", err)
    }

    return s.buildRankResponse(playerID, rank, score, around), nil
}

func (s *LeaderboardService) buildRankResponse(
    playerID string,
    rank int,
    score int64,
    around []models.LeaderboardEntry,
) *models.RankResponse {
    var above, below []models.LeaderboardEntry

    for _, entry := range around {
        if entry.Rank < rank {
            above = append(above, entry)
        } else if entry.Rank > rank {
            below = append(below, entry)
        }
    }

    return &models.RankResponse{
        PlayerID: playerID,
        Rank:     rank,
        Score:    score,
        Above:    above,
        Below:    below,
    }
}

// Метод для сброса сезона
func (s *LeaderboardService) ResetSeason() error {
    s.mutex.Lock()
    defer s.mutex.Unlock()

    if err := s.repo.ResetSeason(); err != nil {
        return err
    }

    // Очищаем весь кэш
    return s.cache.InvalidateAll()
}