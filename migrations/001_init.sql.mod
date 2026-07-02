-- Создаем таблицу для хранения очков игроков
CREATE TABLE IF NOT EXISTS player_scores (
    id SERIAL PRIMARY KEY,
    player_id VARCHAR(255) NOT NULL,
    score BIGINT NOT NULL DEFAULT 0,
    last_update TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    season_id INTEGER NOT NULL
);

-- Создаем таблицу для сезонов
CREATE TABLE IF NOT EXISTS seasons (
    id SERIAL PRIMARY KEY,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    end_date TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE
);

-- Индексы для быстрого поиска
CREATE INDEX idx_player_scores_season ON player_scores(season_id);
CREATE INDEX idx_player_scores_player_season ON player_scores(player_id, season_id);
CREATE INDEX idx_player_scores_score_rank ON player_scores(season_id, score DESC, last_update ASC);

-- Функция для получения текущего сезона
CREATE OR REPLACE FUNCTION current_season_id()
RETURNS INTEGER AS $$
DECLARE
    season_id INTEGER;
BEGIN
    -- Пытаемся найти активный сезон
    SELECT id INTO season_id 
    FROM seasons 
    WHERE is_active = TRUE 
    ORDER BY start_date DESC 
    LIMIT 1;
    
    -- Если нет активного сезона, создаем новый
    IF season_id IS NULL THEN
        INSERT INTO seasons (start_date, is_active) 
        VALUES (NOW(), TRUE) 
        RETURNING id INTO season_id;
    END IF;
    
    RETURN season_id;
END;
$$ LANGUAGE plpgsql;

-- Функция для сброса сезона
CREATE OR REPLACE FUNCTION reset_season()
RETURNS VOID AS $$
DECLARE
    old_season_id INTEGER;
    new_season_id INTEGER;
BEGIN
    -- Деактивируем текущий сезон
    UPDATE seasons 
    SET is_active = FALSE, end_date = NOW() 
    WHERE is_active = TRUE 
    RETURNING id INTO old_season_id;
    
    -- Создаем новый сезон
    INSERT INTO seasons (start_date, is_active) 
    VALUES (NOW(), TRUE) 
    RETURNING id INTO new_season_id;
    
    -- Очищаем старые данные (опционально)
    -- DELETE FROM player_scores WHERE season_id = old_season_id;
    
    -- Или оставляем для истории
END;
$$ LANGUAGE plpgsql;

-- Создаем начальный сезон
INSERT INTO seasons (start_date, is_active) 
VALUES (NOW(), TRUE);