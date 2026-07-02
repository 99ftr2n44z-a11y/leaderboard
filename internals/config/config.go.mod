package config

import (
    "fmt"
    "os"
    "strconv"
)

type Config struct {
    ServerPort     string
    DBHost         string
    DBPort         string
    DBUser         string
    DBPassword     string
    DBName         string
    RedisHost      string
    RedisPort      string
    RedisPassword  string
    RedisDB        int
    SeasonDuration int // in days
    NeighborCount  int
}

func Load() (*Config, error) {
    redisDB, err := strconv.Atoi(getEnv("REDIS_DB", "0"))
    if err != nil {
        redisDB = 0
    }

    seasonDays, err := strconv.Atoi(getEnv("SEASON_DAYS", "30"))
    if err != nil {
        seasonDays = 30
    }

    neighborCount, err := strconv.Atoi(getEnv("NEIGHBOR_COUNT", "5"))
    if err != nil {
        neighborCount = 5
    }

    return &Config{
        ServerPort:     getEnv("SERVER_PORT", "8080"),
        DBHost:         getEnv("DB_HOST", "localhost"),
        DBPort:         getEnv("DB_PORT", "5432"),
        DBUser:         getEnv("DB_USER", "postgres"),
        DBPassword:     getEnv("DB_PASSWORD", "postgres"),
        DBName:         getEnv("DB_NAME", "leaderboard"),
        RedisHost:      getEnv("REDIS_HOST", "localhost"),
        RedisPort:      getEnv("REDIS_PORT", "6379"),
        RedisPassword:  getEnv("REDIS_PASSWORD", ""),
        RedisDB:        redisDB,
        SeasonDuration: seasonDays,
        NeighborCount:  neighborCount,
    }
}

func (c *Config) GetDBConnString() string {
    return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
        c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName)
}

func (c *Config) GetRedisAddr() string {
    return fmt.Sprintf("%s:%s", c.RedisHost, c.RedisPort)
}

func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}