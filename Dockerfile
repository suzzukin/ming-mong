# Используем официальный образ Go для сборки
FROM golang:1.21-alpine AS builder

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем go.mod и go.sum (если есть)
COPY go.* ./

# Загружаем зависимости
RUN go mod download

# Копируем исходный код
COPY . .

# Собираем приложение
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Используем минимальный образ для финального контейнера
FROM alpine:latest

# Устанавливаем необходимые пакеты (ca-certificates для HTTPS, openssl для создания сертификатов)
RUN apk --no-cache add ca-certificates openssl

# Создаем пользователя для безопасности
RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем собранное приложение из builder
COPY --from=builder /app/main .

# Создаем директорию для TLS сертификатов
RUN mkdir -p /app/certs

# Меняем владельца файлов
RUN chown -R appuser:appgroup /app

# Переключаемся на пользователя appuser
USER appuser

# Открываем порт
EXPOSE 8080

# Запускаем приложение
CMD ["./main"]