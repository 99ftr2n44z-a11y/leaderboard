package repository

import (
    "database/sql"
    "fmt"
    "leaderboard/internal/models"
    "time"

    _ "github.com/lib/pq"
)

type PostgresRepository struct {
    db *sql.DB
    // потокобезопасно
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
    // Используем транзакцию для атомарности
    tx, err := r.db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    query := `
        INSERT INTO player_scores (player_id, score, last_update, season_id)
        VALUES ($1, $2, NOW(), (SELECT current_season_id()))
        ON CONFLICT (player_id, season_id) 
        DO UPDATE SET 
            score = player_scores.score + $2,
            last_update = NOW()
        WHERE player_scores.player_id = $1 
          AND player_scores.season_id = (SELECT current_season_id())
        RETURNING score
    `

    var newScore int64
    err = tx.QueryRow(query, playerID, delta).Scan(&newScore)
    if err != nil {
        return err
    }

    return tx.Commit()
}

func (r *PostgresRepository) GetTopPlayers(limit int) ([]models.LeaderboardEntry, error) {
    // Оптимизированный запрос с использованием MATERIALIZED CTE
    query := `
        WITH ranked AS MATERIALIZED (
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
        LIMIT $1
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

// Опитимизировал
func (r *PostgresRepository) GetPlayersAround(playerID string, n int) ([]models.LeaderboardEntry, error) {
    query := `
        WITH ranked AS MATERIALIZED (
            SELECT 
                player_id,
                score,
                ROW_NUMBER() OVER (ORDER BY score DESC, last_update ASC) as rank
            FROM player_scores
            WHERE season_id = (SELECT current_season_id())
        ),
        target_rank AS (
            SELECT rank FROM ranked WHERE player_id = $1
        )
        SELECT 
            r.player_id,
            r.score,
            r.rank
        FROM ranked r, target_rank t
        WHERE r.rank BETWEEN t.rank - $2 AND t.rank + $2
        ORDER BY r.rank
    `

    rows, err := r.db.Query(query, playerID, n)
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
        WITH ranked AS MATERIALIZED (
            SELECT 
                player_id,
                score,
                ROW_NUMBER() OVER (ORDER BY score DESC, last_update ASC) as rank
            FROM player_scores
            WHERE season_id = (SELECT current_season_id())
        )
        SELECT rank, score
        FROM ranked
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