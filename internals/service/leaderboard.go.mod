package service

import (
    "fmt"
    "leaderboard/internal/cache"
    "leaderboard/internal/models"
    "leaderboard/internal/repository"
    "sync"
    "time"
)

type LeaderboardService struct {
    repo         *repository.PostgresRepository
    cache        *cache.RedisCache
    mutex        sync.RWMutex
    neighborCount int
    cacheTTL     time.Duration
}

func NewLeaderboardService(
    repo *repository.PostgresRepository,
    cache *cache.RedisCache,
    neighborCount int,
) *LeaderboardService {
    return &LeaderboardService{
        repo:          repo,
        cache:         cache,
        neighborCount: neighborCount,
        cacheTTL:      30 * time.Second,
    }
}

func (s *LeaderboardService) UpdateScore(playerID string, delta int64) error {
    // Обновляем в БД
    if err := s.repo.UpdateScore(playerID, delta); err != nil {
        return err
    }

    // Инвалидируем кэш
    s.mutex.Lock()
    defer s.mutex.Unlock()

    // Инвалидируем топ-лист
    s.cache.InvalidateTop()

    // Инвалидируем данные игрока
    s.cache.InvalidatePlayer(playerID)

    return nil
}

func (s *LeaderboardService) GetTopPlayers(limit int) ([]models.LeaderboardEntry, error) {
    s.mutex.RLock()
    defer s.mutex.RUnlock()

    // Пытаемся получить из кэша
    entries, err := s.cache.GetTopPlayers()
    if err == nil && entries != nil {
        return entries, nil
    }

    // Если в кэше нет, берем из БД
    entries, err = s.repo.GetTopPlayers(limit)
    if err != nil {
        return nil, err
    }

    // Сохраняем в кэш
    s.cache.SetTopPlayers(entries, s.cacheTTL)

    return entries, nil
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

    // Сохраняем в кэш
    s.cache.SetPlayerRank(playerID, rank, score, s.cacheTTL)
    s.cache.SetPlayersAround(playerID, around, s.cacheTTL)

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