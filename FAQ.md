Обновление очков

POST /api/v1/score
{
    "player_id": "player_123",
    "score_delta": 100
}

Получение топа

GET /api/v1/leaderboard/top?limit=100

Получение ранка игрока

GET /api/v1/leaderboard/rank/player_123

SELECT reset_season();