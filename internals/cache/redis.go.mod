package cache

import (
    "context"
    "encoding/json"
    "fmt"
    "leaderboard/internal/models"
    "time"

    "github.com/redis/go-redis/v9"
)

type RedisCache struct {
    client *redis.Client
    ctx    context.Context
}

func NewRedisCache(addr, password string, db int) (*RedisCache, error) {
    client := redis.NewClient(&redis.Options{
        Addr:     addr,
        Password: password,
        DB:       db,
    })

    ctx := context.Background()
    if err := client.Ping(ctx).Err(); err != nil {
        return nil, err
    }

    return &RedisCache{
        client: client,
        ctx:    ctx,
    }, nil
}

func (r *RedisCache) Close() error {
    return r.client.Close()
}

// Кэширование топ-листа
func (r *RedisCache) SetTopPlayers(entries []models.LeaderboardEntry, ttl time.Duration) error {
    data, err := json.Marshal(entries)
    if err != nil {
        return err
    }

    return r.client.Set(r.ctx, "top_players", data, ttl).Err()
}

func (r *RedisCache) GetTopPlayers() ([]models.LeaderboardEntry, error) {
    data, err := r.client.Get(r.ctx, "top_players").Bytes()
    if err == redis.Nil {
        return nil, nil
    }
    if err != nil {
        return nil, err
    }

    var entries []models.LeaderboardEntry
    if err := json.Unmarshal(data, &entries); err != nil {
        return nil, err
    }

    return entries, nil
}

// Кэширование ранка игрока
func (r *RedisCache) SetPlayerRank(playerID string, rank int, score int64, ttl time.Duration) error {
    key := fmt.Sprintf("rank:%s", playerID)
    data := fmt.Sprintf("%d:%d", rank, score)
    return r.client.Set(r.ctx, key, data, ttl).Err()
}

func (r *RedisCache) GetPlayerRank(playerID string) (int, int64, error) {
    key := fmt.Sprintf("rank:%s", playerID)
    data, err := r.client.Get(r.ctx, key).Result()
    if err == redis.Nil {
        return 0, 0, nil
    }
    if err != nil {
        return 0, 0, err
    }

    var rank int
    var score int64
    fmt.Sscanf(data, "%d:%d", &rank, &score)
    return rank, score, nil
}

// Кэширование окружения игрока
func (r *RedisCache) SetPlayersAround(playerID string, entries []models.LeaderboardEntry, ttl time.Duration) error {
    key := fmt.Sprintf("around:%s", playerID)
    data, err := json.Marshal(entries)
    if err != nil {
        return err
    }
    return r.client.Set(r.ctx, key, data, ttl).Err()
}

func (r *RedisCache) GetPlayersAround(playerID string) ([]models.LeaderboardEntry, error) {
    key := fmt.Sprintf("around:%s", playerID)
    data, err := r.client.Get(r.ctx, key).Bytes()
    if err == redis.Nil {
        return nil, nil
    }
    if err != nil {
        return nil, err
    }

    var entries []models.LeaderboardEntry
    if err := json.Unmarshal(data, &entries); err != nil {
        return nil, err
    }

    return entries, nil
}

// Инвалидация кэша
func (r *RedisCache) InvalidateTop() error {
    return r.client.Del(r.ctx, "top_players").Err()
}

func (r *RedisCache) InvalidatePlayer(playerID string) error {
    keys := []string{
        fmt.Sprintf("rank:%s", playerID),
        fmt.Sprintf("around:%s", playerID),
    }
    return r.client.Del(r.ctx, keys...).Err()
}

func (r *RedisCache) InvalidateAll() error {
    return r.client.FlushDB(r.ctx).Err()
}