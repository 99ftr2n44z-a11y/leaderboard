package repository

import (
    "database/sql"
    "fmt"
    "leaderboard/internal/models"
    "sync"
    "time"

    _ "github.com/lib/pq"
)

type PostgresRepository struct {
    db *sql.DB
    mu sync.RWMutex
}

func NewPostgresRepository(connString string) (*PostgresRepository, error) {
    db, err := sql.Open("postgres", connString)
    if err != nil {
        return nil, err
    }

    if err := db.Ping(); err != nil {
        return nil, err
    }

    // Настройка пула соединений
    db.SetMaxOpenConns(100)
    db.SetMaxIdleConns(10)
    db.SetConnMaxLifetime(time.Hour)

    return &PostgresRepository{db: db}, nil
}

func (r *PostgresRepository) Close() error {
    return r.db.Close()
}

func (r *PostgresRepository) UpdateScore(playerID string, delta int64) error {
    r.mu.Lock()
    defer r.mu.Unlock()

    query := `
        INSERT INTO player_scores (player_id, score, last_update, season_id)
        VALUES ($1, $2, NOW(), (SELECT current_season_id()))
        ON CONFLICT (player_id, season_id) 
        DO UPDATE SET 
            score = player_scores.score + $2,
            last_update = NOW()
        WHERE player_scores.player_id = $1 
          AND player_scores.season_id = (SELECT current_season_id())
    `

    _, err := r.db.Exec(query, playerID, delta)
    return err
}

func (r *PostgresRepository) GetTopPlayers(limit int) ([]models.LeaderboardEntry, error) {
    query := `
        WITH ranked AS (
            SELECT 
                player_id,
                score,
                ROW_NUMBER() OVER (ORDER BY score DESC, last_update ASC) as rank
            FROM player_scores
            WHERE season_id = (SELECT current_season_id())
        )
        SELECT player_id, score, rank
        FROM ranked
        WHERE rank <= $1
        ORDER BY rank
    `

    rows, err := r.db.Query(query, limit)
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var entries []models.LeaderboardEntry
    for rows.Next() {
        var entry models.LeaderboardEntry
        if err := rows.Scan(&entry.PlayerID, &entry.Score, &entry.Rank); err != nil {
            return nil, err
        }
        entries = append(entries, entry)
    }

    return entries, nil
}

func (r *PostgresRepository) GetPlayerRank(playerID string) (int, int64, error) {
    query := `
        SELECT 
            rank,
            score
        FROM (
            SELECT 
                player_id,
                score,
                ROW_NUMBER() OVER (ORDER BY score DESC, last_update ASC) as rank
            FROM player_scores
            WHERE season_id = (SELECT current_season_id())
        ) ranked
        WHERE player_id = $1
    `

    var rank int
    var score int64
    err := r.db.QueryRow(query, playerID).Scan(&rank, &score)
    if err == sql.ErrNoRows {
        return 0, 0, nil
    }
    if err != nil {
        return 0, 0, err
    }

    return rank, score, nil
}

func (r *PostgresRepository) GetPlayersAround(playerID string, n int) ([]models.LeaderboardEntry, error) {
    // Получаем ранг игрока
    rank, _, err := r.GetPlayerRank(playerID)
    if err != nil {
        return nil, err
    }
    if rank == 0 {
        return []models.LeaderboardEntry{}, nil
    }

    startRank := rank - n
    if startRank < 1 {
        startRank = 1
    }
    endRank := rank + n

    query := `
        WITH ranked AS (
            SELECT 
                player_id,
                score,
                ROW_NUMBER() OVER (ORDER BY score DESC, last_update ASC) as rank
            FROM player_scores
            WHERE season_id = (SELECT current_season_id())
        )
        SELECT player_id, score, rank
        FROM ranked
        WHERE rank BETWEEN $1 AND $2
        ORDER BY rank
    `

    rows, err := r.db.Query(query, startRank, endRank)
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var entries []models.LeaderboardEntry
    for rows.Next() {
        var entry models.LeaderboardEntry
        if err := rows.Scan(&entry.PlayerID, &entry.Score, &entry.Rank); err != nil {
            return nil, err
        }
        entries = append(entries, entry)
    }

    return entries, nil
}

func (r *PostgresRepository) GetTotalPlayers() (int, error) {
    query := `
        SELECT COUNT(*)
        FROM player_scores
        WHERE season_id = (SELECT current_season_id())
    `

    var count int
    err := r.db.QueryRow(query).Scan(&count)
    return count, err
}

// Методы для управления сезонами
func (r *PostgresRepository) GetCurrentSeasonID() (int, error) {
    var id int
    err := r.db.QueryRow("SELECT current_season_id()").Scan(&id)
    return id, err
}

func (r *PostgresRepository) ResetSeason() error {
    _, err := r.db.Exec("SELECT reset_season()")
    return err
}